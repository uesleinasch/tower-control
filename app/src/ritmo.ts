import { join } from "node:path"
import corpusEmbutido from "../modelos/ritmo-corpus.json"
import ritmoPoe from "../modelos/profiles/poe/ritmo.json"
import ritmoNati from "../modelos/profiles/nati/ritmo.json"
import ritmoLucas from "../modelos/profiles/lucas/ritmo.json"
import ritmoPami from "../modelos/profiles/pami/ritmo.json"
import { RISADA, palavras, type RitmoCorpus } from "./ritmo-corpus"
import type { Conselheiro } from "./tipos"

export type Situacao = "padrao" | "profundidade"
export type Risada = "nunca" | "rara" | "as-vezes"

export interface RitmoPersona {
  baloes: number
  palavras: number
  risada: Risada
  minusculas: boolean
  pontoFinal: boolean
}

export interface Orcamento {
  situacao: Situacao
  baloes: [number, number]
  palavrasPorBalao: number
}

export const CORPUS = corpusEmbutido as RitmoCorpus
export const RITMO_NEUTRO: RitmoPersona = { baloes: 1, palavras: 1, risada: "rara", minusculas: false, pontoFinal: false }
const RISADAS: readonly Risada[] = ["nunca", "rara", "as-vezes"]
const EMBUTIDOS: Record<Conselheiro, unknown> = { poe: ritmoPoe, nati: ritmoNati, lucas: ritmoLucas, pami: ritmoPami }

export const SEPARADOR_BALAO = /\n\s*-{3,}\s*\n/

function limitar(valor: number, minimo: number, maximo: number): number {
  return Math.min(maximo, Math.max(minimo, valor))
}

function multiplicador(valor: unknown): number {
  return typeof valor === "number" && Number.isFinite(valor) ? limitar(valor, 0.5, 2) : 1
}

export function lerRitmo(bruto: unknown): RitmoPersona {
  if (!bruto || typeof bruto !== "object") return RITMO_NEUTRO
  const r = bruto as Record<string, unknown>
  return {
    baloes: multiplicador(r.baloes),
    palavras: multiplicador(r.palavras),
    risada: RISADAS.includes(r.risada as Risada) ? (r.risada as Risada) : RITMO_NEUTRO.risada,
    minusculas: typeof r.minusculas === "boolean" ? r.minusculas : RITMO_NEUTRO.minusculas,
    pontoFinal: typeof r.pontoFinal === "boolean" ? r.pontoFinal : RITMO_NEUTRO.pontoFinal,
  }
}

export async function carregarRitmo(raiz: string, persona: Conselheiro): Promise<RitmoPersona> {
  try {
    const arquivo = Bun.file(join(raiz, "profiles", persona, "ritmo.json"))
    if (await arquivo.exists()) return lerRitmo(await arquivo.json())
  } catch {
    return RITMO_NEUTRO
  }
  return lerRitmo(EMBUTIDOS[persona])
}

const PEDIDO_DE_PROFUNDIDADE =
  /\b(me explica|explica|explique|detalh\w*|aprofund\w*|compar\w*|pr[óo]s e contras|passo a passo|an[áa]lis\w*|em detalhes?)\b/i

export function classificar(mensagem: string): Situacao {
  if (PEDIDO_DE_PROFUNDIDADE.test(mensagem)) return "profundidade"
  const perguntas = (mensagem.match(/\?/g) ?? []).length
  return palavras(mensagem) > 60 && perguntas >= 2 ? "profundidade" : "padrao"
}

export function orcamento(situacao: Situacao, ritmo: RitmoPersona, corpus: RitmoCorpus = CORPUS): Orcamento {
  const porBalao = Math.max(3, Math.round(corpus.palavrasPorBalao.p90 * ritmo.palavras))
  if (situacao === "profundidade") return { situacao, baloes: [3, 6], palavrasPorBalao: porBalao * 3 }
  const maximo = limitar(Math.round(corpus.baloesPorResposta.p50 * ritmo.baloes) + 1, 1, Math.max(1, corpus.baloesPorResposta.p90))
  return { situacao, baloes: [1, maximo], palavrasPorBalao: porBalao }
}

