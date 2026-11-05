import { casar, lerPedido, respostaJson, sseDaResposta, type PedidoRecebido, type Regra } from "./roteiro"

const PRAZO_DO_ENCONTRO_MS = 90_000

interface Encontro {
  chegaram: Set<string>
  esperando: Array<() => void>
}

function json(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), { status, headers: { "content-type": "application/json" } })
}

export function servirModeloFalso(porta = 0): { porta: number; fechar(): void } {
  let cena = ""
  let regras: Regra[] = []
  let usadas = new Map<string, number>()
  const pedidosPorCena = new Map<string, PedidoRecebido[]>()
  const semRegra: PedidoRecebido[] = []
  const encontros = new Map<string, Encontro>()

  function registrar(pedido: PedidoRecebido) {
    const lista = pedidosPorCena.get(cena) ?? []
    lista.push(pedido)
    pedidosPorCena.set(cena, lista)
  }

  async function mensagens(req: Request): Promise<Response> {
    const corpo = await req.json().catch(() => ({}))
    const pedido = lerPedido(corpo)
    registrar(pedido)
    const regra = casar(regras, usadas, pedido)
    if (!regra) {
      semRegra.push(pedido)
      return json({ error: { type: "api_error", message: "sem regra no roteiro" } }, 500)
    }
    const transmitir = (corpo as { stream?: boolean }).stream === true
    if (!transmitir) return json(respostaJson(regra.responde, pedido.modelo))
    return new Response(sseDaResposta(regra.responde, pedido.modelo), {
      headers: { "content-type": "text/event-stream", "cache-control": "no-cache" },
    })
  }

  async function encontro(req: Request): Promise<Response> {
    const { nome, lado, lados } = (await req.json()) as { nome: string; lado: string; lados: string[] }
    let e = encontros.get(nome)
    if (!e) {
      e = { chegaram: new Set(), esperando: [] }
      encontros.set(nome, e)
    }
    e.chegaram.add(lado)
    if (lados.every((l) => e.chegaram.has(l))) {
      encontros.delete(nome)
      e.esperando.forEach((liberar) => liberar())
      return json({ ok: true })
    }
    return new Promise<Response>((resolve) => {
      const liberar = () => {
        clearTimeout(prazo)
        resolve(json({ ok: true }))
      }
      const prazo = setTimeout(() => {
        e.chegaram.delete(lado)
        e.esperando = e.esperando.filter((f) => f !== liberar)
        resolve(json({ erro: "encontro estourou o prazo" }, 408))
      }, PRAZO_DO_ENCONTRO_MS)
      e.esperando.push(liberar)
    })
  }

  const servidor = Bun.serve({
    port: porta,
    hostname: "127.0.0.1",
    idleTimeout: 255,
    async fetch(req) {
      const url = new URL(req.url)
      const { pathname } = url
      if (pathname === "/api/hello") return new Response("ok")
      if (req.method === "POST" && pathname === "/v1/messages") return mensagens(req)
      if (req.method === "POST" && pathname === "/v1/messages/count_tokens") return json({ input_tokens: 10 })
      if (req.method === "POST" && pathname === "/_controle/roteiro") {
        const corpo = (await req.json()) as { cena: string; regras: Regra[] }
        cena = corpo.cena
        regras = corpo.regras
        usadas = new Map()
        pedidosPorCena.set(cena, [])
        semRegra.length = 0
        encontros.clear()
        return json({ ok: true })
      }
      if (req.method === "GET" && pathname === "/_controle/pedidos") {
        return json(pedidosPorCena.get(url.searchParams.get("cena") ?? cena) ?? [])
      }
      if (req.method === "GET" && pathname === "/_controle/sem-regra") return json(semRegra)
      if (req.method === "POST" && pathname === "/_controle/encontro") return encontro(req)
      return new Response("não encontrado", { status: 404 })
    },
  })

  return { porta: servidor.port as number, fechar: () => void servidor.stop(true) }
}
