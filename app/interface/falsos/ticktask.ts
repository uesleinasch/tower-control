import { createServer } from "node:http"
import type { AddressInfo } from "node:net"
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js"
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js"
import { z } from "zod"

interface Tarefa {
  id: number
  name: string
  status: string
  parent_task_id: number | null
  notas: string
}

function texto(dados: unknown, erro = false) {
  return { content: [{ type: "text" as const, text: JSON.stringify(dados) }], ...(erro ? { isError: true } : {}) }
}

export function servirTickTaskFalso(porta = 0, token = "token-falso"): { porta: number; token: string; fechar(): void } {
  const tarefas = new Map<number, Tarefa>()
  let proximoId = 1

  function criarServidor(): McpServer {
    const mcp = new McpServer({ name: "ticktask-falso", version: "1" })
    mcp.tool(
      "create_task",
      { name: z.string(), status: z.string().optional(), parent_task_id: z.number().optional() },
      async (args) => {
        const tarefa: Tarefa = {
          id: proximoId++,
          name: args.name,
          status: args.status ?? "proximas",
          parent_task_id: args.parent_task_id ?? null,
          notas: "",
        }
        tarefas.set(tarefa.id, tarefa)
        return texto({ created: { id: tarefa.id } })
      },
    )
    mcp.tool("update_task", { id: z.number(), status: z.string().optional(), name: z.string().optional() }, async (args) => {
      const tarefa = tarefas.get(args.id)
      if (!tarefa) return texto({ code: "not_found", message: "tarefa não encontrada" }, true)
      if (args.status) tarefa.status = args.status
      if (args.name) tarefa.name = args.name
      return texto({ updated: { id: tarefa.id } })
    })
    mcp.tool("write_notes", { task_id: z.number(), markdown: z.string(), mode: z.string().optional() }, async (args) => {
      const tarefa = tarefas.get(args.task_id)
      if (!tarefa) return texto({ code: "not_found", message: "tarefa não encontrada" }, true)
      tarefa.notas = args.mode === "append" ? tarefa.notas + args.markdown : args.markdown
      return texto({ ok: true })
    })
    mcp.tool("get_task", { id: z.number() }, async (args) => {
      const tarefa = tarefas.get(args.id)
      if (!tarefa) return texto({ code: "not_found", message: "tarefa não encontrada" }, true)
      const { id, name, status, parent_task_id } = tarefa
      const subtasks = [...tarefas.values()]
        .filter((t) => t.parent_task_id === id)
        .map((t) => ({ id: t.id, name: t.name, status: t.status }))
      return texto({ task: { id, name, status, parent_task_id }, subtasks })
    })
    mcp.tool("server_info", {}, async () => texto({ name: "ticktask-falso", version: "1" }))
    return mcp
  }

  const servidor = createServer(async (req, res) => {
    const url = new URL(req.url ?? "/", "http://127.0.0.1")
    const responder = (status: number, corpo: unknown) => {
      res.writeHead(status, { "content-type": "application/json" })
      res.end(JSON.stringify(corpo))
    }
    if (url.pathname === "/_controle/tarefas" && req.method === "GET") {
      return responder(200, [...tarefas.values()])
    }
    const finalizar = url.pathname.match(/^\/_controle\/finalizar\/(\d+)$/)
    if (finalizar && req.method === "POST") {
      const tarefa = tarefas.get(Number(finalizar[1]))
      if (!tarefa) return responder(404, { erro: "tarefa não encontrada" })
      tarefa.status = "finalizada"
      return responder(200, { ok: true })
    }
    if (url.pathname === "/mcp") {
      if (req.headers.authorization !== `Bearer ${token}`) return responder(401, { erro: "token inválido" })
      const mcp = criarServidor()
      const transporte = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true })
      res.on("close", () => {
        void transporte.close()
        void mcp.close()
      })
      await mcp.connect(transporte)
      return transporte.handleRequest(req, res)
    }
    responder(404, { erro: "rota desconhecida" })
  })
  servidor.listen(porta, "127.0.0.1")
  return {
    get porta() {
      return (servidor.address() as AddressInfo).port
    },
    token,
    fechar() {
      servidor.closeAllConnections()
      servidor.close()
    },
  }
}
