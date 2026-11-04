import type { PersonaId } from "./equipe"
import { NOMES_DE_STATUS, type Registro, type Tarefa } from "./tarefa"

export type StatusExecucao = "na_fila" | "rodando" | "concluida" | "falhou" | "interrompida"
export type Gatilho = "atribuicao" | "comentario" | "dependencia" | "retomada" | "nova_tentativa"
export type TipoDeEvento = "texto" | "ferramenta" | "comando" | "aprovacao" | "erro"

export interface Execucao {
  id: number
  tarefa: number
  posicao: string
  persona: PersonaId | null
  gatilho: Gatilho
  status: StatusExecucao
  tentativa: number
  naoAntes: string | null
  falha: boolean
  sessionId: string | null
  modelo: string | null
  criadaEm: string
  inicio: string | null
  fim: string | null
  resultado: string | null
  erro: string | null
  custoUSD: number | null
}

export interface Evento {
  id: number
  execucao: number
  tipo: TipoDeEvento
  conteudo: string
  em: string
}

export const LIMITE_DO_EVENTO = 4_000
export const FALHAS_PARA_BLOQUEAR = 2
export const ESPERA_DA_NOVA_TENTATIVA_MS = 60_000

export const NOMES_DE_GATILHO: Record<Gatilho, string> = {
  atribuicao: "atribuição",
  comentario: "comentário",
  dependencia: "dependência concluída",
  retomada: "retomada após queda",
  nova_tentativa: "nova tentativa",
}

const TRANSICOES: Record<StatusExecucao, readonly StatusExecucao[]> = {
  na_fila: ["rodando", "interrompida"],
  rodando: ["concluida", "falhou", "interrompida"],
  concluida: [],
  falhou: [],
  interrompida: [],
}

export function podeMudarExecucao(de: StatusExecucao, para: StatusExecucao): boolean {
  return TRANSICOES[de].includes(para)
}

export function exigirMudancaDeExecucao(execucao: Execucao, para: StatusExecucao): void {
  if (!podeMudarExecucao(execucao.status, para)) {
    throw new Error(`execução ${execucao.id}: não dá para ir de ${execucao.status} para ${para}`)
  }
}

// Conta da mais recente para trás, só entre as que chegaram a rodar; a primeira que não
// conta como falha (concluída ou parada pelo Ueslei) zera a sequência.
export function falhasSeguidas(execucoes: Execucao[]): number {
  let falhas = 0
  for (const e of [...execucoes].filter((e) => e.inicio !== null).sort((a, b) => b.id - a.id)) {
    if (e.status === "na_fila" || e.status === "rodando") continue
    if (!e.falha) break
    falhas++
  }
  return falhas
}

export interface Candidata {
  execucao: Execucao
  tarefa: Tarefa
  persona: PersonaId | null
  dependenciasConcluidas: boolean
}

export type Decisao =
  | { acao: "comecar"; execucao: number; persona: PersonaId }
  | { acao: "descartar"; execucao: number; motivo: string }

export function escolher(
  candidatas: Candidata[],
  rodando: Pick<Execucao, "tarefa" | "persona">[],
  teto: number,
  agora: Date,
): Decisao[] {
  const ocupadas = new Set(rodando.map((r) => r.persona))
  const tarefasVivas = new Set(rodando.map((r) => r.tarefa))
  let vagas = teto - rodando.length
  const decisoes: Decisao[] = []
  for (const c of [...candidatas].sort((a, b) => a.execucao.id - b.execucao.id)) {
    const { execucao, tarefa } = c
    if (execucao.naoAntes && Date.parse(execucao.naoAntes) > agora.getTime()) continue
    if (tarefasVivas.has(tarefa.id)) continue
    if (tarefa.status !== "a_fazer") {
      decisoes.push({ acao: "descartar", execucao: execucao.id, motivo: `nada a fazer: a tarefa está ${NOMES_DE_STATUS[tarefa.status]}` })
      continue
    }
    if (!c.dependenciasConcluidas) {
      decisoes.push({ acao: "descartar", execucao: execucao.id, motivo: "nada a fazer: depende de tarefa não concluída" })
      continue
    }
    if (c.persona === null || ocupadas.has(c.persona) || vagas <= 0) continue
    decisoes.push({ acao: "comecar", execucao: execucao.id, persona: c.persona })
    ocupadas.add(c.persona)
    tarefasVivas.add(tarefa.id)
    vagas--
  }
  return decisoes
}

export function custoDaExecucao(acumulado: number | undefined, anteriorDaSessao: number | null, retomada: boolean): number | null {
  if (acumulado === undefined) return null
  if (anteriorDaSessao !== null) return Math.max(0, acumulado - anteriorDaSessao)
  return retomada ? null : acumulado
}

export function truncar(texto: string, limite = LIMITE_DO_EVENTO): string {
  return texto.length > limite ? `${texto.slice(0, limite - 1)}…` : texto
}

const REGRAS_DO_MODO_TAREFA = `Você está trabalhando numa tarefa do orquestrador, não numa conversa.

- Ninguém está olhando esta conversa enquanto você trabalha. Não pergunte no texto: se faltar
  algo que muda o resultado, chame a ferramenta pedir_ajuda com o motivo e pare.
- Sua última resposta é a entrega. Escreva para o Ueslei ler depois: o que foi feito, o que
  encontrou e o que ficou de fora.
- Use a ferramenta comentar só para registrar progresso que vale ler mesmo se a execução cair.
- Comando negado é definitivo: relate na entrega e pare.`

function rotuloDoRegistro(r: Registro): string {
  const quem = r.autor === "ueslei" ? "Ueslei" : r.autor
  switch (r.tipo) {
    case "comentario":
      return `- ${quem} comentou: ${r.texto}`
    case "entrega":
      return `- ${quem} entregou: ${r.texto}`
    case "ajuda":
      return `- ${quem} pediu ajuda: ${r.texto}`
    default:
      return `- status (${quem}): ${r.texto}`
  }
}

export function blocoDaTarefa(
  tarefa: Tarefa,
  pais: Tarefa[],
  registros: Registro[],
  persona: PersonaId,
  desde: string | null,
): string {
  const novos = registros.filter(
    (r) => (desde === null || r.em > desde) && r.autor !== persona && !r.autor.startsWith("execucao:") && r.autor !== "orquestra",
  )
  const partes = [
    REGRAS_DO_MODO_TAREFA,
    `## Tarefa #${tarefa.id}: ${tarefa.titulo}`,
    tarefa.descricao ? `### Descrição\n\n${tarefa.descricao}` : "",
    tarefa.porque ? `### Por quê\n\n${tarefa.porque}` : "",
    pais.length
      ? `### Faz parte de\n\n${pais.map((p) => `- #${p.id} ${p.titulo}${p.porque ? `: ${p.porque}` : ""}`).join("\n")}`
      : "",
    novos.length
      ? `### ${desde === null ? "Histórico" : "Desde a sua última execução"}\n\n${novos.map(rotuloDoRegistro).join("\n")}`
      : "",
  ]
  return `<tarefa>\n${partes.filter(Boolean).join("\n\n")}\n</tarefa>`
}