const TRACO_RISADA: Record<Risada, string> = {
  nunca: "Não use kkk nem risada escrita.",
  rara: "Risada escrita (kkk) só de vez em quando, quando algo for engraçado de verdade.",
  "as-vezes": "Quando algo for engraçado, ria como no chat (kkkk), sem forçar.",
}

export function blocoDeEscrita(o: Orcamento, ritmo: RitmoPersona): string {
  const [min, max] = o.baloes
  const forma =
    o.situacao === "profundidade"
      ? `Ele pediu profundidade: de ${min} a ${max} balões, cada um com até ~${o.palavrasPorBalao} palavras. Diga o que importa por inteiro, mas isto ainda é chat, não documento.`
      : `Escreva como no WhatsApp: de ${min} a ${max} balões, cada um com até ~${o.palavrasPorBalao} palavras. Uma reação curta ("boa", "eita", "faz sentido") já é resposta inteira quando basta. Opinião também cabe curta: diga o que acha numa frase; se ele quiser o porquê, ele pergunta.`
  return `## Como escrever

${forma}
- Um pensamento por balão. Para separar balões, uma linha contendo apenas "---".
- Nada de título, lista, negrito, nem fechamento oferecendo ajuda. Não resuma o que ele acabou de dizer.
- ${TRACO_RISADA[ritmo.risada]}
- ${ritmo.minusculas ? "Pode começar balão com minúscula." : "Comece balão com maiúscula."} ${ritmo.pontoFinal ? "Ponto final quando fizer falta." : "Não termine balão com ponto final."}`
}

export function lembreteDeForma(o: Orcamento): string {
  const [min, max] = o.baloes
  return o.situacao === "profundidade"
    ? `(pode aprofundar: ${min} a ${max} balões de até ~${o.palavrasPorBalao} palavras, ainda como chat)`
    : `(responda como no chat: até ${max} balão(ões) de no máximo ~${o.palavrasPorBalao} palavras)`
}

const CERCA = /^\s*```/
const SEPARADOR = /^\s*-{3,}\s*$/
const TITULO = /^\s{0,3}#{1,6}\s+/
const MARCADOR = /^\s*[-*•]\s+/
const INICIO_AMBIGUO = /^\s*[#*•`-]/

type Peca = { quebra: true } | { quebra: false; texto: string }

function limparLinha(linha: string): string {
  return linha.replace(TITULO, "").replace(MARCADOR, "").replace(/\*\*/g, "").trimEnd()
}

