import type { Repositorio } from "./repositorio"
import { donoDaExecucao } from "./repositorio"
import {
  ESPERA_DA_NOVA_TENTATIVA_MS,
  FALHAS_PARA_BLOQUEAR,
  NOMES_DE_GATILHO,
  blocoDaTarefa,
  custoDaExecucao,
  escolher,
  falhasSeguidas,
  type Candidata,
  type Evento,
  type Execucao,
  type Gatilho,
  type ModoDaExecucao,
  type TipoDeEvento,
} from "./execucao"
import { TUDO, planoAprovado, planoPendente, precisaDePlano, recusaDeDelegacao, type MotivoDeBloqueio } from "./governanca"
import {
  CHAVE_DO_BOARD,
  SEM_DECISAO,
  aposAprovar,
  aposEntrega,
  aposMudanca,
  descreverEtapa,
  etapaAtual,
  etapaDoUeslei,
  membrosDoBoard,
  quemDecide,
  ultimaEntrega,
  type Decisao,
} from "./politica"
import type { StatusTarefa, Tarefa } from "./tarefa"
import { subordinadas, type Equipe, type Posicao } from "./equipe"
import type { Delegacao } from "./ferramentas"
import type { Memoria } from "../memoria/tipos"
import type { NovoAviso } from "../avisos/central"
import {
  avisoDeAprovacaoPendente,
  avisoDeAutorrevisao,
  avisoDeBloqueio,
  avisoDeConclusaoPelaPolitica,
  avisoDeDelegacao,
  avisoDeEntrega,
  avisoDePedidoDeAjuda,
  avisoDePlano,
  avisoDeVoltas,
} from "../avisos/fontes"
import type { trabalhar } from "../sessions"
import type { RegistroDeUso } from "../uso"
import type { ResultadoDaRevisao, RevisaoDoBoard } from "../board"
import { validarValores, type Saidas, type Valor } from "./workflow"
import { SEM_DEVOLUCAO, type EscopoDoCancelamento } from "./motor"

export interface GanchosDoFluxo {
  aoEntregar: (tarefa: Tarefa, entrega: string, devolvido?: Record<string, Valor>) => boolean
  saidasDa: (tarefa: Tarefa) => Saidas | undefined
  aoConcluir: (id: number) => void
  aoCancelar: (id: number, escopo: EscopoDoCancelamento) => void
}

export interface Ambiente {
  raiz: string
  repo: Repositorio
  memoria?: Memoria
  teto: number
  equipe: (id: string) => Equipe | undefined
  nome: (persona: string) => string
  modelo: (persona: string) => string
  trabalhar: typeof trabalhar
  revisarComBoard?: (pedido: Omit<RevisaoDoBoard, "memoria">) => Promise<ResultadoDaRevisao>
  publicarTarefa: (id: number) => void
  publicarExecucao: (execucao: Execucao) => void
  publicarEvento: (evento: Evento, tarefaId: number) => void
  avisar: (aviso: NovoAviso) => void
  pedirComando: (tarefaId: number, persona: string, comando: string, aprovar: boolean) => Promise<boolean>
  cancelarPedidos: (tarefaId: number) => void
  bloqueio?: (persona: string) => MotivoDeBloqueio | null
  aposExecucao?: (persona: string) => void
  fluxo?: GanchosDoFluxo
}

interface Viva {
  tarefa: number
  persona: string
  membros?: string[]
  controle: AbortController
  parada: boolean
  devolver: boolean
}

type Custo = { custoUSD: number | null; custoAcumuladoUSD: number | null }

const INTERVALO_DE_SEGURANCA_MS = 30_000
const MODELO_DO_BOARD = "sonnet"

export function tetoDeExecucoes(bruto = process.env.CT_EXECUCOES_SIMULTANEAS): number {
  const n = Number(bruto)
  return Number.isInteger(n) && n > 0 ? n : 2
}

export class Orquestra {
  private readonly vivas = new Map<number, Viva>()
  private relogio: ReturnType<typeof setInterval> | undefined

  constructor(private readonly amb: Ambiente) {}

  get repo(): Repositorio {
    return this.amb.repo
  }

  rodando(tarefa: number): boolean {
    return [...this.vivas.values()].some((v) => v.tarefa === tarefa)
  }

