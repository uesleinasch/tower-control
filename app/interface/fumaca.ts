import { mkdtemp, readFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { subirAmbiente } from "./ambiente"
import type { PedidoRecebido, Regra } from "./falsos/roteiro"

const PRAZO_MS = 60_000

async function falar(ambiente: { servidor: string; pasta: string }): Promise<void> {
  const alvo = join(ambiente.pasta, "fumaca.txt")
  let pediuPermissao = false
  const ws = new WebSocket(`${ambiente.servidor.replace("http", "ws")}/ws`)
  await new Promise<void>((ok, falha) => {
    const prazo = setTimeout(() => falha(new Error("a fumaça não terminou no prazo")), PRAZO_MS)
    ws.onerror = () => falha(new Error("erro no WebSocket"))
    ws.onopen = () => ws.send(JSON.stringify({ tipo: "nova", perfil: "alfred", texto: "rode o comando" }))
    ws.onmessage = (evento) => {
      const mensagem = JSON.parse(String(evento.data))
      if (mensagem.tipo === "permissao") {
        if (!String(mensagem.comando).includes(alvo)) return falha(new Error(`comando inesperado: ${mensagem.comando}`))
        pediuPermissao = true
        ws.send(JSON.stringify({ tipo: "permissao-resposta", id: mensagem.id, permitido: true }))
      } else if (mensagem.tipo === "fim") {
        clearTimeout(prazo)
        if (!pediuPermissao) return falha(new Error("o comando rodou sem pedir permissão"))
        ok()
      } else if (mensagem.tipo === "erro") {
        falha(new Error(`erro do servidor: ${JSON.stringify(mensagem)}`))
      }
    }
  })
  ws.close()
}

const pasta = await mkdtemp(join(tmpdir(), "ct-fumaca-"))
const ambiente = await subirAmbiente(pasta)
let falhou: unknown

try {
  const alvo = join(pasta, "fumaca.txt")
  const regras: Regra[] = [
    {
      nome: "alfred-roda-comando",
      quando: { sistema: "Alfred", temFerramenta: "Bash" },
      responde: [{ ferramenta: "Bash", entrada: { command: `echo fumaca > ${alvo}`, description: "fumaça" } }],
    },
    { nome: "alfred-conclui", quando: { resultadoDe: "Bash" }, responde: [{ texto: "feito" }] },
  ]
  await fetch(`${ambiente.modelo}/_controle/roteiro`, {
    method: "POST",
    body: JSON.stringify({ cena: "fumaca", regras }),
  })

  let erroDaConversa: unknown
  await falar(ambiente).catch((erro) => {
    erroDaConversa = erro
  })
  const pedidos = (await (await fetch(`${ambiente.modelo}/_controle/pedidos?cena=fumaca`)).json()) as PedidoRecebido[]
  if (!pedidos.some((p) => p.sistema.includes("Alfred") && p.ferramentas.includes("Bash")))
    throw new Error("o modelo falso não recebeu pedido do Alfred com Bash")
  if (erroDaConversa) throw erroDaConversa

  const conteudo = (await readFile(alvo, "utf8").catch(() => "")).trim()
  if (conteudo !== "fumaca") throw new Error(`fumaca.txt com conteúdo inesperado: "${conteudo}"`)
  const semRegra = await (await fetch(`${ambiente.modelo}/_controle/sem-regra`)).json()
  if ((semRegra as unknown[]).length) throw new Error(`pedidos sem regra: ${JSON.stringify(semRegra)}`)
} catch (erro) {
  falhou = erro
} finally {
  await ambiente.encerrar()
}

if (falhou) {
  console.error(`fumaça falhou: ${(falhou as Error).message}`)
  process.exit(1)
}
console.log("fumaça ok")
process.exit(0)
