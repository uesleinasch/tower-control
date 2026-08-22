import { join } from "node:path"
import { mkdir } from "node:fs/promises"
import { randomUUID } from "node:crypto"
import type { Anexo, TipoAnexo } from "./tipos"

export const LIMITE_BYTES = 10 * 1024 * 1024

const MIMES_IMAGEM = new Set(["image/png", "image/jpeg", "image/webp", "image/gif"])

const EXTENSOES_TEXTO = new Set([
  "log", "md", "txt", "csv", "json", "ts", "js", "py", "sql", "yml", "yaml", "sh",
])

const PADRAO_ID = /^[a-z0-9-]{8,64}$/

function extensaoBruta(nome: string): string {
  const ponto = nome.lastIndexOf(".")
  return ponto < 0 ? "" : nome.slice(ponto + 1).toLowerCase()
}

// A extensão vem do nome do cliente, então precisa ser incapaz de compor caminho.
export function extensaoSegura(nome: string): string {
  const bruta = extensaoBruta(nome)
  return /^[a-z0-9]{1,8}$/.test(bruta) ? bruta : "txt"
}

export function classificarAnexo(mime: string, nome: string): TipoAnexo | null {
  const limpo = (mime.split(";")[0] ?? "").trim().toLowerCase()
  if (MIMES_IMAGEM.has(limpo)) return "imagem"
  if (limpo === "application/pdf") return "pdf"
  if (limpo.startsWith("text/")) return "texto"
  if (EXTENSOES_TEXTO.has(extensaoBruta(nome))) return "texto"
  return null
}

export function nomeExibivel(nome: string): string {
  return nome.replace(/[\r\n\t]/g, " ").trim().slice(0, 120) || "arquivo"
}

export function formatarTamanho(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  const kb = bytes / 1024
  if (kb < 1024) return `${Math.round(kb)} kB`
  return `${(kb / 1024).toFixed(1).replace(".", ",")} MB`
}

export function idValido(id: string): boolean {
  return PADRAO_ID.test(id)
}

export function montarBlocoDeAnexos(anexos: Anexo[], raiz: string): string {
  if (!anexos.length) return ""
  const linhas = anexos.map(
    (a) => `- ${join(raiz, a.arquivo)} — ${a.tipo} "${a.nome}" (${formatarTamanho(a.bytes)})`,
  )
  return `[Anexos desta mensagem. Leia cada um com a ferramenta Read antes de responder:]\n${linhas.join("\n")}`
}

function dirAnexos(raiz: string): string {
  return join(raiz, "conversations", "anexos")
}

export async function gravarAnexo(
  raiz: string,
  nome: string,
  mime: string,
  dados: ArrayBuffer,
): Promise<Anexo> {
  const tipo = classificarAnexo(mime, nome)
  if (!tipo) throw new Error(`tipo de arquivo não aceito: ${mime || nome}`)
  if (dados.byteLength > LIMITE_BYTES) {
    throw new Error(`anexo acima do limite de ${formatarTamanho(LIMITE_BYTES)}`)
  }
  const id = `${Date.now().toString(36)}-${randomUUID().replace(/-/g, "").slice(0, 8)}`
  const arquivo = join("conversations", "anexos", `${id}.${extensaoSegura(nome)}`)
  const anexo: Anexo = {
    id,
    nome: nomeExibivel(nome),
    tipo,
    mime,
    bytes: dados.byteLength,
    arquivo,
  }
  await mkdir(dirAnexos(raiz), { recursive: true })
  await Bun.write(join(raiz, arquivo), dados)
  await Bun.write(join(dirAnexos(raiz), `${id}.json`), JSON.stringify(anexo))
  return anexo
}

export async function lerAnexo(raiz: string, id: string): Promise<Anexo | null> {
  if (!idValido(id)) return null
  const sidecar = Bun.file(join(dirAnexos(raiz), `${id}.json`))
  if (!(await sidecar.exists())) return null
  return sidecar.json()
}

export async function lerAnexos(raiz: string, ids: string[]): Promise<Anexo[]> {
  const encontrados = await Promise.all(ids.map((id) => lerAnexo(raiz, id)))
  return encontrados.filter((a): a is Anexo => a !== null)
}
