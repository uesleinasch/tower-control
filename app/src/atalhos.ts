import { join } from "node:path"

export interface Atalho {
  rotulo: string
  texto: string
}

function analisarLinha(corpo: string): Atalho | null {
  const corte = corpo.indexOf("::")
  if (corte < 0) return { rotulo: corpo, texto: corpo }
  const rotulo = corpo.slice(0, corte).trim()
  const texto = corpo.slice(corte + 2).trim()
  if (!texto) return null
  return { rotulo: rotulo || texto, texto }
}

export function lerAtalhos(markdown: string): Atalho[] {
  return markdown
    .split("\n")
    .map((linha) => linha.trim())
    .filter((linha) => linha.startsWith("- "))
    .map((linha) => analisarLinha(linha.slice(2).trim()))
    .filter((atalho): atalho is Atalho => atalho !== null)
}

export async function carregarAtalhos(raiz: string): Promise<Atalho[]> {
  const arquivo = Bun.file(join(raiz, "atalhos.md"))
  if (!(await arquivo.exists())) return []
  return lerAtalhos(await arquivo.text())
}
