import { randomBytes, timingSafeEqual } from "node:crypto"
import { lerCron, proximoHorario } from "./cron"
import type { Equipe } from "./equipe"
import { TUDO } from "./governanca"
import type { Repositorio } from "./repositorio"
import {
  LIMITE_DO_CORPO,
  autorDaRotina,
  descricaoComDados,
  excedeLimite,
  horarioDevido,
  planoDoDisparo,
  tituloDaTarefa,
  type Disparo,
  type OrigemDoDisparo,
  type Rotina,
} from "./rotinas"
import { lerNovaTarefa, type StatusTarefa, type Tarefa } from "./tarefa"
import type { NovoAviso } from "../avisos/central"
import { avisoDeRotinaQueFalhou } from "../avisos/fontes"

export interface AmbienteDoAgendador {
  repo: Repositorio
  equipe: (id: string) => Equipe | undefined
  aoCriar: (tarefa: Tarefa) => void
  aoMudarStatus: (id: number, de: StatusTarefa, para: StatusTarefa) => void
  publicarTarefa: (id: number) => void
  publicarRotinas: () => void
  avisar: (aviso: NovoAviso) => void
  sistema?: () => Promise<void>
  agora?: () => Date
}

export interface RotinaDaEquipe {
  equipe: string
  rotina: Rotina
}

export const CRON_DO_SISTEMA = "*/5 * * * *"
const INTERVALO_DO_RELOGIO_MS = 30_000

const chave = (equipe: string, id: string) => `${equipe}/${id}`

export class Agendador {
  private readonly rotinas = new Map<string, RotinaDaEquipe>()
  private readonly recentes = new Map<string, string[]>()
  private relogio: ReturnType<typeof setInterval> | undefined
  private marcaDoSistema: Date
  private sistemaRodando = false
  private ultimoDoSistema: { em: string; erro: string | null } | null = null

  constructor(private readonly amb: AmbienteDoAgendador) {
    this.marcaDoSistema = this.agora()
  }

  private agora(): Date {
    return this.amb.agora?.() ?? new Date()
  }

  carregar(lista: RotinaDaEquipe[]): void {
    this.rotinas.clear()
    const agora = this.agora()
    for (const item of lista) {
      this.rotinas.set(chave(item.equipe, item.rotina.id), item)
      if (!this.amb.repo.estadoDaRotina(item.equipe, item.rotina.id)) this.amb.repo.marcarRotina(item.equipe, item.rotina.id, agora)
    }
  }

  rotina(equipe: string, id: string): Rotina | undefined {
    return this.rotinas.get(chave(equipe, id))?.rotina
  }

  daEquipe(equipe: string): Rotina[] {
    return [...this.rotinas.values()].filter((r) => r.equipe === equipe).map((r) => r.rotina)
  }

  // Salvar ou reativar põe a marca em agora: mudar o cron nunca dispara o passado.
  definir(equipe: string, rotina: Rotina): void {
    this.rotinas.set(chave(equipe, rotina.id), { equipe, rotina })
    this.amb.repo.marcarRotina(equipe, rotina.id, this.agora())
    const token = this.amb.repo.estadoDaRotina(equipe, rotina.id)?.token ?? null
    if (rotina.webhook && !token) this.amb.repo.trocarToken(equipe, rotina.id, novoToken())
    if (!rotina.webhook && token) this.amb.repo.trocarToken(equipe, rotina.id, null)
  }

  remover(equipe: string, id: string): void {
    this.rotinas.delete(chave(equipe, id))
    this.amb.repo.esquecerRotina(equipe, id)
  }

  removerDaEquipe(equipe: string): void {
    for (const r of this.daEquipe(equipe)) this.remover(equipe, r.id)
  }

  trocarToken(equipe: string, id: string): void {
    const rotina = this.exigir(equipe, id)
    if (!rotina.webhook) throw new Error(`a rotina ${rotina.nome} não tem webhook`)
    this.amb.repo.trocarToken(equipe, id, novoToken())
  }

