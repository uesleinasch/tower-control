import { join } from "node:path"
import { mkdir, readdir, rm } from "node:fs/promises"
import { dataHoraLocal } from "../texto"
import { NOMES, lerPerfil } from "../prompt"
import { atualizarMeta, filaPorChave, lerMensagens, lerMeta, listarConversas } from "../store"
import { ehConselheiro, type Conselheiro, type Mensagem, type MetaConversa } from "../tipos"
import { carregarRitmo, espelho } from "../ritmo"
import { consolidacaoPendente, registrarAtividade } from "./agenda"
import { instrucoesDeBastidor, rodarPersona } from "./sessao"
import type { Memoria, Trecho } from "./tipos"

const TAREFA = `Tarefa: repassar um trecho de conversa que você acabou de ter com o Ueslei e guardar
o que vale lembrar.

1. Grave um episodio desta conversa: o que conversaram, como ele estava, o que ficou em
   aberto. Título curto que você reconheceria depois.
2. Grave ou atualize os fatos novos sobre ele. Se algo contradiz um fato antigo, atualize
   a página antiga dizendo o que mudou e quando.
3. Se algo mudou em você — uma opinião que você formou, um jeito de falar com ele que
   funcionou, uma piada interna, uma posição que defendeu —, grave ou atualize um jeito.
4. Conversa sem nada durável ainda vira episodio, curto.
5. Olhe o espelho da sua escrita e atualize o jeito com título "Como eu escrevo" (crie se
   não existir): expressões suas, tiques, o que fez o Ueslei rir, o que o fez pedir para
   encurtar. É a sua voz, não uma cópia da dele.`

function linha(m: Mensagem, persona: Conselheiro): string {
  const quem = m.role === "user" ? "Ueslei" : NOMES[persona]
  const quando = dataHoraLocal(new Date(m.ts))
  return `[${quando}] ${quem}: ${m.texto.trim()}`
}

export function montarPedidoConsolidacao(
  persona: Conselheiro,
  meta: MetaConversa,
  novas: Mensagem[],
  anteriores: Trecho[],
  espelhoDaEscrita = "",
): string {
  const lembrancas = anteriores.length
    ? anteriores.map((t) => `- ${t.titulo}: ${t.trecho} (${t.path})`).join("\n")
    : "(nenhuma sobre esses assuntos)"
  return `## Conversa "${meta.titulo}" (${meta.id})

${novas.map((m) => linha(m, persona)).join("\n\n")}

## O que você já lembra sobre esses assuntos

${lembrancas}
${espelhoDaEscrita ? `\n${espelhoDaEscrita}\n` : ""}
Repasse a conversa e guarde o que vale lembrar.`
}

const naFilaDaConsolidacao = filaPorChave()

// O meta é relido dentro da fila: a agenda, a conversa nova e a exclusão podem pedir a
// mesma conversa ao mesmo tempo, e só a primeira encontra mensagens novas.
export function consolidarConversa(raiz: string, m: Memoria, meta: MetaConversa): Promise<void> {
  return naFilaDaConsolidacao(meta.id, async () => {
    if (!ehConselheiro(meta.perfil)) return
    const atual = await lerMeta(raiz, meta.id).catch(() => null)
    if (!atual) return
    const mensagens = await lerMensagens(raiz, meta.id)
    const novas = mensagens.slice(atual.consolidadoAte ?? 0)
    if (!novas.length) return
    await consolidarMensagens(raiz, m, atual, novas)
    await atualizarMeta(raiz, meta.id, { consolidadoAte: mensagens.length })
  })
}

async function consolidarMensagens(raiz: string, m: Memoria, meta: MetaConversa, novas: Mensagem[]): Promise<void> {
  if (!ehConselheiro(meta.perfil)) return
  const persona = meta.perfil
  const assunto = novas
    .filter((x) => x.role === "user")
    .map((x) => x.texto)
    .join(" ")
    .slice(0, 500)
  const anteriores = assunto ? await m.buscar(persona, assunto, 8) : []

  const perfil = await lerPerfil(raiz, persona)
  await rodarPersona({
    raiz,
    persona,
    system: [perfil, instrucoesDeBastidor(persona, TAREFA)].filter(Boolean).join("\n\n---\n\n"),
    prompt: montarPedidoConsolidacao(persona, meta, novas, anteriores, espelho(novas, await carregarRitmo(raiz, persona))),
    memoria: m,
    exigirGravacao: true,
    origem: `conversa:${meta.id}`,
    tipo: "consolidacao",
  })
  await registrarAtividade(raiz, persona, new Date(novas[novas.length - 1]!.ts))
  console.log(`[memoria] ${persona} consolidou ${novas.length} mensagem(ns) de ${meta.id}`)
}

interface Guardada {
  meta: MetaConversa
  novas: Mensagem[]
}

function dirGuardadas(raiz: string): string {
  return join(raiz, "conversations", "a-consolidar")
}

// Chamado antes de apagar a conversa: o que ainda não virou memória fica guardado fora
// dela, e a persona repassa depois, mesmo que a memória esteja fora do ar agora.
export function guardarParaConsolidar(raiz: string, id: string): Promise<void> {
  return naFilaDaConsolidacao(id, async () => {
    const meta = await lerMeta(raiz, id).catch(() => null)
    if (!meta || !ehConselheiro(meta.perfil)) return
    const novas = (await lerMensagens(raiz, id)).slice(meta.consolidadoAte ?? 0)
    if (!novas.length) return
    await mkdir(dirGuardadas(raiz), { recursive: true })
    await Bun.write(join(dirGuardadas(raiz), `${id}.json`), JSON.stringify({ meta, novas } satisfies Guardada))
  })
}

export async function consolidarGuardadas(raiz: string, m: Memoria, persona?: Conselheiro): Promise<void> {
  let nomes: string[]
  try {
    nomes = (await readdir(dirGuardadas(raiz))).filter((n) => n.endsWith(".json"))
  } catch {
    return
  }
  const falhas: string[] = []
  for (const nome of nomes) {
    const id = nome.slice(0, -".json".length)
    await naFilaDaConsolidacao(id, async () => {
      const caminho = join(dirGuardadas(raiz), nome)
      const arquivo = Bun.file(caminho)
      if (!(await arquivo.exists())) return
      const guardada = (await arquivo.json()) as Guardada
      if (persona && guardada.meta.perfil !== persona) return
      await consolidarMensagens(raiz, m, guardada.meta, guardada.novas)
      await rm(caminho, { force: true })
    }).catch((erro: Error) => falhas.push(`${id}: ${erro.message}`))
  }
  if (falhas.length) throw new Error(`conversas apagadas sem consolidar — ${falhas.join("; ")}`)
}

export async function consolidarPendentesDe(raiz: string, m: Memoria, persona: Conselheiro, exceto?: string): Promise<void> {
  for (const meta of await listarConversas(raiz)) {
    if (meta.perfil !== persona || meta.id === exceto) continue
    await consolidarConversa(raiz, m, meta)
  }
  await consolidarGuardadas(raiz, m, persona)
}

export async function conversasPendentes(raiz: string, agora: Date): Promise<MetaConversa[]> {
  const pendentes: MetaConversa[] = []
  for (const meta of await listarConversas(raiz)) {
    if (!ehConselheiro(meta.perfil)) continue
    if (consolidacaoPendente(meta, await lerMensagens(raiz, meta.id), agora)) pendentes.push(meta)
  }
  return pendentes.reverse()
}