// No modo parcial a saída precisa ser prefixo da saída final: por isso a última linha,
// ainda incompleta, só entra quando não há como ela mudar de natureza.
function ambigua(linha: string, dentroDeCodigo: boolean): boolean {
  if (!linha.trim()) return true
  if (/^\s*`/.test(linha)) return true
  if (dentroDeCodigo) return false
  if (/^\s*-+\s*$/.test(linha)) return true
  return INICIO_AMBIGUO.test(linha) && linha.length < 8
}

export function normalizar(texto: string, parcial = false): string {
  const linhas = texto.replace(/\r\n?/g, "\n").split("\n")
  const incompleta = parcial ? (linhas.pop() ?? "") : undefined
  const pecas: Peca[] = []
  let dentroDeCodigo = false

  for (const linha of linhas) {
    if (CERCA.test(linha)) {
      dentroDeCodigo = !dentroDeCodigo
      pecas.push({ quebra: false, texto: linha.trimEnd() })
    } else if (dentroDeCodigo) {
      pecas.push({ quebra: false, texto: linha })
    } else {
      const limpa = limparLinha(linha)
      pecas.push(SEPARADOR.test(linha) || !limpa.trim() ? { quebra: true } : { quebra: false, texto: limpa })
    }
  }
  if (incompleta !== undefined && !ambigua(incompleta, dentroDeCodigo)) {
    const limpa = (dentroDeCodigo ? incompleta : limparLinha(incompleta)).replace(/\*+$/, "").trimEnd()
    if (limpa.trim()) pecas.push({ quebra: false, texto: limpa })
  }

  let saida = ""
  let quebraPendente = false
  for (const peca of pecas) {
    if (peca.quebra) {
      quebraPendente = saida !== ""
      continue
    }
    if (saida) saida += quebraPendente ? "\n---\n" : "\n"
    saida += peca.texto
    quebraPendente = false
  }
  return saida
}

export function normalizadorDeStream(emitir: (pedaco: string) => void) {
  let bruto = ""
  let emitido = ""
  function avancar(alvo: string): void {
    if (alvo.length > emitido.length && alvo.startsWith(emitido)) {
      emitir(alvo.slice(emitido.length))
      emitido = alvo
    }
  }
  return {
    receber(pedaco: string): void {
      bruto += pedaco
      avancar(normalizar(bruto, true))
    },
    finalizar(): string {
      const final = normalizar(bruto)
      avancar(final)
      return final
    },
  }
}

export function baloesDe(texto: string): string[] {
  return texto
    .split(SEPARADOR_BALAO)
    .map((b) => b.trim())
    .filter(Boolean)
}

export function cabeNoOrcamento(texto: string, o: Orcamento): boolean {
  const baloes = baloesDe(texto)
  const teto = Math.ceil(o.palavrasPorBalao * 1.5)
  return baloes.length <= o.baloes[1] && baloes.every((b) => palavras(b) <= teto)
}

export type Reacao = "riu" | "confuso" | "pediu-curto" | "engajou" | "neutra"

const PEDIU_CURTO = /\b(resum\w*|muito longo|longo demais|text[ãa]o|mais curto|menos texto|direto ao ponto|vai direto)\b/i
const CONFUSO = /^\s*\?+\s*$|\bn[ãa]o entendi\b|\bcomo assim\b/i

export function reacaoDoUeslei(texto: string): Reacao {
  if (PEDIU_CURTO.test(texto)) return "pediu-curto"
  if (CONFUSO.test(texto)) return "confuso"
  if (RISADA.test(texto)) return "riu"
  if (palavras(texto) >= 15) return "engajou"
  return "neutra"
}

function mediana(valores: number[]): number {
  const ordenados = [...valores].sort((a, b) => a - b)
  return ordenados[Math.floor(ordenados.length / 2)] ?? 0
}

export function espelho(
  mensagens: { role: string; texto: string }[],
  ritmo: RitmoPersona,
  corpus: RitmoCorpus = CORPUS,
): string {
  const contagem: Record<Reacao, number> = { riu: 0, confuso: 0, "pediu-curto": 0, engajou: 0, neutra: 0 }
  const baloesPorResposta: number[] = []
  const palavrasPorBalao: number[] = []
  let passaram = 0
  let ultimaDoUeslei = ""
  let respondeuAgora = false

  for (const m of mensagens) {
    if (m.role === "user") {
      if (respondeuAgora) contagem[reacaoDoUeslei(m.texto)]++
      ultimaDoUeslei = m.texto
      respondeuAgora = false
      continue
    }
    const baloes = baloesDe(m.texto)
    baloesPorResposta.push(baloes.length)
    palavrasPorBalao.push(...baloes.map(palavras))
    if (!cabeNoOrcamento(m.texto, orcamento(classificar(ultimaDoUeslei), ritmo, corpus))) passaram++
    respondeuAgora = true
  }
  if (!baloesPorResposta.length) return ""

  const alvo = orcamento("padrao", ritmo, corpus)
  const reacoes = Object.values(contagem).some(Boolean)
    ? `\nComo o Ueslei reagiu logo depois: riu ${contagem.riu} · ficou confuso ${contagem.confuso} · pediu mais curto ${contagem["pediu-curto"]} · respondeu longo ${contagem.engajou} · neutro ${contagem.neutra}.`
    : ""
  return `## Espelho da sua escrita

Suas falas: ${baloesPorResposta.length} resposta(s), mediana de ${mediana(baloesPorResposta)} balão(ões) e ${mediana(palavrasPorBalao)} palavra(s) por balão (seu alvo no dia a dia: até ${alvo.baloes[1]} balões de ~${alvo.palavrasPorBalao} palavras). Passaram do ponto: ${passaram} de ${baloesPorResposta.length}.${reacoes}`
}
