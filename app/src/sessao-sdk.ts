import { homedir } from "node:os"
import { join, resolve, sep } from "node:path"
import { rm } from "node:fs/promises"

const PADRAO_SESSAO = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

// O Claude Code guarda o histórico de cada sessão em ~/.claude/projects/<slug>/<id>.jsonl
// e monta o slug trocando por "-" tudo que não é alfanumérico no caminho do projeto.
export function diretorioDeSessoes(raiz: string): string {
  const slug = resolve(raiz).replace(/[^a-zA-Z0-9]/g, "-")
  return join(homedir(), ".claude", "projects", slug)
}

// Único ponto do app que apaga arquivo fora do repositório, e o diretório também
// guarda as sessões do Claude Code deste repo: fora do formato exato, não apaga nada.
export async function apagarSessao(raiz: string, sessionId?: string): Promise<boolean> {
  if (!sessionId || !PADRAO_SESSAO.test(sessionId)) return false
  const dir = diretorioDeSessoes(raiz)
  const alvo = resolve(dir, `${sessionId}.jsonl`)
  if (!alvo.startsWith(dir + sep)) return false
  if (!(await Bun.file(alvo).exists())) return false
  await rm(alvo, { force: true })
  return true
}
