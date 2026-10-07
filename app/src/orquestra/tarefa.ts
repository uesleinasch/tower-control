import type { Equipe } from "./equipe"

export type StatusTarefa = "backlog" | "a_fazer" | "em_andamento" | "em_revisao" | "bloqueada" | "concluida" | "cancelada"

export const STATUS: readonly StatusTarefa[] = [
  "backlog",
  "a_fazer",
  "em_andamento",
  "em_revisao",
  "bloqueada",
  "concluida",
  "cancelada",
]

export interface Tarefa {
  id: number
  equipe: string
  posicao: string
  titulo: string
  descricao: string
  porque: string
  pai: number | null
  status: StatusTarefa
  dono: string | null
  criadaPor: string
  criadaEm: string
  atualizadaEm: string
  dependeDe: number[]
}

export interface Registro {
  id: number
  tarefa: number
  tipo: "comentario" | "status"
  autor: string
  texto: string
  em: string
}

export interface NovaTarefa {
  equipe: string
  posicao: string
  titulo: string
  descricao: string
  porque: string
  pai: number | null
  dependeDe: number[]
  status: StatusTarefa
}

const TRANSICOES: Record<StatusTarefa, readonly StatusTarefa[]> = {
  backlog: ["a_fazer", "cancelada"],
  a_fazer: ["em_andamento", "backlog", "bloqueada", "cancelada"],
  em_andamento: ["em_revisao", "concluida", "bloqueada", "a_fazer", "cancelada"],
  em_revisao: ["concluida", "em_andamento", "cancelada"],
  bloqueada: ["a_fazer", "cancelada"],
  concluida: ["a_fazer"],
  cancelada: ["backlog"],
}

export const NOMES_DE_STATUS: Record<StatusTarefa, string> = {
  backlog: "backlog",
  a_fazer: "a fazer",
  em_andamento: "em andamento",
  em_revisao: "em revisão",
  bloqueada: "bloqueada",
  concluida: "concluída",
  cancelada: "cancelada",
}

export function statusValido(valor: unknown): valor is StatusTarefa {
  return STATUS.includes(valor as StatusTarefa)
}

export function podeMudar(de: StatusTarefa, para: StatusTarefa): boolean {
  return TRANSICOES[de].includes(para)
}

// Só dá para começar quando tudo de que a tarefa depende já foi concluído.
export function exigirMudanca(tarefa: Tarefa, para: StatusTarefa, statusDasDependencias: StatusTarefa[]): void {
  if (!podeMudar(tarefa.status, para)) {
    throw new Error(`tarefa ${tarefa.id}: não dá para ir de ${NOMES_DE_STATUS[tarefa.status]} para ${NOMES_DE_STATUS[para]}`)
  }
  if (para === "em_andamento" && statusDasDependencias.some((s) => s !== "concluida")) {
    throw new Error(`tarefa ${tarefa.id}: ainda depende de tarefa não concluída`)
  }
}

function texto(valor: unknown, limite: number): string {
  return typeof valor === "string" ? valor.trim().slice(0, limite) : ""
}

function ids(valor: unknown): number[] {
  if (!Array.isArray(valor)) return []
  return [...new Set(valor.map(Number).filter((n) => Number.isInteger(n) && n > 0))]
}

export function lerNovaTarefa(bruto: unknown, equipes: (id: string) => Equipe | undefined): NovaTarefa {
  const t = (bruto && typeof bruto === "object" ? bruto : {}) as Record<string, unknown>
  const equipe = equipes(String(t.equipe ?? ""))
  if (!equipe) throw new Error("equipe desconhecida")
  const posicao = equipe.posicoes.find((p) => p.id === t.posicao)
  if (!posicao) throw new Error(`a equipe ${equipe.nome} não tem a posição ${String(t.posicao)}`)
  const titulo = texto(t.titulo, 200)
  if (!titulo) throw new Error("a tarefa precisa de um título")
  const pai = t.pai === null || t.pai === undefined || t.pai === "" ? null : Number(t.pai)
  if (pai !== null && !(Number.isInteger(pai) && pai > 0)) throw new Error("tarefa-pai inválida")
  const status = t.status === undefined ? "a_fazer" : t.status
  if (status !== "a_fazer" && status !== "backlog") throw new Error("tarefa nova começa em backlog ou a fazer")
  return {
    equipe: equipe.id,
    posicao: posicao.id,
    titulo,
    descricao: texto(t.descricao, 20_000),
    porque: texto(t.porque, 4_000),
    pai,
    dependeDe: ids(t.dependeDe),
    status,
  }
}
