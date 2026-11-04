import { createSdkMcpServer, tool } from "@anthropic-ai/claude-agent-sdk"
import { z } from "zod"

export interface Delegacao {
  posicao: string
  titulo: string
  descricao?: string
  porque?: string
}

export interface AcoesDaTarefa {
  comentar: (texto: string) => string
  pedirAjuda: (motivo: string) => string
  delegar?: (pedido: Delegacao) => string
}

function resposta(texto: string) {
  return { content: [{ type: "text" as const, text: texto }] }
}

function protegido(acao: () => string): string {
  try {
    return acao()
  } catch (erro) {
    return `Não deu certo: ${(erro as Error).message}`
  }
}

// A tarefa é fixada na criação: nenhuma ferramenta recebe id de tarefa do modelo.
export function servidorDaOrquestra(acoes: AcoesDaTarefa) {
  const delegar = acoes.delegar
  return createSdkMcpServer({
    name: "orquestra",
    version: "1.0.0",
    tools: [
      ...(delegar
        ? [
            tool(
              "delegar",
              "Cria uma subtarefa para uma posição que responde a você. Ela nasce no backlog e só roda quando o Ueslei liberar.",
              {
                posicao: z.string().min(1).describe("id da posição subordinada"),
                titulo: z.string().min(1),
                descricao: z.string().optional(),
                porque: z.string().optional(),
              },
              async (args) => resposta(protegido(() => delegar(args))),
            ),
          ]
        : []),
      tool(
        "comentar",
        "Registra um comentário de progresso na tarefa, que o Ueslei lê depois.",
        { texto: z.string().min(1) },
        async ({ texto }) => resposta(protegido(() => acoes.comentar(texto))),
      ),
      tool(
        "pedir_ajuda",
        "Pede ajuda ao Ueslei quando falta algo que muda o resultado. A tarefa fica bloqueada até ele responder; depois de chamar, pare.",
        { motivo: z.string().min(1) },
        async ({ motivo }) => resposta(protegido(() => acoes.pedirAjuda(motivo))),
      ),
    ],
  })
}