  iniciar(): void {
    for (const e of this.repo.interrompidasNaSubida()) {
      this.amb.publicarExecucao(e)
      this.depoisDeFalhar(e, "retomada")
    }
    this.despachar()
    this.relogio = setInterval(() => this.despachar(), INTERVALO_DE_SEGURANCA_MS)
  }

  parar(): void {
    if (this.relogio) clearInterval(this.relogio)
    for (const viva of this.vivas.values()) {
      viva.parada = true
      viva.controle.abort()
    }
  }

  acordar(tarefa: number, gatilho: Gatilho, extra?: Parameters<Repositorio["enfileirar"]>[3]): void {
    const { execucao, juntada } = this.repo.enfileirar(tarefa, gatilho, new Date(), extra)
    if (juntada) this.repo.comentar(tarefa, "orquestra", `acordar juntado: ${NOMES_DE_GATILHO[gatilho]}`, new Date(), "status")
    else this.amb.publicarExecucao(execucao)
    this.amb.publicarTarefa(tarefa)
    this.despachar()
  }

  private acordarEtapa(tarefa: Tarefa, gatilho: Gatilho, extra: { tentativa?: number; naoAntes?: Date } = {}): void {
    const etapa = tarefa.etapa!
    const decisor = quemDecide(tarefa.politica[etapa]!)
    this.acordar(tarefa.id, gatilho, { ...extra, etapa, posicao: decisor.tipo === "posicao" ? decisor.posicao : "board" })
  }

  aoCriar(tarefa: Tarefa): void {
    if (tarefa.status === "a_fazer") this.acordar(tarefa.id, "atribuicao")
  }

  aoMudarStatus(id: number, de: StatusTarefa, para: StatusTarefa, escopo: EscopoDoCancelamento = "fluxo"): void {
    if (de === "em_andamento" || de === "em_revisao") this.interromper(id)
    if (para !== "em_revisao") this.repo.marcarRetorno(id, null, 0)
    if (para === "cancelada" || para === "backlog") {
      const naFila = this.repo.naFilaDa(id)
      if (naFila) this.amb.publicarExecucao(this.repo.descartar(naFila.id, `a tarefa foi para ${para}`))
    }
    if (para === "a_fazer") this.acordar(id, "atribuicao")
    if (para === "concluida") {
      this.acordarDependentes(id)
      this.amb.fluxo?.aoConcluir(id)
    }
    if (para === "cancelada") this.amb.fluxo?.aoCancelar(id, escopo)
  }

  aoComentar(id: number): void {
    const tarefa = this.repo.exigir(id)
    if (tarefa.status === "em_revisao") {
      const etapa = etapaAtual(tarefa)
      if (etapa && quemDecide(etapa).tipo !== "ueslei") {
        this.acordarEtapa(tarefa, "comentario")
        return
      }
      if (etapa) {
        const { retorno, voltas } = aposMudanca(tarefa, tarefa.etapa!, true)
        this.repo.marcarRetorno(id, retorno, voltas)
      }
      this.repo.mudarStatus(id, "a_fazer", "ueslei")
    } else if (tarefa.status === "bloqueada") {
      this.repo.marcarRetorno(id, tarefa.retorno, 0)
      this.repo.mudarStatus(id, "a_fazer", "ueslei")
    } else if (tarefa.status !== "a_fazer" && tarefa.status !== "em_andamento") {
      return
    }
    this.acordar(id, "comentario")
  }

  private acordarDependentes(id: number): void {
    for (const dependente of this.repo.dependentes(id)) {
      if (this.repo.exigir(dependente).status === "a_fazer") this.acordar(dependente, "dependencia")
    }
  }

  private interromper(tarefa: number): void {
    for (const viva of this.vivas.values()) {
      if (viva.tarefa !== tarefa) continue
      viva.parada = true
      viva.controle.abort()
    }
    this.amb.cancelarPedidos(tarefa)
  }

  private posicaoDe(tarefa: Tarefa): Posicao | undefined {
    return this.amb.equipe(tarefa.equipe)?.posicoes.find((p) => p.id === tarefa.posicao)
  }

  private executoraDe(tarefa: Tarefa): string | null {
    return ultimaEntrega(this.repo.registros(tarefa.id))?.autor ?? this.posicaoDe(tarefa)?.persona ?? null
  }

