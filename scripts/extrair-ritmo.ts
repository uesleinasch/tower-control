#!/usr/bin/env bun
import { join } from "node:path"
import { readdir } from "node:fs/promises"
import { lerExport, medirCorpus } from "../app/src/ritmo-corpus"

const pasta = process.argv[2] ?? join(import.meta.dir, "..", "conversas")
const destino = join(import.meta.dir, "..", "app", "modelos", "ritmo-corpus.json")

const arquivos = (await readdir(pasta)).filter((n) => n.endsWith(".txt"))
if (!arquivos.length) {
  console.error(`nenhum export .txt em ${pasta}`)
  process.exit(1)
}
const conversas = await Promise.all(arquivos.map(async (n) => lerExport(await Bun.file(join(pasta, n)).text())))
const corpus = medirCorpus(conversas, new Date().toISOString().slice(0, 10))
await Bun.write(destino, `${JSON.stringify(corpus, null, 2)}\n`)
console.log(`${destino}: ${corpus.fonte.mensagens} mensagens de ${corpus.fonte.conversas} conversas`)
console.log(JSON.stringify(corpus, null, 2))
