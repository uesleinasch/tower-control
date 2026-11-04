import type { Equipe, Etapa } from "./equipe"
import type { Registro, Tarefa } from "./tarefa"

export const VOLTAS_MAXIMAS = 3
export const CHAVE_DO_BOARD = "@board"
export const SEM_DECISAO = "a revisão terminou sem decisão"

export type Destino = { tipo: "etapa"; etapa: number } | { tipo: "concluida" } | { tipo: "ueslei" }
export type Decisor = { tipo: "posicao"; posicao: string } | { tipo: "board" } | { tipo: "ueslei" }
export type Decisao = { tipo: "aprovar" | "mudanca"; texto: string }

export function quemDecide(etapa: Etapa): Decisor {
  if ("posicao" in etapa.por) return { tipo: "posicao", posicao: etapa.por.posicao }
  return "board" in etapa.por ? { tipo: "board" } : { tipo: "ueslei" }
}

export function aposEntrega(politica: Etapa[], retorno: number | null): Destino {
  if (!politica.length) return { tipo: "ueslei" }
  return { tipo: "etapa", etapa: retorno !== null && retorno < politica.length ? retorno : 0 }
}

export function aposAprovar(politica: Etapa[], etapa: number): Destino {
  return etapa + 1 < politica.length ? { tipo: "etapa", etapa: etapa + 1 } : { tipo: "concluida" }
}

// As voltas contam só os pedidos da etapa que recebe a próxima entrega; o do Ueslei não conta.
export function aposMudanca(
  tarefa: Pick<Tarefa, "retorno" | "voltas">,
  etapa: number,
  peloUeslei: boolean,
): { retorno: number; voltas: number; estourou: boolean } {
  const anteriores = tarefa.retorno === etapa ? tarefa.voltas : 0
  const voltas = peloUeslei ? anteriores : anteriores + 1
  return { retorno: etapa, voltas, estourou: voltas > VOLTAS_MAXIMAS }
}

export function etapaAtual(tarefa: Pick<Tarefa, "status" | "etapa" | "politica">): Etapa | undefined {
  return tarefa.status === "em_revisao" && tarefa.etapa !== null ? tarefa.politica[tarefa.etapa] : undefined
}

export function etapaDoUeslei(tarefa: Pick<Tarefa, "status" | "etapa" | "politica">): boolean {
  const etapa = etapaAtual(tarefa)
  return etapa !== undefined && quemDecide(etapa).tipo === "ueslei"
}

export function ultimaEntrega(registros: Registro[]): Registro | undefined {
  return registros.findLast((r) => r.tipo === "entrega")
}

export function membrosDoBoard(equipe: Equipe, executora: string | null): string[] {
  return equipe.posicoes
    .filter((p) => p.capacidades.includes("board") && p.persona !== null && p.persona !== executora)
    .map((p) => p.persona!)
}

export function nomeDoDecisor(etapa: Etapa, equipe: Equipe | undefined, nome: (persona: string) => string): string {
  const decisor = quemDecide(etapa)
  if (decisor.tipo === "board") return "o board"
  if (decisor.tipo === "ueslei") return "o Ueslei"
  const posicao = equipe?.posicoes.find((p) => p.id === decisor.posicao)
  return posicao?.persona ? nome(posicao.persona) : `${posicao?.titulo ?? decisor.posicao} (vaga)`
}

export function descreverEtapa(etapa: Etapa, equipe: Equipe | undefined, nome: (persona: string) => string): string {
  const quem = nomeDoDecisor(etapa, equipe, nome)
  return `${etapa.tipo === "revisao" ? "revisão" : "aprovação"} ${quem.startsWith("o ") ? `d${quem}` : `de ${quem}`}`
}

export function comQuem(
  tarefa: Pick<Tarefa, "status" | "etapa" | "politica">,
  equipe: Equipe | undefined,
  nome: (persona: string) => string,
): string | null {
  if (tarefa.status !== "em_revisao") return null
  const etapa = etapaAtual(tarefa)
  if (!etapa || quemDecide(etapa).tipo === "ueslei") return "com você"
  return `com ${nomeDoDecisor(etapa, equipe, nome)}`
}

const LINHA_DE_DECISAO = /^[\s*_#>-]*DECIS[AÃ]O:\s*\**\s*(aprovar|mudan[cç]a)\b/gim

export function decisaoDaSintese(sintese: string): Decisao["tipo"] | null {
  const linhas = [...sintese.matchAll(LINHA_DE_DECISAO)]
  const ultima = linhas.at(-1)?.[1]?.toLowerCase()
  if (!ultima) return null
  return ultima === "aprovar" ? "aprovar" : "mudanca"
}
