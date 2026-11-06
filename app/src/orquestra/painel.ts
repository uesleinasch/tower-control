import type { Equipe } from "./equipe"
import type { Evento, Execucao } from "./execucao"
import { TUDO, planoPendente, type Gasto, type MotivoDeBloqueio } from "./governanca"
import { CHAVE_DO_BOARD, etapaAtual, etapaDoUeslei, ultimaEntrega } from "./politica"
import type { LinhaDeAuditoria } from "./repositorio"
import type { Disparo } from "./rotinas"
import type { Registro, StatusTarefa, Tarefa } from "./tarefa"
import type { Ficha, Fluxo } from "./repositorio"
import { interpolar, type Contexto } from "./workflow"

export type TipoDeAtencao =
  | "comando"
  | "aprovacao"
  | "decisao"
  | "plano"
  | "entrega"
  | "sinal"
  | "parada"
  | "bloqueada"
  | "atrasada"
  | "backlog"
  | "orcamento"
  | "rotina"
  | "vaga"
export type AcaoDoPainel =
  | "aprovar"
  | "negar"
  | "pedir-mudanca"
  | "aprovar-plano"
  | "concluir"
  | "liberar"
  | "abrir"
  | "decidir"
  | "sinalizar"
  | "recriar"
  | "cancelar-fluxo"

export interface ItemDeAtencao {
  tipo: TipoDeAtencao
  titulo: string
  detalhe: string
  desde: string
  acoes: AcaoDoPainel[]
  tarefaId?: number
  permissaoId?: string
  conversaId?: string
  persona?: string
  equipe?: string
  rotina?: string
  fluxo?: number
  ficha?: number
  opcoes?: string[]
}

export interface FluxoNoPainel {
  fluxo: number
  equipe: string
  workflow: string
  nome: string
  desde: string
  ativas: { ficha: number; no: string; titulo: string; tipo: string; tarefaId: number | null; parada?: true }[]
}

export interface ExecucaoViva {
  execucao: number
  tarefaId: number
  titulo: string
  equipe: string
  persona: string | null
  papel: "executa" | "revisa" | "board"
  inicio: string
  ultimoEvento: { tipo: string; conteudo: string; em: string } | null
}

export interface Espera {
  execucao: number
  tarefaId: number
  titulo: string
  persona: string | null
  motivo: string
  desde: string
}

export type EstadoDaPersona = "rodando" | "na_fila" | "ocioso" | "pausada" | "sem_orcamento"

export interface CartaoDePersona {
  id: string
  nome: string
  cor: string
  estado: EstadoDaPersona
  tarefaId: number | null
  gastoMesUSD: number
  limiteUSD: number | null
  tokensMes: number
  limiteTokens: number | null
  abertas: number
}

export interface ItemDeAtividade {
  em: string
  tipo: "entrega" | "plano" | "ajuda" | "decisao" | "comentario" | "auditoria" | "disparo"
  quem: string
  texto: string
  tarefaId?: number
  equipe?: string
}

export interface Retrato {
  em: string
  pausadoTudo: boolean
  atencao: ItemDeAtencao[]
  agora: { rodando: ExecucaoViva[]; naFila: Espera[] }
  personas: CartaoDePersona[]
  tarefas: Record<string, Partial<Record<StatusTarefa, number>>>
  gasto: { mes: string; tarefasUSD: number; totalUSD: number; tokensTarefas: number; tokensTotal: number }
  proximasRotinas: { equipe: string; id: string; nome: string; proximo: string }[]
  atividade: ItemDeAtividade[]
  workflows: FluxoNoPainel[]
}

export interface PersonaDoPainel {
  id: string
  nome: string
  cor: string
  limiteUSD: number | null
  limiteTokens: number | null
  gasto: Gasto
}

export interface ComandoPendente {
  id: string
  comando: string
  quem: string
  desde: string
  tarefaId?: number
  conversaId?: string
}

export interface RotinaDoPainel {
  equipe: string | null
  id: string
  nome: string
  ativa: boolean
  proximo: string | null
  ultimoDisparo: Disparo | null
  sistema?: boolean
}

