import { join } from "node:path"
import { readdir } from "node:fs/promises"
import type { Decisao } from "./tipos"

export function parseFrontmatter(conteudo: string): Record<string, string | string[]> {
  const casado = conteudo.match(/^---\n([\s\S]*?)\n---/)
  if (!casado) return {}
  const campos: Record<string, string | string[]> = {}
  for (const linha of casado[1].split("\n")) {
    const par = linha.match(/^(\w+):\s*(.*)$/)
    if (!par) continue
    const [, chave, bruto] = par
    const valor = bruto.trim()
    if (valor.startsWith("[") && valor.endsWith("]")) {
      campos[chave] = valor
        .slice(1, -1)
        .split(",")
        .map((v) => v.trim())
        .filter(Boolean)
    } else {
      campos[chave] = valor
    }
  }
  return campos
}

function paraDecisao(campos: Record<string, string | string[]>, arquivo: string): Decisao | null {
  const texto = (v: string | string[] | undefined) => (typeof v === "string" ? v : "")
  const lista = (v: string | string[] | undefined) =>
    Array.isArray(v) ? v : typeof v === "string" && v ? [v] : []
  const id = texto(campos.id)
  if (!id) return null
  return {
    id,
    date: texto(campos.date),
    title: texto(campos.title),
    status: (texto(campos.status) || "proposta") as Decisao["status"],
    tags: lista(campos.tags),
    projeto: texto(campos.projeto),
    participantes: lista(campos.participantes),
    arquivo,
  }
}

export async function lerDecisoes(raiz: string): Promise<Decisao[]> {
  const dir = join(raiz, "decisions")
  let nomes: string[]
  try {
    nomes = await readdir(dir)
  } catch {
    return []
  }
  const decisoes: Decisao[] = []
  for (const nome of nomes.filter((n) => n.endsWith(".md") && n !== "INDEX.md")) {
    const conteudo = await Bun.file(join(dir, nome)).text()
    const decisao = paraDecisao(parseFrontmatter(conteudo), nome)
    if (decisao) decisoes.push(decisao)
  }
  return decisoes.sort((a, b) => b.date.localeCompare(a.date))
}

export interface FiltroDecisoes {
  texto?: string
  tags?: string[]
  status?: string
}

export async function buscarDecisoes(raiz: string, filtro: FiltroDecisoes): Promise<Decisao[]> {
  const todas = await lerDecisoes(raiz)
  const termo = filtro.texto?.toLowerCase()
  const resultados: Decisao[] = []
  for (const d of todas) {
    if (filtro.status && d.status !== filtro.status) continue
    if (filtro.tags?.length && !filtro.tags.every((t) => d.tags.includes(t))) continue
    if (termo) {
      const corpo = await Bun.file(join(raiz, "decisions", d.arquivo)).text()
      if (!corpo.toLowerCase().includes(termo) && !d.title.toLowerCase().includes(termo)) continue
    }
    resultados.push(d)
  }
  return resultados
}

export async function lerDecisao(raiz: string, id: string): Promise<string | null> {
  const decisao = (await lerDecisoes(raiz)).find((d) => d.id === id)
  if (!decisao) return null
  return Bun.file(join(raiz, "decisions", decisao.arquivo)).text()
}

export function linhaIndice(d: Decisao): string {
  return `- ${d.date} · ${d.status} · [${d.title}](${d.arquivo}) · ${d.tags.join(", ")}`
}

export async function regenerarIndice(raiz: string): Promise<string> {
  const decisoes = await lerDecisoes(raiz)
  const linhas = decisoes.map(linhaIndice).join("\n")
  const caminho = join(raiz, "decisions", "INDEX.md")
  const atual = await Bun.file(caminho).text()
  const novo = atual.replace(/(<!-- decisões -->)[\s\S]*$/, `$1\n${linhas}\n`)
  await Bun.write(caminho, novo)
  return novo
}
