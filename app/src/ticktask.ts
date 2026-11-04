import { join } from "node:path"
import { homedir } from "node:os"
import type { McpServerConfig } from "@anthropic-ai/claude-agent-sdk"

interface ConfigTickTask {
  enabled?: boolean
  port?: number
  token?: string
}

export interface EnderecoTickTask {
  url: string
  token: string
}

// O TickTask é um app do próprio Ueslei e expõe um servidor MCP; porta e token ficam na
// config dele. Sem app aberto não há porta, então isto devolve nada e quem chama segue sem
// o TickTask em vez de quebrar.
export async function enderecoTickTask(): Promise<EnderecoTickTask | undefined> {
  const arquivo = Bun.file(join(homedir(), ".config", "ticktask", "mcp-config.json"))
  if (!(await arquivo.exists())) return undefined
  try {
    const config: ConfigTickTask = await arquivo.json()
    if (config.enabled === false || !config.port || !config.token) return undefined
    return { url: `http://127.0.0.1:${config.port}/mcp`, token: config.token }
  } catch {
    return undefined
  }
}

export async function servidorTickTask(): Promise<Record<string, McpServerConfig> | undefined> {
  const endereco = await enderecoTickTask()
  if (!endereco) return undefined
  return {
    ticktask: {
      type: "http",
      url: endereco.url,
      headers: { authorization: `Bearer ${endereco.token}` },
    },
  }
}

// Nomeadas uma a uma porque não se sabe se allowedTools casa prefixo de MCP.
export const FERRAMENTAS_TICKTASK = [
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
