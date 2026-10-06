import type { Conselheiro } from "../tipos"

export const WORKSPACE = "control-tower"
export const COLETIVO = "coletivo"

export type Projeto = Conselheiro | typeof COLETIVO
export type TipoLembranca = "fato" | "episodio" | "jeito"
export type Tier = "working" | "episodic" | "semantic" | "procedural"

export interface Trecho {
  path: string
  titulo: string
  trecho: string
}

export interface Resumo {
  path: string
  titulo: string
}

export interface Pagina {
  path: string
  titulo: string
  corpo: string
  tier: string
  pinned: boolean
}

export interface NovaPagina {
  path: string
  corpo: string
  tier: Tier
  pinned: boolean
  tags: string[]
  expiraEm?: string
}

export interface Memoria {
  buscar(projeto: Projeto, consulta: string, limite: number): Promise<Trecho[]>
  listar(projeto: Projeto): Promise<Resumo[]> // mais recente primeiro
  ler(projeto: Projeto, path: string): Promise<Pagina | null>
  gravar(projeto: Projeto, pagina: NovaPagina): Promise<void>
  frias(projeto: Projeto, limite: number): Promise<string[]>
}

export class MemoriaIndisponivel extends Error {
  constructor(motivo: string) {
    super(`memória indisponível: ${motivo}`)
  }
}

const PREFIXOS: Record<TipoLembranca, string> = {
  fato: "fatos/",
  episodio: "episodios/",
  jeito: "jeito/",
}

const TIERS: Record<TipoLembranca, Tier> = {
  fato: "semantic",
  episodio: "episodic",
  jeito: "procedural",
}

export function prefixoDe(tipo: TipoLembranca): string {
  return PREFIXOS[tipo]
}

export function tierDe(tipo: TipoLembranca): Tier {
  return TIERS[tipo]
}

export function tipoDoCaminho(path: string): TipoLembranca | null {
  const achado = (Object.keys(PREFIXOS) as TipoLembranca[]).find((t) => path.startsWith(PREFIXOS[t]))
  return achado ?? null
}

// O caminho vem do modelo e vira arquivo no data_dir do ai-memory.
const PADRAO_CAMINHO = /^(episodios|fatos|jeito|decisoes|atas)\/[a-z0-9][a-z0-9-]*(\/[a-z0-9][a-z0-9-]*)*\.md$/

export function caminhoValido(path: string): boolean {
  return PADRAO_CAMINHO.test(path)
}
