import { createSdkMcpServer, tool } from "@anthropic-ai/claude-agent-sdk"
import { z } from "zod"
import type { PedidoDeLembrete } from "./lembretes"

export const FERRAMENTA_LEMBRETE = "mcp__lembretes__agendar_lembrete"

const DESCRICAO = `Agenda um lembrete que chega como notificação no celular e no desktop do Ueslei, criado
como tarefa no TickTask. Use quando ele pedir para ser lembrado de algo.
Passe data (AAAA-MM-DD) e hora (HH:MM) no horário local, resolvendo expressões como
"amanhã às 9h" a partir da data de hoje. Para pedidos relativos, como "daqui a 40 minutos",
passe em_minutos no lugar de data e hora. Se a resposta disser que não agendou, conte isso
ao Ueslei em vez de dizer que agendou.`

export function servidorDeLembretes(agendar: (pedido: PedidoDeLembrete) => Promise<string>) {
  return createSdkMcpServer({
    name: "lembretes",
    version: "1.0.0",
    tools: [
      tool(
        "agendar_lembrete",
        DESCRICAO,
        {
          titulo: z.string().min(1),
          data: z.string().optional(),
          hora: z.string().optional(),
          em_minutos: z.number().int().optional(),
        },
        async (args) => ({ content: [{ type: "text" as const, text: await agendar(args) }] }),
      ),
    ],
  })
}
