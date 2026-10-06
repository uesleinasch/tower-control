import { randomUUID } from "node:crypto"
import { mkdir, rename } from "node:fs/promises"
import { dirname } from "node:path"
import { dataLocal } from "../texto"
import type { Aviso, CentralDeAvisos } from "./central"
import type { Adiamento } from "./http"
import {
  ETIQUETA_LEMBRETE,
  STATUS_ABERTOS,
  camposDoAdiamento,
  caminhoDaConfig,
  caminhoDosLembretes,
  disparos,
  lerConfig,
  novoHorario,
  podarDisparados,
  retratoDe,
  validarLembrete,
  type EstadoLembretes,
  type PedidoDeLembrete,
  type Retrato,
} from "./lembretes"
import { TickTaskFechado, type ChamarTickTask } from "./ticktask-cliente"

const RETRATO_MS = 5 * 60_000
const DISPARO_MS = 60_000
const DIAS_DE_PRAZO = 3

export async function tirarRetrato(chamar: ChamarTickTask, agora: Date): Promise<Retrato> {
  const ate = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate() + DIAS_DE_PRAZO)
  const agenda = await chamar("agenda", { range: "week", date: dataLocal(agora) })
  const buscas = await Promise.all(
    STATUS_ABERTOS.map((status) => chamar("search_tasks", { status, dueBefore: dataLocal(ate), limit: 200 })),
  )
  return retratoDe(agenda, buscas, agora)
}

export class Lembretes {
  private estado: EstadoLembretes = { retrato: null, disparados: {} }
  private fila: Promise<unknown> = Promise.resolve()

  constructor(
    private readonly raiz: string,
    private readonly central: CentralDeAvisos,
    private readonly chamar: ChamarTickTask,
    private readonly relogio: () => Date = () => new Date(),
  ) {}

  get retrato(): Retrato | null {
    return this.estado.retrato
  }

  async carregar(): Promise<void> {
    const arquivo = Bun.file(caminhoDosLembretes(this.raiz))
    if (!(await arquivo.exists())) return
    try {
      const lido = (await arquivo.json()) as Partial<EstadoLembretes>
      this.estado = { retrato: lido.retrato ?? null, disparados: lido.disparados ?? {} }
    } catch {
      console.warn("[lembretes] lembretes.json ilegível; recomeçando do zero")
    }
  }

  iniciar(): void {
    void this.carregar()
      .then(() => this.atualizarRetrato())
      .then(() => this.disparar())
      .catch((erro: Error) => console.warn(`[lembretes] subida falhou — ${erro.message}`))
    setInterval(() => void this.atualizarRetrato(), RETRATO_MS)
    setInterval(() => void this.disparar(), DISPARO_MS)
  }

  atualizarRetrato(): Promise<void> {
    return this.emFila(async () => {
      try {
        this.estado.retrato = await tirarRetrato(this.chamar, this.relogio())
        await this.gravar()
      } catch (erro) {
        if (!(erro instanceof TickTaskFechado)) console.warn(`[lembretes] retrato falhou — ${(erro as Error).message}`)
      }
    })
  }

  disparar(): Promise<void> {
    return this.emFila(async () => {
      const agora = this.relogio()
      const config = lerConfig(await this.lerConfigBruta())
      const novos = disparos(this.estado.retrato, agora, config, this.estado.disparados)
      const disparados = podarDisparados(this.estado.disparados, agora)
      for (const { chave, momento } of novos) disparados[chave] = momento
      if (!novos.length && Object.keys(disparados).length === Object.keys(this.estado.disparados).length) return
      this.estado.disparados = disparados
      await this.gravar()
      for (const { aviso } of novos) await this.central.criar(aviso)
    })
  }

  async concluir(aviso: Aviso): Promise<void> {
    const id = this.tarefaDo(aviso)
    await this.chamar("update_task", { id, status: "finalizada" })
    await this.emFila(async () => {
      if (this.estado.retrato) {
        this.estado.retrato.tarefas = this.estado.retrato.tarefas.filter((t) => t.id !== id)
        await this.gravar()
      }
    })
  }

  async adiar(aviso: Aviso, para: Adiamento): Promise<void> {
    const id = this.tarefaDo(aviso)
    const campo = aviso.alvo.campo ?? "agendamento"
    const tarefa = this.estado.retrato?.tarefas.find((t) => t.id === id)
    const campos = camposDoAdiamento(tarefa, campo, novoHorario(para, this.relogio()))
    await this.chamar("update_task", { id, ...campos })
    await this.emFila(async () => {
      if (tarefa) Object.assign(tarefa, campos)
      await this.gravar()
    })
  }

  async agendar(pedido: PedidoDeLembrete): Promise<string> {
    const valido = validarLembrete(pedido, this.relogio())
    if ("erro" in valido) return valido.erro
    let criada: unknown
    try {
      criada = await this.chamar("create_task", {
        name: valido.titulo,
        scheduled_date: valido.data,
        scheduled_time: valido.hora,
        tags: [ETIQUETA_LEMBRETE],
      })
    } catch (erro) {
      return `Não agendei: ${(erro as Error).message}`
    }
    void this.atualizarRetrato()
    const id = (criada as { task?: { id?: number }; id?: number })?.task?.id ?? (criada as { id?: number })?.id
    return `Lembrete agendado para ${valido.data} às ${valido.hora}${id ? ` (tarefa #${id} no TickTask)` : ""}.`
  }

  private tarefaDo(aviso: Aviso): number {
    if (typeof aviso.alvo.tarefaId !== "number") throw new Error("aviso sem tarefa")
    return aviso.alvo.tarefaId
  }

  private async lerConfigBruta(): Promise<unknown> {
    const arquivo = Bun.file(caminhoDaConfig(this.raiz))
    try {
      return (await arquivo.exists()) ? await arquivo.json() : {}
    } catch {
      return {}
    }
  }

  private emFila<T>(tarefa: () => Promise<T>): Promise<T> {
    const atual = this.fila.then(tarefa, tarefa)
    this.fila = atual.catch(() => {})
    return atual
  }

  private async gravar(): Promise<void> {
    const caminho = caminhoDosLembretes(this.raiz)
    await mkdir(dirname(caminho), { recursive: true })
    const temporario = `${caminho}.${randomUUID()}.tmp`
    await Bun.write(temporario, JSON.stringify(this.estado, null, 2))
    await rename(temporario, caminho)
  }
}
