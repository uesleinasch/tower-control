#!/usr/bin/env bun
import { join } from "node:path"
import { readdir, stat } from "node:fs/promises"
import { raizDosDados } from "../app/src/caminhos"
import { baloesDe, cabeNoOrcamento, carregarRitmo, classificar, orcamento, type Situacao } from "../app/src/ritmo"
import { palavras } from "../app/src/ritmo-corpus"
import { conselheiros } from "../app/src/tipos"

const RAIZ = raizDosDados()
const SEPARADOR_BALAO = /\n\s*-{3,}\s*\n/

interface Mensagem {
  role: string
  texto: string
}

function media(valores: number[]): number {
  return valores.reduce((a, b) => a + b, 0) / valores.length
}

async function conversas(): Promise<string[]> {
  const alvo = process.argv[2]
  if (alvo) return [alvo]
  const nomes = await readdir(join(RAIZ, "conversations"))
  return nomes.filter((n) => n.endsWith(".jsonl")).map((n) => n.replace(/\.jsonl$/, ""))
}

async function medir(id: string): Promise<void> {
  const arquivo = Bun.file(join(RAIZ, "conversations", `${id}.jsonl`))
  if (!(await arquivo.exists())) {
    console.log(`conversa "${id}" não encontrada`)
    return
  }
  const msgs: Mensagem[] = (await arquivo.text())
    .split("\n")
    .filter((linha) => linha.trim())
    .map((linha) => JSON.parse(linha))

  const razoes: number[] = []
  const baloes: number[] = []
  const tamanhos: number[] = []
  let pergunta = 0

  console.log(`\n== ${id}`)
  console.log("turno | pergunta | resposta | balões")
  console.log("------|----------|----------|-------")

  let turno = 0
  for (const msg of msgs) {
    if (msg.role === "user") {
      pergunta = msg.texto.length
      turno++
      continue
    }
    const partes = msg.texto.split(SEPARADOR_BALAO).map((p) => p.trim()).filter(Boolean)
    razoes.push(pergunta ? msg.texto.length / pergunta : 0)
    baloes.push(partes.length)
    tamanhos.push(msg.texto.length)
    console.log(
      `${String(turno).padStart(5)} | ${String(pergunta).padStart(8)} | ` +
        `${String(msg.texto.length).padStart(8)} | ${String(partes.length).padStart(6)}`,
    )
  }

  if (!razoes.length) {
    console.log("(sem resposta do perfil ainda)")
    return
  }

  console.log(`\nturnos: ${razoes.length}`)
  console.log(`razão resposta/pergunta: média ${media(razoes).toFixed(1)}x · máxima ${Math.max(...razoes).toFixed(1)}x`)
  console.log(`tamanho da resposta: mínimo ${Math.min(...tamanhos)} · média ${Math.round(media(tamanhos))} · máximo ${Math.max(...tamanhos)} chars`)
  console.log(`balões: média ${media(baloes).toFixed(1)} · máximo ${Math.max(...baloes)}`)
  console.log(`respostas de 1 balão: ${baloes.filter((b) => b === 1).length} de ${baloes.length}`)
}

const FORMATACAO = /^\s{0,3}#{1,6}\s|^\s*[-*•]\s|\*\*/m

interface Resumo {
  respostas: number
  palavrasMediana: number
  palavrasMedia: number
  baloesMedia: number
  formatadas: number
  noOrcamento: number
}

function mediana(valores: number[]): number {
  const ordenados = [...valores].sort((a, b) => a - b)
  return ordenados[Math.floor(ordenados.length / 2)] ?? 0
}

async function resumirSonda(pasta: string): Promise<Map<string, Record<Situacao, Resumo>>> {
  const resumos = new Map<string, Record<Situacao, Resumo>>()
  for (const persona of conselheiros()) {
    const arquivo = Bun.file(join(pasta, `${persona}.jsonl`))
    if (!(await arquivo.exists())) continue
    const ritmo = await carregarRitmo(RAIZ, persona)
    const msgs: Mensagem[] = (await arquivo.text()).split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l))
    const grupos: Record<Situacao, { palavras: number[]; baloes: number[]; formatadas: number; dentro: number }> = {
      padrao: { palavras: [], baloes: [], formatadas: 0, dentro: 0 },
      profundidade: { palavras: [], baloes: [], formatadas: 0, dentro: 0 },
    }
    let pergunta = ""
    for (const m of msgs) {
      if (m.role === "user") {
        pergunta = m.texto
        continue
      }
      const situacao = classificar(pergunta)
      const g = grupos[situacao]
      g.palavras.push(palavras(m.texto))
      g.baloes.push(baloesDe(m.texto).length)
      if (FORMATACAO.test(m.texto)) g.formatadas++
      if (cabeNoOrcamento(m.texto, orcamento(situacao, ritmo))) g.dentro++
    }
    const resumir = (g: (typeof grupos)[Situacao]): Resumo => ({
      respostas: g.palavras.length,
      palavrasMediana: mediana(g.palavras),
      palavrasMedia: g.palavras.length ? Math.round(media(g.palavras)) : 0,
      baloesMedia: g.baloes.length ? Math.round(media(g.baloes) * 10) / 10 : 0,
      formatadas: g.formatadas,
      noOrcamento: g.palavras.length ? Math.round((g.dentro / g.palavras.length) * 100) : 0,
    })
    resumos.set(persona, { padrao: resumir(grupos.padrao), profundidade: resumir(grupos.profundidade) })
  }
  return resumos
}

function linhaResumo(r: Resumo): string {
  return `${String(r.respostas).padStart(4)} | ${String(r.palavrasMediana).padStart(7)} | ${String(r.palavrasMedia).padStart(5)} | ${String(r.baloesMedia).padStart(6)} | ${String(r.formatadas).padStart(5)} | ${String(r.noOrcamento).padStart(4)}%`
}

async function medirSonda(pastas: string[]): Promise<void> {
  const resumos = await Promise.all(pastas.map(resumirSonda))
  for (const situacao of ["padrao", "profundidade"] as Situacao[]) {
    console.log(`\n== ${situacao}`)
    console.log("persona | rótulo | resp | pal.med | média | balões | form. | orç.")
    for (const persona of conselheiros()) {
      resumos.forEach((r, i) => {
        const dado = r.get(persona)?.[situacao]
        if (dado) console.log(`${persona.padEnd(7)} | ${pastas[i]!.split("/").pop()!.padEnd(6)} | ${linhaResumo(dado)}`)
      })
      if (resumos.length === 2) {
        const [a, b] = resumos.map((r) => r.get(persona)?.[situacao])
        if (a?.palavrasMedia && b) {
          console.log(`${"".padEnd(7)} | saída  | ${Math.round(((b.palavrasMedia - a.palavrasMedia) / a.palavrasMedia) * 100)}% palavras por resposta`)
        }
      }
    }
  }
}

async function ehPasta(caminho: string | undefined): Promise<boolean> {
  if (!caminho) return false
  try {
    return (await stat(caminho)).isDirectory()
  } catch {
    return false
  }
}

if (await ehPasta(process.argv[2])) await medirSonda(process.argv.slice(2))
else for (const id of await conversas()) await medir(id)
