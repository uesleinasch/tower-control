import { Client } from "@modelcontextprotocol/sdk/client/index.js"
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js"
import { join } from "node:path"
import type { ItemDeAtencao } from "./painel"

export const TIPOS_ESPELHAVEIS = [
  "aprovacao",
  "plano",
  "entrega",
  "decisao",
  "sinal",
  "bloqueada",
  "backlog",
  "atrasada",
  "orcamento",
  "rotina",
  "vaga",
] as const
export type TipoEspelhavel = (typeof TIPOS_ESPELHAVEIS)[number]
export const TIPOS_PADRAO: TipoEspelhavel[] = ["aprovacao", "plano", "entrega", "decisao", "sinal", "bloqueada"]

export interface ConfigDoEspelho {
  ativo: boolean
  projeto: string
  tag: string
  tipos: TipoEspelhavel[]
}

export const CONFIG_PADRAO_DO_ESPELHO: ConfigDoEspelho = { ativo: false, projeto: "Control Tower", tag: "control-tower", tipos: TIPOS_PADRAO }

export function validarConfigDoEspelho(bruto: unknown): ConfigDoEspelho {
  const c = (bruto && typeof bruto === "object" && !Array.isArray(bruto) ? bruto : {}) as Record<string, unknown>
  const projeto = typeof c.projeto === "string" ? c.projeto.trim() : CONFIG_PADRAO_DO_ESPELHO.projeto
  const tag = typeof c.tag === "string" ? c.tag.trim() : CONFIG_PADRAO_DO_ESPELHO.tag
  if (!projeto) throw new Error("espelho: projeto do TickTask obrigatório")
  if (!tag) throw new Error("espelho: tag obrigatória")
  const tipos = c.tipos === undefined ? CONFIG_PADRAO_DO_ESPELHO.tipos : c.tipos
  if (!Array.isArray(tipos)) throw new Error("espelho: tipos precisam ser uma lista")
  const estranho = tipos.find((t) => !TIPOS_ESPELHAVEIS.includes(t as TipoEspelhavel))
  if (estranho !== undefined) throw new Error(`espelho: tipo desconhecido (${String(estranho)})`)
  return { ativo: c.ativo === true, projeto, tag, tipos: TIPOS_ESPELHAVEIS.filter((t) => tipos.includes(t)) }
}

export function caminhoDaConfigDoEspelho(raiz: string): string {
  return join(raiz, "ticktask.json")
}

export async function lerConfigDoEspelho(raiz: string): Promise<ConfigDoEspelho> {
  const arquivo = Bun.file(caminhoDaConfigDoEspelho(raiz))
  if (!(await arquivo.exists())) return CONFIG_PADRAO_DO_ESPELHO
  return validarConfigDoEspelho(await arquivo.json())
}

export async function gravarConfigDoEspelho(raiz: string, config: ConfigDoEspelho): Promise<void> {
  await Bun.write(caminhoDaConfigDoEspelho(raiz), `${JSON.stringify(config, null, 2)}\n`)
}

// ── itens, chaves e ações ──────────────────────────────────────────

export type AcaoDoEspelho =
  | { tipo: "aprovar"; tarefa: number }
  | { tipo: "aprovar-plano"; tarefa: number }
  | { tipo: "concluir"; tarefa: number }
  | { tipo: "liberar"; tarefa: number }
  | { tipo: "decidir"; fluxo: number; ficha: number; opcao?: string }
  | { tipo: "sinalizar"; fluxo: number; ficha: number }
  | { tipo: "nenhuma" }

export function chaveDo(item: ItemDeAtencao): string | null {
  switch (item.tipo) {
    case "aprovacao":
    case "plano":
    case "entrega":
    case "bloqueada":
    case "backlog":
    case "vaga":
      return item.tarefaId === undefined ? null : `${item.tipo}:${item.tarefaId}`
    case "decisao":
    case "sinal":
    case "atrasada":
      return item.fluxo === undefined || item.ficha === undefined ? null : `${item.tipo}:${item.fluxo}:${item.ficha}`
    case "orcamento":
      return item.persona ? `orcamento:${item.persona}` : null
    case "rotina":
      return item.rotina ? `rotina:${item.equipe ?? ""}/${item.rotina}` : null
    default:
      return null
  }
}

export function acaoDo(item: ItemDeAtencao): AcaoDoEspelho {
  const tarefa = item.tarefaId
  switch (item.tipo) {
    case "aprovacao":
      return tarefa === undefined ? { tipo: "nenhuma" } : { tipo: "aprovar", tarefa }
    case "plano":
      return tarefa === undefined ? { tipo: "nenhuma" } : { tipo: "aprovar-plano", tarefa }
    case "entrega":
      return tarefa === undefined ? { tipo: "nenhuma" } : { tipo: "concluir", tarefa }
    case "backlog":
      return tarefa === undefined ? { tipo: "nenhuma" } : { tipo: "liberar", tarefa }
    case "decisao":
      return { tipo: "decidir", fluxo: item.fluxo!, ficha: item.ficha! }
    case "sinal":
      return { tipo: "sinalizar", fluxo: item.fluxo!, ficha: item.ficha! }
    default:
      return { tipo: "nenhuma" }
  }
}

