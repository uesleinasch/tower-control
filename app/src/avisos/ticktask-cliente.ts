import { Client } from "@modelcontextprotocol/sdk/client/index.js"
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js"
import { enderecoTickTask } from "../ticktask"

export class TickTaskFechado extends Error {
  constructor() {
    super("O TickTask está fechado: abra o app e tente de novo.")
  }
}

export type ChamarTickTask = (ferramenta: string, argumentos: Record<string, unknown>) => Promise<unknown>

export const chamarTickTask: ChamarTickTask = async (ferramenta, argumentos) => {
  const endereco = await enderecoTickTask()
  if (!endereco) throw new TickTaskFechado()
  const cliente = new Client({ name: "control-tower-avisos", version: "1.0.0" })
  const transporte = new StreamableHTTPClientTransport(new URL(endereco.url), {
    requestInit: { headers: { authorization: `Bearer ${endereco.token}` } },
  })
  try {
    await cliente.connect(transporte)
  } catch {
    throw new TickTaskFechado()
  }
  try {
    const resultado = await cliente.callTool({ name: ferramenta, arguments: argumentos })
    const texto = ((resultado.content ?? []) as { type: string; text?: string }[])
      .filter((parte) => parte.type === "text")
      .map((parte) => parte.text ?? "")
      .join("")
    if (resultado.isError) throw new Error(`o TickTask recusou ${ferramenta}: ${texto}`)
    return JSON.parse(texto) as unknown
  } finally {
    await cliente.close().catch(() => {})
  }
}
