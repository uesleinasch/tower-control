import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js"
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js"
import { z } from "zod"
import { raizDosDados } from "../src/caminhos"
import { buscarDecisoes, lerDecisao, linhaIndice } from "../src/decisions"

const RAIZ = raizDosDados()

const servidor = new McpServer({ name: "control-tower", version: "0.1.0" })

servidor.registerTool(
  "buscar_decisoes",
  {
    description:
      "Busca no registro de decisões do control-tower (sala de decisões do Ueslei). " +
      "Filtra por texto livre (título e corpo), tags e status (proposta|aceita|revogada). " +
      "Sem filtros, lista todas as decisões.",
    inputSchema: {
      texto: z.string().optional().describe("busca livre no título e no corpo"),
      tags: z.array(z.string()).optional().describe("todas as tags precisam casar"),
      status: z.enum(["proposta", "aceita", "revogada"]).optional(),
    },
  },
  async ({ texto, tags, status }) => {
    const decisoes = await buscarDecisoes(RAIZ, { texto, tags, status })
    const corpo = decisoes.length
      ? decisoes.map((d) => `${linhaIndice(d)} · id: ${d.id}`).join("\n")
      : "Nenhuma decisão encontrada com esses filtros."
    return { content: [{ type: "text", text: corpo }] }
  },
)

servidor.registerTool(
  "ler_decisao",
  {
    description:
      "Lê o conteúdo integral de uma decisão registrada no control-tower, pelo id " +
      "(ex.: 2026-08-22-arquitetura-do-control-tower).",
    inputSchema: {
      id: z.string().describe("id da decisão, conforme retornado por buscar_decisoes"),
    },
  },
  async ({ id }) => {
    const conteudo = await lerDecisao(RAIZ, id)
    return {
      content: [{ type: "text", text: conteudo ?? `Decisão "${id}" não encontrada.` }],
      isError: conteudo === null,
    }
  },
)

await servidor.connect(new StdioServerTransport())
