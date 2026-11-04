import type { Repositorio } from "./repositorio"
import { donoDaExecucao } from "./repositorio"
import {
  ESPERA_DA_NOVA_TENTATIVA_MS,
  FALHAS_PARA_BLOQUEAR,
  NOMES_DE_GATILHO,
  blocoDaTarefa,
  custoDaExecucao,
  escolher,
  falhasSeguidas,
  type Candidata,
  type Evento,
  type Execucao,
  type Gatilho,
  type ModoDaExecucao,
  type TipoDeEvento,
} from "./execucao"
import { TUDO, planoAprovado, planoPendente, precisaDePlano, recusaDeDelegacao, type MotivoDeBloqueio } from "./governanca"
import type { StatusTarefa, Tarefa } from "./tarefa"
import { subordinadas, type Equipe, type Posicao } from "./equipe"
import type { Delegacao } from "./ferramentas"
import type { Memoria } from "../memoria/tipos"
import type { NovoAviso } from "../avisos/central"
import { avisoDeBloqueio, avisoDeDelegacao, avisoDeEntrega, avisoDePedidoDeAjuda, avisoDePlano } from "../avisos/fontes"
import type { trabalhar } from "../sessions"
import type { RegistroDeUso } from "../uso"

export interface Ambiente {
  raiz: string
  repo: Repositorio
  memoria?: Memoria
  teto: number
  equipe: (id: string) => Equipe | undefined
  nome: (persona: string) => string
  modelo: (persona: string) => string
  trabalhar: typeof trabalhar
  publicarTarefa: (id: number) => void
  publicarExecucao: (execucao: Execucao) => void
  publicarEvento: (evento: Evento, tarefaId: number) => void
  avisar: (aviso: NovoAviso) => void
  pedirComando: (tarefaId: number, persona: string, comando: string, aprovar: boolean) => Promise<boolean>
  cancelarPedidos: (tarefaId: number) => void
  bloqueio?: (persona: string) => MotivoDeBloqueio | null
  aposExecucao?: (persona: string) => void
}

interface Viva {
  tarefa: number
  persona: string
  controle: AbortController
  parada: boolean
  devolver: boolean
}

const INTERVALO_DE_SEGURANCA_MS = 30_000

export function tetoDeExecucoes(bruto = process.env.CT_EXECUCOES_SIMULTANEAS): number {
  const n = Number(bruto)
  return Number.isInteger(n) && n > 0 ? n : 2
}

export class Orquestra {
  private readonly vivas = new Map<number, Viva>()
  private relogio: ReturnType<typeof setInterval> | undefined

  constructor(private readonly amb: Ambiente) {}

  get repo(): Repositorio {
    return this.amb.repo
  }

  rodando(tarefa: number): boolean {
    return [...this.vivas.values()].some((v) => v.tarefa === tarefa)
  }

  iniciar(): void {
    for (const e of this.repo.interrompidasNaSubida()) {
      this.amb.publicarExecucao(e)
      this.depoisDeFalhar(e, "retomada")
    }
    this.despachar()
    this.relogio = setInterval(() => this.despachar(), INTERVALO_DE_SEGURANCA_MS)
  }

  parar(): void {
    if (this.relogio) clearInterval(this.relogio)
    for (const viva of this.vivas.values()) {
      viva.parada = true
      viva.controle.abort()
    }
  }

  acordar(tarefa: number, gatilho: Gatilho, extra?: Parameters<Repositorio["enfileirar"]>[3]): void {
    const { execucao, juntada } = this.repo.enfileirar(tarefa, gatilho, new Date(), extra)
    if (juntada) this.repo.comentar(tarefa, "orquestra", `acordar juntado: ${NOMES_DE_GATILHO[gatilho]}`, new Date(), "status")
    else this.amb.publicarExecucao(execucao)
    this.amb.publicarTarefa(tarefa)
    this.despachar()
  }

  aoCriar(tarefa: Tarefa): void {
    if (tarefa.status === "a_fazer") this.acordar(tarefa.id, "atribuicao")
  }

  aoMudarStatus(id: number, de: StatusTarefa, para: StatusTarefa): void {
    if (de === "em_andamento") this.interromper(id)
    if (para === "cancelada" || para === "backlog") {
      const naFila = this.repo.naFilaDa(id)
      if (naFila) this.amb.publicarExecucao(this.repo.descartar(naFila.id, `a tarefa foi para ${para}`))
    }
    if (para === "a_fazer") this.acordar(id, "atribuicao")
    if (para === "concluida") this.acordarDependentes(id)
  }

