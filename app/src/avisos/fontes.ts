import type { NovoAviso } from "./central"
import { nomeDe, type Perfil } from "../tipos"
import { formatarTokens } from "../orquestra/governanca"

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

export function avisoDeAprovacaoEmTarefa(
  permissaoId: string,
  tarefaId: number,
  nome: string,
  comando: string,
  expiraEm: Date,
): NovoAviso {
  return {
    id: permissaoId,
    tipo: "aprovacao",
    titulo: `${nome} quer rodar um comando em #${tarefaId}`,
    corpo: comando,
    alvo: { tarefaId, permissaoId },
    acoes: ["aprovar", "negar"],
    expiraEm: expiraEm.toISOString(),
  }
}

function avisoDeTarefa(tarefaId: number, titulo: string, corpo: string): NovoAviso {
  return { tipo: "tarefa", titulo, corpo: resumir(corpo) || "(sem texto)", alvo: { tarefaId }, acoes: [] }
}

export const avisoDeEntrega = (tarefaId: number, nome: string, entrega: string) =>
  avisoDeTarefa(tarefaId, `${nome} entregou #${tarefaId}`, entrega)

export const avisoDePedidoDeAjuda = (tarefaId: number, nome: string, motivo: string) =>
  avisoDeTarefa(tarefaId, `${nome} pediu ajuda em #${tarefaId}`, motivo)

export const avisoDeBloqueio = (tarefaId: number, erro: string) =>
  avisoDeTarefa(tarefaId, `#${tarefaId} bloqueada`, `Falhou duas vezes seguidas. Último erro: ${erro}`)

export const avisoDeDelegacao = (tarefaId: number, nome: string, titulo: string) =>
  avisoDeTarefa(tarefaId, `${nome} delegou #${tarefaId}`, `${titulo}. Está no backlog: libere quando quiser que rode.`)

export const avisoDePlano = (tarefaId: number, nome: string, plano: string) =>
  avisoDeTarefa(tarefaId, `${nome} propôs um plano para #${tarefaId}`, plano)

export function avisoDeOrcamento(
  nome: string,
  nivel: "alerta" | "estourado",
  dimensao: "usd" | "tokens",
  gasto: number,
  limite: number,
): NovoAviso {
  const valores =
    dimensao === "usd"
      ? `US$ ${gasto.toFixed(2)} de US$ ${limite.toFixed(2)} no mês`
      : `${formatarTokens(gasto)} de ${formatarTokens(limite)} no mês`
  const qual = dimensao === "usd" ? "orçamento" : "orçamento de tokens"
  return {
    tipo: "tarefa",
    titulo: nivel === "alerta" ? `${nome} passou de 80% do ${qual}` : `${nome} parou: ${qual} do mês estourado`,
    corpo: nivel === "alerta" ? valores : `${valores}. As tarefas dele esperam na fila até você subir o limite ou o mês virar.`,
    alvo: {},
    acoes: [],
  }
}

export const avisoDeAprovacaoPendente = (tarefaId: number, entrega: string) =>
  avisoDeTarefa(tarefaId, `#${tarefaId} espera sua aprovação`, entrega)

export const avisoDeConclusaoPelaPolitica = (tarefaId: number, quem: string, parecer: string) =>
  avisoDeTarefa(tarefaId, `${quem} aprovou #${tarefaId}; tarefa concluída`, parecer)

export const avisoDeVoltas = (tarefaId: number, revisora: string, executora: string, pedido: string) =>
  avisoDeTarefa(tarefaId, `${revisora} e ${executora} não convergiram em #${tarefaId}`, `Último pedido de mudança: ${pedido}`)

export const avisoDeAutorrevisao = (tarefaId: number, nome: string) =>
  avisoDeTarefa(tarefaId, `#${tarefaId} parada: ${nome} revisaria o próprio trabalho`, "Troque a persona da etapa ou a política e comente na tarefa para seguir.")

export function avisoDeRotinaQueFalhou(nome: string, motivo: string): NovoAviso {
  return { tipo: "tarefa", titulo: `A rotina ${nome} não criou a tarefa`, corpo: resumir(motivo) || "(sem motivo)", alvo: {}, acoes: [] }
}
