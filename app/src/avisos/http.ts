import { linhaNdjson, type Acao, type Aviso, type CentralDeAvisos, type Como, type Linha } from "./central"

export const KEEP_ALIVE_MS = 25_000
const ADIAMENTOS = ["1h", "amanha"] as const
export type Adiamento = (typeof ADIAMENTOS)[number]

export interface PedidoDeAcao {
  acao: Acao
  texto?: string
  adiarPara?: Adiamento
  aparelho?: string
}

export type Executor = (aviso: Aviso, pedido: PedidoDeAcao) => Promise<Como>

export class AvisoVencido extends Error {}

export interface Dependencias {
  soltarPermissao: (id: string, permitido: boolean) => boolean
  responder: (conversaId: string, texto: string) => void
  concluir?: (aviso: Aviso) => Promise<void>
  adiar?: (aviso: Aviso, para: Adiamento) => Promise<void>
}

export function executorDeAvisos(deps: Dependencias): Executor {
  return async (aviso, pedido) => {
    if (pedido.acao === "aprovar" || pedido.acao === "negar") {
      const permitido = pedido.acao === "aprovar"
      if (!deps.soltarPermissao(aviso.id, permitido)) throw new AvisoVencido()
      return permitido ? "aprovado" : "negado"
    }
    if (pedido.acao === "responder") {
      const conversaId = aviso.alvo.conversaId
      if (!conversaId) throw new Error("aviso sem conversa")
      deps.responder(conversaId, pedido.texto!)
      return "respondido"
    }
    if (pedido.acao === "concluir" && deps.concluir) {
      await deps.concluir(aviso)
      return "concluida"
    }
    if (pedido.acao === "adiar" && deps.adiar) {
      await deps.adiar(aviso, pedido.adiarPara!)
      return "adiada"
    }
    throw new Error(`a ação "${pedido.acao}" não está disponível`)
  }
}

export function lerDesde(bruto: string | null): number {
  const n = Number(bruto)
  return Number.isInteger(n) && n > 0 ? n : 0
}

export function lerPedido(corpo: unknown, aviso: Aviso): PedidoDeAcao | { erro: string } {
  if (!corpo || typeof corpo !== "object") return { erro: "corpo inválido" }
  const { acao, texto, adiarPara, aparelho } = corpo as Record<string, unknown>
  if (typeof acao !== "string" || !aviso.acoes.includes(acao as Acao)) {
    return { erro: `ação "${String(acao)}" não vale para este aviso` }
  }
  const pedido: PedidoDeAcao = { acao: acao as Acao }
  if (typeof aparelho === "string" && aparelho.trim()) pedido.aparelho = aparelho.trim().slice(0, 40)
  if (acao === "responder") {
    if (typeof texto !== "string" || !texto.trim()) return { erro: "resposta vazia" }
    pedido.texto = texto.trim()
  }
  if (acao === "adiar") {
    if (!ADIAMENTOS.includes(adiarPara as Adiamento)) return { erro: 'adiarPara deve ser "1h" ou "amanha"' }
    pedido.adiarPara = adiarPara as Adiamento
  }
  return pedido
}

function jaResolvido(central: CentralDeAvisos, id: string): Response | undefined {
  const resolucao = central.resolucao(id)
  if (!resolucao) return undefined
  return Response.json(
    { erro: "aviso já resolvido", como: resolucao.como, aparelho: resolucao.aparelho },
    { status: 409 },
  )
}

export async function tratarAcao(
  central: CentralDeAvisos,
  id: string,
  corpo: unknown,
  executar: Executor,
): Promise<Response> {
  const aviso = central.obter(id)
  if (!aviso) return Response.json({ erro: "aviso não encontrado" }, { status: 404 })
  const recusa = jaResolvido(central, id)
  if (recusa) return recusa
  const pedido = lerPedido(corpo, aviso)
  if ("erro" in pedido) return Response.json(pedido, { status: 400 })

  let como: Como
  try {
    como = await executar(aviso, pedido)
  } catch (erro) {
    if (erro instanceof AvisoVencido) {
      await central.resolver(id, "expirado")
      return jaResolvido(central, id)!
    }
    return Response.json({ erro: (erro as Error).message }, { status: 503 })
  }
  const resultado = await central.resolver(id, como, pedido.aparelho)
  if ("recusado" in resultado) return jaResolvido(central, id)!
  return Response.json({ ok: true, como, resolucao: resultado })
}

export function streamDeAvisos(
  central: CentralDeAvisos,
  desde: number,
  sinal?: AbortSignal,
  keepAliveMs = KEEP_ALIVE_MS,
): Response {
  const codificador = new TextEncoder()
  let encerrar = () => {}
  const corpo = new ReadableStream<Uint8Array>({
    start(controle) {
      const enviar = (linha: Linha | Record<string, never>) => {
        try {
          controle.enqueue(codificador.encode(linhaNdjson(linha)))
        } catch {
          encerrar()
        }
      }
      // O Bun só manda os headers com o primeiro dado; sem backlog, o cliente esperaria o
      // primeiro keep-alive para saber que conectou.
      enviar({})
      for (const linha of central.desde(desde)) enviar(linha)
      const sair = central.assinar(enviar)
      const pulso = setInterval(() => enviar({}), keepAliveMs)
      let encerrado = false
      encerrar = () => {
        if (encerrado) return
        encerrado = true
        clearInterval(pulso)
        sair()
        try {
          controle.close()
        } catch {}
      }
      sinal?.addEventListener("abort", () => encerrar(), { once: true })
    },
    cancel() {
      encerrar()
    },
  })
  return new Response(corpo, {
    headers: { "content-type": "application/x-ndjson; charset=utf-8", "cache-control": "no-store" },
  })
}
