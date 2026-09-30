import { join } from "node:path"
import { readdir } from "node:fs/promises"
import { parseFrontmatter } from "../decisions"
import { COLETIVO, MemoriaIndisponivel, caminhoValido, type Memoria, type NovaPagina } from "./tipos"

export type OrigemColetiva = "decisao" | "ata"

const FONTES: Record<OrigemColetiva, { dir: string[]; prefixo: string; tier: NovaPagina["tier"]; tag: string }> = {
  decisao: { dir: ["decisions"], prefixo: "decisoes/", tier: "semantic", tag: "origem:decisions" },
  ata: { dir: ["board", "minutes"], prefixo: "atas/", tier: "episodic", tag: "origem:board" },
}

export function paginaDoColetivo(origem: OrigemColetiva, arquivo: string, conteudo: string): NovaPagina | null {
  const fonte = FONTES[origem]
  const path = `${fonte.prefixo}${arquivo}`
  if (!caminhoValido(path)) return null
  return { path, corpo: semFrontmatter(conteudo), tier: fonte.tier, pinned: false, tags: [fonte.tag] }
}

export function semFrontmatter(conteudo: string): string {
  const casado = conteudo.match(/^---\n[\s\S]*?\n---\n*/)
  if (!casado) return conteudo
  const campos = parseFrontmatter(conteudo)
  const texto = (v: string | string[] | undefined) => (Array.isArray(v) ? v.join(", ") : (v ?? ""))
  const resto = conteudo.slice(casado[0].length).replace(/^#\s+.*\n+/, "")
  const detalhes = [texto(campos.date), texto(campos.status), texto(campos.tags)].filter(Boolean).join(" · ")
  return [`# ${texto(campos.title) || "Decisão"}`, detalhes, resto.trim()].filter(Boolean).join("\n\n") + "\n"
}

async function arquivos(raiz: string, origem: OrigemColetiva): Promise<string[]> {
  try {
    const nomes = await readdir(join(raiz, ...FONTES[origem].dir))
    return nomes.filter((n) => n.endsWith(".md") && n !== "INDEX.md")
  } catch {
    return []
  }
}

// Reescrever conteúdo idêntico não gera versão no ai-memory, então espelhar tudo de novo é barato.
export async function espelharColetivo(raiz: string, m: Memoria): Promise<number> {
  let espelhadas = 0
  for (const origem of Object.keys(FONTES) as OrigemColetiva[]) {
    for (const nome of await arquivos(raiz, origem)) {
      const conteudo = await Bun.file(join(raiz, ...FONTES[origem].dir, nome)).text()
      const pagina = paginaDoColetivo(origem, nome, conteudo)
      if (!pagina) {
        console.warn(`[memoria] ${nome} fora do formato de caminho; não espelhado no coletivo`)
        continue
      }
      try {
        await m.gravar(COLETIVO, pagina)
        espelhadas++
      } catch (erro) {
        if (erro instanceof MemoriaIndisponivel) throw erro
        console.warn(`[memoria] ${pagina.path} não espelhado no coletivo — ${(erro as Error).message}`)
      }
    }
  }
  return espelhadas
}
