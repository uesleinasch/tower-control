#!/usr/bin/env bun
import { join } from "node:path"
import { mkdir } from "node:fs/promises"
import { raizDosDados } from "../app/src/caminhos"
import { conversar } from "../app/src/sessions"
import { apagarSessao } from "../app/src/sessao-sdk"
import { conselheiros, type Conselheiro } from "../app/src/tipos"

const rotulo = process.argv[2]
if (!rotulo || !/^[a-z0-9-]+$/.test(rotulo)) {
  console.error("uso: bun run scripts/sondar-ritmo.ts <rótulo> [persona...]")
  process.exit(1)
}
const pedidas = process.argv.slice(3) as Conselheiro[]
const personas = pedidas.length ? pedidas : conselheiros()

const RAIZ = raizDosDados()
const sonda = (await Bun.file(join(import.meta.dir, "sonda-ritmo.txt")).text())
  .split("\n")
  .map((l) => l.trim())
  .filter(Boolean)
const saida = join(import.meta.dir, "saida-sonda", rotulo)
await mkdir(saida, { recursive: true })

async function sondar(persona: Conselheiro): Promise<void> {
  const linhas: string[] = []
  for (const texto of sonda) {
    try {
      const resposta = await conversar({ raiz: RAIZ, perfil: persona, texto, onChunk: () => {} })
      if (resposta.sessionId) await apagarSessao(RAIZ, resposta.sessionId)
      linhas.push(JSON.stringify({ role: "user", texto }), JSON.stringify({ role: "assistant", texto: resposta.texto }))
    } catch (erro) {
      console.error(`[${persona}] "${texto}": ${erro}`)
    }
  }
  await Bun.write(join(saida, `${persona}.jsonl`), linhas.join("\n") + "\n")
  console.log(`[${persona}] ${linhas.length / 2} respostas`)
}

await Promise.all(personas.map(sondar))
