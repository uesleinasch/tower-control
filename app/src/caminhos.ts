import { homedir } from "node:os"
import { dirname, join, resolve } from "node:path"

// Dentro de um executável do bun build --compile, import.meta.dir aponta para o sistema
// de arquivos virtual ($bunfs); fora dele, é a pasta deste arquivo no clone.
function compilado(): boolean {
  return import.meta.dir.includes("$bunfs") || import.meta.dir.startsWith("B:")
}

export function raizDoCodigo(ambiente: Record<string, string | undefined> = process.env): string {
  if (ambiente.CT_INSTALACAO) return resolve(ambiente.CT_INSTALACAO)
  if (compilado()) return resolve(dirname(process.execPath), "..")
  return resolve(import.meta.dir, "..", "..")
}

export function raizDosDados(ambiente: Record<string, string | undefined> = process.env): string {
  if (ambiente.CT_DADOS) return resolve(ambiente.CT_DADOS)
  const base = ambiente.XDG_DATA_HOME || join(ambiente.HOME || homedir(), ".local", "share")
  return join(base, "control-tower")
}

export function dirWeb(codigo: string): string {
  return compilado() || process.env.CT_INSTALACAO ? join(codigo, "web") : join(codigo, "app", "web")
}

export function dirModelos(codigo: string): string {
  return compilado() || process.env.CT_INSTALACAO ? join(codigo, "modelos") : join(codigo, "app", "modelos")
}

export function executavelDoClaude(): string | undefined {
  return process.env.CT_CLAUDE || undefined
}

// settingSources: [] não cobre os conectores da conta claude.ai: sem isto o Claude Code
// os carrega sozinho em toda sessão das personas.
export function ambienteDoClaude(): Record<string, string | undefined> {
  return { ...process.env, ENABLE_CLAUDEAI_MCP_SERVERS: "false" }
}