  aoComentar(id: number): void {
    const tarefa = this.repo.exigir(id)
    if (tarefa.status === "em_revisao" || tarefa.status === "bloqueada") {
      this.repo.mudarStatus(id, "a_fazer", "ueslei")
    } else if (tarefa.status !== "a_fazer" && tarefa.status !== "em_andamento") {
      return
    }
    this.acordar(id, "comentario")
  }

  private acordarDependentes(id: number): void {
    for (const dependente of this.repo.dependentes(id)) {
      if (this.repo.exigir(dependente).status === "a_fazer") this.acordar(dependente, "dependencia")
    }
  }

  private interromper(tarefa: number): void {
    for (const viva of this.vivas.values()) {
      if (viva.tarefa !== tarefa) continue
      viva.parada = true
      viva.controle.abort()
    }
    this.amb.cancelarPedidos(tarefa)
  }

  private posicaoDe(tarefa: Tarefa): Posicao | undefined {
    return this.amb.equipe(tarefa.equipe)?.posicoes.find((p) => p.id === tarefa.posicao)
  }

  despachar(): void {
    const candidatas: Candidata[] = this.repo.comStatus("na_fila").map((execucao) => {
      const tarefa = this.repo.exigir(execucao.tarefa)
      return {
        execucao,
        tarefa,
        persona: this.posicaoDe(tarefa)?.persona ?? null,
        dependenciasConcluidas: tarefa.dependeDe.every((d) => this.repo.exigir(d).status === "concluida"),
      }
    })
    const rodando = [...this.vivas.values()].map((v) => ({ tarefa: v.tarefa, persona: v.persona }))
    const pausas = this.repo.pausas()
    const bloqueadas = new Set(
      candidatas.flatMap((c) =>
        c.persona !== null && (pausas.has(TUDO) || pausas.has(c.persona) || this.amb.bloqueio?.(c.persona)) ? [c.persona] : [],
      ),
    )
    for (const decisao of escolher(candidatas, rodando, this.amb.teto, new Date(), bloqueadas)) {
      if (decisao.acao === "descartar") {
        this.amb.publicarExecucao(this.repo.descartar(decisao.execucao, decisao.motivo))
        continue
      }
      let execucao: Execucao
      try {
        execucao = this.repo.comecar(decisao.execucao, decisao.persona, this.amb.modelo(decisao.persona))
      } catch (erro) {
        this.amb.publicarExecucao(this.repo.descartar(decisao.execucao, (erro as Error).message))
        continue
      }
      const viva: Viva = {
        tarefa: execucao.tarefa,
        persona: decisao.persona,
        controle: new AbortController(),
        parada: false,
        devolver: false,
      }
      this.vivas.set(execucao.id, viva)
      this.amb.publicarExecucao(execucao)
      this.amb.publicarTarefa(execucao.tarefa)
      void this.rodar(execucao, viva).finally(() => {
        this.vivas.delete(execucao.id)
        this.amb.publicarTarefa(execucao.tarefa)
        this.amb.aposExecucao?.(viva.persona)
        this.despachar()
      })
    }
  }

  private evento(execucao: Execucao, tipo: TipoDeEvento, conteudo: string): void {
    this.amb.publicarEvento(this.repo.registrarEvento(execucao.id, tipo, conteudo), execucao.tarefa)
  }

