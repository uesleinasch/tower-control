#!/usr/bin/env bun
import { join } from "node:path"
import { readdir } from "node:fs/promises"
import { raizDosDados } from "../app/src/caminhos"

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

for (const id of await conversas()) await medir(id)
