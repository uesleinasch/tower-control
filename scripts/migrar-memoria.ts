#!/usr/bin/env bun
import { join } from "node:path"
import { rm } from "node:fs/promises"
import { CONSELHEIROS } from "../app/src/tipos"
import { memoriaHttp } from "../app/src/memoria/cliente"
import { corposDaPersona, itensNaoCobertos, migrarPersona } from "../app/src/memoria/migracao"
import { espelharColetivo } from "../app/src/memoria/coletivo"

const RAIZ = join(import.meta.dir, "..")
const verificar = process.argv.includes("--verificar")
const memoria = memoriaHttp()
let falhou = false

for (const persona of CONSELHEIROS) {
  const caminho = join(RAIZ, "profiles", persona, "memory.md")
  const arquivo = Bun.file(caminho)
  if (!(await arquivo.exists())) {
    console.log(`${persona}: sem memory.md, nada a migrar`)
    continue
  }
  const memoriaMd = await arquivo.text()

  if (!verificar) {
    console.log(`${persona}: migrando…`)
    await migrarPersona(RAIZ, memoria, persona, memoriaMd)
  }

  const faltando = itensNaoCobertos(memoriaMd, await corposDaPersona(memoria, persona))
  if (faltando.length) {
    falhou = true
    console.error(`${persona}: ${faltando.length} item(ns) não apareceram em nenhuma página; memory.md mantido:`)
    for (const item of faltando) console.error(`  - ${item}`)
    continue
  }
  if (verificar) {
    console.log(`${persona}: tudo coberto`)
    continue
  }
  await rm(caminho)
  console.log(`${persona}: migrado e memory.md removido`)
}

console.log(`coletivo: ${await espelharColetivo(RAIZ, memoria)} página(s) espelhada(s)`)
process.exit(falhou ? 1 : 0)