  private membrosDisponiveis(tarefa: Tarefa): string[] {
    const equipe = this.amb.equipe(tarefa.equipe)
    if (!equipe) return []
    const pausas = this.repo.pausas()
    return membrosDoBoard(equipe, this.executoraDe(tarefa)).filter((p) => !pausas.has(p) && !this.amb.bloqueio?.(p))
  }

  personaDaFila(execucao: Execucao): string | null {
    return this.personaDa(execucao, this.repo.exigir(execucao.tarefa))
  }

  private personaDa(execucao: Execucao, tarefa: Tarefa): string | null {
    if (execucao.etapa === null) return this.posicaoDe(tarefa)?.persona ?? null
    const etapa = tarefa.politica[execucao.etapa]
    if (!etapa || tarefa.status !== "em_revisao" || tarefa.etapa !== execucao.etapa) return null
    const decisor = quemDecide(etapa)
    if (decisor.tipo === "ueslei") return null
    if (decisor.tipo === "board") return this.membrosDisponiveis(tarefa).length ? CHAVE_DO_BOARD : null
    return this.amb.equipe(tarefa.equipe)?.posicoes.find((p) => p.id === decisor.posicao)?.persona ?? null
  }

  despachar(): void {
    const candidatas: Candidata[] = this.repo.comStatus("na_fila").map((execucao) => {
      const tarefa = this.repo.exigir(execucao.tarefa)
      return {
        execucao,
        tarefa,
        persona: this.personaDa(execucao, tarefa),
        dependenciasConcluidas: tarefa.dependeDe.every((d) => this.repo.exigir(d).status === "concluida"),
      }
    })
    const rodando = [...this.vivas.values()].map((v) => ({ tarefa: v.tarefa, persona: v.persona }))
    const pausas = this.repo.pausas()
    const bloqueadas = new Set(
      candidatas.flatMap((c) =>
        c.persona !== null && (pausas.has(TUDO) || pausas.has(c.persona) || this.amb.bloqueio?.(c.persona)) ? [c.persona] : [],
      ),
    )
    for (const decisao of escolher(candidatas, rodando, this.amb.teto, new Date(), bloqueadas)) {
      if (decisao.acao === "descartar") {
        this.amb.publicarExecucao(this.repo.descartar(decisao.execucao, decisao.motivo))
        continue
      }
      const naFila = this.repo.exigirExecucao(decisao.execucao)
      const doBoard = decisao.persona === CHAVE_DO_BOARD
      if (naFila.etapa !== null && !doBoard && ultimaEntrega(this.repo.registros(naFila.tarefa))?.autor === decisao.persona) {
        this.pararPorAutorrevisao(naFila, decisao.persona)
        continue
      }
      let execucao: Execucao
      try {
        execucao = this.repo.comecar(
          decisao.execucao,
          doBoard ? null : decisao.persona,
          doBoard ? MODELO_DO_BOARD : this.amb.modelo(decisao.persona),
        )
      } catch (erro) {
        this.amb.publicarExecucao(this.repo.descartar(decisao.execucao, (erro as Error).message))
        continue
      }
      const viva: Viva = {
        tarefa: execucao.tarefa,
        persona: decisao.persona,
        membros: doBoard ? this.membrosDisponiveis(this.repo.exigir(execucao.tarefa)) : undefined,
        controle: new AbortController(),
        parada: false,
        devolver: false,
      }
      this.vivas.set(execucao.id, viva)
      this.amb.publicarExecucao(execucao)
      this.amb.publicarTarefa(execucao.tarefa)
      const rodada = execucao.etapa === null ? this.rodar(execucao, viva) : this.rodarEtapa(execucao, viva)
      void rodada.finally(() => {
        this.vivas.delete(execucao.id)
        this.amb.publicarTarefa(execucao.tarefa)
        for (const p of viva.membros ?? [viva.persona]) this.amb.aposExecucao?.(p)
        this.despachar()
      })
    }
  }

  private evento(execucao: Execucao, tipo: TipoDeEvento, conteudo: string): void {
    this.amb.publicarEvento(this.repo.registrarEvento(execucao.id, tipo, conteudo), execucao.tarefa)
  }

