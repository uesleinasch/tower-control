import { join, relative } from "node:path"
import { mkdir, readdir, rm } from "node:fs/promises"

export const DONO_CASA = "casa"
export const LIMITE_DA_DESCRICAO = 1024
export const LIMITE_DO_CORPO = 100_000
const PADRAO_ID = /^[a-z][a-z0-9-]{0,63}$/

export interface Skill {
  dono: string
  id: string
  descricao: string
  corpo: string
  arquivos: string[]
  erro?: string
}

export interface RascunhoDeSkill {
  id: string
  descricao: string
  corpo: string
}

export function skillIdValido(id: unknown): id is string {
  return typeof id === "string" && PADRAO_ID.test(id)
}

export function nomeDoPlugin(dono: string): string {
  return `ct-${dono}`
}

export function nomeQualificado(skill: Pick<Skill, "dono" | "id">): string {
  return `${nomeDoPlugin(skill.dono)}:${skill.id}`
}

export function pastaDoDono(raiz: string, dono: string): string {
  return dono === DONO_CASA ? join(raiz, "skills") : join(raiz, "profiles", dono, "skills")
}

// ── SKILL.md ───────────────────────────────────────────────────────

function separar(texto: string): { frontmatter: string; corpo: string } {
  const normal = texto.replace(/\r\n/g, "\n")
  const m = /^---\n([\s\S]*?)\n---[ \t]*(?:\n|$)([\s\S]*)$/.exec(normal)
  if (!m) throw new Error("falta o frontmatter (--- no começo e no fim)")
  return { frontmatter: m[1]!, corpo: m[2]! }
}

export function lerSkillMd(texto: string, id: string): { descricao: string; corpo: string } {
  const { frontmatter, corpo } = separar(texto)
  let dados: unknown
  try {
    dados = Bun.YAML.parse(frontmatter)
  } catch (erro) {
    throw new Error(`frontmatter inválido: ${(erro as Error).message}`)
  }
  const d = (dados && typeof dados === "object" ? dados : {}) as Record<string, unknown>
  if (d.name !== id) throw new Error(`o name do frontmatter (${String(d.name ?? "vazio")}) precisa ser igual ao nome da pasta (${id})`)
  const descricao = typeof d.description === "string" ? d.description.trim() : ""
  const erros = errosDoRascunho({ id, descricao, corpo })
  if (erros.length) throw new Error(erros.join("; "))
  return { descricao, corpo: corpo.replace(/^\n+/, "").trimEnd() }
}

export function errosDoRascunho(r: RascunhoDeSkill): string[] {
  const erros: string[] = []
  if (!skillIdValido(r.id)) erros.push("id inválido (letras minúsculas, números e hífen, começando por letra)")
  if (!r.descricao.trim()) erros.push("a descrição é obrigatória")
  if (r.descricao.trim().length > LIMITE_DA_DESCRICAO) erros.push(`a descrição passa de ${LIMITE_DA_DESCRICAO} caracteres`)
  if (!r.corpo.trim()) erros.push("o corpo da skill está vazio")
  if (r.corpo.length > LIMITE_DO_CORPO) erros.push("o corpo da skill passa de 100 mil caracteres")
  return erros
}

// Chaves do frontmatter que o editor não conhece (allowed-tools, license...) voltam como estavam.
function outrasChaves(frontmatter: string): string[] {
  const linhas = frontmatter.split("\n")
  const ficam: string[] = []
  let pulando = false
  for (const linha of linhas) {
    const topo = /^([A-Za-z0-9_-]+)\s*:/.exec(linha)
    if (topo) pulando = topo[1] === "name" || topo[1] === "description"
    else if (linha.trim() && !/^\s/.test(linha)) pulando = false
    if (!pulando) ficam.push(linha)
  }
  while (ficam.length && !ficam.at(-1)!.trim()) ficam.pop()
  return ficam
}

export function montarSkillMd(r: RascunhoDeSkill, anterior?: string): string {
  let extras: string[] = []
  if (anterior) {
    try {
      extras = outrasChaves(separar(anterior).frontmatter)
    } catch {
      extras = []
    }
  }
  const frontmatter = [`name: ${r.id}`, `description: ${JSON.stringify(r.descricao.trim())}`, ...extras].join("\n")
  return `---\n${frontmatter}\n---\n\n${r.corpo.trim()}\n`
}

export function exigirRascunho(bruto: unknown): RascunhoDeSkill {
  const s = (bruto && typeof bruto === "object" ? bruto : {}) as Record<string, unknown>
  const r = {
    id: typeof s.id === "string" ? s.id.trim() : "",
    descricao: typeof s.descricao === "string" ? s.descricao.trim() : "",
    corpo: typeof s.corpo === "string" ? s.corpo : "",
  }
  const erros = errosDoRascunho(r)
  if (erros.length) throw new Error(`skill ${r.id || "sem id"}: ${erros.join("; ")}`)
  return r
}

// ── conjunto de uma chamada ────────────────────────────────────────

export function conjuntoDaChamada(
  biblioteca: Skill[],
  persona: string,
  daPersona: readonly string[] = [],
  daPosicao: readonly string[] = [],
): Skill[] {
  const anexadas = new Set([...daPersona, ...daPosicao])
  return biblioteca.filter(
    (s) => !s.erro && (s.dono === persona || (s.dono === DONO_CASA && anexadas.has(s.id))),
  )
}

