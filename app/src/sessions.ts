import { ambienteDoClaude, executavelDoClaude } from "./caminhos"
import { comUso, type RegistroDeUso } from "./uso"
import { query, type SDKUserMessage } from "@anthropic-ai/claude-agent-sdk"
import { mensagemDoConselheiro, mensagemDoExecutor, montarSystemPrompt } from "./prompt"
import { blocoDeEscrita, carregarRitmo, classificar, lembreteDeForma, normalizadorDeStream, orcamento } from "./ritmo"
import { MODELO_PADRAO, ehConselheiro, rodaComandos, type Perfil } from "./tipos"
import { elenco } from "./orquestra/elenco"
import { FERRAMENTAS_TICKTASK, servidorTickTask } from "./ticktask"
import { exigeAprovacaoSempre } from "./comandos"
import type { Memoria } from "./memoria/tipos"
import { montarBrief } from "./memoria/recuperacao"
import { FERRAMENTAS_MEMORIA, servidorDeMemoria } from "./memoria/ferramentas"
import { FERRAMENTA_LEMBRETE, servidorDeLembretes } from "./avisos/ferramenta"
import type { PedidoDeLembrete } from "./avisos/lembretes"
import type { Posicao } from "./orquestra/equipe"
import type { TipoDeEvento } from "./orquestra/execucao"
import { opcoesDaPosicao, opcoesDePlano } from "./orquestra/capacidades"
import { servidorDaOrquestra, type AcoesDaTarefa } from "./orquestra/ferramentas"

// allowedTools é lista de AUTO-APROVADAS, não de disponíveis. Pôr "Bash" aqui faria o
// canUseTool ser pulado e o comando rodar sem ninguém aprovar.
const AUTO_APROVADAS = ["Read", "Write", "Edit", "Grep", "Glob"]

// Restringe as ferramentas nativas do Claude Code. Sem isto a sessão expõe TaskList,
// TaskCreate, Cron etc., e o Alfred no foco TickTask confunde "tasks" com o TaskList nativo.
const NATIVAS_DO_CONSELHEIRO = AUTO_APROVADAS
const NATIVAS_DO_EXECUTOR = [...AUTO_APROVADAS, "Bash"]

interface OpcoesConversa {
  raiz: string
  perfil: Perfil
  texto: string
  sessionId?: string
  modelo?: string
  auto?: boolean
  foco?: "ticktask"
  focoDesligado?: boolean
  memoria?: Memoria
  conversaId?: string
  consulta?: string
  onChunk: (texto: string) => void
  onComando?: (comando: string, aprovar: boolean) => Promise<boolean>
  onSessao?: (sessionId: string) => Promise<unknown>
  agendarLembrete?: (pedido: PedidoDeLembrete) => Promise<string>
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
            const liberado = onComando ? await onComando(comando, !auto || exigeAprovacaoSempre(comando)) : false
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
  const perfil = opcoes.perfil
  const conselheiro = !rodaComandos(perfil)
  const comMemoria = conselheiro && ehConselheiro(perfil) ? opcoes.memoria : undefined
  const brief =
    comMemoria
      ? await montarBrief(comMemoria, perfil, opcoes.consulta ?? opcoes.texto)
      : ""
  let escrita: string | undefined
  let prompt = mensagemDoExecutor(opcoes.texto, opcoes.foco, opcoes.focoDesligado)
  if (conselheiro) {
    const ritmo = await carregarRitmo(opcoes.raiz, perfil)
    const o = orcamento(classificar(opcoes.consulta ?? opcoes.texto), ritmo)
    escrita = blocoDeEscrita(orcamento("padrao", ritmo), ritmo)
    prompt = mensagemDoConselheiro(opcoes.texto, brief, lembreteDeForma(o))
  }
  const system = await montarSystemPrompt(opcoes.raiz, perfil, escrita)
  const saida = conselheiro ? normalizadorDeStream(opcoes.onChunk) : undefined
  const emitir = (pedaco: string) => (saida ? saida.receber(pedaco) : opcoes.onChunk(pedaco))
  const comTickTask = !conselheiro && elenco().tem(perfil, "ticktask")
  const base = comTickTask
    ? await servidorTickTask()
    : comMemoria
      ? { memoria: servidorDeMemoria(comMemoria, perfil, `conversa:${opcoes.conversaId ?? "avulsa"}`) }
      : undefined
  const lembretes = opcoes.agendarLembrete ? { lembretes: servidorDeLembretes(opcoes.agendarLembrete) } : undefined
  const mcp = base || lembretes ? { ...base, ...lembretes } : undefined
  const extras = [
    ...(comTickTask ? FERRAMENTAS_TICKTASK : comMemoria ? FERRAMENTAS_MEMORIA : []),
    ...(lembretes ? [FERRAMENTA_LEMBRETE] : []),
  ]
  let acumulado = ""
  let sessionId = opcoes.sessionId