export interface DadosDoPainel {
  agora: Date
  mes: string
  teto: number
  pausas: ReadonlyMap<string, string>
  bloqueio: (persona: string) => MotivoDeBloqueio | null
  equipes: Equipe[]
  personas: PersonaDoPainel[]
  tarefas: Tarefa[]
  registros: (tarefa: number) => Registro[]
  rodando: Execucao[]
  naFila: Execucao[]
  personaDaFila: (execucao: Execucao) => string | null
  ultimoEvento: (execucao: number) => Evento | undefined
  comandos: ComandoPendente[]
  rotinas: RotinaDoPainel[]
  registrosRecentes: (Registro & { equipe: string })[]
  auditoria: LinhaDeAuditoria[]
  disparos: Disparo[]
  fluxos?: { fluxo: Fluxo; fichas: Ficha[] }[]
}

export const LIMITE_DO_DETALHE = 180
export const LIMITE_DA_ATIVIDADE = 100

const PRIORIDADE: Record<TipoDeAtencao, number> = {
  comando: 1,
  aprovacao: 2,
  decisao: 3,
  plano: 4,
  entrega: 5,
  sinal: 6,
  parada: 7,
  bloqueada: 8,
  atrasada: 9,
  backlog: 10,
  orcamento: 11,
  rotina: 12,
  vaga: 13,
}

export function cortar(texto: string, limite = LIMITE_DO_DETALHE): string {
  const corrido = texto.replace(/\s+/g, " ").trim()
  return corrido.length > limite ? `${corrido.slice(0, limite - 1)}…` : corrido
}

const ABERTAS: readonly StatusTarefa[] = ["backlog", "a_fazer", "em_andamento", "em_revisao", "bloqueada"]

function posicaoDa(equipes: Equipe[], tarefa: Pick<Tarefa, "equipe" | "posicao">) {
  return equipes.find((e) => e.id === tarefa.equipe)?.posicoes.find((p) => p.id === tarefa.posicao)
}

function nomeDe(dados: DadosDoPainel, persona: string): string {
  if (persona === CHAVE_DO_BOARD || persona === "board") return "o board"
  if (persona === "ueslei") return "Ueslei"
  return dados.personas.find((p) => p.id === persona)?.nome ?? persona
}

function atencaoDaTarefa(dados: DadosDoPainel, t: Tarefa): ItemDeAtencao | undefined {
  const base = { tarefaId: t.id, equipe: t.equipe, desde: t.atualizadaEm }
  if (t.status === "em_revisao") {
    const registros = dados.registros(t.id)
    const entrega = ultimaEntrega(registros)
    if (etapaDoUeslei(t)) {
      return {
        ...base,
        tipo: "aprovacao",
        titulo: `#${t.id} espera sua aprovação`,
        detalhe: cortar(`${t.titulo}: ${entrega?.texto ?? ""}`),
        acoes: ["aprovar", "pedir-mudanca", "abrir"],
      }
    }
    if (etapaAtual(t)) return undefined
    if (planoPendente(registros)) {
      const plano = registros.findLast((r) => r.tipo === "plano")!
      return {
        ...base,
        tipo: "plano",
        titulo: `${nomeDe(dados, plano.autor)} propôs um plano para #${t.id}`,
        detalhe: cortar(plano.texto),
        acoes: ["aprovar-plano", "abrir"],
      }
    }
    return {
      ...base,
      tipo: "entrega",
      titulo: entrega ? `${nomeDe(dados, entrega.autor)} entregou #${t.id}` : `#${t.id} em revisão com você`,
      detalhe: cortar(entrega ? `${t.titulo}: ${entrega.texto}` : t.titulo),
      acoes: ["concluir", "abrir"],
    }
  }
  if (t.status === "bloqueada") {
    const motivo = dados
      .registros(t.id)
      .findLast((r) => r.tipo === "ajuda" || (r.tipo === "status" && r.autor === "orquestra" && r.texto.startsWith("bloqueada")))
    return {
      ...base,
      tipo: "bloqueada",
      titulo: `#${t.id} bloqueada`,
      detalhe: cortar(motivo ? `${t.titulo}: ${motivo.texto}` : t.titulo),
      acoes: ["abrir"],
    }
  }
  if (t.status === "backlog" && t.pai !== null && t.criadaPor.startsWith("execucao:")) {
    return {
      ...base,
      tipo: "backlog",
      titulo: `#${t.id} delegada espera ser liberada`,
      detalhe: cortar(t.titulo),
      acoes: ["liberar", "abrir"],
    }
  }
  if (t.status === "a_fazer") {
    const posicao = posicaoDa(dados.equipes, t)
    if (posicao && posicao.persona === null) {
      return {
        ...base,
        tipo: "vaga",
        titulo: `#${t.id} numa posição vaga`,
        detalhe: cortar(`${posicao.titulo}: ${t.titulo}`),
        acoes: ["abrir"],
      }
    }
  }
  return undefined
}

