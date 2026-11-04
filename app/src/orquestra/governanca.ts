import { custosPorConsulta, type RegistroDeUso } from "../uso"
import type { Posicao } from "./equipe"
import type { Registro } from "./tarefa"

export const TUDO = "*"
export const LIMIAR_DE_ALERTA = 0.8
export const PROFUNDIDADE_MAXIMA = 3
export const SUBTAREFAS_ABERTAS_MAXIMAS = 5

export type NivelDoOrcamento = "alerta" | "estourado"
export type MotivoDeBloqueio = "tudo" | "ueslei" | "orcamento"

export interface Gasto {
  tarefas: number
  total: number
  tokensTarefas: number
  tokensTotal: number
}

export type Dimensao = "usd" | "tokens"

export interface Limites {
  usd?: number
  tokens?: number
}

const SEM_GASTO: Gasto = { tarefas: 0, total: 0, tokensTarefas: 0, tokensTotal: 0 }

export function tokensDe(r: Pick<RegistroDeUso, "entrada" | "escritaCache" | "leituraCache" | "saida">): number {
  return (r.entrada ?? 0) + (r.escritaCache ?? 0) + (r.leituraCache ?? 0) + (r.saida ?? 0)
}

export function formatarTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1).replace(".", ",")} mi tokens`
  if (n >= 1_000) return `${Math.round(n / 1_000)} mil tokens`
  return `${Math.round(n)} tokens`
}

export function mesDe(quando: Date | string): string {
  const d = new Date(quando)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`
}

export function gastosDoMes(registros: RegistroDeUso[], mes: string): Map<string, Gasto> {
  const custos = custosPorConsulta(registros)
  const gastos = new Map<string, Gasto>()
  registros.forEach((r, i) => {
    if (!r.perfil || mesDe(r.ts) !== mes) return
    const custo = custos[i] ?? 0
    const tokens = tokensDe(r)
    const g = gastos.get(r.perfil) ?? { ...SEM_GASTO }
    g.total += custo
    g.tokensTotal += tokens
    if (r.tipo === "tarefa") {
      g.tarefas += custo
      g.tokensTarefas += tokens
    }
    gastos.set(r.perfil, g)
  })
  return gastos
}

export class Contas {
  private registros: RegistroDeUso[] = []
  private cache: { mes: string; tamanho: number; gastos: Map<string, Gasto> } | undefined

  carregar(registros: RegistroDeUso[]): void {
    this.registros = [...registros]
    this.cache = undefined
  }

  registrar(registro: RegistroDeUso): void {
    this.registros.push(registro)
  }

  gasto(persona: string, agora = new Date()): Gasto {
    const mes = mesDe(agora)
    if (!this.cache || this.cache.mes !== mes || this.cache.tamanho !== this.registros.length) {
      this.cache = { mes, tamanho: this.registros.length, gastos: gastosDoMes(this.registros, mes) }
    }
    return this.cache.gastos.get(persona) ?? { ...SEM_GASTO }
  }
}

export function nivelDoOrcamento(gasto: number, limite: number | undefined): NivelDoOrcamento | null {
  if (limite === undefined) return null
  if (gasto >= limite) return "estourado"
  if (gasto >= limite * LIMIAR_DE_ALERTA) return "alerta"
  return null
}

export function niveisDoOrcamento(gasto: Gasto, limites: Limites): Record<Dimensao, NivelDoOrcamento | null> {
  return {
    usd: nivelDoOrcamento(gasto.tarefas, limites.usd),
    tokens: nivelDoOrcamento(gasto.tokensTarefas, limites.tokens),
  }
}

export function motivoDeBloqueio(
  persona: string,
  pausas: ReadonlySet<string>,
  gasto: Gasto,
  limites: Limites,
): MotivoDeBloqueio | null {
  if (pausas.has(TUDO)) return "tudo"
  if (pausas.has(persona)) return "ueslei"
  const niveis = niveisDoOrcamento(gasto, limites)
  if (niveis.usd === "estourado" || niveis.tokens === "estourado") return "orcamento"
  return null
}

function ultimoIndice(registros: Registro[], tipo: Registro["tipo"]): number {
  for (let i = registros.length - 1; i >= 0; i--) if (registros[i]!.tipo === tipo) return i
  return -1
}

export function precisaDePlano(posicao: Pick<Posicao, "aprovarPlano">, registros: Registro[]): boolean {
  if (!posicao.aprovarPlano) return false
  const plano = ultimoIndice(registros, "plano")
  return plano < 0 || ultimoIndice(registros, "plano-aprovado") < plano
}

export function planoAprovado(registros: Registro[]): string | null {
  const plano = ultimoIndice(registros, "plano")
  return plano >= 0 && ultimoIndice(registros, "plano-aprovado") > plano ? registros[plano]!.texto : null
}

export function planoPendente(registros: Registro[]): boolean {
  const plano = ultimoIndice(registros, "plano")
  return plano >= 0 && ultimoIndice(registros, "plano-aprovado") < plano
}

export function recusaDeDelegacao(profundidadeDaNova: number, abertasDaMae: number): string | null {
  if (profundidadeDaNova > PROFUNDIDADE_MAXIMA) {
    return `Não dá para delegar mais fundo: já são ${PROFUNDIDADE_MAXIMA} níveis de subtarefa. Faça você mesma, entregue ou peça ajuda.`
  }
  if (abertasDaMae >= SUBTAREFAS_ABERTAS_MAXIMAS) {
    return `Esta tarefa já tem ${SUBTAREFAS_ABERTAS_MAXIMAS} subtarefas abertas. Espere alguma terminar, entregue ou peça ajuda.`
  }
  return null
}