  private async rodar(execucao: Execucao, viva: Viva): Promise<void> {
    const persona = viva.persona
    const tarefa = this.repo.exigir(execucao.tarefa)
    const posicao = this.posicaoDe(tarefa)!
    const sessao = this.repo.sessaoDoPar(tarefa.id, persona, execucao.id)
    const anterior = this.repo.anteriorDoPar(tarefa.id, persona, execucao.id)
    const equipe = this.amb.equipe(tarefa.equipe)!
    const registros = this.repo.registros(tarefa.id)
    const deTrabalho = !precisaDePlano(posicao, registros)
    const aprovado = planoAprovado(registros)
    const modo: ModoDaExecucao = !deTrabalho ? { tipo: "plano" } : aprovado ? { tipo: "plano_aprovado", plano: aprovado } : { tipo: "normal" }
    const abaixo = deTrabalho ? subordinadas(equipe, posicao.id) : []
    const saidas = deTrabalho ? this.amb.fluxo?.saidasDa(tarefa) : undefined
    let devolvido: Record<string, Valor> | undefined
    let pedidoDeAjuda: string | undefined
    let uso: RegistroDeUso | undefined
    try {
      const resposta = await this.amb.trabalhar({
        raiz: this.amb.raiz,
        persona,
        posicao,
        plano: !deTrabalho,
        bloco: blocoDaTarefa(
          tarefa,
          this.repo.cadeiaDePais(tarefa.id),
          registros,
          persona,
          anterior?.inicio ?? null,
          abaixo.map((p) => ({ id: p.id, titulo: p.titulo, persona: p.persona ? this.amb.nome(p.persona) : null })),
          modo,
        ),
        consulta: [tarefa.titulo, tarefa.descricao].filter(Boolean).join("\n"),
        modelo: execucao.modelo ?? this.amb.modelo(persona),
        sessionId: sessao?.sessionId,
        memoria: this.amb.memoria,
        tarefaId: tarefa.id,
        execucaoId: execucao.id,
        controle: viva.controle,
        acoes: {
          comentar: (texto) => {
            this.repo.comentar(tarefa.id, persona, texto)
            this.amb.publicarTarefa(tarefa.id)
            return "Comentário registrado."
          },
          pedirAjuda: (motivo) => {
            this.repo.comentar(tarefa.id, persona, motivo, new Date(), "ajuda")
            pedidoDeAjuda = motivo
            this.amb.publicarTarefa(tarefa.id)
            return "Pedido registrado. A tarefa fica bloqueada até o Ueslei responder: pare agora."
          },
          delegar: abaixo.length ? (pedido) => this.delegar(tarefa, execucao, persona, posicao, abaixo, pedido) : undefined,
          devolver: saidas
            ? {
                saidas,
                registrar: (dados) => {
                  devolvido = validarValores(saidas, dados)
                  return "Devolutiva registrada. Termine com um resumo do que fez."
                },
              }
            : undefined,
        },
        onEvento: (tipo, conteudo) => this.evento(execucao, tipo, conteudo),
        onComando: (comando, aprovar) => this.amb.pedirComando(tarefa.id, persona, comando, aprovar),
        onSessao: (sessionId) => this.repo.gravarSessao(execucao.id, sessionId),
        onUso: (registro) => (uso = registro),
      })
      const custo = this.custo(uso, sessao?.custoAcumuladoUSD ?? null)
      if (viva.parada) {
        this.interrompida(execucao, viva, custo)
        return
      }
      if (saidas && !devolvido && !pedidoDeAjuda) throw new Error(SEM_DEVOLUCAO)
      const entrega = resposta.texto || "(a execução terminou sem texto)"
      this.terminar(execucao, { status: "concluida", falha: false, resultado: entrega, ...custo })
      this.repo.comentar(tarefa.id, persona, entrega, new Date(), deTrabalho ? "entrega" : "plano")
      const comentouNoMeio = this.repo.naFilaDa(tarefa.id) !== undefined
      const destino: StatusTarefa = comentouNoMeio ? "a_fazer" : pedidoDeAjuda ? "bloqueada" : "em_revisao"
      if (!this.repo.devolver(execucao.id, destino, donoDaExecucao(execucao.id))) return
      if (comentouNoMeio) return
      const nome = this.amb.nome(persona)
      if (pedidoDeAjuda) this.amb.avisar(avisoDePedidoDeAjuda(tarefa.id, nome, pedidoDeAjuda))
      else if (!deTrabalho) this.amb.avisar(avisoDePlano(tarefa.id, nome, entrega))
      else this.depoisDaEntrega(tarefa.id, nome, entrega, devolvido)
    } catch (erro) {
      const custo = this.custo(uso, sessao?.custoAcumuladoUSD ?? null)
      if (viva.parada) {
        this.interrompida(execucao, viva, custo)
        return
      }
      const mensagem = (erro as Error).message
      this.evento(execucao, "erro", mensagem)
      const falhou = this.terminar(execucao, { status: "falhou", falha: true, erro: mensagem, ...custo })
      this.repo.devolver(execucao.id, "a_fazer", "orquestra")
      this.depoisDeFalhar(falhou, "nova_tentativa")
    }
  }

