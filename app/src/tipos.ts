export const PERFIS = ["poe", "nati", "lucas", "pami"] as const
export type Perfil = (typeof PERFIS)[number]

export interface Mensagem {
  role: "user" | "assistant"
  texto: string
  ts: string
  perfil: Perfil
}

export interface MetaConversa {
  id: string
  perfil: Perfil
  titulo: string
  criadaEm: string
  sessionId?: string
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
