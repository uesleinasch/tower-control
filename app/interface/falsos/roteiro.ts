export type Bloco = { texto: string } | { ferramenta: string; entrada: Record<string, unknown> }

export interface Regra {
  nome: string
  quando: { sistema?: string; mensagem?: string; resultadoDe?: string; temFerramenta?: string }
  responde: Bloco[]
  vezes?: number
  fundo?: boolean
}

export interface PedidoRecebido {
  em: string
  modelo: string
  sistema: string
  ultimaMensagem: string
  resultadoDe: string | null
  ferramentas: string[]
  corpo: unknown
}

type Dicionario = Record<string, unknown>

function textoDe(conteudo: unknown): string {
  if (typeof conteudo === "string") return conteudo
  if (!Array.isArray(conteudo)) return ""
  return conteudo
    .filter((b): b is Dicionario => !!b && typeof b === "object" && (b as Dicionario).type === "text")
    .map((b) => String(b.text ?? ""))
    .join("\n")
}

function blocosDe(conteudo: unknown): Dicionario[] {
  return Array.isArray(conteudo) ? conteudo.filter((b): b is Dicionario => !!b && typeof b === "object") : []
}

export function lerPedido(corpo: unknown): PedidoRecebido {
  const c = (corpo && typeof corpo === "object" ? corpo : {}) as Dicionario
  const mensagens = (Array.isArray(c.messages) ? c.messages : []) as Dicionario[]
  const doUsuario = mensagens.filter((m) => m.role === "user")

  let ultimaMensagem = ""
  for (let i = doUsuario.length - 1; i >= 0 && !ultimaMensagem; i--) {
    ultimaMensagem = textoDe(doUsuario[i].content)
  }

  let resultadoDe: string | null = null
  const ultima = mensagens.findLast((m) => m.role !== "system")
  if (ultima?.role === "user") {
    const resultados = blocosDe(ultima.content).filter((b) => b.type === "tool_result")
    const id = resultados[resultados.length - 1]?.tool_use_id
    if (id !== undefined) {
      for (const m of mensagens) {
        const uso = blocosDe(m.content).find((b) => b.type === "tool_use" && b.id === id)
        if (uso) resultadoDe = String(uso.name ?? "")
      }
    }
  }

  const ferramentas = (Array.isArray(c.tools) ? c.tools : [])
    .map((f) => String((f as Dicionario)?.name ?? ""))
    .filter(Boolean)

  return {
    em: new Date().toISOString(),
    modelo: typeof c.model === "string" ? c.model : "",
    sistema: textoDe(c.system),
    ultimaMensagem,
    resultadoDe,
    ferramentas,
    corpo,
  }
}

function bate(regra: Regra, pedido: PedidoRecebido): boolean {
  const q = regra.quando
  if (q.sistema !== undefined && !pedido.sistema.includes(q.sistema)) return false
  if (q.mensagem !== undefined && !pedido.ultimaMensagem.includes(q.mensagem)) return false
  if (q.resultadoDe !== undefined && !(pedido.resultadoDe ?? "").includes(q.resultadoDe)) return false
  if (q.temFerramenta !== undefined && !pedido.ferramentas.some((f) => f.includes(q.temFerramenta!))) return false
  return true
}

export function casar(regras: Regra[], usadas: Map<string, number>, pedido: PedidoRecebido): Regra | null {
  for (const regra of regras) {
    const usos = usadas.get(regra.nome) ?? 0
    if (!regra.fundo && usos >= (regra.vezes ?? 1)) continue
    if (!bate(regra, pedido)) continue
    usadas.set(regra.nome, usos + 1)
    return regra
  }
  return null
}

let contadorDeFerramentas = 0

function evento(tipo: string, dados: unknown): string {
  return `event: ${tipo}\ndata: ${JSON.stringify(dados)}\n\n`
}

export function sseDaResposta(blocos: Bloco[], modelo: string): string {
  const temFerramenta = blocos.some((b) => "ferramenta" in b)
  let saida = evento("message_start", {
    type: "message_start",
    message: {
      id: `msg_falso_${++contadorDeFerramentas}`,
      type: "message",
      role: "assistant",
      model: modelo,
      content: [],
      stop_reason: null,
      stop_sequence: null,
      usage: { input_tokens: 10, output_tokens: 1 },
    },
  })
  blocos.forEach((bloco, index) => {
    if ("ferramenta" in bloco) {
      saida += evento("content_block_start", {
        type: "content_block_start",
        index,
        content_block: { type: "tool_use", id: `toolu_falso_${++contadorDeFerramentas}`, name: bloco.ferramenta, input: {} },
      })
      saida += evento("content_block_delta", {
        type: "content_block_delta",
        index,
        delta: { type: "input_json_delta", partial_json: JSON.stringify(bloco.entrada) },
      })
    } else {
      saida += evento("content_block_start", {
        type: "content_block_start",
        index,
        content_block: { type: "text", text: "" },
      })
      saida += evento("content_block_delta", {
        type: "content_block_delta",
        index,
        delta: { type: "text_delta", text: bloco.texto },
      })
    }
    saida += evento("content_block_stop", { type: "content_block_stop", index })
  })
  saida += evento("message_delta", {
    type: "message_delta",
    delta: { stop_reason: temFerramenta ? "tool_use" : "end_turn", stop_sequence: null },
    usage: { output_tokens: 5 },
  })
  saida += evento("message_stop", { type: "message_stop" })
  return saida
}

export function respostaJson(blocos: Bloco[], modelo: string): Record<string, unknown> {
  const temFerramenta = blocos.some((b) => "ferramenta" in b)
  return {
    id: `msg_falso_${++contadorDeFerramentas}`,
    type: "message",
    role: "assistant",
    model: modelo,
    content: blocos.map((b) =>
      "ferramenta" in b
        ? { type: "tool_use", id: `toolu_falso_${++contadorDeFerramentas}`, name: b.ferramenta, input: b.entrada }
        : { type: "text", text: b.texto },
    ),
    stop_reason: temFerramenta ? "tool_use" : "end_turn",
    stop_sequence: null,
    usage: { input_tokens: 10, output_tokens: 5 },
  }
}
