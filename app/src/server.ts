import { join } from "node:path"
import { dirModelos, dirWeb, raizDoCodigo, raizDosDados } from "./caminhos"
import { garantirIgnorado, origemDaImportacao, prepararDados, registrarNoGit } from "./dados"
import { migrarPendentes } from "./memoria/migracao"
import {
  apagarEquipe,
  apagarRotina,
  apagarWorkflow,
  carregarElenco,
  elenco,
  gravarEquipe,
  gravarPersona,
  gravarRotina,
  conferirVersao,
  gravarWorkflow,
  lerWorkflowDoDisco,
  versaoNoDisco,
  lerRotinas,
  lerWorkflows,
  migrarParaPersonas,
  validarWorkflowDaEquipe,
} from "./orquestra/elenco"
import { Agendador } from "./orquestra/agendador"
import { LIMITE_DO_CORPO, validarRotina } from "./orquestra/rotinas"
import { corDaPersona, exigirMudancaDeEquipe, resumoDaMudanca, slugValido, validarEquipe, validarPersona } from "./orquestra/equipe"
import { Contas, TUDO, formatarTokens, mesDe, motivoDeBloqueio, niveisDoOrcamento, type Limites } from "./orquestra/governanca"
import { aoGravarUso, lerUso } from "./uso"
import { criarPersona, excluirPersona, gerarPerfil, lerPedidoDePersona } from "./orquestra/personas"
import { Repositorio, caminhoDoBanco } from "./orquestra/repositorio"
import { lerNovaTarefa, statusValido } from "./orquestra/tarefa"
import { Orquestra, tetoDeExecucoes } from "./orquestra/runtime"
import type { Evento, Execucao } from "./orquestra/execucao"
import { randomUUID } from "node:crypto"
import type { ServerWebSocket } from "bun"
import { MODELO_PADRAO, ehConselheiro, ehPerfil, lerFoco, modeloEfetivo, nomeDe, perfilExcluivel, rodaComandos, type Anexo } from "./tipos"
import { gravarAnexo, lerAnexo, lerAnexos, mimeDeEntrega, montarBlocoDeAnexos } from "./anexos"
import { carregarAtalhos } from "./atalhos"
import { conversar, trabalhar } from "./sessions"
import { convocarBoard, deliberarComBoard, revisarComBoard } from "./board"
import { Motor } from "./orquestra/motor"
import { membrosDoBoard } from "./orquestra/politica"
import { comQuem } from "./orquestra/politica"
import { AssinaturaDoPainel, TIPOS_DA_ATIVIDADE, montarRetrato } from "./orquestra/painel"
import type { Tarefa } from "./orquestra/tarefa"
import { enderecos, respostaEnderecos } from "./rede"
import { lerDecisoes, lerDecisao } from "./decisions"
import { apagarSessao } from "./sessao-sdk"
import { memoriaHttp } from "./memoria/cliente"
import { espelharColetivo } from "./memoria/coletivo"
import { MemoriaIndisponivel } from "./memoria/tipos"
import { Espera, rodarUmaVez } from "./memoria/agenda"
import {
  consolidarConversa,
  consolidarGuardadas,
  consolidarPendentesDe,
  conversasPendentes,
  guardarParaConsolidar,
} from "./memoria/consolidacao"
import { sonhar } from "./memoria/sonho"
import { CentralDeAvisos, caminhoDosAvisos, type Como } from "./avisos/central"
import { Presenca, type Mudanca } from "./avisos/presenca"
import { avisoDeAprovacao, avisoDeAprovacaoEmTarefa, avisoDeOrcamento, avisoDeResposta } from "./avisos/fontes"
import type { NovoAviso } from "./avisos/central"
import { executorDeAvisos, lerDesde, streamDeAvisos, tratarAcao } from "./avisos/http"
import { Lembretes } from "./avisos/motor"
import { chamarTickTask } from "./avisos/ticktask-cliente"
import {
  idValido,
  criarConversa,
  atualizarMeta,
  lerMeta,
  anexarMensagem,
  lerMensagens,
  listarConversas,
  excluirConversa,
  filaPorChave,
} from "./store"

const CODIGO = raizDoCodigo()
const RAIZ = raizDosDados()
const WEB = dirWeb(CODIGO)

try {
  await prepararDados({ dados: RAIZ, modelos: dirModelos(CODIGO), origem: await origemDaImportacao(RAIZ, CODIGO) })
  if (await migrarParaPersonas(RAIZ)) await registrarNoGit(RAIZ, "personas como dados e equipe Casa")
  await carregarElenco(RAIZ)
  await garantirIgnorado(RAIZ, "orquestra/")
} catch (erro) {
  console.error(`não consegui preparar a pasta de dados ${RAIZ}: ${(erro as Error).message}`)
  process.exit(1)
}
const TAREFAS = new Repositorio(caminhoDoBanco(RAIZ))
const CONTAS = new Contas()
CONTAS.carregar(await lerUso(RAIZ).catch(() => []))
aoGravarUso((registro) => CONTAS.registrar(registro))
const PORTA = Number(process.env.TOWER_PORTA ?? 7878)
const MEMORIA = memoriaHttp()
const naFilaDaConversa = filaPorChave()
const AVISOS = new CentralDeAvisos(caminhoDosAvisos(RAIZ))
await AVISOS.carregar().catch((erro: Error) => console.warn(`[avisos] histórico não carregou — ${erro.message}`))
const LEMBRETES = new Lembretes(RAIZ, AVISOS, chamarTickTask)

function avisar(promessa: Promise<unknown>): void {
  void promessa.catch((erro: Error) => console.warn(`[avisos] ${erro.message}`))
}

const ESPELHADAS = new Map<string, string>()
const TENTATIVAS_NA_SUBIDA = 20

function espelharEmSegundoPlano(): void {
  void espelharColetivo(RAIZ, MEMORIA, ESPELHADAS).catch((erro: Error) =>
    console.warn(`[memoria] espelho do coletivo falhou — ${erro.message}`),
  )
}

async function espelharNaSubida(): Promise<void> {
  for (let tentativa = 1; ; tentativa++) {
    try {
      await espelharColetivo(RAIZ, MEMORIA, ESPELHADAS)
      return
    } catch (erro) {
      if (!(erro instanceof MemoriaIndisponivel) || tentativa >= TENTATIVAS_NA_SUBIDA) {
        console.warn(`[memoria] espelho do coletivo falhou — ${(erro as Error).message}`)
        return
      }
      await Bun.sleep(3_000)
    }
  }
}

function versionarEmSegundoPlano(motivo: string): void {
  void registrarNoGit(RAIZ, motivo).catch((erro: Error) =>
    console.warn(`[dados] commit falhou — ${erro.message}`),
  )
}

const ESTATICOS: Record<string, string> = {
  "/": "index.html",
  "/index.html": "index.html",
  "/app.js": "app.js",
  "/style.css": "style.css",
  "/manifest.webmanifest": "manifest.webmanifest",
  "/icone.svg": "icone.svg",
  "/icone-192.png": "icone-192.png",
  "/icone-512.png": "icone-512.png",
}