  private depoisDaEntrega(id: number, nome: string, entrega: string, devolvido?: Record<string, Valor>): void {
    if (this.amb.fluxo?.aoEntregar(this.repo.exigir(id), entrega, devolvido)) return
    const tarefa = this.repo.exigir(id)
    const destino = aposEntrega(tarefa.politica, tarefa.retorno)
    if (destino.tipo === "etapa") this.entrarNaEtapa(id, destino.etapa)
    else this.amb.avisar(avisoDeEntrega(id, nome, entrega))
  }

  private entrarNaEtapa(id: number, etapa: number): void {
    const antes = this.repo.exigir(id)
    const passo = antes.politica[etapa]!
    const tarefa = this.repo.irParaEtapa(
      id,
      etapa,
      "orquestra",
      `etapa ${etapa + 1}: ${descreverEtapa(passo, this.amb.equipe(antes.equipe), this.amb.nome)}`,
    )
    this.amb.publicarTarefa(id)
    if (quemDecide(passo).tipo === "ueslei") {
      this.amb.avisar(avisoDeAprovacaoPendente(id, ultimaEntrega(this.repo.registros(id))?.texto ?? tarefa.titulo))
    } else {
      this.acordarEtapa(tarefa, "revisao")
    }
  }

  private async rodarEtapa(execucao: Execucao, viva: Viva): Promise<void> {
    const tarefa = this.repo.exigir(execucao.tarefa)
    const indice = execucao.etapa!
    const etapa = tarefa.politica[indice]!
    const registros = this.repo.registros(tarefa.id)
    const pais = this.repo.cadeiaDePais(tarefa.id)
    const executora = this.amb.nome(this.executoraDe(tarefa) ?? "a executora")
    const doBoard = viva.persona === CHAVE_DO_BOARD
    let decisao: Decisao | undefined
    let uso: RegistroDeUso | undefined
    let anteriorDaSessao: number | null = null
    const decidir = (tipo: Decisao["tipo"], texto: string) => {
      if (decisao) return "Você já decidiu. Pare agora."
      decisao = { tipo, texto: texto.trim() }
      return tipo === "aprovar" ? "Aprovação registrada. Pare agora." : "Pedido de mudança registrado. Pare agora."
    }
    try {
      if (doBoard) {
        if (!this.amb.revisarComBoard) throw new Error("o board não está disponível neste servidor")
        const resultado = await this.amb.revisarComBoard({
          titulo: `Revisão da tarefa #${tarefa.id}: ${tarefa.titulo}`,
          pauta: blocoDaTarefa(tarefa, pais, registros, "board", null, [], { tipo: "board", executora }),
          membros: viva.membros ?? [],
          modelo: this.amb.modelo,
          tarefaId: tarefa.id,
          execucaoId: execucao.id,
          controle: viva.controle,
        })
        if (resultado.decisao) decidir(resultado.decisao, `${resultado.sintese.trim()}\n\nAta: ${resultado.ata}`)
      } else {
        const persona = viva.persona
        const decisor = quemDecide(etapa)
        const posicao = this.amb.equipe(tarefa.equipe)?.posicoes.find((p) => decisor.tipo === "posicao" && p.id === decisor.posicao)
        if (!posicao) throw new Error("a posição desta etapa não existe mais na equipe")
        const sessao = this.repo.sessaoDoPar(tarefa.id, persona, execucao.id)
        const anterior = this.repo.anteriorDoPar(tarefa.id, persona, execucao.id)
        anteriorDaSessao = sessao?.custoAcumuladoUSD ?? null
        await this.amb.trabalhar({
          raiz: this.amb.raiz,
          persona,
          posicao,
          revisao: true,
          bloco: blocoDaTarefa(tarefa, pais, registros, persona, anterior?.inicio ?? null, [], {
            tipo: "revisao",
            executora,
            final: etapa.tipo === "aprovacao",
            semDecisao: anterior?.erro === SEM_DECISAO,
          }),
          consulta: [tarefa.titulo, tarefa.descricao].filter(Boolean).join("\n"),
          modelo: execucao.modelo ?? this.amb.modelo(persona),
          sessionId: sessao?.sessionId,
          memoria: this.amb.memoria,
          tarefaId: tarefa.id,
          execucaoId: execucao.id,
          controle: viva.controle,
          acoes: {
            comentar: (texto) => {
              this.repo.comentar(tarefa.id, persona, texto)
              this.amb.publicarTarefa(tarefa.id)
              return "Comentário registrado."
            },
            aprovar: (parecer) => decidir("aprovar", parecer),
            pedirMudanca: (oQueMudar) => decidir("mudanca", oQueMudar),
          },
          onEvento: (tipo, conteudo) => this.evento(execucao, tipo, conteudo),
          onComando: async () => false,
          onSessao: (sessionId) => this.repo.gravarSessao(execucao.id, sessionId),
          onUso: (registro) => (uso = registro),
        })
      }
      const custo = this.custo(uso, anteriorDaSessao)
      if (viva.parada) {
        this.interrompida(execucao, viva, custo)
        return
      }
      const final = decisao as Decisao | undefined
      if (!final) throw new Error(SEM_DECISAO)
      this.terminar(execucao, { status: "concluida", falha: false, resultado: final.texto, ...custo })
      if (!this.repo.soltarEtapa(execucao.id)) return
      this.aplicarDecisao(tarefa.id, indice, final, doBoard ? "board" : viva.persona)
    } catch (erro) {
      const custo = this.custo(uso, anteriorDaSessao)
      if (viva.parada) {
        this.interrompida(execucao, viva, custo)
        return
      }
      const mensagem = (erro as Error).message
      this.evento(execucao, "erro", mensagem)
      const falhou = this.terminar(execucao, { status: "falhou", falha: true, erro: mensagem, ...custo })
      this.repo.soltarEtapa(execucao.id)
      this.depoisDeFalhar(falhou, "nova_tentativa")
    }
  }

