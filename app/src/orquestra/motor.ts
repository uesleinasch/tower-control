import type { Equipe } from "./equipe"
import type { Ficha, Fluxo, Repositorio } from "./repositorio"
import { ultimaEntrega } from "./politica"
import type { StatusTarefa, Tarefa } from "./tarefa"
import {
  avaliar,
  corrente,
  duracaoEmMs,
  etapasDaCorrente,
  interpolar,
  nomeDoTipo,
  proximoHorarioDoDia,
  validarValores,
  QUANDO_SENAO,
  type Contexto,
  type No,
  type Saidas,
  type Valor,
  type Workflow,
} from "./workflow"
import type { NovoAviso } from "../avisos/central"

export interface PedidoDeDeliberacao {
  titulo: string
  pauta: string
  opcoes?: string[]
  equipe: string
  fluxo: number
}

export interface AmbienteDoMotor {
  repo: Repositorio
  equipe: (id: string) => Equipe | undefined
  aoCriarTarefa: (tarefa: Tarefa) => void
  aoCancelarTarefa: (id: number, de: StatusTarefa) => void
  publicarTarefa: (id: number) => void
  publicarFluxos: () => void
  avisar: (aviso: NovoAviso) => void
  deliberar?: (pedido: PedidoDeDeliberacao) => Promise<{ sintese: string; decisao: string | null }>
  tudoPausado: () => boolean
  agora?: () => Date
}

export const MAX_FICHAS_VIVAS = 20
export const MAX_FICHAS_CRIADAS = 200
export const SEM_DEVOLUCAO = "a caixa terminou sem chamar devolver"
const TENTATIVAS_DO_BOARD = 2
const ESPERA_DO_BOARD_MS = 5 * 60_000

type Depois = (() => void)[]

class FluxoParado extends Error {}

export type EscopoDoCancelamento = "tarefa" | "fluxo"

const viva = (f: Ficha) => f.status === "esperando" || f.status === "parada"
const chave = (equipe: string, id: string) => `${equipe}/${id}`
const nomeDaCaixa = (no: No) => no.titulo ?? no.id
const autorDoFluxo = (id: number) => `fluxo:${id}`

function avisoDoFluxo(titulo: string, corpo: string, alvo: NovoAviso["alvo"] = {}): NovoAviso {
  const resumo = corpo.replace(/\s+/g, " ").trim()
  return { tipo: "tarefa", titulo, corpo: resumo.length > 180 ? `${resumo.slice(0, 179)}…` : resumo || "(sem texto)", alvo, acoes: [] }
}

export function descricaoDaCaixa(no: Extract<No, { tipo: "executar" }>, contexto: Contexto): string {
  const partes = [interpolar(no.instrucao, contexto)]
  if (no.criterio) partes.push(`### O que se espera\n\n${interpolar(no.criterio, contexto)}`)
  if (no.saidas) {
    const campos = Object.entries(no.saidas).map(([campo, tipo]) => `- ${campo}: ${nomeDoTipo(tipo)}`)
    partes.push(`### Devolutiva\n\nAntes de terminar, chame a ferramenta devolver com:\n${campos.join("\n")}`)
  }
  return partes.join("\n\n")
}

export class Motor {
  private readonly definicoes = new Map<string, { equipe: string; workflow: Workflow }>()
  private readonly deliberando = new Set<number>()
  private readonly falhasDoBoard = new Map<number, { vezes: number; ate: number }>()

  constructor(private readonly amb: AmbienteDoMotor) {}

  private get repo(): Repositorio {
    return this.amb.repo
  }

  private agora(): Date {
    return this.amb.agora?.() ?? new Date()
  }

  carregar(lista: { equipe: string; workflow: Workflow }[]): void {
    this.definicoes.clear()
    for (const item of lista) this.definicoes.set(chave(item.equipe, item.workflow.id), item)
  }

  definir(equipe: string, workflow: Workflow): void {
    this.definicoes.set(chave(equipe, workflow.id), { equipe, workflow })
  }

  remover(equipe: string, id: string): void {
    this.definicoes.delete(chave(equipe, id))
  }

  removerDaEquipe(equipe: string): void {
    for (const d of this.daEquipe(equipe)) this.remover(equipe, d.id)
  }

  definicao(equipe: string, id: string): Workflow | undefined {
    return this.definicoes.get(chave(equipe, id))?.workflow
  }