type Cliente = ServerWebSocket<undefined>

const PRESENCA = new Presenca<Cliente>()
const CLIENTES = new Set<Cliente>()

function mandar(ws: Cliente, msg: Record<string, unknown>): void {
  ws.send(JSON.stringify(msg))
}

function mandarATodos(msg: Record<string, unknown>): void {
  const texto = JSON.stringify(msg)
  for (const ws of CLIENTES) if (ws.readyState === WebSocket.OPEN) ws.send(texto)
}

function equipesParaCliente() {
  return elenco()
    .equipes()
    .map((e) => ({
      id: e.id,
      nome: e.nome,
      layout: e.layout,
      posicoes: e.posicoes.map((p) => ({ ...p, personaNome: p.persona ? elenco().nome(p.persona) : null })),
    }))
}

const GERANDO_PERFIL = new Set<string>()

function limitesDe(persona: string): Limites {
  const p = elenco().persona(persona)
  return { usd: p?.orcamentoMensalUSD, tokens: p?.orcamentoMensalTokens }
}

function bloqueioDe(persona: string) {
  const pausas = new Set(TAREFAS.pausas().keys())
  return motivoDeBloqueio(persona, pausas, CONTAS.gasto(persona), limitesDe(persona))
}

function conferirOrcamento(persona: string): void {
  const limites = limitesDe(persona)
  const gasto = CONTAS.gasto(persona)
  const niveis = niveisDoOrcamento(gasto, limites)
  for (const dimensao of ["usd", "tokens"] as const) {
    const nivel = niveis[dimensao]
    const limite = limites[dimensao]
    if (!nivel || limite === undefined) continue
    if (!TAREFAS.marcarAvisoDeOrcamento(persona, mesDe(new Date()), `${nivel}:${dimensao}`)) continue
    const valor = dimensao === "usd" ? gasto.tarefas : gasto.tokensTarefas
    const texto =
      dimensao === "usd" ? `US$ ${valor.toFixed(2)} de US$ ${limite.toFixed(2)}` : `${formatarTokens(valor)} de ${formatarTokens(limite)}`
    const qual = dimensao === "usd" ? "orçamento" : "orçamento de tokens"
    TAREFAS.auditar("orquestra", nivel === "alerta" ? `${qual} em 80%` : `${qual} estourado`, `persona:${persona}`, texto)
    avisar(AVISOS.criar(avisoDeOrcamento(elenco().nome(persona), nivel, dimensao, valor, limite)))
  }
  mandarATodos({ tipo: "personas", lista: personasParaCliente() })
}

function estadoDaOrquestra() {
  return { tipo: "orquestra", pausadoTudo: TAREFAS.pausas().has(TUDO) }
}

async function salvarPersona(bruto: unknown): Promise<void> {
  const pedido = (bruto && typeof bruto === "object" ? bruto : {}) as Record<string, unknown>
  const id = String(pedido.id ?? "")
  const atual = elenco().persona(id)
  if (!atual) throw new Error(`a persona ${id} não existe`)
  const nova: Record<string, unknown> = { ...atual }
  const mudancas: string[] = []
  if ("orcamentoMensalUSD" in pedido) {
    if (pedido.orcamentoMensalUSD === null || pedido.orcamentoMensalUSD === "") delete nova.orcamentoMensalUSD
    else nova.orcamentoMensalUSD = Number(pedido.orcamentoMensalUSD)
    mudancas.push(nova.orcamentoMensalUSD === undefined ? "sem limite em US$" : `orçamento US$ ${Number(nova.orcamentoMensalUSD).toFixed(2)}`)
  }
  if ("orcamentoMensalTokens" in pedido) {
    if (pedido.orcamentoMensalTokens === null || pedido.orcamentoMensalTokens === "") delete nova.orcamentoMensalTokens
    else nova.orcamentoMensalTokens = Number(pedido.orcamentoMensalTokens)
    mudancas.push(
      nova.orcamentoMensalTokens === undefined ? "sem limite de tokens" : `orçamento ${formatarTokens(Number(nova.orcamentoMensalTokens))}`,
    )
  }
  if ("modelo" in pedido) {
    if (pedido.modelo) nova.modelo = String(pedido.modelo)
    else delete nova.modelo
    mudancas.push(`modelo ${String(nova.modelo ?? "padrão")}`)
  }
  if ("cor" in pedido) {
    if (pedido.cor) nova.cor = String(pedido.cor)
    else delete nova.cor
    mudancas.push("cor")
  }
  if (typeof pedido.nome === "string" && pedido.nome.trim()) {
    nova.nome = pedido.nome.trim()
    mudancas.push(`nome ${pedido.nome.trim()}`)
  }
  const valida = validarPersona(nova)
  await gravarPersona(RAIZ, valida)
  await carregarElenco(RAIZ)
  await registrarNoGit(RAIZ, `persona ${valida.nome}: ${mudancas.join(", ") || "sem mudança"}`)
  publicarElenco()
  ORQUESTRA.despachar()
}

function alvoDaPausa(bruto: unknown): string {
  const alvo = String(bruto ?? "")
  if (alvo === TUDO) return TUDO
  if (!elenco().existe(alvo)) throw new Error(`a persona ${alvo} não existe`)
  return alvo
}

function personasParaCliente() {
  return elenco()
    .personas()
    .map((p) => {
      const naCasa = elenco().posicaoNaCasa(p.id)
      return {
        id: p.id,
        nome: p.nome,
        inicial: p.nome.charAt(0).toUpperCase(),
        cor: corDaPersona(p),
        titulo: naCasa?.titulo ?? null,
        conversa: Boolean(naCasa),
        executor: rodaComandos(p.id),
        excluivel: perfilExcluivel(p.id),
        modelo: p.modelo ?? null,
        gerandoPerfil: GERANDO_PERFIL.has(p.id),
        orcamentoMensalUSD: p.orcamentoMensalUSD ?? null,
        orcamentoMensalTokens: p.orcamentoMensalTokens ?? null,
        gastoMesUSD: CONTAS.gasto(p.id).tarefas,
        gastoTotalMesUSD: CONTAS.gasto(p.id).total,
        tokensMes: CONTAS.gasto(p.id).tokensTarefas,
        tokensTotalMes: CONTAS.gasto(p.id).tokensTotal,
        pausa: (() => {
          const motivo = bloqueioDe(p.id)
          return motivo ? { motivo } : null
        })(),
      }
    })
}

function publicarElenco(): void {
  mandarATodos({ tipo: "personas", lista: personasParaCliente() })
  mandarATodos({ tipo: "equipes", lista: equipesParaCliente() })
  agendarPainel()
}

const equipePorId = (id: string) => elenco().equipe(id)

