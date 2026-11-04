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
  pedirAjuda?: (motivo: string) => string
  delegar?: (pedido: Delegacao) => string
  aprovar?: (parecer: string) => string
  pedirMudanca?: (oQueMudar: string) => string
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
  const { delegar, pedirAjuda, aprovar, pedirMudanca } = acoes
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
      ...(pedirAjuda
        ? [
            tool(
              "pedir_ajuda",
              "Pede ajuda ao Ueslei quando falta algo que muda o resultado. A tarefa fica bloqueada até ele responder; depois de chamar, pare.",
              { motivo: z.string().min(1) },
              async ({ motivo }) => resposta(protegido(() => pedirAjuda(motivo))),
            ),
          ]
        : []),
      ...(aprovar
        ? [
            tool(
              "aprovar",
              "Aprova a entrega que você está revisando, com o seu parecer. Depois de chamar, pare.",
              { parecer: z.string().min(1).describe("o que você conferiu e por que aprova") },
              async ({ parecer }) => resposta(protegido(() => aprovar(parecer))),
            ),
          ]
        : []),
      ...(pedirMudanca
        ? [
            tool(
              "pedir_mudanca",
              "Devolve a entrega à executora pedindo uma mudança. A nova entrega volta para você. Depois de chamar, pare.",
              { o_que_mudar: z.string().min(1).describe("o que precisa mudar e por quê") },
              async ({ o_que_mudar }) => resposta(protegido(() => pedirMudanca(o_que_mudar))),
            ),
          ]
        : []),
    ],
  })
}
