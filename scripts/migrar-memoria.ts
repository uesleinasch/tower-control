#!/usr/bin/env bun
import { conselheiros } from "../app/src/tipos"
import { raizDosDados } from "../app/src/caminhos"
import { memoriaHttp } from "../app/src/memoria/cliente"
import { migrarUma } from "../app/src/memoria/migracao"
import { alterarEstado } from "../app/src/memoria/agenda"
import { espelharColetivo } from "../app/src/memoria/coletivo"

const RAIZ = raizDosDados()
const soVerificar = process.argv.includes("--verificar")
const memoria = memoriaHttp()
let falhou = false

console.log(`dados em ${RAIZ}`)
for (const persona of conselheiros()) {
  if (!soVerificar) console.log(`${persona}: migrando…`)
  const resultado = await migrarUma(RAIZ, memoria, persona, { soVerificar })
  if (resultado === "sem-arquivo") {
    console.log(`${persona}: sem memory.md, nada a migrar`)
  } else if (resultado === "migrada") {
    console.log(soVerificar ? `${persona}: tudo coberto` : `${persona}: migrado e memory.md removido`)
    if (!soVerificar) {
      await alterarEstado(RAIZ, (e) => {
        if (e.migracaoBloqueada) delete e.migracaoBloqueada[persona]
      })
    }
  } else {
    falhou = true
    console.error(`${persona}: ${resultado.faltando.length} item(ns) não apareceram em nenhuma página; memory.md mantido:`)
    for (const item of resultado.faltando) console.error(`  - ${item}`)
  }
}

console.log(`coletivo: ${await espelharColetivo(RAIZ, memoria)} página(s) espelhada(s)`)
process.exit(falhou ? 1 : 0)