function contarTarefas(equipe: string) {
  const tarefas = TAREFAS.listar(equipe)
  return (posicao: string) => {
    const abertas = tarefas.filter((t) => t.status !== "concluida" && t.status !== "cancelada")
    return {
      abertas: abertas.filter((t) => t.posicao === posicao).length,
      emAndamento: tarefas.filter((t) => t.posicao === posicao && t.status === "em_andamento").length,
      citadas: abertas.filter((t) => t.politica.some((e) => "posicao" in e.por && e.por.posicao === posicao)).length,
      rotinas: AGENDADOR.daEquipe(equipe).filter((r) => r.posicao === posicao).length,
      workflows: MOTOR.daEquipe(equipe).filter((w) =>
        w.nos.some((n) => ("posicao" in n && n.posicao === posicao) || ("por" in n && "posicao" in n.por && n.por.posicao === posicao)),
      ).length,
    }
  }
}

async function salvarEquipe(bruto: unknown): Promise<void> {
  const equipe = validarEquipe(bruto, new Set(elenco().ids()))
  const antes = elenco().equipe(equipe.id)
  exigirMudancaDeEquipe(antes, equipe, contarTarefas(equipe.id))
  await gravarEquipe(RAIZ, equipe)
  await carregarElenco(RAIZ)
  await registrarNoGit(RAIZ, resumoDaMudanca(antes, equipe))
  publicarElenco()
}

async function removerEquipe(id: string): Promise<void> {
  const equipe = elenco().equipe(id)
  if (!equipe) throw new Error(`a equipe ${id} não existe`)
  const abertas = TAREFAS.listar(id).filter((t) => t.status !== "concluida" && t.status !== "cancelada").length
  if (abertas) throw new Error(`a equipe ${equipe.nome} tem ${abertas} tarefa(s) aberta(s) e não pode ser excluída`)
  if (TAREFAS.fluxosAbertos().some((f) => f.equipe === id)) throw new Error(`a equipe ${equipe.nome} tem workflow rodando e não pode ser excluída`)
  await apagarEquipe(RAIZ, id)
  AGENDADOR.removerDaEquipe(id)
  MOTOR.removerDaEquipe(id)
  await carregarElenco(RAIZ)
  await registrarNoGit(RAIZ, `equipe ${equipe.nome} excluída`)
  publicarElenco()
  publicarRotinas()
}

function equipeDaRotina(bruto: unknown) {
  const id = String(bruto ?? "")
  const equipe = elenco().equipe(id)
  if (!equipe) throw new Error(`a equipe ${id} não existe`)
  return equipe
}

function rotinaExistente(equipe: string, bruto: unknown) {
  const id = String(bruto ?? "")
  const rotina = AGENDADOR.rotina(equipe, id)
  if (!rotina) throw new Error(`a rotina ${id} não existe na equipe ${equipe}`)
  return rotina
}

function workflowsParaCliente() {
  const fluxos = [...TAREFAS.fluxosAbertos(), ...TAREFAS.fluxosRecentes(20)]
  return {
    tipo: "workflows",
    definicoes: MOTOR.todas().map(({ equipe, workflow }) => ({ ...workflow, equipe })),
    fluxos: fluxos.map((f) => ({ ...f, fichas: TAREFAS.fichasDo(f.id) })),
  }
}

function publicarFluxos(): void {
  mandarATodos(workflowsParaCliente())
  agendarPainel()
}

async function salvarWorkflow(equipeId: unknown, bruto: unknown): Promise<void> {
  const equipe = equipeDaRotina(equipeId)
  if (!bruto || typeof bruto !== "object" || Array.isArray(bruto)) throw new Error("workflow inválido")
  const { equipe: _equipe, ...recebido } = bruto as Record<string, unknown>
  const id = String(recebido.id ?? "")
  const disco = slugValido(id) ? await lerWorkflowDoDisco(RAIZ, equipe.id, id) : null
  conferirVersao(disco, id, recebido.versao)
  const antes = MOTOR.definicao(equipe.id, id)
  const cru = { ...recebido, versao: versaoNoDisco(disco) + 1 }
  const workflow = await validarWorkflowDaEquipe(RAIZ, equipe, cru)
  await gravarWorkflow(RAIZ, equipe.id, cru, disco)
  MOTOR.definir(equipe.id, workflow)
  await registrarNoGit(RAIZ, `workflow ${workflow.nome} ${antes ? "editado" : "criado"} (versão ${workflow.versao})`)
  publicarFluxos()
}

async function excluirWorkflow(equipeId: unknown, idBruto: unknown): Promise<void> {
  const equipe = equipeDaRotina(equipeId)
  const id = String(idBruto ?? "")
  const workflow = MOTOR.definicao(equipe.id, id)
  if (!workflow) throw new Error(`o workflow ${id} não existe na equipe ${equipe.nome}`)
  if (TAREFAS.fluxosAbertos().some((f) => f.equipe === equipe.id && f.workflow === id)) throw new Error(`o workflow ${workflow.nome} está rodando`)
  const rotina = AGENDADOR.daEquipe(equipe.id).find((r) => r.workflow === id)
  if (rotina) throw new Error(`a rotina ${rotina.nome} dispara o workflow ${workflow.nome}`)
  await apagarWorkflow(RAIZ, equipe.id, id)
  MOTOR.remover(equipe.id, id)
  await registrarNoGit(RAIZ, `workflow ${workflow.nome} excluído`)
  publicarFluxos()
}

const idDeFluxo = (bruto: unknown) => idDeTarefa(bruto)

function publicarRotinas(): void {
  mandarATodos({ tipo: "rotinas", lista: AGENDADOR.paraCliente() })
  agendarPainel()
}

async function salvarRotina(equipeId: unknown, bruto: unknown): Promise<void> {
  const equipe = equipeDaRotina(equipeId)
  const rotina = validarRotina(bruto, equipe, (w) => MOTOR.definicao(equipe.id, w)?.entrada)
  const antes = AGENDADOR.rotina(equipe.id, rotina.id)
  await gravarRotina(RAIZ, equipe.id, rotina)
  AGENDADOR.definir(equipe.id, rotina)
  const gatilho = [rotina.cron ? `cron ${rotina.cron}` : "", rotina.webhook ? "webhook" : ""].filter(Boolean).join(" e ") || "só manual"
  await registrarNoGit(RAIZ, `rotina ${rotina.nome} ${antes ? "editada" : "criada"}: ${gatilho}`)
  publicarRotinas()
}

async function excluirRotina(equipeId: unknown, idBruto: unknown): Promise<void> {
  const equipe = equipeDaRotina(equipeId)
  const rotina = rotinaExistente(equipe.id, idBruto)
  await apagarRotina(RAIZ, equipe.id, rotina.id)
  AGENDADOR.remover(equipe.id, rotina.id)
  await registrarNoGit(RAIZ, `rotina ${rotina.nome} excluída`)
  publicarRotinas()
}

async function ativarRotina(equipeId: unknown, idBruto: unknown, ativa: boolean): Promise<void> {
  const equipe = equipeDaRotina(equipeId)
  const rotina = { ...rotinaExistente(equipe.id, idBruto), ativa }
  await gravarRotina(RAIZ, equipe.id, rotina)
  AGENDADOR.definir(equipe.id, rotina)
  TAREFAS.auditar("ueslei", ativa ? "ativou a rotina" : "desativou a rotina", `rotina:${equipe.id}/${rotina.id}`)
  await registrarNoGit(RAIZ, `rotina ${rotina.nome} ${ativa ? "ativada" : "desativada"}`)
  publicarRotinas()
}

