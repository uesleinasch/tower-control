import type { Posicao } from "./equipe"
import { FERRAMENTAS_MEMORIA } from "../memoria/ferramentas"
import { FERRAMENTAS_TICKTASK } from "../ticktask"

export const NATIVAS_DE_ARQUIVO = ["Read", "Write", "Edit", "Grep", "Glob"]

export const FERRAMENTAS_ORQUESTRA = ["mcp__orquestra__comentar", "mcp__orquestra__pedir_ajuda", "mcp__orquestra__delegar"]

export interface OpcoesDaPosicao {
  nativas: string[]
  autoAprovadas: string[]
  comandos: boolean
  memoria: boolean
  ticktask: boolean
  permissionMode: "default" | "acceptEdits"
  liberaComandoComum: boolean
}

// allowedTools é a lista de auto-aprovadas: Bash ali pularia o hook de aprovação.
export function opcoesDaPosicao(posicao: Posicao): OpcoesDaPosicao {
  const tem = (c: Posicao["capacidades"][number]) => posicao.capacidades.includes(c)
  const arquivos = tem("arquivos") ? NATIVAS_DE_ARQUIVO : []
  const comandos = tem("comandos")
  const memoria = tem("memoria")
  const ticktask = tem("ticktask")
  return {
    nativas: comandos ? [...arquivos, "Bash"] : arquivos,
    autoAprovadas: [
      ...arquivos,
      ...FERRAMENTAS_ORQUESTRA,
      ...(memoria ? FERRAMENTAS_MEMORIA : []),
      ...(ticktask ? FERRAMENTAS_TICKTASK : []),
    ].filter((f) => f !== "Bash"),
    comandos,
    memoria,
    ticktask,
    permissionMode: comandos ? "default" : "acceptEdits",
    liberaComandoComum: posicao.aprovacao !== "sempre",
  }
}

export const NATIVAS_DE_LEITURA = ["Read", "Grep", "Glob"]

export function opcoesDePlano(posicao: Posicao): OpcoesDaPosicao {
  const base = opcoesDaPosicao(posicao)
  return {
    ...base,
    nativas: NATIVAS_DE_LEITURA,
    autoAprovadas: base.autoAprovadas.filter(
      (f) => (!NATIVAS_DE_ARQUIVO.includes(f) || NATIVAS_DE_LEITURA.includes(f)) && f !== "mcp__orquestra__delegar",
    ),
    comandos: false,
    permissionMode: "default",
  }
}