const O_QUE_FINALIZAR_FAZ: Record<AcaoDoEspelho["tipo"], string> = {
  aprovar: "Finalizar aqui aprova a entrega. Para pedir mudança, abra o control-tower.",
  "aprovar-plano": "Finalizar aqui aprova o plano.",
  concluir: "Finalizar aqui conclui a tarefa.",
  liberar: "Finalizar aqui libera a subtarefa delegada.",
  decidir: "Finalize a subtarefa da opção escolhida. Finalizar só esta tarefa não decide nada.",
  sinalizar: "Finalizar aqui dá o sinal.",
  nenhuma: "Finalizar aqui só tira o aviso da sua lista.",
}

export function descricaoNoTickTask(item: ItemDeAtencao, endereco: string | null): string {
  const acao = acaoDo(item)
  return [item.detalhe, O_QUE_FINALIZAR_FAZ[acao.tipo], endereco ? `control-tower: ${endereco}` : ""].filter(Boolean).join("\n\n")
}

// ── linhas e a volta ───────────────────────────────────────────────

export type EstadoDaLinha = "criar" | "aberto" | "fechar" | "resolvido_aqui" | "resolvido_la" | "dispensado" | "arquivado"
export const ESTADOS_QUE_SEGURAM: readonly EstadoDaLinha[] = ["criar", "aberto", "dispensado"]

export interface LinhaDoEspelho {
  id: number
  chave: string
  tipo: string
  titulo: string
  ticktask: number | null
  opcoes: Record<string, number>
  estado: EstadoDaLinha
  acao: AcaoDoEspelho
  criadoEm: string
  atualizadoEm: string
  erro: string | null
}

export interface Comparacao {
  criar: { chave: string; item: ItemDeAtencao }[]
  fechar: number[]
  resolverSemSubir: number[]
  arquivar: number[]
}

export function desejados(itens: ItemDeAtencao[], config: ConfigDoEspelho): Map<string, ItemDeAtencao> {
  const mapa = new Map<string, ItemDeAtencao>()
  for (const item of itens) {
    if (!config.tipos.includes(item.tipo as TipoEspelhavel)) continue
    const chave = chaveDo(item)
    if (chave && !mapa.has(chave)) mapa.set(chave, item)
  }
  return mapa
}

export function comparar(querem: Map<string, ItemDeAtencao>, linhas: LinhaDoEspelho[]): Comparacao {
  const seguradas = new Set(linhas.filter((l) => ESTADOS_QUE_SEGURAM.includes(l.estado)).map((l) => l.chave))
  return {
    criar: [...querem].filter(([chave]) => !seguradas.has(chave)).map(([chave, item]) => ({ chave, item })),
    fechar: linhas
      .filter((l) => (l.estado === "aberto" || (l.estado === "criar" && l.ticktask !== null)) && !querem.has(l.chave))
      .map((l) => l.id),
    resolverSemSubir: linhas.filter((l) => l.estado === "criar" && l.ticktask === null && !querem.has(l.chave)).map((l) => l.id),
    arquivar: linhas.filter((l) => l.estado === "dispensado" && !querem.has(l.chave)).map((l) => l.id),
  }
}

export interface TarefaNoTickTask {
  finalizada: boolean
  subtarefas: { id: number; finalizada: boolean }[]
}

export type Puxada =
  | { estado: "aberto" }
  | { estado: "resolvido_aqui" | "dispensado" }
  | { estado: "resolvido_la"; acao: AcaoDoEspelho }

export function decidirPuxada(linha: LinhaDoEspelho, lida: TarefaNoTickTask | null, querem: Map<string, ItemDeAtencao>): Puxada {
  const pendente = querem.has(linha.chave)
  if (!lida) return { estado: pendente ? "dispensado" : "resolvido_aqui" }
  if (linha.acao.tipo === "decidir") {
    const escolhida = Object.entries(linha.opcoes).find(([, id]) => lida.subtarefas.some((s) => s.id === id && s.finalizada))
    if (escolhida) return pendente ? { estado: "resolvido_la", acao: { ...linha.acao, opcao: escolhida[0] } } : { estado: "resolvido_aqui" }
    if (!lida.finalizada) return { estado: "aberto" }
    return { estado: pendente ? "dispensado" : "resolvido_aqui" }
  }
  if (!lida.finalizada) return { estado: "aberto" }
  if (!pendente) return { estado: "resolvido_aqui" }
  return linha.acao.tipo === "nenhuma" ? { estado: "dispensado" } : { estado: "resolvido_la", acao: linha.acao }
}

