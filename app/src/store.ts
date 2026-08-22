import { join } from "node:path"
import { mkdir, readdir, rename, rm } from "node:fs/promises"
import { excluirAnexos } from "./anexos"
import type { Mensagem, MetaConversa, Perfil } from "./tipos"

// O id vem do cliente e vira caminho de arquivo; o app escuta na rede local sem
// autenticação, então nada que não case com o formato gerado aqui passa adiante.
const PADRAO_ID = /^\d{4}-\d{2}-\d{2}-[a-z]+-[a-z0-9]+$/

export function idValido(id: string): boolean {
  return PADRAO_ID.test(id)
}

function exigirId(id: string): string {
  if (!idValido(id)) throw new Error("conversa inválida")
  return id
}

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
  const caminho = join(dirConversas(raiz), `${exigirId(id)}.meta.json`)
  const atual: MetaConversa = await Bun.file(caminho).json()
  const nova = { ...atual, ...mudancas }
  await escreverAtomico(caminho, JSON.stringify(nova, null, 2))
  return nova
}

export async function lerMeta(raiz: string, id: string): Promise<MetaConversa> {
  return Bun.file(join(dirConversas(raiz), `${exigirId(id)}.meta.json`)).json()
}

export async function anexarMensagem(raiz: string, id: string, msg: Mensagem): Promise<void> {
  const caminho = join(dirConversas(raiz), `${exigirId(id)}.jsonl`)
  const arquivo = Bun.file(caminho)
  const existente = (await arquivo.exists()) ? await arquivo.text() : ""
  await Bun.write(caminho, existente + JSON.stringify(msg) + "\n")
}

export async function lerMensagens(raiz: string, id: string): Promise<Mensagem[]> {
  const arquivo = Bun.file(join(dirConversas(raiz), `${exigirId(id)}.jsonl`))
  if (!(await arquivo.exists())) return []
  const texto = await arquivo.text()
  return texto
    .split("\n")
    .filter((linha) => linha.trim())
    .map((linha) => JSON.parse(linha) as Mensagem)
}

// Devolve o sessionId do meta: o histórico que o Agent SDK mantém fora daqui é
// apagado pelo caller, que é quem pode escrever fora do repositório.
export async function excluirConversa(raiz: string, id: string): Promise<string | undefined> {
  exigirId(id)
  const dir = dirConversas(raiz)
  let meta: MetaConversa | undefined
  try {
    meta = await lerMeta(raiz, id)
  } catch {
    // meta ausente ou corrompida não impede apagar o resto
  }
  const mensagens = await lerMensagens(raiz, id)
  await excluirAnexos(raiz, mensagens.flatMap((m) => m.anexos ?? []))
  await rm(join(dir, `${id}.jsonl`), { force: true })
  await rm(join(dir, `${id}.meta.json`), { force: true })
  return meta?.sessionId
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
