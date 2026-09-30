import { NOMES, lerPerfil } from "../prompt"
import { atualizarMeta, lerMensagens, listarConversas } from "../store"
import { ehConselheiro, type Conselheiro, type Mensagem, type MetaConversa } from "../tipos"
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
4. Conversa sem nada durável ainda vira episodio, curto.`

function linha(m: Mensagem, persona: Conselheiro): string {
  const quem = m.role === "user" ? "Ueslei" : NOMES[persona]
  const quando = m.ts.slice(0, 16).replace("T", " ")
  return `[${quando}] ${quem}: ${m.texto.trim()}`
}

export function montarPedidoConsolidacao(
  persona: Conselheiro,
  meta: MetaConversa,
  novas: Mensagem[],
  anteriores: Trecho[],
): string {
  const lembrancas = anteriores.length
    ? anteriores.map((t) => `- ${t.titulo}: ${t.trecho} (${t.path})`).join("\n")
    : "(nenhuma sobre esses assuntos)"
  return `## Conversa "${meta.titulo}" (${meta.id})

${novas.map((m) => linha(m, persona)).join("\n\n")}

## O que você já lembra sobre esses assuntos

${lembrancas}

Repasse a conversa e guarde o que vale lembrar.`
}

export async function consolidarConversa(raiz: string, m: Memoria, meta: MetaConversa): Promise<void> {
  if (!ehConselheiro(meta.perfil)) return
  const persona = meta.perfil
  const mensagens = await lerMensagens(raiz, meta.id)
  const novas = mensagens.slice(meta.consolidadoAte ?? 0)
  if (!novas.length) return

  const assunto = novas
    .filter((x) => x.role === "user")
    .map((x) => x.texto)
    .join(" ")
    .slice(0, 500)
  const anteriores = assunto ? await m.buscar(persona, assunto, 8).catch(() => []) : []

  const perfil = await lerPerfil(raiz, persona)
  await rodarPersona({
    raiz,
    persona,
    system: [perfil, instrucoesDeBastidor(persona, TAREFA)].filter(Boolean).join("\n\n---\n\n"),
    prompt: montarPedidoConsolidacao(persona, meta, novas, anteriores),
    memoria: m,
    origem: `conversa:${meta.id}`,
  })
  await atualizarMeta(raiz, meta.id, { consolidadoAte: mensagens.length })
  await registrarAtividade(raiz, persona, new Date(novas[novas.length - 1]!.ts))
  console.log(`[memoria] ${persona} consolidou ${novas.length} mensagem(ns) de ${meta.id}`)
}

export async function conversasPendentes(raiz: string, agora: Date): Promise<MetaConversa[]> {
  const pendentes: MetaConversa[] = []
  for (const meta of await listarConversas(raiz)) {
    if (!ehConselheiro(meta.perfil)) continue
    if (consolidacaoPendente(meta, await lerMensagens(raiz, meta.id), agora)) pendentes.push(meta)
  }
  return pendentes.reverse()
}
