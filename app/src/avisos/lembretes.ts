import { join } from "node:path"
import { dataLocal } from "../texto"
import type { NovoAviso } from "./central"
import type { Adiamento } from "./http"

export interface Tarefa {
  id: number
  nome: string
  status: string
  lembrete: boolean
  scheduled_date: string | null
  scheduled_time: string | null
  scheduled_end_time: string | null
  due_date: string | null
  due_time: string | null
}

export interface Retrato {
  atualizadoEm: string
  tarefas: Tarefa[]
}

export interface ConfigAvisos {
  antecedenciaMin: number
  resumoDiario: string
}

export interface EstadoLembretes {
  retrato: Retrato | null
  disparados: Record<string, string>
}

export interface Disparo {
  chave: string
  momento: string
  aviso: NovoAviso
}

export type Campo = "agendamento" | "prazo"

export const CONFIG_PADRAO: ConfigAvisos = { antecedenciaMin: 10, resumoDiario: "08:00" }
export const ETIQUETA_LEMBRETE = "lembrete"
export const STATUS_ABERTOS = ["inbox", "aguardando", "proximas", "executando", "someday"]

const MINUTO = 60_000
const HORA = 60 * MINUTO
const TOLERANCIA_LEMBRETE = 30 * MINUTO
const JANELA_ATRASADA = 24 * HORA
const GUARDA_DISPARADOS = 48 * HORA
const ITENS_NO_RESUMO = 8

const PADRAO_DATA = /^(\d{4})-(\d{2})-(\d{2})$/
const PADRAO_HORA = /^([01]\d|2[0-3]):([0-5]\d)$/

const dois = (n: number) => String(n).padStart(2, "0")
export const horaLocal = (quando: Date) => `${dois(quando.getHours())}:${dois(quando.getMinutes())}`
const diaMes = (quando: Date) => `${dois(quando.getDate())}/${dois(quando.getMonth() + 1)}`

export function momentoLocal(data: string | null | undefined, hora: string | null | undefined): Date | null {
  const d = data ? PADRAO_DATA.exec(data) : null
  const h = hora ? PADRAO_HORA.exec(hora) : null
  if (!d || !h) return null
  const momento = new Date(Number(d[1]), Number(d[2]) - 1, Number(d[3]), Number(h[1]), Number(h[2]))
  return dataLocal(momento) === data ? momento : null
}

export const caminhoDosLembretes = (raiz: string) => join(raiz, "conversations", "lembretes.json")
export const caminhoDaConfig = (raiz: string) => join(raiz, "avisos.json")

export function lerConfig(bruto: unknown): ConfigAvisos {
  const valor = (bruto && typeof bruto === "object" ? bruto : {}) as Record<string, unknown>
  const antecedencia = Number(valor.antecedenciaMin)
  return {
    antecedenciaMin:
      Number.isInteger(antecedencia) && antecedencia >= 0 && antecedencia <= 240 ? antecedencia : CONFIG_PADRAO.antecedenciaMin,
    resumoDiario:
      typeof valor.resumoDiario === "string" && PADRAO_HORA.test(valor.resumoDiario)
        ? valor.resumoDiario
        : CONFIG_PADRAO.resumoDiario,
  }
}

function tarefaDe(bruta: Record<string, unknown>): Tarefa | null {
  if (typeof bruta.id !== "number" || typeof bruta.name !== "string") return null
  const texto = (campo: string) => (typeof bruta[campo] === "string" ? (bruta[campo] as string) : null)
  const etiquetas = Array.isArray(bruta.tags) ? (bruta.tags as { name?: unknown }[]) : []
  return {
    id: bruta.id,
    nome: bruta.name,
    status: texto("status") ?? "",
    lembrete: etiquetas.some((t) => t?.name === ETIQUETA_LEMBRETE),
    scheduled_date: texto("scheduled_date"),
    scheduled_time: texto("scheduled_time"),
    scheduled_end_time: texto("scheduled_end_time"),
    due_date: texto("due_date"),
    due_time: texto("due_time"),
  }
}