  const uso = {
    tipo: "chat" as const,
    perfil,
    conversaId: opcoes.conversaId,
    modelo: opcoes.modelo ?? MODELO_PADRAO,
    retomada: Boolean(opcoes.sessionId),
  }
  for await (const msg of comUso(opcoes.raiz, uso, query({
    prompt: conselheiro ? prompt : comoStream(prompt),
    options: {
      cwd: opcoes.raiz,
      pathToClaudeCodeExecutable: executavelDoClaude(),
      env: ambienteDoClaude(),
      resume: opcoes.sessionId,
      // Sem isto o SDK carrega ~/.claude/settings.json do usuário: plugins, MCPs pessoais
      // e hooks de PreToolUse que negam comando já aprovado na tela (o do context-mode
      // nega curl e manda usar uma ferramenta que o Alfred não tem).
      settingSources: [],
      model: opcoes.modelo ?? MODELO_PADRAO,
      systemPrompt: system,
      tools: conselheiro ? NATIVAS_DO_CONSELHEIRO : NATIVAS_DO_EXECUTOR,
      allowedTools: mcp ? [...AUTO_APROVADAS, ...extras] : AUTO_APROVADAS,
      mcpServers: mcp,
      // Executor fica em "default" para o canUseTool decidir tudo explicitamente, em vez
      // de depender de como acceptEdits e canUseTool interagem entre si.
      permissionMode: conselheiro ? "acceptEdits" : "default",
      hooks: conselheiro ? undefined : hookDeComando(opcoes.auto === true, opcoes.onComando),
      includePartialMessages: true,
    },
  }))) {
    const daMensagem = (msg as { session_id?: string }).session_id
    if (daMensagem && daMensagem !== sessionId) {
      sessionId = daMensagem
      await opcoes.onSessao?.(daMensagem)
    }
    if (msg.type === "stream_event") {
      const evento = (
        msg as { event?: { type?: string; delta?: { type?: string; text?: string }; content_block?: { type?: string } } }
      ).event
      if (evento?.type === "content_block_start" && evento.content_block?.type === "text" && acumulado) {
        acumulado += "\n\n"
        emitir("\n\n")
      }
      if (evento?.type === "content_block_delta" && evento.delta?.type === "text_delta" && evento.delta.text) {
        acumulado += evento.delta.text
        emitir(evento.delta.text)
      }
    } else if (msg.type === "result") {
      const resultado = msg as { subtype?: string; result?: string }
      if (resultado.subtype !== "success") {
        throw new Error(`a sessão do perfil terminou com "${resultado.subtype}"`)
      }
      if (!acumulado && typeof resultado.result === "string") {
        acumulado = resultado.result
        emitir(resultado.result)
      }
    }
  }
  return { texto: saida ? saida.finalizar() : acumulado, sessionId }
}

interface OpcoesTrabalho {
  raiz: string
  persona: Perfil
  posicao: Posicao
  plano?: boolean
  bloco: string
  consulta: string
  modelo: string
  sessionId?: string
  memoria?: Memoria
  tarefaId: number
  execucaoId: number
  acoes: AcoesDaTarefa
  controle: AbortController
  onEvento: (tipo: TipoDeEvento, conteudo: string) => void
  onComando: (comando: string, aprovar: boolean) => Promise<boolean>
  onSessao: (sessionId: string) => void
  onUso: (registro: RegistroDeUso) => void
}

const LIMITE_DE_TURNOS_EM_TAREFA = 60

function resumirEntrada(entrada: unknown): string {
  const texto = typeof entrada === "string" ? entrada : JSON.stringify(entrada ?? {})
  return texto.length > 300 ? `${texto.slice(0, 299)}…` : texto
}

