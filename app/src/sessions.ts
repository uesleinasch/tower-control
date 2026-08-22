import { query, type SDKUserMessage } from "@anthropic-ai/claude-agent-sdk"
import { montarSystemPrompt } from "./prompt"
import { MODELO_PADRAO, ehConselheiro, type Perfil } from "./tipos"
import { servidorTickTask } from "./ticktask"

// allowedTools é lista de AUTO-APROVADAS, não de disponíveis. Pôr "Bash" aqui faria o
// canUseTool ser pulado e o comando rodar sem ninguém aprovar.
const AUTO_APROVADAS = ["Read", "Write", "Edit", "Grep", "Glob"]

// Nomeadas uma a uma porque não se sabe se allowedTools casa prefixo de MCP.
const FERRAMENTAS_TICKTASK = [
  "mcp__ticktask",
  "mcp__ticktask__server_info",
  "mcp__ticktask__list_structure",
  "mcp__ticktask__manage_structure",
  "mcp__ticktask__search_tasks",
  "mcp__ticktask__get_task",
  "mcp__ticktask__create_task",
  "mcp__ticktask__update_task",
  "mcp__ticktask__bulk_update_tasks",
  "mcp__ticktask__delete_tasks",
  "mcp__ticktask__read_notes",
  "mcp__ticktask__write_notes",
  "mcp__ticktask__organize_overview",
  "mcp__ticktask__agenda",
  "mcp__ticktask__plan_day",
  "mcp__ticktask__timer",
  "mcp__ticktask__time_report",
  "mcp__ticktask__weekly_review",
]

interface OpcoesConversa {
  raiz: string
  perfil: Perfil
  texto: string
  sessionId?: string
  modelo?: string
  auto?: boolean
  foco?: "ticktask"
  onChunk: (texto: string) => void
  onComando?: (comando: string, aprovar: boolean) => Promise<boolean>
}

// O canUseTool chega como control request, e control request só existe em modo de
// entrada em streaming. Com prompt: string ele nunca dispara.
async function* comoStream(texto: string): AsyncIterable<SDKUserMessage> {
  yield {
    type: "user",
    message: { role: "user", content: texto },
    parent_tool_use_id: null,
  }
}

// Hook, e não canUseTool: um PreToolUse vindo de settings (o rtk casa "Bash") sombreia
// o callback, e o próprio SDK avisa que para barrar toda chamada o caminho é o hook.
// Comando sem canal de aprovação é negado — nunca liberado por omissão.
// Em modo auto o hook continua registrado e responde allow: sem hook nenhum, o Bash fica
// bloqueado em vez de liberado.
function hookDeComando(
  auto: boolean,
  onComando?: (comando: string, aprovar: boolean) => Promise<boolean>,
): NonNullable<Parameters<typeof query>[0]["options"]>["hooks"] {
  return {
    PreToolUse: [
      {
        matcher: "Bash",
        hooks: [
          async (entrada) => {
            const bruto = entrada as { tool_input?: { command?: unknown } }
            const comando = String(bruto.tool_input?.command ?? "")
            const liberado = onComando ? await onComando(comando, !auto) : false
            return {
              hookSpecificOutput: {
                hookEventName: "PreToolUse" as const,
                permissionDecision: liberado ? ("allow" as const) : ("deny" as const),
                // O texto da recusa é o que o modelo lê. Sem deixar claro que é
                // definitivo, ele tenta variações do comando e gera vários cartões.
                permissionDecisionReason: liberado
                  ? "aprovado na tela"
                  : "O Ueslei negou este comando. Não tente outro comando nem variação " +
                    "deste: responda a ele dizendo que a execução foi negada, e pare.",
              },
            }
          },
        ],
      },
    ],
  }
}

export async function conversar(opcoes: OpcoesConversa): Promise<{ texto: string; sessionId?: string }> {
  const system = await montarSystemPrompt(opcoes.raiz, opcoes.perfil, opcoes.foco)
  const conselheiro = ehConselheiro(opcoes.perfil)
  const mcp = conselheiro ? undefined : await servidorTickTask()
  let acumulado = ""
  let sessionId = opcoes.sessionId

  for await (const msg of query({
    prompt: conselheiro ? opcoes.texto : comoStream(opcoes.texto),
    options: {
      cwd: opcoes.raiz,
      resume: opcoes.sessionId,
      model: opcoes.modelo ?? MODELO_PADRAO,
      systemPrompt: system,
      allowedTools: mcp ? [...AUTO_APROVADAS, ...FERRAMENTAS_TICKTASK] : AUTO_APROVADAS,
      mcpServers: mcp,
      // Executor fica em "default" para o canUseTool decidir tudo explicitamente, em vez
      // de depender de como acceptEdits e canUseTool interagem entre si.
      permissionMode: conselheiro ? "acceptEdits" : "default",
      hooks: conselheiro ? undefined : hookDeComando(opcoes.auto === true, opcoes.onComando),
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
  // Sem "model" de propósito: o board delibera no padrão do SDK (Opus), e não no
  // MODELO_PADRAO do chat. Deliberação é onde o modelo forte se paga.
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