  private aplicarDecisao(id: number, indice: number, decisao: Decisao, autor: string): void {
    const tarefa = this.repo.exigir(id)
    const texto = decisao.texto || (decisao.tipo === "aprovar" ? "aprovou" : "pediu mudança")
    this.repo.comentar(id, autor, texto, new Date(), decisao.tipo === "aprovar" ? "aprovado" : "mudanca")
    const quem = autor === "board" ? "O board" : autor === "ueslei" ? "Ueslei" : this.amb.nome(autor)
    if (decisao.tipo === "aprovar") {
      const destino = aposAprovar(tarefa.politica, indice)
      if (destino.tipo === "etapa") {
        this.entrarNaEtapa(id, destino.etapa)
        return
      }
      this.repo.mudarStatus(id, "concluida", autor)
      this.amb.publicarTarefa(id)
      if (autor !== "ueslei" && tarefa.fluxo === null) this.amb.avisar(avisoDeConclusaoPelaPolitica(id, quem, texto))
      this.acordarDependentes(id)
      this.amb.fluxo?.aoConcluir(id)
      return
    }
    const mudanca = aposMudanca(tarefa, indice, autor === "ueslei")
    this.repo.marcarRetorno(id, mudanca.retorno, mudanca.voltas)
    if (mudanca.estourou) {
      this.repo.mudarStatus(id, "bloqueada", "orquestra")
      this.repo.comentar(id, "orquestra", `bloqueada: ${mudanca.voltas} pedidos de mudança na mesma etapa sem convergir`, new Date(), "status")
      this.amb.publicarTarefa(id)
      this.amb.avisar(avisoDeVoltas(id, quem, this.amb.nome(this.executoraDe(tarefa) ?? "a executora"), texto))
      return
    }
    this.repo.mudarStatus(id, "a_fazer", autor)
    this.amb.publicarTarefa(id)
    this.acordar(id, "mudanca")
  }

