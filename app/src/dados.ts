import { join, resolve } from "node:path"
import { cp, mkdir, readdir, stat } from "node:fs/promises"
import { diretorioDeSessoes } from "./sessao-sdk"

export const MARCADOR = ".control-tower"
export const ARQUIVO_ORIGEM = ".importar-de"
const IMPORTAVEIS = ["profiles", "decisions", "board", "atalhos.md", "conversations"]
const VERSIONADOS = ["profiles", "equipes", "skills", "decisions", "board", "atalhos.md", "ticktask.json"]
const GITIGNORE = "conversations/\nmemoria/\norquestra/\n.importar-de\n"
const IDENTIDADE = ["-c", "user.name=control-tower", "-c", "user.email=control-tower@localhost", "-c", "commit.gpgsign=false"]

async function existe(caminho: string): Promise<boolean> {
  try {
    await stat(caminho)
    return true
  } catch {
    return false
  }
}

async function git(dados: string, args: string[]): Promise<string> {
  const processo = Bun.spawn(["git", ...IDENTIDADE, ...args], { cwd: dados, stdout: "pipe", stderr: "pipe" })
  const [saida, erro, codigo] = await Promise.all([
    new Response(processo.stdout).text(),
    new Response(processo.stderr).text(),
    processo.exited,
  ])
  if (codigo !== 0) throw new Error(`git ${args[0]}: ${erro.trim() || saida.trim()}`)
  return saida
}

export async function origemDaImportacao(
  dados: string,
  codigo: string,
  ambiente: Record<string, string | undefined> = process.env,
): Promise<string | undefined> {
  if (ambiente.CT_IMPORTAR_DE) return resolve(ambiente.CT_IMPORTAR_DE)
  const arquivo = Bun.file(join(dados, ARQUIVO_ORIGEM))
  if (await arquivo.exists()) {
    const caminho = (await arquivo.text()).trim()
    if (caminho) return resolve(caminho)
  }
  if (await existe(join(codigo, "profiles"))) return codigo
  return undefined
}

async function sessoesReferenciadas(conversas: string): Promise<string[]> {
  let nomes: string[]
  try {
    nomes = await readdir(conversas)
  } catch {
    return []
  }
  const ids: string[] = []
  for (const nome of nomes.filter((n) => n.endsWith(".meta.json"))) {
    try {
      const meta = (await Bun.file(join(conversas, nome)).json()) as { sessionId?: unknown }
      if (typeof meta.sessionId === "string") ids.push(meta.sessionId)
    } catch {
      // meta corrompida não impede a importação do resto
    }
  }
  return ids
}

async function copiarSessoes(origem: string, dados: string, home?: string): Promise<number> {
  const de = diretorioDeSessoes(origem, home)
  const para = diretorioDeSessoes(dados, home)
  let copiadas = 0
  for (const id of await sessoesReferenciadas(join(dados, "conversations"))) {
    if (!/^[0-9a-f-]{36}$/.test(id)) continue
    const arquivo = join(de, `${id}.jsonl`)
    if (!(await existe(arquivo))) continue
    await mkdir(para, { recursive: true })
    await cp(arquivo, join(para, `${id}.jsonl`), { force: false, errorOnExist: false })
    copiadas++
  }
  return copiadas
}

async function versionadosPresentes(dados: string): Promise<string[]> {
  const presentes: string[] = []
  for (const item of VERSIONADOS) if (await existe(join(dados, item))) presentes.push(item)
  return presentes
}

export interface Preparo {
  dados: string
  modelos: string
  origem?: string
  home?: string
}

export async function prepararDados(opcoes: Preparo): Promise<boolean> {
  const { dados, modelos, origem, home } = opcoes
  if (await existe(join(dados, MARCADOR))) return false

  await mkdir(dados, { recursive: true })
  await cp(modelos, dados, { recursive: true, force: true })
  if (origem && resolve(origem) !== resolve(dados)) {
    for (const item of IMPORTAVEIS) {
      const fonte = join(origem, item)
      if (await existe(fonte)) await cp(fonte, join(dados, item), { recursive: true, force: true })
    }
    const sessoes = await copiarSessoes(origem, dados, home)
    console.log(`[dados] importado de ${origem} (${sessoes} sessão(ões) do SDK)`)
  }

  await Bun.write(join(dados, ".gitignore"), GITIGNORE)
  if (!(await existe(join(dados, ".git")))) await git(dados, ["init", "-q"])
  await git(dados, ["add", "-A", "--", ".gitignore", ...(await versionadosPresentes(dados))])
  await git(dados, ["commit", "-q", "--allow-empty", "-m", origem ? `dados: importados de ${origem}` : "dados: modelos iniciais"])
  await Bun.write(join(dados, MARCADOR), `${new Date().toISOString()}\n`)
  return true
}

export async function garantirIgnorado(dados: string, linha: string): Promise<void> {
  const arquivo = Bun.file(join(dados, ".gitignore"))
  const atual = (await arquivo.exists()) ? await arquivo.text() : ""
  if (atual.split("\n").includes(linha)) return
  await Bun.write(arquivo, `${atual}${atual && !atual.endsWith("\n") ? "\n" : ""}${linha}\n`)
}

const filaDoGit = new Map<string, Promise<unknown>>()

// Duas gravações seguidas (duas equipes, dois workflows) disputariam o index.lock do git.
export function registrarNoGit(dados: string, motivo: string): Promise<boolean> {
  const anterior = filaDoGit.get(dados) ?? Promise.resolve()
  const vez = anterior.then(
    () => registrarAgora(dados, motivo),
    () => registrarAgora(dados, motivo),
  )
  filaDoGit.set(dados, vez.catch(() => {}))
  return vez
}

async function registrarAgora(dados: string, motivo: string): Promise<boolean> {
  const presentes = await versionadosPresentes(dados)
  if (!presentes.length || !(await existe(join(dados, ".git")))) return false
  const mudancas = await git(dados, ["status", "--porcelain", "--", ...presentes])
  if (!mudancas.trim()) return false
  await git(dados, ["add", "-A", "--", ...presentes])
  await git(dados, ["commit", "-q", "-m", `dados: ${motivo}`])
  return true
}