export function itensDeAtencao(dados: DadosDoPainel): ItemDeAtencao[] {
  const itens: ItemDeAtencao[] = dados.comandos.map((c) => ({
    tipo: "comando",
    titulo: `${c.quem} quer rodar um comando${c.tarefaId ? ` em #${c.tarefaId}` : " na conversa"}`,
    detalhe: cortar(c.comando),
    desde: c.desde,
    acoes: ["aprovar", "negar"],
    permissaoId: c.id,
    ...(c.tarefaId ? { tarefaId: c.tarefaId } : {}),
    ...(c.conversaId ? { conversaId: c.conversaId } : {}),
  }))
  for (const t of dados.tarefas) {
    const item = atencaoDaTarefa(dados, t)
    if (item) itens.push(item)
  }
  for (const p of dados.personas) {
    if (dados.bloqueio(p.id) !== "orcamento") continue
    const esperando = dados.naFila.filter((e) => dados.personaDaFila(e) === p.id)
    if (!esperando.length) continue
    const valores = [
      p.limiteUSD !== null ? `US$ ${p.gasto.tarefas.toFixed(2)} de US$ ${p.limiteUSD.toFixed(2)}` : "",
      p.limiteTokens !== null ? `${p.gasto.tokensTarefas} de ${p.limiteTokens} tokens` : "",
    ].filter(Boolean)
    itens.push({
      tipo: "orcamento",
      titulo: `${p.nome} sem orçamento`,
      detalhe: cortar(`${valores.join(" · ")} · ${esperando.length} tarefa(s) esperando`),
      desde: esperando.map((e) => e.criadaEm).sort()[0]!,
      acoes: ["abrir"],
      persona: p.id,
    })
  }
  for (const { fluxo, fichas } of dados.fluxos ?? []) {
    if (fluxo.status !== "rodando") continue
    const contexto: Contexto = { entrada: fluxo.entrada }
    for (const f of fichas) if (f.status === "concluida") contexto[f.no] = f.saidas
    for (const ficha of fichas) {
      if (ficha.status !== "esperando" && ficha.status !== "parada") continue
      const no = fluxo.definicao.nos.find((n) => n.id === ficha.no)
      if (!no) continue
      const caixa = no.titulo ?? no.id
      const base = { fluxo: fluxo.id, ficha: ficha.id, equipe: fluxo.equipe, desde: ficha.criadaEm }
      if (ficha.status === "parada") {
        itens.push({
          ...base,
          tipo: "parada",
          titulo: `Caixa parada no workflow #${fluxo.id}`,
          detalhe: cortar(
            `A tarefa #${ficha.tarefa ?? "?"} da caixa "${caixa}" foi cancelada. O workflow "${fluxo.definicao.nome}" está esperando você decidir.`,
          ),
          desde: ficha.concluidaEm ?? ficha.criadaEm,
          acoes: ["recriar", "cancelar-fluxo"],
          ...(ficha.tarefa ? { tarefaId: ficha.tarefa } : {}),
        })
      } else if (no.tipo === "decisao_humana") {
        itens.push({
          ...base,
          tipo: "decisao",
          titulo: `${fluxo.definicao.nome} pergunta`,
          detalhe: cortar(interpolar(no.pergunta, contexto)),
          acoes: ["decidir"],
          opcoes: no.opcoes,
        })
      } else if (no.tipo === "espera" && no.sinal) {
        itens.push({ ...base, tipo: "sinal", titulo: `${fluxo.definicao.nome} espera o sinal "${no.sinal}"`, detalhe: caixa, acoes: ["sinalizar"] })
      } else if (no.tipo !== "espera" && ficha.prazoEm && Date.parse(ficha.prazoEm) <= dados.agora.getTime()) {
        itens.push({
          ...base,
          tipo: "atrasada",
          titulo: `${fluxo.definicao.nome}: ${caixa} passou do prazo`,
          detalhe: `prazo de ${no.prazo ?? ""}`,
          desde: ficha.prazoEm,
          acoes: ["abrir"],
          ...(ficha.tarefa ? { tarefaId: ficha.tarefa } : {}),
        })
      }
    }
  }
  for (const r of dados.rotinas) {
    if (r.ultimoDisparo?.resultado !== "falhou") continue
    itens.push({
      tipo: "rotina",
      titulo: `A rotina ${r.nome} falhou`,
      detalhe: cortar(r.ultimoDisparo.motivo),
      desde: r.ultimoDisparo.em,
      acoes: ["abrir"],
      rotina: r.id,
      ...(r.equipe ? { equipe: r.equipe } : {}),
    })
  }
  return itens.sort((a, b) => PRIORIDADE[a.tipo] - PRIORIDADE[b.tipo] || a.desde.localeCompare(b.desde))
}