// ── o TickTask ─────────────────────────────────────────────────────

export interface NovaTarefa {
  nome: string
  descricao: string
  projeto: string
  tag: string
  pai?: number
}

export interface TickTask {
  criar(t: NovaTarefa): Promise<number>
  finalizar(id: number, nota: string): Promise<void>
  ler(id: number): Promise<TarefaNoTickTask | null>
  fechar(): Promise<void>
}

class ErroDoTickTask extends Error {
  constructor(
    mensagem: string,
    readonly codigo?: string,
  ) {
    super(mensagem)
  }
}

export async function conectarTickTask(endereco: { url: string; token: string }): Promise<TickTask> {
  const cliente = new Client({ name: "control-tower", version: "1" })
  await cliente.connect(
    new StreamableHTTPClientTransport(new URL(endereco.url), { requestInit: { headers: { authorization: `Bearer ${endereco.token}` } } }),
  )
  const chamar = async (name: string, args: Record<string, unknown>): Promise<Record<string, unknown>> => {
    const r = (await cliente.callTool({ name, arguments: args })) as { content?: { type: string; text?: string }[]; isError?: boolean }
    const texto = r.content?.find((c) => c.type === "text")?.text ?? "{}"
    let dados: Record<string, unknown>
    try {
      dados = JSON.parse(texto) as Record<string, unknown>
    } catch {
      dados = { message: texto }
    }
    if (r.isError) throw new ErroDoTickTask(String(dados.message ?? texto), typeof dados.code === "string" ? dados.code : undefined)
    return dados
  }
  return {
    async criar(t) {
      const r = await chamar("create_task", {
        name: t.nome,
        description: t.descricao,
        status: "proximas",
        project: t.projeto,
        tags: [t.tag],
        ...(t.pai ? { parent_task_id: t.pai } : {}),
      })
      const id = (r.task as { id?: unknown } | undefined)?.id ?? r.id
      if (typeof id !== "number") throw new Error("o TickTask não devolveu o id da tarefa criada")
      return id
    },
    async finalizar(id, nota) {
      await chamar("update_task", { id, status: "finalizada" })
      if (nota) await chamar("write_notes", { task_id: id, markdown: nota, mode: "append" })
    },
    async ler(id) {
      try {
        const r = await chamar("get_task", { id })
        const tarefa = r.task as { status?: unknown }
        const subtarefas = (Array.isArray(r.subtasks) ? r.subtasks : []) as { id: number; status: unknown }[]
        return {
          finalizada: tarefa.status === "finalizada",
          subtarefas: subtarefas.map((s) => ({ id: s.id, finalizada: s.status === "finalizada" })),
        }
      } catch (erro) {
        if (erro instanceof ErroDoTickTask && erro.codigo === "not_found") return null
        throw erro
      }
    },
    async fechar() {
      await cliente.close()
    },
  }
}

// ── a volta ────────────────────────────────────────────────────────

export interface RepositorioDoEspelho {
  linhasDoEspelho(): LinhaDoEspelho[]
  criarLinha(l: { chave: string; tipo: string; titulo: string; acao: AcaoDoEspelho }): LinhaDoEspelho
  mudarLinha(id: number, mudanca: Partial<Pick<LinhaDoEspelho, "estado" | "ticktask" | "opcoes" | "erro">>): void
}

export interface AmbienteDoEspelho {
  repo: RepositorioDoEspelho
  config(): ConfigDoEspelho
  itens(): ItemDeAtencao[]
  conectar(): Promise<TickTask | null>
  agir(acao: AcaoDoEspelho): void
  endereco(): string | null
  mudou(): void
  agora?: () => Date
}

export interface EstadoDoEspelho {
  conectado: boolean
  ultimaVolta: string | null
  erro: string | null
  abertos: number
  pendentes: number
}

export class Espelho {
  private fila: Promise<unknown> = Promise.resolve()
  private estado: { conectado: boolean; ultimaVolta: string | null; erro: string | null } = { conectado: false, ultimaVolta: null, erro: null }
  private agendada: ReturnType<typeof setTimeout> | null = null

  constructor(private readonly amb: AmbienteDoEspelho) {}

  resumo(): EstadoDoEspelho {
    const linhas = this.amb.repo.linhasDoEspelho()
    return {
      ...this.estado,
      abertos: linhas.filter((l) => l.estado === "aberto").length,
      pendentes: linhas.filter((l) => l.estado === "criar" || l.estado === "fechar").length,
    }
  }