async function receberWebhook(req: Request, equipe: string, id: string): Promise<Response> {
  const tamanho = Number(req.headers.get("content-length") ?? 0)
  const token = req.headers.get("x-token") ?? new URL(req.url).searchParams.get("token") ?? ""
  const corpo = tamanho > LIMITE_DO_CORPO ? "x".repeat(LIMITE_DO_CORPO + 1) : await req.text()
  const { status, resposta } = AGENDADOR.webhook(equipe, id, token, corpo)
  return Response.json(resposta, { status })
}

async function novaPersonaPeloCliente(bruto: unknown): Promise<void> {
  const pedido = lerPedidoDePersona(bruto)
  const persona = await criarPersona(RAIZ, pedido)
  await registrarNoGit(RAIZ, `persona ${persona.nome} criada`)
  GERANDO_PERFIL.add(persona.id)
  publicarElenco()
  void gerarPerfil(RAIZ, persona, pedido.base)
    .then(() => registrarNoGit(RAIZ, `perfil de ${persona.nome} gerado`))
    .catch((erro: Error) => {
      console.warn(`[personas] perfil de ${persona.id} não foi gerado — ${erro.message}`)
      const aviso: NovoAviso = {
        tipo: "tarefa",
        titulo: `O perfil de ${persona.nome} não foi gerado`,
        corpo: `Ficou o perfil provisório (a descrição). Erro: ${erro.message}`.slice(0, 180),
        alvo: {},
        acoes: [],
      }
      avisar(AVISOS.criar(aviso))
    })
    .finally(() => {
      GERANDO_PERFIL.delete(persona.id)
      publicarElenco()
    })
}

async function excluirPersonaPeloCliente(id: string, confirmacao: string): Promise<void> {
  if (!elenco().existe(id)) throw new Error(`a persona ${id} não existe`)
  ORQUESTRA.interromperPersona(id)
  const nome = await excluirPersona(RAIZ, id, confirmacao)
  await registrarNoGit(RAIZ, `persona ${nome} excluída`)
  publicarElenco()
}

function idDeTarefa(bruto: unknown): number {
  const id = Number(bruto)
  if (!Number.isInteger(id) || id <= 0) throw new Error("tarefa inválida")
  return id
}

function paraCliente(tarefa: Tarefa) {
  return { ...tarefa, rodando: ORQUESTRA.rodando(tarefa.id), comQuem: comQuem(tarefa, equipePorId(tarefa.equipe), nomeDe) }
}

function tarefaParaCliente(id: number) {
  return paraCliente(TAREFAS.exigir(id))
}

function detalheDaTarefa(id: number) {
  const execucoes = TAREFAS.execucoesDaTarefa(id)
  return {
    tarefa: tarefaParaCliente(id),
    registros: TAREFAS.registros(id),
    execucoes,
    custoUSD: execucoes.reduce((soma, e) => soma + (e.custoUSD ?? 0), 0),
  }
}

function publicarTarefa(id: number): void {
  mandarATodos({ tipo: "tarefa", ...detalheDaTarefa(id) })
  agendarPainel()
}

function publicarExecucao(execucao: Execucao): void {
  mandarATodos({ tipo: "execucao", execucao })
  agendarPainel()
}

function publicarEvento(evento: Evento, tarefaId: number): void {
  mandarATodos({ tipo: "execucao-evento", execucaoId: evento.execucao, tarefaId, evento })
  agendarPainel()
}

// ── painel ─────────────────────────────────────────────────────────

function retratoDoPainel() {
  const agora = new Date()
  const execucoes = (status: "rodando" | "na_fila") => TAREFAS.comStatus(status)
  return montarRetrato(
    {
      agora,
      mes: mesDe(agora),
      teto: tetoDeExecucoes(),
      pausas: TAREFAS.pausas(),
      bloqueio: bloqueioDe,
      equipes: elenco().equipes(),
      personas: elenco()
        .personas()
        .map((p) => ({
          id: p.id,
          nome: p.nome,
          cor: corDaPersona(p),
          limiteUSD: p.orcamentoMensalUSD ?? null,
          limiteTokens: p.orcamentoMensalTokens ?? null,
          gasto: CONTAS.gasto(p.id, agora),
        })),
      tarefas: TAREFAS.listar(),
      registros: (id) => TAREFAS.registros(id),
      rodando: execucoes("rodando"),
      naFila: execucoes("na_fila"),
      personaDaFila: (e) => ORQUESTRA.personaDaFila(e),
      ultimoEvento: (id) => TAREFAS.ultimoEvento(id),
      comandos: [...pendentes].map(([id, p]) => ({
        id,
        comando: p.comando,
        quem: p.quem,
        desde: p.desde.toISOString(),
        ...(p.tarefaId !== undefined ? { tarefaId: p.tarefaId } : {}),
        ...(p.conversaId !== undefined ? { conversaId: p.conversaId } : {}),
      })),
      rotinas: AGENDADOR.paraCliente() as never,
      registrosRecentes: TAREFAS.registrosRecentes(TIPOS_DA_ATIVIDADE),
      auditoria: TAREFAS.auditoria(100),
      disparos: TAREFAS.disparosRecentes(100),
      fluxos: TAREFAS.fluxosAbertos().map((fluxo) => ({ fluxo, fichas: TAREFAS.fichasDo(fluxo.id) })),
    },
    (id) => TAREFAS.execucao(id)?.persona ?? null,
  )
}

const PAINEL = new AssinaturaDoPainel<Cliente>(retratoDoPainel, (ws, retrato) => mandar(ws, { tipo: "painel", retrato }))

function agendarPainel(): void {
  PAINEL.mudou()
}

const abertoOuNada = (ws?: Cliente) => (ws?.readyState === WebSocket.OPEN ? ws : undefined)

// ── permissão de comando do executor ───────────────────────────────

const PRAZO_PERMISSAO = 120_000
const PRAZO_PERMISSAO_EM_TAREFA = 600_000

interface Pendente {
  ws?: Cliente
  conversaId?: string
  tarefaId?: number
  comando: string
  quem: string
  desde: Date
  expiraEm: Date
  avisado: boolean
  resolver: (permitido: boolean) => void
  prazo: ReturnType<typeof setTimeout>
}

const pendentes = new Map<string, Pendente>()

// O cartão do chat precisa saber quando a permissão se resolve por fora (aviso ou prazo):
// senão fica com os botões vivos para uma permissão que já não existe.
function soltarPermissao(id: string, permitido: boolean, como: Como = permitido ? "aprovado" : "negado"): boolean {
  const pendente = pendentes.get(id)
  if (!pendente) return false
  clearTimeout(pendente.prazo)
  pendentes.delete(id)
  pendente.resolver(permitido)
  agendarPainel()
  if (pendente.tarefaId !== undefined) {
    TAREFAS.auditar("ueslei", `comando ${como}`, `tarefa:${pendente.tarefaId}`, pendente.comando)
    mandarATodos({ tipo: "permissao-resolvida", id, como, tarefaId: pendente.tarefaId })
    return true
  }
  const aberto = abertoOuNada(pendente.ws)
  if (aberto) mandar(aberto, { tipo: "permissao-resolvida", id, como })
  return true
}