const hora = (iso: string) => {
  const d = new Date(iso)
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`
}

export function motivoDaEspera(dados: DadosDoPainel, execucao: Execucao, tarefa: Tarefa | undefined): string {
  const persona = dados.personaDaFila(execucao)
  if (dados.pausas.has(TUDO)) return "tudo pausado"
  if (persona && dados.pausas.has(persona)) return `${nomeDe(dados, persona)} pausada`
  if (persona && dados.bloqueio(persona) === "orcamento") return `${nomeDe(dados, persona)} sem orçamento`
  if (persona === null) return execucao.etapa !== null && execucao.posicao === "board" ? "board sem membros disponíveis" : "posição vaga"
  const pendente = tarefa?.dependeDe.find((d) => dados.tarefas.find((t) => t.id === d)?.status !== "concluida")
  if (execucao.etapa === null && pendente !== undefined) return `depende da #${pendente}`
  if (execucao.naoAntes && Date.parse(execucao.naoAntes) > dados.agora.getTime()) return `nova tentativa às ${hora(execucao.naoAntes)}`
  const ocupada = dados.rodando.find((r) => r.persona === persona || (persona === CHAVE_DO_BOARD && r.persona === null))
  if (ocupada) return `${nomeDe(dados, persona)} ocupada com a #${ocupada.tarefa}`
  if (dados.rodando.length >= dados.teto) return `limite de ${dados.teto} execuções ao mesmo tempo`
  return "esperando a vez"
}

function agora(dados: DadosDoPainel): Retrato["agora"] {
  const tarefa = (id: number) => dados.tarefas.find((t) => t.id === id)
  const rodando = dados.rodando.map((e): ExecucaoViva => {
    const t = tarefa(e.tarefa)
    const evento = dados.ultimoEvento(e.id)
    return {
      execucao: e.id,
      tarefaId: e.tarefa,
      titulo: t?.titulo ?? `#${e.tarefa}`,
      equipe: t?.equipe ?? "",
      persona: e.persona ? nomeDe(dados, e.persona) : null,
      papel: e.etapa === null ? "executa" : e.persona === null ? "board" : "revisa",
      inicio: e.inicio ?? e.criadaEm,
      ultimoEvento: evento ? { tipo: evento.tipo, conteudo: cortar(evento.conteudo), em: evento.em } : null,
    }
  })
  const naFila = dados.naFila.map((e): Espera => {
    const t = tarefa(e.tarefa)
    const persona = dados.personaDaFila(e)
    return {
      execucao: e.id,
      tarefaId: e.tarefa,
      titulo: t?.titulo ?? `#${e.tarefa}`,
      persona: persona ? nomeDe(dados, persona) : null,
      motivo: motivoDaEspera(dados, e, t),
      desde: e.criadaEm,
    }
  })
  return { rodando, naFila }
}

