import { join } from "node:path"
import { mkdir, readdir, rename } from "node:fs/promises"
import type { Mensagem, MetaConversa, Perfil } from "./tipos"

function dirConversas(raiz: string): string {
  return join(raiz, "conversations")
}

async function escreverAtomico(caminho: string, conteudo: string): Promise<void> {
  const temporario = `${caminho}.tmp`
  await Bun.write(temporario, conteudo)
  await rename(temporario, caminho)
}

export async function criarConversa(
  raiz: string,
  perfil: Perfil,
  titulo: string,
  modelo?: string,
  extras?: Partial<MetaConversa>,
): Promise<MetaConversa> {
  const agora = new Date()
  const id = `${agora.toISOString().slice(0, 10)}-${perfil}-${agora.getTime().toString(36)}`
  const meta: MetaConversa = {
    id,
    perfil,
    titulo,
    criadaEm: agora.toISOString(),
    modelo,
    ...extras,
  }
  await mkdir(dirConversas(raiz), { recursive: true })
  await escreverAtomico(join(dirConversas(raiz), `${id}.meta.json`), JSON.stringify(meta, null, 2))
  return meta
}

export async function atualizarMeta(
  raiz: string,
  id: string,
  mudancas: Partial<MetaConversa>,
): Promise<MetaConversa> {
  const caminho = join(dirConversas(raiz), `${id}.meta.json`)
  const atual: MetaConversa = await Bun.file(caminho).json()
  const nova = { ...atual, ...mudancas }
  await escreverAtomico(caminho, JSON.stringify(nova, null, 2))
  return nova
}

export async function lerMeta(raiz: string, id: string): Promise<MetaConversa> {
  return Bun.file(join(dirConversas(raiz), `${id}.meta.json`)).json()
}

export async function anexarMensagem(raiz: string, id: string, msg: Mensagem): Promise<void> {
  const caminho = join(dirConversas(raiz), `${id}.jsonl`)
  const arquivo = Bun.file(caminho)
  const existente = (await arquivo.exists()) ? await arquivo.text() : ""
  await Bun.write(caminho, existente + JSON.stringify(msg) + "\n")
}

export async function lerMensagens(raiz: string, id: string): Promise<Mensagem[]> {
  const arquivo = Bun.file(join(dirConversas(raiz), `${id}.jsonl`))
  if (!(await arquivo.exists())) return []
  const texto = await arquivo.text()
  return texto
    .split("\n")
    .filter((linha) => linha.trim())
    .map((linha) => JSON.parse(linha) as Mensagem)
}

export async function listarConversas(raiz: string): Promise<MetaConversa[]> {
  let nomes: string[]
  try {
    nomes = await readdir(dirConversas(raiz))
  } catch {
    return []
  }
  const metas: MetaConversa[] = []
  for (const nome of nomes.filter((n) => n.endsWith(".meta.json"))) {
    try {
      metas.push(await Bun.file(join(dirConversas(raiz), nome)).json())
    } catch {
      // meta corrompida não derruba a listagem
    }
  }
  return metas.sort((a, b) => b.criadaEm.localeCompare(a.criadaEm))
}