export interface OpcoesDeSkills {
  plugins: { type: "local"; path: string; skipMcpDiscovery: true }[]
  skills: string[]
  ferramentas: string[]
  additionalDirectories?: string[]
}

export function opcoesDeSkills(raiz: string, conjunto: Skill[], cwd: string = raiz): OpcoesDeSkills | null {
  if (!conjunto.length) return null
  const donos = [...new Set(conjunto.map((s) => s.dono))].sort((a, b) => (a === DONO_CASA ? -1 : b === DONO_CASA ? 1 : a.localeCompare(b)))
  const pastas = donos.map((d) => pastaDoDono(raiz, d))
  const foraDoCwd = pastas.filter((p) => relative(cwd, p).startsWith(".."))
  return {
    plugins: pastas.map((path) => ({ type: "local" as const, path, skipMcpDiscovery: true as const })),
    skills: conjunto.map(nomeQualificado),
    ferramentas: ["Skill"],
    ...(foraDoCwd.length ? { additionalDirectories: foraDoCwd } : {}),
  }
}

export function opcoesDoSdk(sk: OpcoesDeSkills | null): {
  plugins?: OpcoesDeSkills["plugins"]
  skills?: string[]
  additionalDirectories?: string[]
} {
  if (!sk) return {}
  return { plugins: sk.plugins, skills: sk.skills, ...(sk.additionalDirectories ? { additionalDirectories: sk.additionalDirectories } : {}) }
}

// ── disco ──────────────────────────────────────────────────────────

export async function garantirManifesto(raiz: string, dono: string): Promise<boolean> {
  const caminho = join(pastaDoDono(raiz, dono), ".claude-plugin", "plugin.json")
  if (await Bun.file(caminho).exists()) return false
  await mkdir(join(caminho, ".."), { recursive: true })
  await Bun.write(caminho, `${JSON.stringify({ name: nomeDoPlugin(dono), skills: "./" }, null, 2)}\n`)
  return true
}

async function listarArquivos(pasta: string): Promise<string[]> {
  const nomes = await readdir(pasta, { recursive: true, withFileTypes: true }).catch(() => [])
  return nomes
    .filter((n) => n.isFile())
    .map((n) => relative(pasta, join(n.parentPath, n.name)))
    .filter((n) => n !== "SKILL.md")
    .sort()
}

export async function lerSkillsDoDono(raiz: string, dono: string): Promise<Skill[]> {
  const pasta = pastaDoDono(raiz, dono)
  const entradas = await readdir(pasta, { withFileTypes: true }).catch(() => [])
  const lidas: Skill[] = []
  for (const e of entradas.filter((e) => e.isDirectory() && !e.name.startsWith(".")).sort((a, b) => a.name.localeCompare(b.name))) {
    const arquivos = await listarArquivos(join(pasta, e.name))
    const base = { dono, id: e.name, descricao: "", corpo: "", arquivos }
    if (!skillIdValido(e.name)) {
      lidas.push({ ...base, erro: "nome de pasta inválido (letras minúsculas, números e hífen)" })
      continue
    }
    const arquivo = Bun.file(join(pasta, e.name, "SKILL.md"))
    if (!(await arquivo.exists())) {
      lidas.push({ ...base, erro: "falta o SKILL.md" })
      continue
    }
    const texto = await arquivo.text()
    try {
      lidas.push({ ...base, ...lerSkillMd(texto, e.name) })
    } catch (erro) {
      lidas.push({ ...base, corpo: texto, erro: (erro as Error).message })
    }
  }
  return lidas
}

export async function lerBiblioteca(raiz: string, personas: readonly string[]): Promise<Skill[]> {
  const todas = await Promise.all([DONO_CASA, ...personas].map((d) => lerSkillsDoDono(raiz, d)))
  return todas.flat()
}

export async function skillsDaChamada(
  raiz: string,
  persona: string,
  daPersona: readonly string[] | undefined,
  daPosicao: readonly string[] | undefined,
  cwd: string = raiz,
): Promise<OpcoesDeSkills | null> {
  const biblioteca = await lerBiblioteca(raiz, [persona])
  return opcoesDeSkills(raiz, conjuntoDaChamada(biblioteca, persona, daPersona, daPosicao), cwd)
}

export async function gravarSkill(raiz: string, dono: string, rascunho: RascunhoDeSkill, nova: boolean): Promise<void> {
  const pasta = join(pastaDoDono(raiz, dono), rascunho.id)
  const arquivo = Bun.file(join(pasta, "SKILL.md"))
  const existe = await arquivo.exists()
  if (nova && existe) throw new Error(`a skill ${rascunho.id} já existe`)
  if (!nova && !existe) throw new Error(`a skill ${rascunho.id} não existe`)
  await garantirManifesto(raiz, dono)
  await mkdir(pasta, { recursive: true })
  await Bun.write(join(pasta, "SKILL.md"), montarSkillMd(rascunho, existe ? await arquivo.text() : undefined))
}

export async function apagarSkill(raiz: string, dono: string, id: string): Promise<void> {
  if (!skillIdValido(id)) throw new Error(`skill: id inválido (${id})`)
  const pasta = join(pastaDoDono(raiz, dono), id)
  if (!(await Bun.file(join(pasta, "SKILL.md")).exists()) && !(await readdir(pasta).catch(() => null))) {
    throw new Error(`a skill ${id} não existe`)
  }
  await rm(pasta, { recursive: true, force: true })
}