function resolverPermissao(id: string, permitido: boolean, como: Como = permitido ? "aprovado" : "negado"): void {
  if (soltarPermissao(id, permitido, como)) avisar(AVISOS.resolver(id, como))
}

function avisarAprovacao(id: string, pendente: Pendente): void {
  if (pendente.avisado || pendente.conversaId === undefined) return
  pendente.avisado = true
  avisar(AVISOS.criar(avisoDeAprovacao(id, pendente.conversaId, pendente.comando, pendente.expiraEm)))
}

function aplicarPresenca({ mostrada, deixadas }: Mudanca): void {
  if (mostrada) {
    for (const aviso of AVISOS.abertos()) {
      if (aviso.tipo === "resposta" && aviso.alvo.conversaId === mostrada) avisar(AVISOS.resolver(aviso.id, "lido"))
    }
  }
  for (const [id, pendente] of pendentes) {
    if (pendente.conversaId !== undefined && deixadas.includes(pendente.conversaId)) avisarAprovacao(id, pendente)
  }
}

// Em modo auto o comando não é barrado, mas aparece no chat: senão o auto seria caixa
// preta e o Ueslei descobriria o que rodou pelo efeito colateral.
function tratarComando(ws: Cliente | undefined, conversaId: string, quem: string, comando: string, aprovar: boolean): Promise<boolean> {
  const aberto = abertoOuNada(ws)
  // Sem ninguém do outro lado (chat ou stream de avisos), nem o auto roda: o comando
  // ficaria sem testemunha.
  if (!aberto && AVISOS.escutando === 0) return Promise.resolve(false)
  if (!aprovar) {
    if (aberto) mandar(aberto, { tipo: "comando", comando })
    return Promise.resolve(true)
  }
  const id = randomUUID()
  return new Promise((resolver) => {
    // Sem prazo, uma aba fechada deixaria o executor esperando para sempre.
    const prazo = setTimeout(() => resolverPermissao(id, false, "expirado"), PRAZO_PERMISSAO)
    const expiraEm = new Date(Date.now() + PRAZO_PERMISSAO)
    const pendente: Pendente = { ws: aberto, conversaId, comando, quem, desde: new Date(), expiraEm, avisado: false, resolver, prazo }
    pendentes.set(id, pendente)
    agendarPainel()
    if (aberto) mandar(aberto, { tipo: "permissao", id, comando })
    if (!PRESENCA.estaVisivel(conversaId)) avisarAprovacao(id, pendente)
  })
}

// Tarefa não tem "conversa visível": o pedido vai para todas as telas e sempre vira aviso.
function tratarComandoDeTarefa(tarefaId: number, persona: string, comando: string, aprovar: boolean): Promise<boolean> {
  if (CLIENTES.size === 0 && AVISOS.escutando === 0) return Promise.resolve(false)
  if (!aprovar) return Promise.resolve(true)
  const id = randomUUID()
  return new Promise((resolver) => {
    const prazo = setTimeout(() => resolverPermissao(id, false, "expirado"), PRAZO_PERMISSAO_EM_TAREFA)
    const expiraEm = new Date(Date.now() + PRAZO_PERMISSAO_EM_TAREFA)
    pendentes.set(id, { tarefaId, comando, quem: nomeDe(persona), desde: new Date(), expiraEm, avisado: true, resolver, prazo })
    agendarPainel()
    mandarATodos({ tipo: "permissao", id, comando, tarefaId })
    avisar(AVISOS.criar(avisoDeAprovacaoEmTarefa(id, tarefaId, nomeDe(persona), comando, expiraEm)))
  })
}

function cancelarPedidosDaTarefa(tarefaId: number): void {
  for (const [id, pendente] of pendentes) {
    if (pendente.tarefaId === tarefaId) resolverPermissao(id, false, "expirado")
  }
}

const ORQUESTRA = new Orquestra({
  raiz: RAIZ,
  repo: TAREFAS,
  memoria: MEMORIA,
  teto: tetoDeExecucoes(),
  equipe: equipePorId,
  nome: nomeDe,
  modelo: (persona) => elenco().persona(persona)?.modelo ?? MODELO_PADRAO,
  trabalhar,
  revisarComBoard: (pedido) => revisarComBoard(RAIZ, { ...pedido, memoria: MEMORIA }),
  publicarTarefa,
  publicarExecucao,
  publicarEvento,
  avisar: (aviso) => avisar(AVISOS.criar(aviso)),
  pedirComando: tratarComandoDeTarefa,
  cancelarPedidos: cancelarPedidosDaTarefa,
  bloqueio: bloqueioDe,
  aposExecucao: conferirOrcamento,
  fluxo: {
    aoEntregar: (tarefa, entrega, devolvido) => MOTOR.aoEntregar(tarefa, entrega, devolvido),
    saidasDa: (tarefa) => MOTOR.saidasDa(tarefa),
    aoConcluir: (id) => MOTOR.aoConcluir(id),
    aoCancelar: (id) => MOTOR.aoCancelar(id),
  },
})

const MOTOR = new Motor({
  repo: TAREFAS,
  equipe: equipePorId,
  aoCriarTarefa: (tarefa) => ORQUESTRA.aoCriar(tarefa),
  aoCancelarTarefa: (id, de) => ORQUESTRA.aoMudarStatus(id, de, "cancelada"),
  publicarTarefa,
  publicarFluxos: () => publicarFluxos(),
  avisar: (aviso) => avisar(AVISOS.criar(aviso)),
  tudoPausado: () => TAREFAS.pausas().has(TUDO),
  deliberar: async (pedido) => {
    const equipe = equipePorId(pedido.equipe)
    const membros = equipe ? membrosDoBoard(equipe, null).filter((m) => !bloqueioDe(m)) : []
    if (!membros.length) throw new Error("nenhum membro do board disponível")
    const r = await deliberarComBoard(RAIZ, {
      titulo: pedido.titulo,
      pauta: pedido.pauta,
      membros,
      modelo: (persona) => elenco().persona(persona)?.modelo ?? MODELO_PADRAO,
      opcoes: pedido.opcoes,
      memoria: MEMORIA,
    })
    return { sintese: `${r.sintese.trim()}\n\nAta: ${r.ata}`, decisao: r.decisao }
  },
})
try {
  MOTOR.carregar(await lerWorkflows(RAIZ, elenco().equipes()))
} catch (erro) {
  console.error(`workflow inválido: ${(erro as Error).message}`)
  process.exit(1)
}

const TRABALHOS_DA_MEMORIA = {
  migrar: () => migrarPendentes(RAIZ, MEMORIA),
  pendentes: (agora: Date) => conversasPendentes(RAIZ, agora),
  consolidar: (meta: Parameters<typeof consolidarConversa>[2]) => consolidarConversa(RAIZ, MEMORIA, meta),
  guardadas: () => consolidarGuardadas(RAIZ, MEMORIA),
  sonhar: (persona: Parameters<typeof sonhar>[2]) => sonhar(RAIZ, MEMORIA, persona),
}
const ESPERA_DA_MEMORIA = new Espera()