  daEquipe(equipe: string): Workflow[] {
    return [...this.definicoes.values()].filter((d) => d.equipe === equipe).map((d) => d.workflow)
  }

  todas(): { equipe: string; workflow: Workflow }[] {
    return [...this.definicoes.values()]
  }

  private emTransacao<T>(acao: (depois: Depois) => T): T {
    const depois: Depois = []
    const resultado = this.repo.db.transaction(() => acao(depois))()
    for (const passo of depois) passo()
    this.amb.publicarFluxos()
    return resultado
  }

  private no(fluxo: Fluxo, id: string): No {
    const no = fluxo.definicao.nos.find((n) => n.id === id)
    if (!no) throw new Error(`o workflow ${fluxo.workflow} não tem a caixa ${id}`)
    return no
  }

  contexto(fluxo: Fluxo): Contexto {
    const contexto: Contexto = { entrada: fluxo.entrada }
    for (const f of this.repo.fichasDo(fluxo.id)) if (f.status === "concluida") contexto[f.no] = f.saidas
    return contexto
  }

  // ── início ───────────────────────────────────────────────────────

  iniciar(equipe: string, id: string, entradaBruta: unknown, criadoPor: string, depoisDe: number | null = null): Fluxo {
    const workflow = this.definicao(equipe, id)
    if (!workflow) throw new Error(`o workflow ${id} não existe na equipe ${equipe}`)
    const entrada = validarValores(workflow.entrada, entradaBruta ?? {})
    const fluxo = this.emTransacao(() =>
      this.repo.criarFluxo({
        equipe,
        workflow: id,
        versao: workflow.versao,
        definicao: workflow,
        entrada,
        status: depoisDe === null ? "rodando" : "esperando",
        criadoPor,
        depoisDe,
        criadoEm: this.agora().toISOString(),
      }),
    )
    if (depoisDe === null) this.protegido(fluxo.id, (depois) => this.chegar(fluxo, workflow.inicio, null, depois))
    return this.repo.exigirFluxo(fluxo.id)
  }

  // Cada enfileirado começa na própria transação: o freio de um não desfaz o fim do anterior.
  private comecarEnfileirados(id: number, depois: Depois): void {
    for (const f of this.repo.fluxosEsperandoPor(id)) {
      depois.push(() =>
        this.protegido(f.id, (d) => {
          const fluxo = this.repo.mudarFluxo(f.id, { status: "rodando" })
          this.chegar(fluxo, fluxo.definicao.inicio, null, d)
        }),
      )
    }
  }

  // ── andar ────────────────────────────────────────────────────────

