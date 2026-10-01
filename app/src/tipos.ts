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

export function perfilExcluivel(perfil: Perfil): boolean {
  return !(EXECUTORES as readonly string[]).includes(perfil)
}

// O pedido de exclusão chega por WebSocket sem autenticação: esconder a opção na UI não basta.
export function exigirPerfilExcluivel(perfil: Perfil): void {
  if (!perfilExcluivel(perfil)) throw new Error(`${perfil} é o executor da casa e não pode ser excluído`)
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
  consolidadoAte?: number
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