  decidir(id: number, decisao: Decisao["tipo"], texto = "", quem = "ueslei"): void {
    const tarefa = this.repo.exigir(id)
    if (!etapaDoUeslei(tarefa)) throw new Error(`a tarefa ${id} não está esperando sua decisão`)
    const limpo = texto.trim().slice(0, 20_000)
    if (decisao === "mudanca" && !limpo) throw new Error("diga o que precisa mudar")
    this.repo.auditar(quem, decisao === "aprovar" ? "aprovou a entrega" : "pediu mudança", `tarefa:${id}`, limpo)
    this.aplicarDecisao(id, tarefa.etapa!, { tipo: decisao, texto: limpo }, quem)
  }

  private pararPorAutorrevisao(execucao: Execucao, persona: string): void {
    const tarefa = this.repo.exigir(execucao.tarefa)
    this.amb.publicarExecucao(this.repo.descartar(execucao.id, "a executora revisaria o próprio trabalho"))
    this.repo.marcarRetorno(tarefa.id, tarefa.etapa, tarefa.voltas)
    this.repo.mudarStatus(tarefa.id, "bloqueada", "orquestra")
    this.repo.comentar(tarefa.id, "orquestra", `bloqueada: ${persona} revisaria o próprio trabalho`, new Date(), "status")
    this.amb.publicarTarefa(tarefa.id)
    this.amb.avisar(avisoDeAutorrevisao(tarefa.id, this.amb.nome(persona)))
  }

  private interrompida(execucao: Execucao, viva: Viva, custo: Custo): void {
    this.terminar(execucao, { status: "interrompida", falha: false, erro: viva.devolver ? "pausada" : "parada pelo Ueslei", ...custo })
    if (!viva.devolver) return
    if (execucao.etapa === null) {
      if (this.repo.devolver(execucao.id, "a_fazer", "orquestra")) this.acordar(execucao.tarefa, "retomada")
      return
    }
    const tarefa = this.repo.soltarEtapa(execucao.id)
    if (tarefa) this.acordarEtapa(tarefa, "retomada")
  }

  private delegar(
    tarefa: Tarefa,
    execucao: Execucao,
    persona: string,
    posicao: Posicao,
    abaixo: Posicao[],
    pedido: Delegacao,
  ): string {
    const alvo = abaixo.find((p) => p.id === pedido.posicao)
    if (!alvo) return `A posição ${pedido.posicao} não responde a você. Pode delegar a: ${abaixo.map((p) => p.id).join(", ")}.`
    const titulo = pedido.titulo.trim().slice(0, 200)
    if (!titulo) return "A subtarefa precisa de um título."
    const recusa = recusaDeDelegacao(this.repo.cadeiaDePais(tarefa.id).length + 1, this.repo.filhasAbertas(tarefa.id))
    if (recusa) return recusa
    const direto = posicao.delegaDireto === true
    const sub = this.repo.criar(
      {
        equipe: tarefa.equipe,
        posicao: alvo.id,
        titulo,
        descricao: (pedido.descricao ?? "").trim().slice(0, 20_000),
        porque: (pedido.porque ?? "").trim().slice(0, 4_000),
        pai: tarefa.id,
        dependeDe: [],
        status: direto ? "a_fazer" : "backlog",
        politica: alvo.politica ?? [],
      },
      donoDaExecucao(execucao.id),
    )
    this.repo.comentar(tarefa.id, persona, `delegou #${sub.id} a ${alvo.id}: ${titulo}`, new Date(), "status")
    this.amb.publicarTarefa(sub.id)
    this.amb.publicarTarefa(tarefa.id)
    if (direto) {
      this.repo.auditar(donoDaExecucao(execucao.id), "delegou direto", `tarefa:${sub.id}`, `${persona} → ${alvo.id}: ${titulo}`)
      this.acordar(sub.id, "atribuicao")
      return `Subtarefa #${sub.id} criada para ${alvo.id}. Ela já entrou na fila e roda sozinha.`
    }
    this.amb.avisar(avisoDeDelegacao(sub.id, this.amb.nome(persona), titulo))
    return `Subtarefa #${sub.id} criada para ${alvo.id}, no backlog. Ela só roda quando o Ueslei liberar.`
  }