  private async rodar(execucao: Execucao, viva: Viva): Promise<void> {
    const persona = viva.persona
    const tarefa = this.repo.exigir(execucao.tarefa)
    const posicao = this.posicaoDe(tarefa)!
    const sessao = this.repo.sessaoDoPar(tarefa.id, persona, execucao.id)
    const anterior = this.repo.anteriorDoPar(tarefa.id, persona, execucao.id)
    const equipe = this.amb.equipe(tarefa.equipe)!
    const registros = this.repo.registros(tarefa.id)
    const deTrabalho = !precisaDePlano(posicao, registros)
    const aprovado = planoAprovado(registros)
    const modo: ModoDaExecucao = !deTrabalho ? { tipo: "plano" } : aprovado ? { tipo: "plano_aprovado", plano: aprovado } : { tipo: "normal" }
    const abaixo = deTrabalho ? subordinadas(equipe, posicao.id) : []
    let pedidoDeAjuda: string | undefined
    let uso: RegistroDeUso | undefined
    try {
      const resposta = await this.amb.trabalhar({
        raiz: this.amb.raiz,
        persona,
        posicao,
        plano: !deTrabalho,
        bloco: blocoDaTarefa(
          tarefa,
          this.repo.cadeiaDePais(tarefa.id),
          registros,
          persona,
          anterior?.inicio ?? null,
          abaixo.map((p) => ({ id: p.id, titulo: p.titulo, persona: p.persona ? this.amb.nome(p.persona) : null })),
          modo,
        ),
        consulta: [tarefa.titulo, tarefa.descricao].filter(Boolean).join("\n"),
        modelo: execucao.modelo ?? this.amb.modelo(persona),
        sessionId: sessao?.sessionId,
        memoria: this.amb.memoria,
        tarefaId: tarefa.id,
        execucaoId: execucao.id,
        controle: viva.controle,
        acoes: {
          comentar: (texto) => {
            this.repo.comentar(tarefa.id, persona, texto)
            this.amb.publicarTarefa(tarefa.id)
            return "Comentário registrado."
          },
          pedirAjuda: (motivo) => {
            this.repo.comentar(tarefa.id, persona, motivo, new Date(), "ajuda")
            pedidoDeAjuda = motivo
            this.amb.publicarTarefa(tarefa.id)
            return "Pedido registrado. A tarefa fica bloqueada até o Ueslei responder: pare agora."
          },
          delegar: abaixo.length ? (pedido) => this.delegar(tarefa, execucao, persona, posicao, abaixo, pedido) : undefined,
        },
        onEvento: (tipo, conteudo) => this.evento(execucao, tipo, conteudo),
        onComando: (comando, aprovar) => this.amb.pedirComando(tarefa.id, persona, comando, aprovar),
        onSessao: (sessionId) => this.repo.gravarSessao(execucao.id, sessionId),
        onUso: (registro) => (uso = registro),
      })
      const custo = this.custo(uso, sessao?.custoAcumuladoUSD ?? null)
      if (viva.parada) {
        this.interrompida(execucao, viva, custo)
        return
      }
      const entrega = resposta.texto || "(a execução terminou sem texto)"
      this.terminar(execucao, { status: "concluida", falha: false, resultado: entrega, ...custo })
      this.repo.comentar(tarefa.id, persona, entrega, new Date(), deTrabalho ? "entrega" : "plano")
      const comentouNoMeio = this.repo.naFilaDa(tarefa.id) !== undefined
      const destino: StatusTarefa = comentouNoMeio ? "a_fazer" : pedidoDeAjuda ? "bloqueada" : "em_revisao"
      if (!this.repo.devolver(execucao.id, destino, donoDaExecucao(execucao.id))) return
      if (comentouNoMeio) return
      const nome = this.amb.nome(persona)
      this.amb.avisar(
        pedidoDeAjuda
          ? avisoDePedidoDeAjuda(tarefa.id, nome, pedidoDeAjuda)
          : deTrabalho
            ? avisoDeEntrega(tarefa.id, nome, entrega)
            : avisoDePlano(tarefa.id, nome, entrega),
      )
    } catch (erro) {
      const custo = this.custo(uso, sessao?.custoAcumuladoUSD ?? null)
      if (viva.parada) {
        this.interrompida(execucao, viva, custo)
        return
      }
      const mensagem = (erro as Error).message
      this.evento(execucao, "erro", mensagem)
      const falhou = this.terminar(execucao, { status: "falhou", falha: true, erro: mensagem, ...custo })
      this.repo.devolver(execucao.id, "a_fazer", "orquestra")
      this.depoisDeFalhar(falhou, "nova_tentativa")
    }
  }

  private interrompida(execucao: Execucao, viva: Viva, custo: ReturnType<Orquestra["custo"]>): void {
    this.terminar(execucao, { status: "interrompida", falha: false, erro: viva.devolver ? "pausada" : "parada pelo Ueslei", ...custo })
    if (!viva.devolver) return
    if (this.repo.devolver(execucao.id, "a_fazer", "orquestra")) this.acordar(execucao.tarefa, "retomada")
  }