const AGENDADOR = new Agendador({
  repo: TAREFAS,
  equipe: equipePorId,
  aoCriar: (tarefa) => ORQUESTRA.aoCriar(tarefa),
  aoMudarStatus: (id, de, para) => ORQUESTRA.aoMudarStatus(id, de, para),
  publicarTarefa,
  publicarRotinas: () => publicarRotinas(),
  avisar: (aviso) => avisar(AVISOS.criar(aviso)),
  sistema: () => rodarUmaVez(RAIZ, TRABALHOS_DA_MEMORIA, ESPERA_DA_MEMORIA),
  fluxos: {
    aberto: (autor) => TAREFAS.fluxoAbertoDe(autor)?.id ?? null,
    entrada: (equipe, workflow) => MOTOR.definicao(equipe, workflow)?.entrada,
    iniciar: (equipe, workflow, entrada, autor, depoisDe) => MOTOR.iniciar(equipe, workflow, entrada, autor, depoisDe).id,
    cancelar: (id, quem, motivo) => MOTOR.cancelar(id, quem, motivo),
  },
})
try {
  AGENDADOR.carregar(await lerRotinas(RAIZ, elenco().equipes(), (equipe, id) => MOTOR.definicao(equipe, id)?.entrada))
} catch (erro) {
  console.error(`rotina inválida: ${(erro as Error).message}`)
  process.exit(1)
}

const executarAviso = executorDeAvisos({
  soltarPermissao,
  concluir: (aviso) => LEMBRETES.concluir(aviso),
  adiar: (aviso, para) => LEMBRETES.adiar(aviso, para),
  responder: (conversaId, texto) =>
    void naFilaDaConversa(conversaId, () => responderNaConversa(undefined, conversaId, texto)).catch((erro: Error) =>
      console.warn(`[avisos] resposta pelo aviso em ${conversaId} falhou — ${erro.message}`),
    ),
})

async function responderNaConversa(
  ws: Cliente | undefined,
  id: string,
  texto: string,
  citacao?: string,
  modelo?: string,
  anexos: Anexo[] = [],
  auto?: boolean,
  foco?: unknown,
): Promise<void> {
  let meta = await lerMeta(RAIZ, id)
  if (!ehPerfil(meta.perfil)) throw new Error(`a persona ${meta.perfil} foi excluída: esta conversa é só leitura`)
  const focoPedido = lerFoco(meta.perfil, foco)
  const focoDesligado = focoPedido === null && meta.foco !== undefined
  if (focoPedido !== undefined && focoPedido !== (meta.foco ?? null)) {
    meta = await atualizarMeta(RAIZ, id, { foco: focoPedido ?? undefined })
  }
  if (modelo !== undefined && modelo !== (meta.modelo ?? "")) {
    meta = await atualizarMeta(RAIZ, id, { modelo: modelo || undefined })
  }
  if (auto !== undefined && auto !== (meta.auto ?? false)) {
    meta = await atualizarMeta(RAIZ, id, { auto })
  }
  const agora = new Date().toISOString()
  await anexarMensagem(RAIZ, id, {
    role: "user",
    texto,
    ts: agora,
    perfil: meta.perfil,
    citacao,
    anexos: anexos.length ? anexos : undefined,
  })

  const textoParaModelo = [
    montarBlocoDeAnexos(anexos, RAIZ),
    citacao ? `[Estou respondendo especificamente a este trecho seu: "${citacao}"]` : "",
    texto,
  ]
    .filter(Boolean)
    .join("\n\n")

  const resposta = await conversar({
    raiz: RAIZ,
    perfil: meta.perfil,
    texto: textoParaModelo,
    sessionId: meta.sessionId,
    modelo: modeloEfetivo(meta),
    auto: meta.auto,
    foco: meta.foco,
    focoDesligado,
    memoria: MEMORIA,
    conversaId: id,
    consulta: texto,
    onChunk: (pedaco) => {
      if (ws) mandar(ws, { tipo: "chunk", conversaId: id, perfil: meta.perfil, texto: pedaco })
    },
    onComando: (comando, aprovar) => tratarComando(ws, id, nomeDe(meta.perfil), comando, aprovar),
    onSessao: (sessionId) => atualizarMeta(RAIZ, id, { sessionId }),
    agendarLembrete: (pedido) => LEMBRETES.agendar(pedido),
  })

  await anexarMensagem(RAIZ, id, {
    role: "assistant",
    texto: resposta.texto,
    ts: new Date().toISOString(),
    perfil: meta.perfil,
  })
  if (ws) mandar(ws, { tipo: "fim", conversaId: id })
  if (!PRESENCA.estaVisivel(id)) avisar(AVISOS.criar(avisoDeResposta(meta.perfil, id, resposta.texto)))
  if (ehConselheiro(meta.perfil)) {
    espelharEmSegundoPlano()
    versionarEmSegundoPlano(`conversa com ${meta.perfil}`)
  }
}

async function resolverAnexos(ws: Cliente, ids: unknown): Promise<Anexo[]> {
  if (!Array.isArray(ids) || !ids.length) return []
  const pedidos = ids.map(String)
  const achados = await lerAnexos(RAIZ, pedidos)
  const perdidos = pedidos.length - achados.length
  if (perdidos > 0) {
    mandar(ws, { tipo: "aviso", texto: `${perdidos} anexo(s) não encontrado(s) e ignorado(s).` })
  }
  return achados
}

