import type { NovoAviso } from "./central"
import { nomeDe, type Perfil } from "../tipos"

const LIMITE_CORPO = 180

function resumir(texto: string): string {
  const corrido = texto.replace(/^\s*---\s*$/gm, " ").replace(/\s+/g, " ").trim()
  return corrido.length > LIMITE_CORPO ? `${corrido.slice(0, LIMITE_CORPO - 1)}…` : corrido
}

export function avisoDeResposta(perfil: Perfil, conversaId: string, texto: string): NovoAviso {
  return {
    tipo: "resposta",
    titulo: `${nomeDe(perfil)} respondeu`,
    corpo: resumir(texto) || "(resposta vazia)",
    alvo: { conversaId },
    acoes: ["responder"],
  }
}

export function avisoDeAprovacao(permissaoId: string, conversaId: string, comando: string, expiraEm: Date): NovoAviso {
  return {
    id: permissaoId,
    tipo: "aprovacao",
    titulo: "Alfred quer rodar um comando",
    corpo: comando,
    alvo: { conversaId, permissaoId },
    acoes: ["aprovar", "negar"],
    expiraEm: expiraEm.toISOString(),
  }
}