export function cartoesDePersonas(dados: DadosDoPainel): CartaoDePersona[] {
  return dados.personas.map((p) => {
    const rodando = dados.rodando.find((e) => e.persona === p.id)
    const naFila = dados.naFila.find((e) => dados.personaDaFila(e) === p.id)
    const estado: EstadoDaPersona = rodando
      ? "rodando"
      : dados.pausas.has(p.id) || dados.pausas.has(TUDO)
        ? "pausada"
        : dados.bloqueio(p.id) === "orcamento"
          ? "sem_orcamento"
          : naFila
            ? "na_fila"
            : "ocioso"
    const abertas = dados.tarefas.filter((t) => ABERTAS.includes(t.status) && posicaoDa(dados.equipes, t)?.persona === p.id).length
    return {
      id: p.id,
      nome: p.nome,
      cor: p.cor,
      estado,
      tarefaId: rodando?.tarefa ?? naFila?.tarefa ?? null,
      gastoMesUSD: p.gasto.tarefas,
      limiteUSD: p.limiteUSD,
      tokensMes: p.gasto.tokensTarefas,
      limiteTokens: p.limiteTokens,
      abertas,
    }
  })
}

const TIPO_DO_REGISTRO: Partial<Record<Registro["tipo"], ItemDeAtividade["tipo"]>> = {
  entrega: "entrega",
  plano: "plano",
  ajuda: "ajuda",
  aprovado: "decisao",
  mudanca: "decisao",
  comentario: "comentario",
}

export const TIPOS_DA_ATIVIDADE = Object.keys(TIPO_DO_REGISTRO) as Registro["tipo"][]

export function atividade(dados: DadosDoPainel, personaDaExecucao: (id: number) => string | null): ItemDeAtividade[] {
  const itens: ItemDeAtividade[] = []
  for (const r of dados.registrosRecentes) {
    const tipo = TIPO_DO_REGISTRO[r.tipo]
    if (!tipo) continue
    const rotulo = r.tipo === "aprovado" ? "aprovou" : r.tipo === "mudanca" ? "pediu mudança" : ""
    const texto = !rotulo ? r.texto : r.texto === rotulo ? rotulo : `${rotulo}: ${r.texto}`
    itens.push({ em: r.em, tipo, quem: r.autor, texto: cortar(texto, 300), tarefaId: r.tarefa, equipe: r.equipe })
  }
  for (const a of dados.auditoria) {
    const execucao = a.quem.match(/^execucao:(\d+)$/)
    const quem = execucao ? (personaDaExecucao(Number(execucao[1])) ?? a.quem) : a.quem
    const tarefa = a.alvo.match(/^tarefa:(\d+)$/)
    itens.push({
      em: a.em,
      tipo: "auditoria",
      quem,
      texto: cortar([a.acao, a.alvo, a.detalhe].filter(Boolean).join(" · "), 300),
      ...(tarefa ? { tarefaId: Number(tarefa[1]) } : {}),
    })
  }
  for (const d of dados.disparos) {
    const nome = dados.rotinas.find((r) => r.equipe === d.equipe && r.id === d.rotina)?.nome ?? d.rotina
    const resultado = d.resultado === "criada" ? `criou a #${d.tarefa}` : d.resultado === "pulada" ? "pulou" : "falhou"
    itens.push({
      em: d.em,
      tipo: "disparo",
      quem: nome,
      texto: cortar(`${d.origem}: ${resultado}${d.motivo ? ` (${d.motivo})` : ""}`, 300),
      ...(d.tarefa ? { tarefaId: d.tarefa } : {}),
      equipe: d.equipe,
    })
  }
  return itens.sort((a, b) => b.em.localeCompare(a.em)).slice(0, LIMITE_DA_ATIVIDADE)
}

