import { query } from "@anthropic-ai/claude-agent-sdk"
import { montarSystemPrompt } from "./prompt"
import type { Perfil } from "./tipos"

interface OpcoesConversa {
  raiz: string
  perfil: Perfil
  texto: string
  sessionId?: string
  modelo?: string
  onChunk: (texto: string) => void
}

export async function conversar(opcoes: OpcoesConversa): Promise<{ texto: string; sessionId?: string }> {
  const system = await montarSystemPrompt(opcoes.raiz, opcoes.perfil)
  let acumulado = ""
  let sessionId = opcoes.sessionId

  for await (const msg of query({
    prompt: opcoes.texto,
    options: {
      cwd: opcoes.raiz,
      resume: opcoes.sessionId,
      model: opcoes.modelo,
      systemPrompt: system,
      allowedTools: ["Read", "Write", "Edit", "Grep", "Glob"],
      permissionMode: "acceptEdits",
      includePartialMessages: true,
    },
  })) {
    if (msg.type === "stream_event") {
      const evento = (msg as { event?: { type?: string; delta?: { type?: string; text?: string } } }).event
      if (evento?.type === "content_block_delta" && evento.delta?.type === "text_delta" && evento.delta.text) {
        acumulado += evento.delta.text
        opcoes.onChunk(evento.delta.text)
      }
    } else if (msg.type === "result") {
      const resultado = msg as { session_id?: string; subtype?: string; result?: string }
      sessionId = resultado.session_id ?? sessionId
      if (resultado.subtype !== "success") {
        throw new Error(`a sessão do perfil terminou com "${resultado.subtype}"`)
      }
      if (!acumulado && typeof resultado.result === "string") {
        acumulado = resultado.result
        opcoes.onChunk(resultado.result)
      }
    }
  }
  return { texto: acumulado, sessionId }
}

export async function perguntarUmaVez(opcoes: {
  raiz: string
  system: string
  prompt: string
  permitirLeitura?: boolean
}): Promise<string> {
  let resposta = ""
  for await (const msg of query({
    prompt: opcoes.prompt,
    options: {
      cwd: opcoes.raiz,
      systemPrompt: opcoes.system,
      allowedTools: opcoes.permitirLeitura ? ["Read", "Grep", "Glob"] : [],
      permissionMode: "default",
      maxTurns: 8,
    },
  })) {
    if (msg.type === "result") {
      const resultado = msg as { subtype?: string; result?: string }
      if (resultado.subtype !== "success") {
        throw new Error(`consulta terminou com "${resultado.subtype}"`)
      }
      resposta = resultado.result ?? ""
    }
  }
  return resposta
}