export function retratoDe(agenda: unknown, buscas: unknown[], agora: Date): Retrato {
  const brutas: Record<string, unknown>[] = []
  const dias = (agenda as { schedule?: { tasks?: unknown[] }[] })?.schedule ?? []
  for (const dia of dias) brutas.push(...((dia.tasks ?? []) as Record<string, unknown>[]))
  for (const busca of buscas) brutas.push(...(((busca as { tasks?: unknown[] })?.tasks ?? []) as Record<string, unknown>[]))
  const porId = new Map<number, Tarefa>()
  for (const bruta of brutas) {
    const tarefa = tarefaDe(bruta)
    if (tarefa && tarefa.status !== "finalizada") porId.set(tarefa.id, tarefa)
  }
  return { atualizadoEm: agora.toISOString(), tarefas: [...porId.values()] }
}

function avisoDeHorario(tarefa: Tarefa, campo: Campo, evento: Date): NovoAviso {
  const hora = horaLocal(evento)
  return {
    tipo: "lembrete",
    titulo: tarefa.nome,
    corpo: campo === "agendamento" ? `Agendada para ${hora}` : `Prazo às ${hora}`,
    alvo: { tarefaId: tarefa.id, campo },
    acoes: ["concluir", "adiar"],
  }
}

function avisoDeAtraso(tarefa: Tarefa, prazo: Date): NovoAviso {
  return {
    tipo: "atrasada",
    titulo: `Atrasada: ${tarefa.nome}`,
    corpo: `O prazo era ${diaMes(prazo)} às ${horaLocal(prazo)}`,
    alvo: { tarefaId: tarefa.id, campo: "prazo" },
    acoes: ["concluir", "adiar"],
  }
}

function listar(nomes: string[]): string {
  const visiveis = nomes.slice(0, ITENS_NO_RESUMO)
  const resto = nomes.length - visiveis.length
  return visiveis.join("; ") + (resto > 0 ? `; e mais ${resto}` : "")
}

function estaAtrasada(tarefa: Tarefa, hoje: string, agora: Date): boolean {
  if (!tarefa.due_date) return false
  if (tarefa.due_date < hoje) return true
  const prazo = momentoLocal(tarefa.due_date, tarefa.due_time)
  return tarefa.due_date === hoje && prazo !== null && prazo < agora
}

export function avisoDeResumo(retrato: Retrato, agora: Date): NovoAviso {
  const hoje = dataLocal(agora)
  const abertas = retrato.tarefas.filter((t) => t.status !== "finalizada")
  const agendadas = abertas
    .filter((t) => t.scheduled_date === hoje)
    .sort((a, b) => (a.scheduled_time ?? "99").localeCompare(b.scheduled_time ?? "99"))
    .map((t) => (t.scheduled_time ? `${t.scheduled_time} ${t.nome}` : t.nome))
  const vencem = abertas.filter((t) => t.due_date === hoje).map((t) => (t.due_time ? `${t.nome} (${t.due_time})` : t.nome))
  const atrasadas = abertas.filter((t) => estaAtrasada(t, hoje, agora)).length

  const linhas = [agendadas.length ? `Agenda: ${listar(agendadas)}` : "Nada agendado para hoje."]
  if (vencem.length) linhas.push(`Vencem hoje: ${listar(vencem)}`)
  if (atrasadas) linhas.push(`Atrasadas: ${atrasadas}`)
  const retratoEm = new Date(retrato.atualizadoEm)
  if (agora.getTime() - retratoEm.getTime() > 24 * HORA) {
    linhas.push(`A agenda pode estar desatualizada: o último retrato é de ${diaMes(retratoEm)} às ${horaLocal(retratoEm)}.`)
  }
  return { tipo: "resumo", titulo: "Seu dia", corpo: linhas.join("\n"), alvo: {}, acoes: [] }
}

