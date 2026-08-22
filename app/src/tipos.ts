export const CONSELHEIROS = ["poe", "nati", "lucas", "pami"] as const
export const EXECUTORES = ["alfred"] as const
export const PERFIS = [...CONSELHEIROS, ...EXECUTORES] as const

// Sem isto o SDK resolve para claude-opus-5[1m] — medido em ~7x o custo do haiku
// na mesma pergunta.
export const MODELO_PADRAO = "haiku"
export type Conselheiro = (typeof CONSELHEIROS)[number]
export type Executor = (typeof EXECUTORES)[number]
export type Perfil = (typeof PERFIS)[number]

export function ehConselheiro(perfil: Perfil): perfil is Conselheiro {
  return (CONSELHEIROS as readonly string[]).includes(perfil)
}

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
  auto?: boolean
  foco?: "ticktask"
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
