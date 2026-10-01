export interface MensagemDoExport {
  autor: string
  texto: string
}

export interface Quantis {
  p10: number
  p50: number
  p90: number
}

export interface RitmoCorpus {
  fonte: { conversas: number; mensagens: number; geradoEm: string }
  palavrasPorBalao: Quantis
  baloesPorResposta: Quantis
  palavrasPorResposta: Quantis
  tracos: {
    reacaoCurta: number
    risada: number
    pontoFinal: number
    inicioMinusculo: number
    perguntaSolta: number
  }
}

const LINHA = /^(\d{2}\/\d{2}\/\d{2,4}),? (\d{2}:\d{2})(?::\d{2})? - ([^:]+): (.*)$/
const DESCARTE = /^<m[íi]dia oculta>$|^<media omitted>$|^mensagem apagada$|^esta mensagem foi apagada$|^this message was deleted$/i
const EDITADA = /\s*<mensagem editada>\s*$/i

export const RISADA = /k{3,}|(?:ha){2,}|\bh[sj][hsj]{2,}|\brs+\b/i

export function palavras(texto: string): number {
  return texto.split(/\s+/).filter(Boolean).length
}

export function lerExport(conteudo: string): MensagemDoExport[] {
  const mensagens: MensagemDoExport[] = []
  for (const bruta of conteudo.replace(/\r\n?/g, "\n").replace(/[‎‏]/g, "").split("\n")) {
    const casou = LINHA.exec(bruta)
    if (casou) mensagens.push({ autor: casou[3]!.trim(), texto: casou[4]! })
    else if (mensagens.length) mensagens[mensagens.length - 1]!.texto += `\n${bruta}`
  }
  return mensagens
    .map((m) => ({ autor: m.autor, texto: m.texto.replace(EDITADA, "").trim() }))
    .filter((m) => m.texto && !DESCARTE.test(m.texto))
}

export function rajadas(mensagens: MensagemDoExport[]): string[][] {
  const grupos: { autor: string; baloes: string[] }[] = []
  for (const m of mensagens) {
    const ultimo = grupos[grupos.length - 1]
    if (ultimo && ultimo.autor === m.autor) ultimo.baloes.push(m.texto)
    else grupos.push({ autor: m.autor, baloes: [m.texto] })
  }
  return grupos.map((g) => g.baloes)
}

function quantis(valores: number[]): Quantis {
  const ordenados = [...valores].sort((a, b) => a - b)
  const em = (p: number) => ordenados[Math.min(ordenados.length - 1, Math.floor(ordenados.length * p))] ?? 0
  return { p10: em(0.1), p50: em(0.5), p90: em(0.9) }
}

function taxa(parte: number, total: number): number {
  return total ? Math.round((parte / total) * 1000) / 1000 : 0
}

export function medirCorpus(conversas: MensagemDoExport[][], geradoEm: string): RitmoCorpus {
  const respostas = conversas.flatMap(rajadas)
  const baloes = respostas.flat()
  const contar = (teste: (b: string) => boolean) => baloes.filter(teste).length
  return {
    fonte: { conversas: conversas.length, mensagens: baloes.length, geradoEm },
    palavrasPorBalao: quantis(baloes.map(palavras)),
    baloesPorResposta: quantis(respostas.map((r) => r.length)),
    palavrasPorResposta: quantis(respostas.map((r) => r.reduce((s, b) => s + palavras(b), 0))),
    tracos: {
      reacaoCurta: taxa(contar((b) => palavras(b) <= 2), baloes.length),
      risada: taxa(respostas.filter((r) => r.some((b) => RISADA.test(b))).length, respostas.length),
      pontoFinal: taxa(contar((b) => /[^.]\.$/.test(b)), baloes.length),
      inicioMinusculo: taxa(contar((b) => /^\p{Ll}/u.test(b)), baloes.length),
      perguntaSolta: taxa(contar((b) => palavras(b) <= 3 && b.endsWith("?")), baloes.length),
    },
  }
}