  private chegar(fluxo: Fluxo, noId: string, veioDe: Ficha | null, depois: Depois): void {
    const atual = this.repo.exigirFluxo(fluxo.id)
    if (atual.status !== "rodando") return
    const fichas = this.repo.fichasDo(fluxo.id)
    if (fichas.length >= MAX_FICHAS_CRIADAS) throw new FluxoParado(`passou de ${MAX_FICHAS_CRIADAS} caixas`)
    if (fichas.filter(viva).length >= MAX_FICHAS_VIVAS) {
      throw new FluxoParado(`passou de ${MAX_FICHAS_VIVAS} caixas ao mesmo tempo`)
    }
    const no = this.no(atual, noId)
    const agora = this.agora()
    if (no.tipo === "juncao") {
      const origem = veioDe?.no ?? ""
      const aberta = fichas.find((f) => f.no === noId && f.status === "esperando")
      const ficha = aberta
        ? this.repo.mudarFicha(aberta.id, { chegadas: [...aberta.chegadas, origem] })
        : this.repo.criarFicha({ fluxo: fluxo.id, no: noId, veioDe: veioDe?.id ?? null, chegadas: [origem] }, agora)
      const precisa = atual.definicao.arestas.filter((a) => a.para === noId).length
      if (ficha.chegadas.length >= precisa) this.concluir(ficha, {}, undefined, depois)
      return
    }
    const prazo = no.prazo ? new Date(agora.getTime() + duracaoEmMs(no.prazo)!).toISOString() : null
    const acordaEm =
      no.tipo === "espera" && no.duracao
        ? new Date(agora.getTime() + duracaoEmMs(no.duracao)!).toISOString()
        : no.tipo === "espera" && no.ate
          ? proximoHorarioDoDia(no.ate, agora).toISOString()
          : null
    const ficha = this.repo.criarFicha({ fluxo: fluxo.id, no: noId, veioDe: veioDe?.id ?? null, acordaEm, prazoEm: prazo }, agora)
    const contexto = this.contexto(atual)
    switch (no.tipo) {
      case "condicao": {
        const regra = no.regras.find((r) => avaliar(r, contexto))
        this.concluir(ficha, {}, regra?.saida ?? QUANDO_SENAO, depois)
        return
      }
      case "paralelo":
      case "fim":
        this.concluir(ficha, {}, undefined, depois)
        return
      case "laco": {
        const voltas = fichas.filter((f) => f.no === noId).length + 1
        const repetir = voltas <= no.maxVoltas && avaliar(no.enquanto, contexto)
        this.concluir(ficha, { voltas }, repetir ? "repetir" : "sair", depois)
        return
      }
      case "executar":
        this.criarTarefaDaCaixa(
          ficha,
          {
            posicao: no.posicao,
            titulo: `${atual.definicao.nome}: ${nomeDaCaixa(no)}`,
            descricao: descricaoDaCaixa(no, contexto),
            porque: `Caixa ${nomeDaCaixa(no)} do workflow ${atual.definicao.nome}.`,
          },
          atual,
          depois,
        )
        return
      case "decisao_humana":
        depois.push(() =>
          this.amb.avisar(avisoDoFluxo(`${atual.definicao.nome} pergunta`, interpolar(no.pergunta, contexto), { fluxo: fluxo.id, ficha: ficha.id })),
        )
        return
      case "board":
        depois.push(() => void this.deliberar(ficha.id))
        return
      case "espera":
        return
      case "revisar":
      case "aprovar":
        throw new FluxoParado(`a caixa ${noId} só pode vir logo depois da caixa executar ${no.de}`)
    }
  }

  private criarTarefaDaCaixa(
    ficha: Ficha,
    texto: Pick<Tarefa, "posicao" | "titulo" | "descricao" | "porque">,
    fluxo: Fluxo,
    depois: Depois,
  ): Tarefa {
    const tarefa = this.repo.criar(
      {
        equipe: fluxo.equipe,
        posicao: texto.posicao,
        titulo: texto.titulo.slice(0, 200),
        descricao: texto.descricao.slice(0, 20_000),
        porque: texto.porque,
        pai: null,
        dependeDe: [],
        status: "a_fazer",
        politica: [],
        fluxo: fluxo.id,
        ficha: ficha.id,
      },
      autorDoFluxo(fluxo.id),
      this.agora(),
    )
    this.repo.ligarFicha(tarefa.id, ficha.id)
    depois.push(() => {
      this.amb.publicarTarefa(tarefa.id)
      this.amb.aoCriarTarefa(this.repo.exigir(tarefa.id))
    })
    return tarefa
  }

  private seguir(fluxo: Fluxo, deNo: string, quando: string | undefined, veioDe: Ficha, depois: Depois): void {
    const no = this.no(fluxo, deNo)
    const arestas = fluxo.definicao.arestas.filter((a) => a.de === deNo && (no.tipo === "paralelo" || a.quando === quando))
    for (const a of arestas) this.chegar(fluxo, a.para, veioDe, depois)
  }

  private concluir(ficha: Ficha, saidas: Record<string, Valor>, quando: string | undefined, depois: Depois): void {
    const feita = this.repo.mudarFicha(ficha.id, { status: "concluida", saidas: { ...ficha.saidas, ...saidas } })
    const fluxo = this.repo.exigirFluxo(ficha.fluxo)
    if (fluxo.status !== "rodando") return
    const no = this.no(fluxo, ficha.no)
    if (no.tipo === "fim" && no.resultado) this.repo.mudarFluxo(fluxo.id, { resultado: no.resultado })
    this.seguir(fluxo, ficha.no, quando, feita, depois)
    this.fecharSePronto(fluxo.id, depois)
  }

  private fecharSePronto(id: number, depois: Depois): void {
    const fluxo = this.repo.exigirFluxo(id)
    if (fluxo.status !== "rodando") return
    if (this.repo.fichasDo(id).some(viva)) return
    this.repo.mudarFluxo(id, { status: "concluido" })
    depois.push(() =>
      this.amb.avisar(avisoDoFluxo(`${fluxo.definicao.nome} terminou`, fluxo.resultado ?? "Todas as caixas foram concluídas.", { fluxo: id })),
    )
    this.comecarEnfileirados(id, depois)
  }

