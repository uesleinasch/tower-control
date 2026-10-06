import { ambienteDoClaude, executavelDoClaude } from "../caminhos"
import { query } from "@anthropic-ai/claude-agent-sdk"
import type { Conselheiro } from "../tipos"
import { NOMES } from "../prompt"
import { FERRAMENTAS_MEMORIA_CONSOLIDACAO, placarVazio, servidorDeMemoria, type Placar } from "./ferramentas"
import type { Memoria } from "./tipos"
import { comUso, type TipoDeUso } from "../uso"

export const MODELO_MEMORIA = "sonnet"

export function instrucoesDeBastidor(persona: Conselheiro, tarefa: string): string {
  return `# Bastidor da sua memória

Você é ${NOMES[persona]}, fora da conversa, cuidando da própria memória. Ninguém vai ler
o que você responder aqui: o que importa é o que você grava com as ferramentas.

${tarefa}

Regras de toda escrita:
- Escreva na primeira pessoa, na sua voz, em português brasileiro.
- Antes de criar, use recordar para ver se já existe lembrança sobre o assunto. Se
  existir, use atualizar_lembranca naquela página em vez de criar outra.
- Tipos: fato (verdade sobre o Ueslei ou o mundo dele), episodio (o que aconteceu,
  com data e como ele estava), jeito (quem você é com ele: opinião formada, jeito de
  falar, piada interna, posição que defendeu).
- jeito acrescenta ao seu perfil acima, nunca o contradiz: valores e limites ficam como
  estão.
- Não invente: grave só o que está no material que você recebeu.
- Cada lembrança curta e específica. Uma ideia por página.`
}

export async function rodarPersona(opcoes: {
  raiz: string
  persona: Conselheiro
  system: string
  prompt: string
  memoria: Memoria
  origem: string
  exigirGravacao: boolean
  tipo: Extract<TipoDeUso, "consolidacao" | "sonho" | "migracao">
}): Promise<Placar> {
  await opcoes.memoria.listar(opcoes.persona)
  const placar = placarVazio()
  const servidor = servidorDeMemoria(opcoes.memoria, opcoes.persona, opcoes.origem, { atualizar: true, placar })
  const uso = { tipo: opcoes.tipo, perfil: opcoes.persona, modelo: MODELO_MEMORIA }
  for await (const msg of comUso(opcoes.raiz, uso, query({
    prompt: opcoes.prompt,
    options: {
      cwd: opcoes.raiz,
      pathToClaudeCodeExecutable: executavelDoClaude(),
      env: ambienteDoClaude(),
      model: MODELO_MEMORIA,
      settingSources: [],
      systemPrompt: opcoes.system,
      mcpServers: { memoria: servidor },
      allowedTools: FERRAMENTAS_MEMORIA_CONSOLIDACAO,
      tools: [],
      permissionMode: "default",
      maxTurns: 40,
      includePartialMessages: true,
    },
  }))) {
    if (msg.type === "result") {
      const resultado = msg as { subtype?: string }
      if (resultado.subtype !== "success") {
        throw new Error(`a sessão de memória de ${opcoes.persona} terminou com "${resultado.subtype}"`)
      }
    }
  }
  if (placar.indisponivel) throw new Error(`a memória caiu durante a sessão de ${opcoes.persona}`)
  if (opcoes.exigirGravacao && !placar.gravacoes) throw new Error(`${opcoes.persona} não gravou nenhuma lembrança`)
  return placar
}