  pausar(alvo: string, quem = "ueslei"): void {
    this.repo.pausar(alvo, quem)
    this.repo.auditar(quem, "pausou", alvo === TUDO ? "tudo" : `persona:${alvo}`)
    for (const viva of this.vivas.values()) {
      if (alvo !== TUDO && viva.persona !== alvo) continue
      viva.parada = true
      viva.devolver = true
      viva.controle.abort()
      this.amb.cancelarPedidos(viva.tarefa)
    }
  }

  retomar(alvo: string, quem = "ueslei"): void {
    if (this.repo.retomar(alvo)) this.repo.auditar(quem, "retomou", alvo === TUDO ? "tudo" : `persona:${alvo}`)
    this.despachar()
  }

  aprovarPlano(id: number, quem = "ueslei"): void {
    const tarefa = this.repo.exigir(id)
    if (tarefa.status !== "em_revisao" || !planoPendente(this.repo.registros(id))) {
      throw new Error(`a tarefa ${id} não tem plano esperando aprovação`)
    }
    this.repo.comentar(id, quem, "aprovou o plano", new Date(), "plano-aprovado")
    this.repo.mudarStatus(id, "a_fazer", quem)
    this.repo.auditar(quem, "aprovou o plano", `tarefa:${id}`)
    this.acordar(id, "plano_aprovado")
  }

  interromperPersona(persona: string): void {
    for (const viva of this.vivas.values()) {
      if (viva.persona !== persona) continue
      viva.parada = true
      viva.controle.abort()
      this.amb.cancelarPedidos(viva.tarefa)
    }
  }

  private custo(uso: RegistroDeUso | undefined, anterior: number | null): Custo {
    return {
      custoUSD: custoDaExecucao(uso?.custoAcumuladoUSD, anterior, uso?.retomada ?? false),
      custoAcumuladoUSD: uso?.custoAcumuladoUSD ?? null,
    }
  }

  private terminar(execucao: Execucao, termino: Parameters<Repositorio["terminar"]>[1]): Execucao {
    const terminada = this.repo.terminar(execucao.id, termino)
    this.amb.publicarExecucao(terminada)
    return terminada
  }

  private depoisDeFalhar(execucao: Execucao, gatilho: "retomada" | "nova_tentativa"): void {
    const tarefa = this.repo.exigir(execucao.tarefa)
    const deEtapa = execucao.etapa !== null
    const esperando = deEtapa
      ? tarefa.status === "em_revisao" && tarefa.etapa === execucao.etapa && tarefa.dono === null
      : tarefa.status === "a_fazer"
    if (!esperando) return
    const falhas = falhasSeguidas(this.repo.execucoesDaTarefa(tarefa.id))
    if (falhas >= FALHAS_PARA_BLOQUEAR) {
      const naFila = this.repo.naFilaDa(tarefa.id)
      if (naFila) this.amb.publicarExecucao(this.repo.descartar(naFila.id, "a tarefa foi bloqueada"))
      if (deEtapa) this.repo.marcarRetorno(tarefa.id, tarefa.etapa, tarefa.voltas)
      this.repo.mudarStatus(tarefa.id, "bloqueada", "orquestra")
      this.repo.comentar(tarefa.id, "orquestra", `bloqueada depois de ${falhas} falhas seguidas: ${execucao.erro ?? "sem erro"}`, new Date(), "status")
      this.amb.publicarTarefa(tarefa.id)
      this.amb.avisar(avisoDeBloqueio(tarefa.id, execucao.erro ?? "sem erro"))
      return
    }
    const naoAntes = gatilho === "nova_tentativa" ? new Date(Date.now() + ESPERA_DA_NOVA_TENTATIVA_MS) : undefined
    if (deEtapa) this.acordarEtapa(tarefa, gatilho, { tentativa: falhas + 1, naoAntes })
    else this.acordar(tarefa.id, gatilho, { tentativa: falhas + 1, naoAntes })
  }
}