  private protegido(fluxoId: number, acao: (depois: Depois) => void): void {
    try {
      this.emTransacao(acao)
    } catch (erro) {
      if (!(erro instanceof FluxoParado)) throw erro
      this.falhar(fluxoId, erro.message)
    }
  }

  // ── eventos do runtime ───────────────────────────────────────────

  saidasDa(tarefa: Pick<Tarefa, "ficha">): Saidas | undefined {
    if (tarefa.ficha === null) return undefined
    const ficha = this.repo.ficha(tarefa.ficha)
    if (!ficha) return undefined
    const no = this.no(this.repo.exigirFluxo(ficha.fluxo), ficha.no)
    return no.tipo === "executar" && no.saidas ? no.saidas : undefined
  }

  private fichaViva(tarefa: Pick<Tarefa, "ficha">): { ficha: Ficha; fluxo: Fluxo } | undefined {
    if (tarefa.ficha === null) return undefined
    const ficha = this.repo.ficha(tarefa.ficha)
    if (!ficha || ficha.status !== "esperando") return undefined
    const fluxo = this.repo.exigirFluxo(ficha.fluxo)
    return fluxo.status === "rodando" ? { ficha, fluxo } : undefined
  }

  // Devolve true quando o motor cuidou da entrega; false deixa o runtime seguir com a política.
  aoEntregar(tarefa: Tarefa, entrega: string, devolvido?: Record<string, Valor>): boolean {
    const viva = this.fichaViva(tarefa)
    if (!viva) return false
    let cuidou = false
    this.protegido(viva.fluxo.id, (depois) => {
      const saidas = { ...viva.ficha.saidas, ...(devolvido ?? {}), devolutiva: entrega }
      const ficha = this.repo.mudarFicha(viva.ficha.id, { saidas })
      if (tarefa.politica.length) return
      const cadeia = corrente(viva.fluxo.definicao, ficha.no)
      if (cadeia.length) {
        this.repo.definirPolitica(tarefa.id, etapasDaCorrente(cadeia))
        return
      }
      this.repo.mudarStatus(tarefa.id, "concluida", autorDoFluxo(viva.fluxo.id))
      depois.push(() => this.amb.publicarTarefa(tarefa.id))
      this.concluir(ficha, {}, undefined, depois)
      cuidou = true
    })
    return cuidou
  }

  aoConcluir(tarefaId: number): void {
    const tarefa = this.repo.exigir(tarefaId)
    const viva = this.fichaViva(tarefa)
    if (!viva) return
    this.protegido(viva.fluxo.id, (depois) => {
      const registros = this.repo.registros(tarefa.id)
      const devolutiva = viva.ficha.saidas.devolutiva ?? ultimaEntrega(registros)?.texto ?? ""
      const ficha = this.repo.mudarFicha(viva.ficha.id, { status: "concluida", saidas: { ...viva.ficha.saidas, devolutiva } })
      const cadeia = corrente(viva.fluxo.definicao, ficha.no)
      const aprovados = registros.filter((r) => r.tipo === "aprovado").slice(-cadeia.length)
      let ultima = ficha
      cadeia.forEach((caixa, i) => {
        const criada = this.repo.criarFicha({ fluxo: viva.fluxo.id, no: caixa.id, veioDe: ultima.id }, this.agora())
        ultima = this.repo.mudarFicha(criada.id, { status: "concluida", saidas: { parecer: aprovados[i]?.texto ?? "" } })
      })
      this.seguir(viva.fluxo, ultima.no, cadeia.length ? "aprovado" : undefined, ultima, depois)
      this.fecharSePronto(viva.fluxo.id, depois)
    })
  }

  aoCancelar(tarefaId: number, escopo: EscopoDoCancelamento = "fluxo"): void {
    const viva = this.fichaViva(this.repo.exigir(tarefaId))
    if (!viva) return
    if (escopo === "fluxo") {
      this.cancelar(viva.fluxo.id, "ueslei", `a tarefa #${tarefaId} foi cancelada`)
      return
    }
    this.repo.auditar("ueslei", "parou a caixa do workflow", `fluxo:${viva.fluxo.id}`, `${viva.ficha.no}: a tarefa #${tarefaId} foi cancelada`)
    this.emTransacao(() => this.repo.mudarFicha(viva.ficha.id, { status: "parada" }, this.agora()))
  }

