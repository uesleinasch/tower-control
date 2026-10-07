import { elenco } from "./orquestra/elenco"
import type { PersonaId } from "./orquestra/equipe"

// Sem isto o SDK resolve para claude-opus-5[1m] — medido em ~7x o custo do haiku
// na mesma pergunta.
export const MODELO_PADRAO = "haiku"
// Com o auto ligado ninguém revisa cada comando; o modelo forte erra menos. Não é
// gravado em MetaConversa.modelo: desligar o auto volta ao modelo escolhido.
export const MODELO_DO_AUTO = "claude-opus-5-5"
export type Perfil = PersonaId
export type Conselheiro = PersonaId

export function perfis(): Perfil[] {
  return elenco().ids()
}

export function ehPerfil(id: unknown): id is Perfil {
  return elenco().existe(id)
}

export function nomeDe(perfil: Perfil): string {
  return elenco().nome(perfil)
}

export function rodaComandos(perfil: Perfil): boolean {
  return elenco().tem(perfil, "comandos")
}

// Conselheiro = conversa com memória e sem terminal, como a posição de conselho da Casa.
export function ehConselheiro(perfil: Perfil): perfil is Conselheiro {
  return elenco().tem(perfil, "memoria") && !rodaComandos(perfil)
}

export function conselheiros(): Conselheiro[] {
  return perfis().filter(ehConselheiro)
}

export function doBoard(): Conselheiro[] {
  return elenco().comCapacidade("board").filter(ehConselheiro)
}

export function perfilExcluivel(perfil: Perfil): boolean {
  return elenco().excluivel(perfil)
}

// O pedido de exclusão chega por WebSocket sem autenticação: esconder a opção na UI não basta.
export function exigirPerfilExcluivel(perfil: Perfil): void {
  if (!perfilExcluivel(perfil)) throw new Error(`${perfil} é o executor da casa e não pode ser excluído`)
}

export function modeloEfetivo(meta: { perfil: Perfil; modelo?: string; auto?: boolean }): string | undefined {
  return meta.auto && rodaComandos(meta.perfil) ? MODELO_DO_AUTO : meta.modelo
}

// undefined = o cliente não mexeu no foco; null = desligar. Só posição com TickTask tem foco.
export function lerFoco(perfil: Perfil, bruto: unknown): "ticktask" | null | undefined {
  if (typeof bruto !== "string" || !elenco().tem(perfil, "ticktask")) return undefined
  return bruto === "ticktask" ? "ticktask" : null
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
