import { join } from "node:path"
import { appendFile, mkdir } from "node:fs/promises"

export type TipoDeUso = "chat" | "board-parecer" | "board-sintese" | "consolidacao" | "sonho" | "migracao" | "tarefa" | "persona"

export interface RegistroDeUso {
  ts: string
  tipo: TipoDeUso
  perfil?: string
  conversaId?: string
  tarefaId?: number
  execucaoId?: number
  sessionId?: string
  modelo?: string
  chamadas: number
  entrada: number
  escritaCache: number
  leituraCache: number
  saida: number
  custoAcumuladoUSD?: number
  retomada: boolean
  duracaoMs: number
}

interface Usage {
  input_tokens?: number
  output_tokens?: number
  cache_creation_input_tokens?: number
  cache_read_input_tokens?: number
}

export function coletorDeUso(base: {
  tipo: TipoDeUso
  perfil?: string
  conversaId?: string
  tarefaId?: number
  execucaoId?: number
  modelo?: string
  retomada?: boolean
}) {
  const inicio = Date.now()
  const porMensagem = new Map<string, Usage>()
  let atual: string | undefined
  let sessionId: string | undefined
  let custoAcumuladoUSD: number | undefined

  // As contagens de uma resposta só crescem ao longo do stream; a saída final só vem no
  // message_delta, que não traz id e pertence à última mensagem iniciada.
  function somar(id: string | undefined, usage: Usage | undefined): void {
    if (!id || !usage) return
    const anterior = porMensagem.get(id) ?? {}
    const maior = (campo: keyof Usage) => Math.max(anterior[campo] ?? 0, usage[campo] ?? 0)
    porMensagem.set(id, {
      input_tokens: maior("input_tokens"),
      output_tokens: maior("output_tokens"),
      cache_creation_input_tokens: maior("cache_creation_input_tokens"),
      cache_read_input_tokens: maior("cache_read_input_tokens"),
    })
  }

  return {
    receber(msg: unknown): void {
      const m = msg as {
        type?: string
        session_id?: string
        total_cost_usd?: number
        message?: { id?: string; usage?: Usage }
        event?: { type?: string; message?: { id?: string; usage?: Usage }; usage?: Usage }
      }
      if (m.session_id) sessionId = m.session_id
      if (m.type === "assistant") somar(m.message?.id, m.message?.usage)
      if (m.type === "stream_event" && m.event?.type === "message_start") {
        atual = m.event.message?.id
        somar(atual, m.event.message?.usage)
      }
      if (m.type === "stream_event" && m.event?.type === "message_delta") somar(atual, m.event.usage)
      if (m.type === "result" && typeof m.total_cost_usd === "number") custoAcumuladoUSD = m.total_cost_usd
    },

    registro(): RegistroDeUso {
      const soma = (campo: keyof Usage) => [...porMensagem.values()].reduce((t, u) => t + (u[campo] ?? 0), 0)
      return {
        ts: new Date().toISOString(),
        tipo: base.tipo,
        perfil: base.perfil,
        conversaId: base.conversaId,
        tarefaId: base.tarefaId,
        execucaoId: base.execucaoId,
        sessionId,
        modelo: base.modelo,
        chamadas: porMensagem.size,
        entrada: soma("input_tokens"),
        escritaCache: soma("cache_creation_input_tokens"),
        leituraCache: soma("cache_read_input_tokens"),
        saida: soma("output_tokens"),
        custoAcumuladoUSD,
        retomada: base.retomada === true,
        duracaoMs: Date.now() - inicio,
      }
    },
  }
}

export async function* comUso<T>(
  raiz: string,
  base: Parameters<typeof coletorDeUso>[0],
  fluxo: AsyncIterable<T>,
  aoRegistrar?: (registro: RegistroDeUso) => void,
): AsyncGenerator<T> {
  const coletor = coletorDeUso(base)
  try {
    for await (const msg of fluxo) {
      coletor.receber(msg)
      yield msg
    }
  } finally {
    const registro = coletor.registro()
    aoRegistrar?.(registro)
    await gravarUso(raiz, registro)
  }
}

export function custosPorConsulta(registros: RegistroDeUso[]): (number | undefined)[] {
  const ultimoDaSessao = new Map<string, number>()
  const ordem = registros.map((r, i) => ({ r, i })).sort((a, b) => a.r.ts.localeCompare(b.r.ts))
  const custos: (number | undefined)[] = new Array(registros.length).fill(undefined)
  for (const { r, i } of ordem) {
    if (r.custoAcumuladoUSD === undefined) continue
    const anterior = r.sessionId ? ultimoDaSessao.get(r.sessionId) : undefined
    if (anterior !== undefined) custos[i] = Math.max(0, r.custoAcumuladoUSD - anterior)
    else if (!r.retomada) custos[i] = r.custoAcumuladoUSD
    if (r.sessionId) ultimoDaSessao.set(r.sessionId, r.custoAcumuladoUSD)
  }
  return custos
}

export interface Agregado {
  consultas: number
  custoUSD: number
  semCusto: number
  entrada: number
  escritaCache: number
  leituraCache: number
  saida: number
  acertoCache: number
}

export function agregarUso(registros: RegistroDeUso[], chave: (r: RegistroDeUso) => string): Map<string, Agregado> {
  const custos = custosPorConsulta(registros)
  const grupos = new Map<string, Agregado>()
  registros.forEach((r, i) => {
    const g = grupos.get(chave(r)) ?? {
      consultas: 0, custoUSD: 0, semCusto: 0, entrada: 0, escritaCache: 0, leituraCache: 0, saida: 0, acertoCache: 0,
    }
    g.consultas++
    if (custos[i] === undefined) g.semCusto++
    else g.custoUSD += custos[i]!
    g.entrada += r.entrada
    g.escritaCache += r.escritaCache
    g.leituraCache += r.leituraCache
    g.saida += r.saida
    const lido = g.entrada + g.escritaCache + g.leituraCache
    g.acertoCache = lido ? g.leituraCache / lido : 0
    grupos.set(chave(r), g)
  })
  return grupos
}

export function caminhoDoUso(raiz: string): string {
  return join(raiz, "conversations", "uso.jsonl")
}

export async function gravarUso(raiz: string, registro: RegistroDeUso): Promise<void> {
  try {
    await mkdir(join(raiz, "conversations"), { recursive: true })
    await appendFile(caminhoDoUso(raiz), JSON.stringify(registro) + "\n")
  } catch (erro) {
    console.warn(`[uso] registro não gravado — ${(erro as Error).message}`)
  }
}
