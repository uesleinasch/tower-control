import { join } from "node:path"
import { homedir } from "node:os"
import type { McpServerConfig } from "@anthropic-ai/claude-agent-sdk"

interface ConfigTickTask {
  enabled?: boolean
  port?: number
  token?: string
}

// O TickTask é um app do próprio Ueslei e expõe um servidor MCP; porta e token ficam na
// config dele. Sem app aberto não há porta, então isto devolve nada e o Alfred segue sem
// as ferramentas em vez de quebrar.
export async function servidorTickTask(): Promise<Record<string, McpServerConfig> | undefined> {
  const arquivo = Bun.file(join(homedir(), ".config", "ticktask", "mcp-config.json"))
  if (!(await arquivo.exists())) return undefined
  try {
    const config: ConfigTickTask = await arquivo.json()
    if (config.enabled === false || !config.port || !config.token) return undefined
    return {
      ticktask: {
        type: "http",
        url: `http://127.0.0.1:${config.port}/mcp`,
        headers: { authorization: `Bearer ${config.token}` },
      },
    }
  } catch {
    return undefined
  }
}