// Lembrete pedido em conversa dispara na hora exata: com antecedência, "me lembra daqui a
// 5 minutos" avisaria na mesma hora.
export function disparos(
  retrato: Retrato | null,
  agora: Date,
  config: ConfigAvisos,
  jaDisparados: Record<string, string>,
): Disparo[] {
  if (!retrato) return []
  const saida: Disparo[] = []
  const t = agora.getTime()
  const novo = (chave: string, momento: Date, aviso: NovoAviso) => {
    if (!jaDisparados[chave]) saida.push({ chave, momento: momento.toISOString(), aviso })
  }

  for (const tarefa of retrato.tarefas) {
    if (tarefa.status === "finalizada") continue
    const antecedencia = (tarefa.lembrete ? 0 : config.antecedenciaMin) * MINUTO
    const horarios: [Campo, string | null, string | null][] = [
      ["agendamento", tarefa.scheduled_date, tarefa.scheduled_time],
      ["prazo", tarefa.due_date, tarefa.due_time],
    ]
    for (const [campo, data, hora] of horarios) {
      const evento = momentoLocal(data, hora)
      if (!evento) continue
      const e = evento.getTime()
      if (t >= e - antecedencia && t <= e + TOLERANCIA_LEMBRETE) {
        novo(`${tarefa.id}|${campo}|${data}T${hora}`, evento, avisoDeHorario(tarefa, campo, evento))
      }
    }
    const prazo = momentoLocal(tarefa.due_date, tarefa.due_time)
    if (prazo && t > prazo.getTime() && t - prazo.getTime() <= JANELA_ATRASADA) {
      novo(`${tarefa.id}|atrasada|${tarefa.due_date}T${tarefa.due_time}`, prazo, avisoDeAtraso(tarefa, prazo))
    }
  }

  const hoje = dataLocal(agora)
  const resumo = momentoLocal(hoje, config.resumoDiario)
  if (resumo) {
    const meioDia = momentoLocal(hoje, "12:00")!.getTime()
    const fim = Math.max(meioDia, resumo.getTime() + HORA)
    if (t >= resumo.getTime() && t < fim) novo(`resumo|${hoje}`, resumo, avisoDeResumo(retrato, agora))
  }
  return saida
}

export function podarDisparados(disparados: Record<string, string>, agora: Date): Record<string, string> {
  const limite = agora.getTime() - GUARDA_DISPARADOS
  return Object.fromEntries(Object.entries(disparados).filter(([, momento]) => Date.parse(momento) >= limite))
}

export function novoHorario(para: Adiamento, agora: Date): { data: string; hora: string } {
  if (para === "1h") {
    const depois = new Date(agora.getTime() + HORA)
    return { data: dataLocal(depois), hora: horaLocal(depois) }
  }
  const amanha = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate() + 1, 9, 0)
  return { data: dataLocal(amanha), hora: "09:00" }
}

export function camposDoAdiamento(
  tarefa: Tarefa | undefined,
  campo: Campo,
  novo: { data: string; hora: string },
): Record<string, string | null> {
  if (campo === "prazo") return { due_date: novo.data, due_time: novo.hora }
  const campos: Record<string, string | null> = { scheduled_date: novo.data, scheduled_time: novo.hora }
  const inicio = momentoLocal(tarefa?.scheduled_date, tarefa?.scheduled_time)
  const fim = momentoLocal(tarefa?.scheduled_date, tarefa?.scheduled_end_time)
  if (inicio && fim && fim > inicio) {
    const novoInicio = momentoLocal(novo.data, novo.hora)!
    const novoFim = new Date(novoInicio.getTime() + (fim.getTime() - inicio.getTime()))
    campos.scheduled_end_time = dataLocal(novoFim) === novo.data ? horaLocal(novoFim) : null
  }
  return campos
}

export interface PedidoDeLembrete {
  titulo?: string
  data?: string
  hora?: string
  em_minutos?: number
}

export function validarLembrete(
  pedido: PedidoDeLembrete,
  agora: Date,
): { titulo: string; data: string; hora: string } | { erro: string } {
  const titulo = pedido.titulo?.trim()
  if (!titulo) return { erro: "Falta o título do lembrete." }
  if (pedido.em_minutos !== undefined) {
    if (!Number.isInteger(pedido.em_minutos) || pedido.em_minutos < 1 || pedido.em_minutos > 7 * 24 * 60) {
      return { erro: "em_minutos deve ser um inteiro entre 1 e 10080." }
    }
    const quando = new Date(agora.getTime() + pedido.em_minutos * MINUTO)
    return { titulo, data: dataLocal(quando), hora: horaLocal(quando) }
  }
  if (!pedido.data || !PADRAO_DATA.test(pedido.data)) return { erro: "data deve estar no formato AAAA-MM-DD." }
  if (!pedido.hora || !PADRAO_HORA.test(pedido.hora)) return { erro: "hora deve estar no formato HH:MM (00:00 a 23:59)." }
  const quando = momentoLocal(pedido.data, pedido.hora)
  if (!quando) return { erro: `${pedido.data} não é uma data válida.` }
  if (quando.getTime() < agora.getTime() - MINUTO) {
    return { erro: `Esse horário já passou: agora são ${horaLocal(agora)} de ${dataLocal(agora)}.` }
  }
  return { titulo, data: pedido.data, hora: pedido.hora }
}