async function tratar(ws: Cliente, bruto: string): Promise<void> {
  const msg = JSON.parse(bruto) as Record<string, unknown>

  switch (msg.tipo) {
    case "listar": {
      mandar(ws, { tipo: "conversas", lista: await listarConversas(RAIZ) })
      return
    }
    case "nova": {
      const perfil = msg.perfil
      const texto = String(msg.texto ?? "").trim()
      const anexos = await resolverAnexos(ws, msg.anexos)
      if (!ehPerfil(perfil)) throw new Error("perfil inválido")
      if (!texto && !anexos.length) throw new Error("mensagem vazia")
      const base = texto || anexos[0]!.nome
      const titulo = base.length > 48 ? `${base.slice(0, 48)}…` : base
      const modelo = msg.modelo ? String(msg.modelo) : undefined
      const meta = await criarConversa(RAIZ, perfil, titulo, modelo, {
        auto: msg.auto === true ? true : undefined,
        foco: msg.foco === "ticktask" ? "ticktask" : undefined,
      })
      await naFilaDaConversa(meta.id, async () => {
        mandar(ws, { tipo: "criada", meta })
        if (ehConselheiro(perfil)) {
          await consolidarPendentesDe(RAIZ, MEMORIA, perfil, meta.id).catch((erro: Error) =>
            console.warn(`[memoria] pendentes de ${perfil} não consolidadas antes da conversa nova — ${erro.message}`),
          )
        }
        return responderNaConversa(
          ws,
          meta.id,
          texto,
          msg.citacao ? String(msg.citacao) : undefined,
          undefined,
          anexos,
        )
      })
      return
    }
    case "mensagem": {
      const id = String(msg.conversaId ?? "")
      const texto = String(msg.texto ?? "").trim()
      const anexos = await resolverAnexos(ws, msg.anexos)
      if (!id) throw new Error("conversa inválida")
      if (!texto && !anexos.length) throw new Error("mensagem vazia")
      await naFilaDaConversa(id, () =>
        responderNaConversa(
          ws,
          id,
          texto,
          msg.citacao ? String(msg.citacao) : undefined,
          msg.modelo !== undefined ? String(msg.modelo) : undefined,
          anexos,
          msg.auto !== undefined ? msg.auto === true : undefined,
          msg.foco,
        ),
      )
      return
    }
    case "permissao-resposta": {
      resolverPermissao(String(msg.id ?? ""), Boolean(msg.permitido))
      return
    }
    case "visivel": {
      const conversaId = typeof msg.conversaId === "string" && idValido(msg.conversaId) ? msg.conversaId : null
      aplicarPresenca(PRESENCA.definir(ws, conversaId))
      return
    }
    case "excluir": {
      const id = String(msg.conversaId ?? "")
      const sessionId = await naFilaDaConversa(id, async () => {
        await guardarParaConsolidar(RAIZ, id)
        return excluirConversa(RAIZ, id)
      })
      await apagarSessao(RAIZ, sessionId)
      mandar(ws, { tipo: "excluida", id })
      mandar(ws, { tipo: "conversas", lista: await listarConversas(RAIZ) })
      void consolidarGuardadas(RAIZ, MEMORIA).catch((erro: Error) => console.warn(`[memoria] ${erro.message}`))
      return
    }
    case "abrir": {
      const id = String(msg.conversaId ?? "")
      const meta = await lerMeta(RAIZ, id)
      mandar(ws, { tipo: "conversa", meta, mensagens: await lerMensagens(RAIZ, id) })
      return
    }
    case "board": {
      const pauta = String(msg.pauta ?? "").trim()
      if (!pauta) throw new Error("pauta vazia")
      const contexto = msg.contexto ? String(msg.contexto) : undefined
      const resultado = await convocarBoard(RAIZ, pauta, contexto, (texto) =>
        mandar(ws, { tipo: "board-status", texto }),
        MEMORIA,
      )
      espelharEmSegundoPlano()
      versionarEmSegundoPlano(`ata do board: ${pauta.slice(0, 60)}`)
      mandar(ws, { tipo: "board-sintese", texto: resultado.sintese, ata: resultado.ata })
      return
    }
    case "equipes": {
      mandar(ws, { tipo: "equipes", lista: equipesParaCliente() })
      return
    }
    case "personas": {
      mandar(ws, { tipo: "personas", lista: personasParaCliente() })
      mandar(ws, estadoDaOrquestra())
      return
    }
    case "persona-salvar": {
      await salvarPersona(msg.persona)
      return
    }
    case "pausar": {
      ORQUESTRA.pausar(alvoDaPausa(msg.alvo))
      mandarATodos(estadoDaOrquestra())
      agendarPainel()
      mandarATodos({ tipo: "personas", lista: personasParaCliente() })
      return
    }
    case "retomar": {
      ORQUESTRA.retomar(alvoDaPausa(msg.alvo))
      mandarATodos(estadoDaOrquestra())
      agendarPainel()
      mandarATodos({ tipo: "personas", lista: personasParaCliente() })
      return
    }
    case "tarefa-aprovar-plano": {
      const id = idDeTarefa(msg.id)
      ORQUESTRA.aprovarPlano(id)
      publicarTarefa(id)
      return
    }
    case "tarefa-decidir": {
      const id = idDeTarefa(msg.id)
      if (msg.decisao !== "aprovar" && msg.decisao !== "mudanca") throw new Error("decisão inválida")
      ORQUESTRA.decidir(id, msg.decisao, typeof msg.texto === "string" ? msg.texto : "")
      publicarTarefa(id)
      return
    }
    case "workflows": {
      mandar(ws, workflowsParaCliente())
      return
    }
    case "workflow-iniciar": {
      const equipe = equipeDaRotina(msg.equipe)
      const fluxo = MOTOR.iniciar(equipe.id, String(msg.id ?? ""), msg.entrada ?? {}, "ueslei")
      TAREFAS.auditar("ueslei", "iniciou o workflow", `fluxo:${fluxo.id}`, fluxo.definicao.nome)
      return
    }
    case "workflow-decidir": {
      MOTOR.decidir(idDeFluxo(msg.execucao), idDeFluxo(msg.ficha), String(msg.opcao ?? ""), typeof msg.comentario === "string" ? msg.comentario : "")
      return
    }
    case "workflow-sinal": {
      MOTOR.sinalizar(idDeFluxo(msg.execucao), idDeFluxo(msg.ficha))
      return
    }
    case "workflow-cancelar": {
      MOTOR.cancelar(idDeFluxo(msg.execucao))
      return
    }
    case "workflow-salvar": {
      await salvarWorkflow(msg.equipe, msg.workflow)
      return
    }
    case "workflow-excluir": {
      await excluirWorkflow(msg.equipe, msg.id)
      return
    }
    case "rotinas": {
      mandar(ws, { tipo: "rotinas", lista: AGENDADOR.paraCliente() })
      return
    }
    case "rotina-salvar": {
      await salvarRotina(msg.equipe, msg.rotina)
      return
    }
    case "rotina-excluir": {
      await excluirRotina(msg.equipe, msg.id)
      return
    }
    case "rotina-ativar": {
      await ativarRotina(msg.equipe, msg.id, msg.ativa === true)
      return
    }
    case "rotina-disparar": {
      const equipe = equipeDaRotina(msg.equipe)
      const rotina = rotinaExistente(equipe.id, msg.id)
      TAREFAS.auditar("ueslei", "disparou a rotina", `rotina:${equipe.id}/${rotina.id}`)
      AGENDADOR.disparar(equipe.id, rotina.id, "manual")
      return
    }
    case "rotina-token": {
      const equipe = equipeDaRotina(msg.equipe)
      const rotina = rotinaExistente(equipe.id, msg.id)
      AGENDADOR.trocarToken(equipe.id, rotina.id)
      TAREFAS.auditar("ueslei", "trocou o token da rotina", `rotina:${equipe.id}/${rotina.id}`)
      publicarRotinas()
      return
    }
    case "painel": {
      if (msg.ativo === true) PAINEL.assinar(ws)
      else PAINEL.sair(ws)
      return
    }
    case "persona-criar": {
      await novaPersonaPeloCliente(msg.persona)
      return
    }
    case "persona-excluir": {
      await excluirPersonaPeloCliente(String(msg.id ?? ""), String(msg.confirmacao ?? ""))
      return
    }
    case "equipe-salvar": {
      await salvarEquipe(msg.equipe)
      return
    }
    case "equipe-excluir": {
      const id = String(msg.id ?? "")
      if (!slugValido(id)) throw new Error("equipe inválida")
      await removerEquipe(id)
      return
    }
    case "tarefas": {
      const equipe = typeof msg.equipe === "string" ? msg.equipe : undefined
      mandar(ws, { tipo: "tarefas", lista: TAREFAS.listar(equipe).map(paraCliente) })
      return
    }
    case "tarefa": {
      const id = idDeTarefa(msg.id)
      mandar(ws, { tipo: "tarefa", ...detalheDaTarefa(id), pedida: true })
      return
    }
    case "execucao": {
      const execucao = TAREFAS.exigirExecucao(idDeTarefa(msg.id))
      mandar(ws, { tipo: "execucao", execucao, eventos: TAREFAS.eventos(execucao.id) })
      return
    }
    case "tarefa-criar": {
      const criada = TAREFAS.criar(lerNovaTarefa(msg.tarefa, equipePorId), "ueslei")
      publicarTarefa(criada.id)
      ORQUESTRA.aoCriar(criada)
      return
    }
    case "tarefa-status": {
      const id = idDeTarefa(msg.id)
      if (!statusValido(msg.status)) throw new Error("status inválido")
      const de = TAREFAS.exigir(id).status
      TAREFAS.mudarStatus(id, msg.status, "ueslei")
      publicarTarefa(id)
      ORQUESTRA.aoMudarStatus(id, de, msg.status)
      return
    }
    case "tarefa-comentar": {
      const id = idDeTarefa(msg.id)
      TAREFAS.comentar(id, "ueslei", String(msg.texto ?? ""))
      publicarTarefa(id)
      ORQUESTRA.aoComentar(id)
      return
    }
    case "decisoes": {
      mandar(ws, { tipo: "decisoes", lista: await lerDecisoes(RAIZ) })
      return
    }
    case "decisao": {
      const id = String(msg.id ?? "")
      const conteudo = await lerDecisao(RAIZ, id)
      if (conteudo === null) throw new Error(`decisão "${id}" não encontrada`)
      mandar(ws, { tipo: "decisao", id, conteudo })
      return
    }
    default:
      throw new Error(`tipo de mensagem desconhecido: ${String(msg.tipo)}`)
  }
}