  private delegar(
    tarefa: Tarefa,
    execucao: Execucao,
    persona: string,
    posicao: Posicao,
    abaixo: Posicao[],
    pedido: Delegacao,
  ): string {
    const alvo = abaixo.find((p) => p.id === pedido.posicao)
    if (!alvo) return `A posição ${pedido.posicao} não responde a você. Pode delegar a: ${abaixo.map((p) => p.id).join(", ")}.`
    const titulo = pedido.titulo.trim().slice(0, 200)
    if (!titulo) return "A subtarefa precisa de um título."
    const recusa = recusaDeDelegacao(this.repo.cadeiaDePais(tarefa.id).length + 1, this.repo.filhasAbertas(tarefa.id))
    if (recusa) return recusa
    const direto = posicao.delegaDireto === true
    const sub = this.repo.criar(
      {
        equipe: tarefa.equipe,
        posicao: alvo.id,
        titulo,
        descricao: (pedido.descricao ?? "").trim().slice(0, 20_000),
        porque: (pedido.porque ?? "").trim().slice(0, 4_000),
        pai: tarefa.id,
        dependeDe: [],
        status: direto ? "a_fazer" : "backlog",
      },
      donoDaExecucao(execucao.id),
    )
    this.repo.comentar(tarefa.id, persona, `delegou #${sub.id} a ${alvo.id}: ${titulo}`, new Date(), "status")
    this.amb.publicarTarefa(sub.id)
    this.amb.publicarTarefa(tarefa.id)
    if (direto) {
      this.repo.auditar(donoDaExecucao(execucao.id), "delegou direto", `tarefa:${sub.id}`, `${persona} → ${alvo.id}: ${titulo}`)
      this.acordar(sub.id, "atribuicao")
      return `Subtarefa #${sub.id} criada para ${alvo.id}. Ela já entrou na fila e roda sozinha.`
    }
    this.amb.avisar(avisoDeDelegacao(sub.id, this.amb.nome(persona), titulo))
    return `Subtarefa #${sub.id} criada para ${alvo.id}, no backlog. Ela só roda quando o Ueslei liberar.`
  }

  pausar(alvo: string, quem = "ueslei"): void {
    this.repo.pausar(alvo, quem)
    this.repo.auditar(quem, "pausou", alvo === TUDO ? "tudo" : `persona:${alvo}`)
    for (const viva of this.vivas.values()) {
      if (alvo !== TUDO && viva.persona !== alvo) continue
      viva.parada = true
      viva.devolver = true
      viva.controle.abort()
      this.amb.cancelarPedidos(viva.tarefa)
    }
  }

  retomar(alvo: string, quem = "ueslei"): void {
    if (this.repo.retomar(alvo)) this.repo.auditar(quem, "retomou", alvo === TUDO ? "tudo" : `persona:${alvo}`)
    this.despachar()
  }

  aprovarPlano(id: number, quem = "ueslei"): void {
    const tarefa = this.repo.exigir(id)
    if (tarefa.status !== "em_revisao" || !planoPendente(this.repo.registros(id))) {
      throw new Error(`a tarefa ${id} não tem plano esperando aprovação`)
    }
    this.repo.comentar(id, quem, "aprovou o plano", new Date(), "plano-aprovado")
    this.repo.mudarStatus(id, "a_fazer", quem)
    this.repo.auditar(quem, "aprovou o plano", `tarefa:${id}`)
    this.acordar(id, "plano_aprovado")
  }

  interromperPersona(persona: string): void {
    for (const viva of this.vivas.values()) {
      if (viva.persona !== persona) continue
      viva.parada = true
      viva.controle.abort()
      this.amb.cancelarPedidos(viva.tarefa)
    }
  }

  private custo(uso: RegistroDeUso | undefined, anterior: number | null) {
    return {
      custoUSD: custoDaExecucao(uso?.custoAcumuladoUSD, anterior, uso?.retomada ?? false),
      custoAcumuladoUSD: uso?.custoAcumuladoUSD ?? null,
    }
  }

  private terminar(execucao: Execucao, termino: Parameters<Repositorio["terminar"]>[1]): Execucao {
    const terminada = this.repo.terminar(execucao.id, termino)
    this.amb.publicarExecucao(terminada)
    return terminada
  }

  private depoisDeFalhar(execucao: Execucao, gatilho: "retomada" | "nova_tentativa"): void {
    const tarefa = this.repo.exigir(execucao.tarefa)
    if (tarefa.status !== "a_fazer") return
    const falhas = falhasSeguidas(this.repo.execucoesDaTarefa(tarefa.id))
    if (falhas >= FALHAS_PARA_BLOQUEAR) {
      const naFila = this.repo.naFilaDa(tarefa.id)
      if (naFila) this.amb.publicarExecucao(this.repo.descartar(naFila.id, "a tarefa foi bloqueada"))
      this.repo.mudarStatus(tarefa.id, "bloqueada", "orquestra")
      this.repo.comentar(tarefa.id, "orquestra", `bloqueada depois de ${falhas} falhas seguidas: ${execucao.erro ?? "sem erro"}`, new Date(), "status")
      this.amb.publicarTarefa(tarefa.id)
      this.amb.avisar(avisoDeBloqueio(tarefa.id, execucao.erro ?? "sem erro"))
      return
    }
    const naoAntes = gatilho === "nova_tentativa" ? new Date(Date.now() + ESPERA_DA_NOVA_TENTATIVA_MS) : undefined
    this.acordar(tarefa.id, gatilho, { tentativa: falhas + 1, naoAntes })
  }
}