  recriar(fluxoId: number, fichaId: number): Tarefa {
    const parada = this.repo.exigirFicha(fichaId)
    const fluxo = this.repo.exigirFluxo(parada.fluxo)
    if (parada.fluxo !== fluxoId || parada.status !== "parada" || fluxo.status !== "rodando") throw new Error("essa caixa não está parada")
    const no = this.no(fluxo, parada.no)
    if (no.tipo !== "executar" || parada.tarefa === null) throw new Error("essa caixa não tem tarefa para recriar")
    const fichas = this.repo.fichasDo(fluxoId)
    if (fichas.length >= MAX_FICHAS_CRIADAS) throw new Error(`o workflow já passou de ${MAX_FICHAS_CRIADAS} caixas; cancele o workflow`)
    const antiga = this.repo.exigir(parada.tarefa)
    this.repo.auditar("ueslei", "recriou a caixa do workflow", `fluxo:${fluxoId}`, `${parada.no}: no lugar da #${antiga.id}`)
    return this.emTransacao((depois) => {
      const agora = this.agora()
      this.repo.mudarFicha(parada.id, { status: "cancelada" }, agora)
      const prazoEm = no.prazo ? new Date(agora.getTime() + duracaoEmMs(no.prazo)!).toISOString() : null
      const ficha = this.repo.criarFicha({ fluxo: fluxoId, no: parada.no, veioDe: parada.veioDe, prazoEm }, agora)
      return this.criarTarefaDaCaixa(ficha, antiga, fluxo, depois)
    })
  }

  // ── decisões, sinais e o relógio ─────────────────────────────────

  private exigirEsperando(fluxoId: number, fichaId: number, tipo: No["tipo"]): { ficha: Ficha; fluxo: Fluxo; no: No } {
    const ficha = this.repo.exigirFicha(fichaId)
    const fluxo = this.repo.exigirFluxo(ficha.fluxo)
    if (ficha.fluxo !== fluxoId || ficha.status !== "esperando" || fluxo.status !== "rodando") {
      throw new Error("essa caixa não está esperando")
    }
    const no = this.no(fluxo, ficha.no)
    if (no.tipo !== tipo) throw new Error("essa caixa não é desse tipo")
    return { ficha, fluxo, no }
  }

  decidir(fluxoId: number, fichaId: number, opcao: string, comentario = ""): void {
    const { ficha, no } = this.exigirEsperando(fluxoId, fichaId, "decisao_humana")
    if (no.tipo !== "decisao_humana" || !no.opcoes.includes(opcao)) throw new Error(`opção inválida: ${opcao}`)
    this.repo.auditar("ueslei", "decidiu no workflow", `fluxo:${fluxoId}`, `${ficha.no}: ${opcao}`)
    this.protegido(fluxoId, (depois) => this.concluir(ficha, { opcao, comentario: comentario.trim().slice(0, 4_000) }, opcao, depois))
  }

  sinalizar(fluxoId: number, fichaId: number): void {
    const { ficha, no } = this.exigirEsperando(fluxoId, fichaId, "espera")
    if (no.tipo !== "espera" || !no.sinal) throw new Error("essa espera não é por sinal")
    this.repo.auditar("ueslei", "sinalizou no workflow", `fluxo:${fluxoId}`, `${ficha.no}: ${no.sinal}`)
    this.protegido(fluxoId, (depois) => this.concluir(ficha, { motivo: "pronto" }, "pronto", depois))
  }