async function receberAnexo(req: Request): Promise<Response> {
  let arquivo: FormDataEntryValue | null
  try {
    arquivo = (await req.formData()).get("arquivo")
  } catch {
    return Response.json({ erro: "corpo inválido" }, { status: 400 })
  }
  if (!(arquivo instanceof File)) {
    return Response.json({ erro: 'mande o arquivo no campo "arquivo"' }, { status: 400 })
  }
  try {
    const anexo = await gravarAnexo(RAIZ, arquivo.name, arquivo.type, await arquivo.arrayBuffer())
    return Response.json(anexo)
  } catch (erro) {
    return Response.json({ erro: (erro as Error).message }, { status: 400 })
  }
}

async function entregarAnexo(id: string): Promise<Response> {
  const anexo = await lerAnexo(RAIZ, id)
  if (!anexo) return new Response("anexo não encontrado", { status: 404 })
  return new Response(Bun.file(join(RAIZ, anexo.arquivo)), {
    headers: {
      "content-type": mimeDeEntrega(anexo),
      "content-disposition": `inline; filename*=UTF-8''${encodeURIComponent(anexo.nome)}`,
      "x-content-type-options": "nosniff",
      "cache-control": "no-store",
    },
  })
}

const servidor = Bun.serve({
  hostname: "0.0.0.0",
  port: PORTA,
  async fetch(req, server) {
    const url = new URL(req.url)
    if (url.pathname === "/ws") {
      return server.upgrade(req) ? undefined : new Response("upgrade falhou", { status: 400 })
    }
    if (url.pathname === "/enderecos") return Response.json(respostaEnderecos(PORTA))
    if (url.pathname === "/avisos" && req.method === "GET") {
      // O idleTimeout padrão (10 s) cortaria o stream antes do keep-alive de 25 s.
      server.timeout(req, 0)
      return streamDeAvisos(AVISOS, lerDesde(url.searchParams.get("desde")), req.signal)
    }
    const rotaDeAcao = url.pathname.match(/^\/avisos\/([^/]+)\/acao$/)
    if (rotaDeAcao && req.method === "POST") {
      const corpo: unknown = await req.json().catch(() => null)
      return tratarAcao(AVISOS, decodeURIComponent(rotaDeAcao[1]!), corpo, executarAviso)
    }
    const rotaDeRotina = url.pathname.match(/^\/rotinas\/([^/]+)\/([^/]+)$/)
    if (rotaDeRotina && req.method === "POST") {
      return receberWebhook(req, decodeURIComponent(rotaDeRotina[1]!), decodeURIComponent(rotaDeRotina[2]!))
    }
    if (url.pathname === "/anexo" && req.method === "POST") return receberAnexo(req)
    if (url.pathname.startsWith("/anexo/")) {
      return entregarAnexo(decodeURIComponent(url.pathname.slice("/anexo/".length)))
    }
    const nome = ESTATICOS[url.pathname]
    if (nome) {
      // Sem isto o navegador do celular serve UI velha do cache e a edição
      // parece não ter surtido efeito.
      return new Response(Bun.file(join(WEB, nome)), {
        headers: { "cache-control": "no-store" },
      })
    }
    return new Response("não encontrado", { status: 404 })
  },
  websocket: {
    // Relido a cada conexão: editar atalhos.md e recarregar a página basta.
    open(ws: Cliente) {
      CLIENTES.add(ws)
      mandar(ws, { tipo: "personas", lista: personasParaCliente() })
      void carregarAtalhos(RAIZ)
        .then((lista) => mandar(ws, { tipo: "atalhos", lista }))
        .catch((erro: Error) => console.warn(`[atalhos] não carregaram — ${erro.message}`))
    },
    message(ws: Cliente, dados) {
      void tratar(ws, String(dados)).catch((erro: Error) => {
        mandar(ws, { tipo: "erro", mensagem: erro.message })
      })
    },
    close(ws: Cliente) {
      CLIENTES.delete(ws)
      PAINEL.sair(ws)
      aplicarPresenca(PRESENCA.remover(ws))
      for (const [id, pendente] of pendentes) {
        if (pendente.ws !== ws) continue
        if (AVISOS.escutando === 0) {
          resolverPermissao(id, false, "expirado")
          continue
        }
        pendente.ws = undefined
        avisarAprovacao(id, pendente)
      }
    },
  },
})

void espelharNaSubida()
LEMBRETES.iniciar()
ORQUESTRA.iniciar()
AGENDADOR.iniciar()
setInterval(agendarPainel, 30_000)
MOTOR.retomar()
setInterval(() => MOTOR.tique(), 30_000)

const rede = enderecos()
console.log(`control-tower de pé (dados: ${RAIZ}, código: ${CODIGO})`)
console.log(`  local:     http://localhost:${servidor.port}`)
if (rede.lan) console.log(`  rede:      http://${rede.lan}:${servidor.port}`)
if (rede.tailscale) console.log(`  tailscale: http://${rede.tailscale}:${servidor.port}`)