  agendar(ms = 2000): void {
    if (this.agendada || !this.amb.config().ativo) return
    this.agendada = setTimeout(() => {
      this.agendada = null
      void this.volta()
    }, ms)
  }

  volta(): Promise<void> {
    const vez = this.fila.then(() => this.umaVolta())
    this.fila = vez.catch(() => {})
    return vez
  }

  private agora(): Date {
    return this.amb.agora?.() ?? new Date()
  }

  private async umaVolta(): Promise<void> {
    const config = this.amb.config()
    if (!config.ativo) return
    const repo = this.amb.repo
    const querem = desejados(this.amb.itens(), config)
    const comp = comparar(querem, repo.linhasDoEspelho())
    for (const { chave, item } of comp.criar) repo.criarLinha({ chave, tipo: item.tipo, titulo: item.titulo, acao: acaoDo(item) })
    for (const id of comp.fechar) repo.mudarLinha(id, { estado: "fechar" })
    for (const id of comp.resolverSemSubir) repo.mudarLinha(id, { estado: "resolvido_aqui" })
    for (const id of comp.arquivar) repo.mudarLinha(id, { estado: "arquivado" })
    let tt: TickTask | null = null
    try {
      tt = await this.amb.conectar()
      if (!tt) throw new Error("TickTask fora do ar (sem config do MCP ou app fechado)")
      await this.subir(tt, querem, config)
      await this.puxar(tt, querem)
      this.estado = { conectado: true, ultimaVolta: this.agora().toISOString(), erro: null }
    } catch (erro) {
      this.estado = { conectado: false, ultimaVolta: this.agora().toISOString(), erro: (erro as Error).message }
    } finally {
      await tt?.fechar().catch(() => {})
      this.amb.mudou()
    }
  }

  private async subir(tt: TickTask, querem: Map<string, ItemDeAtencao>, config: ConfigDoEspelho): Promise<void> {
    const repo = this.amb.repo
    for (const linha of repo.linhasDoEspelho().filter((l) => l.estado === "criar")) {
      const item = querem.get(linha.chave)
      if (!item) continue
      const id =
        linha.ticktask ??
        (await tt.criar({
          nome: `[CT] ${item.titulo}`,
          descricao: descricaoNoTickTask(item, this.amb.endereco()),
          projeto: config.projeto,
          tag: config.tag,
        }))
      if (linha.ticktask === null) repo.mudarLinha(linha.id, { ticktask: id })
      const opcoes = { ...linha.opcoes }
      for (const opcao of item.tipo === "decisao" ? (item.opcoes ?? []) : []) {
        if (opcoes[opcao] !== undefined) continue
        opcoes[opcao] = await tt.criar({ nome: `[CT] ${opcao}`, descricao: `Finalizar escolhe "${opcao}".`, projeto: config.projeto, tag: config.tag, pai: id })
        repo.mudarLinha(linha.id, { opcoes })
      }
      repo.mudarLinha(linha.id, { estado: "aberto", erro: null })
    }
    const quando = this.agora().toLocaleString("pt-BR")
    for (const linha of repo.linhasDoEspelho().filter((l) => l.estado === "fechar")) {
      if (linha.ticktask !== null) {
        for (const sub of Object.values(linha.opcoes)) await tt.finalizar(sub, "")
        await tt.finalizar(linha.ticktask, `Resolvido no control-tower em ${quando}.`)
      }
      repo.mudarLinha(linha.id, { estado: "resolvido_aqui" })
    }
  }

  private async puxar(tt: TickTask, querem: Map<string, ItemDeAtencao>): Promise<void> {
    const repo = this.amb.repo
    for (const linha of repo.linhasDoEspelho().filter((l) => l.estado === "aberto" && l.ticktask !== null)) {
      const puxada = decidirPuxada(linha, await tt.ler(linha.ticktask!), querem)
      if (puxada.estado === "aberto") continue
      if (puxada.estado !== "resolvido_la") {
        repo.mudarLinha(linha.id, { estado: puxada.estado })
        continue
      }
      try {
        this.amb.agir(puxada.acao)
        repo.mudarLinha(linha.id, { estado: "resolvido_la" })
        if (puxada.acao.tipo === "decidir") {
          for (const [opcao, sub] of Object.entries(linha.opcoes)) if (opcao !== puxada.acao.opcao) await tt.finalizar(sub, "")
          await tt.finalizar(linha.ticktask!, `Decidido "${puxada.acao.opcao}" pelo TickTask.`)
        }
      } catch (erro) {
        const mensagem = (erro as Error).message
        repo.mudarLinha(linha.id, { estado: "resolvido_aqui", erro: mensagem })
        await tt.finalizar(linha.ticktask!, `Não deu para agir no control-tower: ${mensagem}`).catch(() => {})
      }
    }
  }
}
