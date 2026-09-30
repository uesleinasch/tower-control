#!/usr/bin/env bun
import { memoriaHttp, URL_PADRAO } from "../app/src/memoria/cliente"
import { montarBrief } from "../app/src/memoria/recuperacao"
import type { Projeto } from "../app/src/memoria/tipos"

const memoria = memoriaHttp()
const projeto = "smoke" as Projeto
const path = "fatos/smoke-control-tower.md"
const marca = `marca-${Date.now().toString(36)}`

function passo(nome: string, ok: boolean, detalhe = ""): void {
  console.log(`${ok ? "ok  " : "FALHOU"} ${nome}${detalhe ? ` — ${detalhe}` : ""}`)
  if (!ok) process.exitCode = 1
}

console.log(`ai-memory em ${URL_PADRAO}`)

await memoria.gravar(projeto, { path, corpo: `# Smoke\n\nteste ${marca}\n`, tier: "semantic", pinned: false, tags: ["origem:smoke"] })
passo("gravar", true)

const lida = await memoria.ler(projeto, path)
passo("ler", lida?.corpo.includes(marca) === true, lida ? `tier ${lida.tier}, pinned ${lida.pinned}` : "página não voltou")

const lista = await memoria.listar(projeto)
passo("listar", lista.some((r) => r.path === path), `${lista.length} página(s)`)

const achados = await memoria.buscar(projeto, marca, 5)
passo("buscar", achados.some((t) => t.path === path), `${achados.length} trecho(s)`)

const frias = await memoria.frias(projeto, 5).catch((e: Error) => e)
passo("frias", Array.isArray(frias), Array.isArray(frias) ? `${frias.length} fria(s)` : frias.message)

const frase = process.argv.slice(2).join(" ") || "como você está?"
console.log(`\nbrief do Poe para "${frase}":\n`)
console.log((await montarBrief(memoria, "poe", frase)) || "(vazio)")