  iniciar(): void {
    this.marcaDoSistema = this.agora()
    this.tique()
    this.relogio = setInterval(() => this.tique(), INTERVALO_DO_RELOGIO_MS)
  }

  parar(): void {
    if (this.relogio) clearInterval(this.relogio)
  }

  tique(agora = this.agora()): void {
    for (const { equipe, rotina } of this.rotinas.values()) {
      if (!rotina.ativa || !rotina.cron) continue
      const estado = this.amb.repo.estadoDaRotina(equipe, rotina.id)
      const marca = estado ? new Date(estado.marca) : agora
      const horario = horarioDevido(rotina.cron, rotina.perdidos, marca, agora)
      this.amb.repo.marcarRotina(equipe, rotina.id, agora)
      if (horario) this.disparar(equipe, rotina.id, "cron", { horario })
    }
    if (this.amb.sistema && horarioDevido(CRON_DO_SISTEMA, "ignorar", this.marcaDoSistema, agora)) void this.rodarSistema(agora)
    this.marcaDoSistema = agora
  }

  private async rodarSistema(agora: Date): Promise<void> {
    if (this.sistemaRodando) return
    this.sistemaRodando = true
    let erro: string | null = null
    try {
      await this.amb.sistema!()
    } catch (e) {
      erro = (e as Error).message
      console.warn(`[agendador] agenda da memória falhou — ${erro}`)
    } finally {
      this.sistemaRodando = false
      this.ultimoDoSistema = { em: agora.toISOString(), erro }
      this.amb.publicarRotinas()
    }
  }

  private exigir(equipe: string, id: string): Rotina {
    const rotina = this.rotina(equipe, id)
    if (!rotina) throw new Error(`a rotina ${id} não existe na equipe ${equipe}`)
    return rotina
  }

  disparar(equipe: string, id: string, origem: OrigemDoDisparo, extra: { horario?: Date; corpo?: string } = {}): Disparo {
    const rotina = this.exigir(equipe, id)
    const agora = this.agora()
    const base = { equipe, rotina: id, origem, horario: extra.horario?.toISOString() ?? null, em: agora.toISOString(), tarefa: null }
    const repo = this.amb.repo
    try {
      if (!rotina.ativa) return repo.registrarDisparo({ ...base, resultado: "pulada", motivo: "a rotina está desativada" })
      if (repo.pausas().has(TUDO)) return repo.registrarDisparo({ ...base, resultado: "pulada", motivo: "tudo pausado" })
      const autor = autorDaRotina(equipe, id)
      const plano = planoDoDisparo(rotina.concorrencia, repo.tarefaAbertaDe(autor))
      if (plano.acao === "pular") return repo.registrarDisparo({ ...base, resultado: "pulada", motivo: plano.motivo })
      const nova = lerNovaTarefa(
        {
          equipe,
          posicao: rotina.posicao,
          titulo: tituloDaTarefa(rotina.tarefa.titulo, extra.horario ?? agora),
          descricao: descricaoComDados(rotina.tarefa.descricao, extra.corpo),
          porque: rotina.tarefa.porque ?? "",
          dependeDe: plano.dependeDe,
        },
        this.amb.equipe,
      )
      if (plano.cancelar !== null) {
        const de = repo.exigir(plano.cancelar).status
        repo.mudarStatus(plano.cancelar, "cancelada", autor)
        this.amb.publicarTarefa(plano.cancelar)
        this.amb.aoMudarStatus(plano.cancelar, de, "cancelada")
      }
      const tarefa = repo.criar(nova, autor)
      const disparo = repo.registrarDisparo({ ...base, resultado: "criada", motivo: "", tarefa: tarefa.id })
      this.amb.publicarTarefa(tarefa.id)
      this.amb.aoCriar(tarefa)
      return disparo
    } catch (erro) {
      const motivo = (erro as Error).message
      this.amb.avisar(avisoDeRotinaQueFalhou(rotina.nome, motivo))
      return repo.registrarDisparo({ ...base, resultado: "falhou", motivo })
    } finally {
      this.amb.publicarRotinas()
    }
  }