  tique(agora = this.agora()): void {
    for (const ficha of this.repo.fichasEsperando()) {
      const fluxo = this.repo.exigirFluxo(ficha.fluxo)
      if (fluxo.status !== "rodando") continue
      const no = this.no(fluxo, ficha.no)
      const vencida = (iso: string | null) => iso !== null && Date.parse(iso) <= agora.getTime()
      if (no.tipo === "espera") {
        if (vencida(ficha.acordaEm)) this.protegido(fluxo.id, (d) => this.concluir(ficha, { motivo: "pronto" }, "pronto", d))
        else if (vencida(ficha.prazoEm)) this.protegido(fluxo.id, (d) => this.concluir(ficha, { motivo: "prazo" }, "prazo", d))
        continue
      }
      if (no.tipo === "board") void this.deliberar(ficha.id)
      if (vencida(ficha.prazoEm) && !ficha.avisada) {
        this.repo.mudarFicha(ficha.id, { avisada: true })
        this.amb.avisar(avisoDoFluxo(`${fluxo.definicao.nome}: ${nomeDaCaixa(no)} passou do prazo`, `Prazo de ${no.prazo}.`, { fluxo: fluxo.id, ficha: ficha.id }))
        this.amb.publicarFluxos()
      }
    }
  }

  retomar(): void {
    this.tique()
  }

  private async deliberar(fichaId: number): Promise<void> {
    if (this.deliberando.has(fichaId) || !this.amb.deliberar || this.amb.tudoPausado()) return
    const espera = this.falhasDoBoard.get(fichaId)
    if (espera && espera.ate > this.agora().getTime()) return
    const ficha = this.repo.ficha(fichaId)
    if (!ficha || ficha.status !== "esperando") return
    const fluxo = this.repo.exigirFluxo(ficha.fluxo)
    const no = this.no(fluxo, ficha.no)
    if (no.tipo !== "board" || fluxo.status !== "rodando") return
    this.deliberando.add(fichaId)
    try {
      const { sintese, decisao } = await this.amb.deliberar({
        titulo: `${fluxo.definicao.nome}: ${nomeDaCaixa(no)}`,
        pauta: interpolar(no.pauta, this.contexto(fluxo)),
        opcoes: no.opcoes,
        equipe: fluxo.equipe,
        fluxo: fluxo.id,
      })
      if (no.opcoes?.length && (!decisao || !no.opcoes.includes(decisao))) throw new Error("a síntese do board não trouxe a linha DECISÃO")
      const atual = this.repo.ficha(fichaId)
      if (!atual || atual.status !== "esperando") return
      this.falhasDoBoard.delete(fichaId)
      this.protegido(fluxo.id, (d) => this.concluir(atual, { sintese, decisao: decisao ?? "" }, no.opcoes?.length ? decisao! : undefined, d))
    } catch (erro) {
      const vezes = (this.falhasDoBoard.get(fichaId)?.vezes ?? 0) + 1
      this.falhasDoBoard.set(fichaId, { vezes, ate: this.agora().getTime() + ESPERA_DO_BOARD_MS })
      if (vezes >= TENTATIVAS_DO_BOARD) this.falhar(fluxo.id, `o board falhou: ${(erro as Error).message}`)
    } finally {
      this.deliberando.delete(fichaId)
    }
  }

  // ── fim antecipado ───────────────────────────────────────────────

  private encerrar(id: number, status: "cancelado" | "falhou", erro: string | null, depois: Depois): void {
    const fluxo = this.repo.exigirFluxo(id)
    if (fluxo.status !== "rodando" && fluxo.status !== "esperando") return
    this.repo.mudarFluxo(id, { status, erro })
    for (const f of this.repo.fichasDo(id)) if (viva(f)) this.repo.mudarFicha(f.id, { status: "cancelada" })
    for (const t of this.repo.listar(fluxo.equipe)) {
      if (t.fluxo !== id || t.status === "concluida" || t.status === "cancelada") continue
      const de = t.status
      this.repo.mudarStatus(t.id, "cancelada", autorDoFluxo(id))
      depois.push(() => {
        this.amb.publicarTarefa(t.id)
        this.amb.aoCancelarTarefa(t.id, de)
      })
    }
    this.comecarEnfileirados(id, depois)
  }

  cancelar(id: number, quem = "ueslei", motivo = "cancelado pelo Ueslei"): void {
    this.repo.auditar(quem, "cancelou o workflow", `fluxo:${id}`, motivo)
    this.emTransacao((depois) => this.encerrar(id, "cancelado", motivo, depois))
  }

  private falhar(id: number, motivo: string): void {
    const fluxo = this.repo.exigirFluxo(id)
    this.emTransacao((depois) => this.encerrar(id, "falhou", motivo, depois))
    this.amb.avisar(avisoDoFluxo(`${fluxo.definicao.nome} parou`, motivo, { fluxo: id }))
  }
}
