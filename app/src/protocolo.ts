export interface Protocolo {
  "cliente→servidor": string[]
  "servidor→cliente": string[]
}

function unicos(fonte: string, padrao: RegExp): string[] {
  return [...new Set([...fonte.matchAll(padrao)].map((m) => m[1]!))].sort()
}

export function tiposEmitidos(fonte: string): string[] {
  return unicos(fonte, /tipo:\s*"([a-z-]+)"/g)
}

export function tiposTratados(fonte: string): string[] {
  const inicio = fonte.indexOf("switch (msg.tipo)")
  if (inicio < 0) return []
  return unicos(fonte.slice(inicio), /case\s+"([a-z-]+)"/g)
}