  webhook(equipe: string, id: string, token: string, corpo: string): { status: number; resposta: Record<string, unknown> } {
    const rotina = this.rotina(equipe, id)
    if (!rotina?.webhook) return { status: 404, resposta: { erro: "rotina inexistente ou sem webhook" } }
    const esperado = this.amb.repo.estadoDaRotina(equipe, id)?.token
    if (!esperado || !mesmoToken(token, esperado)) return { status: 403, resposta: { erro: "token inválido" } }
    if (new TextEncoder().encode(corpo).length > LIMITE_DO_CORPO) return { status: 413, resposta: { erro: "corpo acima de 64 KB" } }
    const agora = this.agora()
    const k = chave(equipe, id)
    const recentes = (this.recentes.get(k) ?? []).filter((em) => Date.parse(em) > agora.getTime() - 60_000)
    if (excedeLimite(recentes, agora)) return { status: 429, resposta: { erro: "mais de 10 disparos por minuto" } }
    this.recentes.set(k, [...recentes, agora.toISOString()])
    const disparo = this.disparar(equipe, id, "webhook", { corpo })
    if (disparo.resultado === "criada") return { status: 202, resposta: { tarefa: disparo.tarefa } }
    if (disparo.resultado === "pulada") return { status: 200, resposta: { pulado: disparo.motivo } }
    return { status: 500, resposta: { erro: disparo.motivo } }
  }

  paraCliente(): Record<string, unknown>[] {
    const agora = this.agora()
    const lista: Record<string, unknown>[] = [...this.rotinas.values()]
      .sort((a, b) => a.equipe.localeCompare(b.equipe) || a.rotina.nome.localeCompare(b.rotina.nome))
      .map(({ equipe, rotina }) => {
        const disparos = this.amb.repo.disparos(equipe, rotina.id, 10)
        const token = rotina.webhook ? (this.amb.repo.estadoDaRotina(equipe, rotina.id)?.token ?? null) : undefined
        return {
          ...rotina,
          equipe,
          proximo: rotina.ativa && rotina.cron ? (proximoHorario(lerCron(rotina.cron), agora)?.toISOString() ?? null) : null,
          ultimoDisparo: disparos[0] ?? null,
          disparos,
          ...(rotina.webhook ? { token, url: `/rotinas/${equipe}/${rotina.id}` } : {}),
        }
      })
    if (this.amb.sistema) {
      const ultimo = this.ultimoDoSistema
      const disparo: Disparo | null = ultimo && {
        id: 0,
        equipe: "",
        rotina: "memoria",
        origem: "cron",
        horario: null,
        em: ultimo.em,
        resultado: ultimo.erro ? "falhou" : "criada",
        motivo: ultimo.erro ?? "a agenda da memória rodou",
        tarefa: null,
      }
      lista.push({
        equipe: null,
        sistema: true,
        id: "memoria",
        nome: "Agenda da memória",
        ativa: true,
        cron: CRON_DO_SISTEMA,
        concorrencia: "pular",
        perdidos: "ignorar",
        proximo: proximoHorario(lerCron(CRON_DO_SISTEMA), agora)?.toISOString() ?? null,
        ultimoDisparo: disparo,
        disparos: disparo ? [disparo] : [],
      })
    }
    return lista
  }
}

function novoToken(): string {
  return randomBytes(24).toString("base64url")
}

function mesmoToken(recebido: string, esperado: string): boolean {
  const a = Buffer.from(recebido)
  const b = Buffer.from(esperado)
  return a.length === b.length && timingSafeEqual(a, b)
}
