export const PERFIS = ["poe", "nati", "lucas", "pami"] as const

// Sem isto o SDK resolve para claude-opus-5[1m] — medido em ~7x o custo do haiku
// na mesma pergunta.
export const MODELO_PADRAO = "haiku"
export type Perfil = (typeof PERFIS)[number]

export type TipoAnexo = "imagem" | "texto" | "pdf"

export interface Anexo {
  id: string
  nome: string
  tipo: TipoAnexo
  mime: string
  bytes: number
  arquivo: string
}

export interface Mensagem {
  role: "user" | "assistant"
  texto: string
  ts: string
  perfil: Perfil
  citacao?: string
  anexos?: Anexo[]
}

export interface MetaConversa {
  id: string
  perfil: Perfil
  titulo: string
  criadaEm: string
  sessionId?: string
  modelo?: string
}

export interface Decisao {
  id: string
  date: string
  title: string
  status: "proposta" | "aceita" | "revogada"
  tags: string[]
  projeto: string
  participantes: string[]
  arquivo: string
}