export function montarRetrato(dados: DadosDoPainel, personaDaExecucao: (id: number) => string | null = () => null): Retrato {
  const tarefas: Retrato["tarefas"] = {}
  for (const t of dados.tarefas) {
    const daEquipe = (tarefas[t.equipe] ??= {})
    daEquipe[t.status] = (daEquipe[t.status] ?? 0) + 1
  }
  const gasto = dados.personas.reduce(
    (soma, p) => ({
      mes: soma.mes,
      tarefasUSD: soma.tarefasUSD + p.gasto.tarefas,
      totalUSD: soma.totalUSD + p.gasto.total,
      tokensTarefas: soma.tokensTarefas + p.gasto.tokensTarefas,
      tokensTotal: soma.tokensTotal + p.gasto.tokensTotal,
    }),
    { mes: dados.mes, tarefasUSD: 0, totalUSD: 0, tokensTarefas: 0, tokensTotal: 0 },
  )
  const proximasRotinas = dados.rotinas
    .filter((r): r is RotinaDoPainel & { equipe: string; proximo: string } => !r.sistema && r.ativa && r.equipe !== null && r.proximo !== null)
    .sort((a, b) => a.proximo.localeCompare(b.proximo))
    .slice(0, 5)
    .map((r) => ({ equipe: r.equipe, id: r.id, nome: r.nome, proximo: r.proximo }))
  return {
    em: dados.agora.toISOString(),
    pausadoTudo: dados.pausas.has(TUDO),
    atencao: itensDeAtencao(dados),
    agora: agora(dados),
    personas: cartoesDePersonas(dados),
    tarefas,
    gasto,
    proximasRotinas,
    atividade: atividade(dados, personaDaExecucao),
    workflows: (dados.fluxos ?? [])
      .filter(({ fluxo }) => fluxo.status === "rodando" || fluxo.status === "esperando")
      .map(({ fluxo, fichas }) => ({
        fluxo: fluxo.id,
        equipe: fluxo.equipe,
        workflow: fluxo.workflow,
        nome: fluxo.definicao.nome,
        desde: fluxo.criadoEm,
        ativas: fichas
          .filter((f) => f.status === "esperando" || f.status === "parada")
          .map((f) => {
            const no = fluxo.definicao.nos.find((n) => n.id === f.no)
            return {
              ficha: f.id,
              no: f.no,
              titulo: no?.titulo ?? f.no,
              tipo: no?.tipo ?? "",
              tarefaId: f.tarefa,
              ...(f.status === "parada" ? { parada: true as const } : {}),
            }
          }),
      })),
  }
}

export class AssinaturaDoPainel<C> {
  private readonly assinantes = new Set<C>()
  private agendado: ReturnType<typeof setTimeout> | undefined
  private ultimo = Number.NEGATIVE_INFINITY

  constructor(
    private readonly montar: () => Retrato,
    private readonly mandar: (cliente: C, retrato: Retrato) => void,
    private readonly ritmoMs = 1_000,
    private readonly relogio: () => number = Date.now,
  ) {}

  get quantos(): number {
    return this.assinantes.size
  }

  assinar(cliente: C): void {
    this.assinantes.add(cliente)
    this.ultimo = this.relogio()
    this.mandar(cliente, this.montar())
  }

  sair(cliente: C): void {
    this.assinantes.delete(cliente)
  }

  mudou(): void {
    if (!this.assinantes.size || this.agendado) return
    const espera = Math.max(0, this.ultimo + this.ritmoMs - this.relogio())
    this.agendado = setTimeout(() => this.enviar(), espera)
  }

  private enviar(): void {
    this.agendado = undefined
    this.ultimo = this.relogio()
    if (!this.assinantes.size) return
    const retrato = this.montar()
    for (const cliente of this.assinantes) this.mandar(cliente, retrato)
  }
}