export async function trabalhar(opcoes: OpcoesTrabalho): Promise<{ texto: string; sessionId?: string }> {
  const posicao = opcoes.plano ? opcoesDePlano(opcoes.posicao) : opcoesDaPosicao(opcoes.posicao)
  const comMemoria = posicao.memoria ? opcoes.memoria : undefined
  const brief = comMemoria ? await montarBrief(comMemoria, opcoes.persona, opcoes.consulta) : ""
  const prompt = [opcoes.bloco, brief ? `<memória>\n${brief}\n</memória>` : ""].filter(Boolean).join("\n\n")
  const ticktask = posicao.ticktask ? await servidorTickTask() : undefined
  const mcp = {
    ...ticktask,
    ...(comMemoria ? { memoria: servidorDeMemoria(comMemoria, opcoes.persona, `tarefa:${opcoes.tarefaId}`) } : {}),
    orquestra: servidorDaOrquestra(opcoes.acoes),
  }
  let sessionId: string | undefined
  let final = ""
  const uso = {
    tipo: "tarefa" as const,
    perfil: opcoes.persona,
    tarefaId: opcoes.tarefaId,
    execucaoId: opcoes.execucaoId,
    modelo: opcoes.modelo,
    retomada: Boolean(opcoes.sessionId),
  }
  const onComando = async (comando: string, aprovar: boolean) => {
    if (aprovar) opcoes.onEvento("aprovacao", `aguardando aprovação: ${comando}`)
    const liberado = await opcoes.onComando(comando, aprovar)
    opcoes.onEvento("comando", `${liberado ? "rodou" : "negado"}: ${comando}`)
    return liberado
  }
  for await (const msg of comUso(
    opcoes.raiz,
    uso,
    query({
      prompt: posicao.comandos ? comoStream(prompt) : prompt,
      options: {
        cwd: opcoes.posicao.diretorio ?? opcoes.raiz,
        pathToClaudeCodeExecutable: executavelDoClaude(),
        env: ambienteDoClaude(),
        resume: opcoes.sessionId,
        settingSources: [],
        model: opcoes.modelo,
        systemPrompt: await montarSystemPrompt(opcoes.raiz, opcoes.persona, undefined, opcoes.posicao.capacidades.includes("comandos")),
        tools: posicao.nativas,
        allowedTools: posicao.autoAprovadas,
        mcpServers: mcp,
        permissionMode: posicao.permissionMode,
        hooks: posicao.comandos ? hookDeComando(posicao.liberaComandoComum, onComando) : undefined,
        maxTurns: LIMITE_DE_TURNOS_EM_TAREFA,
        abortController: opcoes.controle,
      },
    }),
    opcoes.onUso,
  )) {
    const daMensagem = (msg as { session_id?: string }).session_id
    if (daMensagem && daMensagem !== sessionId) {
      sessionId = daMensagem
      opcoes.onSessao(daMensagem)
    }
    if (msg.type === "assistant") {
      const blocos = (msg as { message?: { content?: { type?: string; text?: string; name?: string; input?: unknown }[] } }).message
        ?.content
      for (const bloco of blocos ?? []) {
        if (bloco.type === "text" && bloco.text?.trim()) opcoes.onEvento("texto", bloco.text.trim())
        if (bloco.type === "tool_use" && bloco.name !== "Bash") opcoes.onEvento("ferramenta", `${bloco.name} ${resumirEntrada(bloco.input)}`)
      }
    } else if (msg.type === "result") {
      const resultado = msg as { subtype?: string; result?: string }
      if (resultado.subtype !== "success") throw new Error(`a execução terminou com "${resultado.subtype}"`)
      final = typeof resultado.result === "string" ? resultado.result.trim() : ""
    }
  }
  return { texto: final, sessionId: sessionId ?? opcoes.sessionId }
}

export async function perguntarUmaVez(opcoes: {
  raiz: string
  system: string
  prompt: string
  permitirLeitura?: boolean
  modelo?: string
  uso: { tipo: "board-parecer" | "board-sintese" | "persona"; perfil?: string }
}): Promise<string> {
  let resposta = ""
  // Sem "model" de propósito: o board delibera no padrão do SDK (Opus), e não no
  // MODELO_PADRAO do chat. Deliberação é onde o modelo forte se paga.
  for await (const msg of comUso(opcoes.raiz, opcoes.uso, query({
    prompt: opcoes.prompt,
    options: {
      cwd: opcoes.raiz,
      pathToClaudeCodeExecutable: executavelDoClaude(),
      env: ambienteDoClaude(),
      systemPrompt: opcoes.system,
      settingSources: [],
      model: opcoes.modelo,
      tools: opcoes.permitirLeitura ? ["Read", "Grep", "Glob"] : [],
      allowedTools: opcoes.permitirLeitura ? ["Read", "Grep", "Glob"] : [],
      permissionMode: "default",
      maxTurns: 8,
      includePartialMessages: true,
    },
  }))) {
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
