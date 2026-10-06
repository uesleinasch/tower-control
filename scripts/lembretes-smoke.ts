// Smoke dos lembretes contra o servidor e o TickTask de verdade (o app do TickTask aberto):
//   bun run ../scripts/lembretes-smoke.ts [http://127.0.0.1:7878]
// Pede ao Alfred um lembrete pela agendar_lembrete e cria outro direto no TickTask, espera os
// dois avisos, adia o primeiro e conclui o segundo pelo aviso, confere no TickTask e finaliza
// as duas tarefas no fim. Gasta uma consulta.

import { chamarTickTask } from "../app/src/avisos/ticktask-cliente"
import { dataLocal } from "../app/src/texto"
import { horaLocal } from "../app/src/avisos/lembretes"

const base = process.argv[2] ?? "http://127.0.0.1:7878"
const PRAZO_MS = 5 * 60_000
const MARCA = "[teste avisos]"

type Linha = Record<string, any>
const recebidas: Linha[] = []
const esperas: { teste: (l: Linha) => boolean; resolver: (l: Linha) => void }[] = []

function esperar(descricao: string, teste: (l: Linha) => boolean): Promise<Linha> {
  const ja = recebidas.find(teste)
  if (ja) return Promise.resolve(ja)
  return new Promise((resolver, rejeitar) => {
    const prazo = setTimeout(() => rejeitar(new Error(`não chegou: ${descricao}`)), PRAZO_MS)
    esperas.push({ teste, resolver: (l) => (clearTimeout(prazo), resolver(l)) })
  })
}

async function escutar(): Promise<void> {
  const resposta = await fetch(`${base}/avisos?desde=0`)
  if (!resposta.ok || !resposta.body) throw new Error(`/avisos devolveu ${resposta.status}`)
  const decodificador = new TextDecoder()
  let resto = ""
  for await (const pedaco of resposta.body) {
    resto += decodificador.decode(pedaco, { stream: true })
    const linhas = resto.split("\n")
    resto = linhas.pop()!
    for (const bruta of linhas) {
      if (!bruta.trim()) continue
      const linha = JSON.parse(bruta) as Linha
      recebidas.push(linha)
      for (const espera of [...esperas]) {
        if (espera.teste(linha)) {
          esperas.splice(esperas.indexOf(espera), 1)
          espera.resolver(linha)
        }
      }
    }
  }
}

const ok = (texto: string) => console.log(`✓ ${texto}`)
const tarefa = async (id: number) => ((await chamarTickTask("get_task", { id })) as { task: Record<string, any> }).task

// O delete_tasks do TickTask recusa o próprio confirm_token (invalid_token), então as tarefas
// de teste ficam finalizadas para não dispararem, e a remoção é manual.
async function finalizar(ids: number[]): Promise<void> {
  for (const id of ids) await chamarTickTask("update_task", { id, status: "finalizada" })
}

async function acao(id: string, corpo: Record<string, unknown>): Promise<Response> {
  return fetch(`${base}/avisos/${id}/acao`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(corpo),
  })
}

void escutar().catch((erro: Error) => {
  console.error(`stream caiu: ${erro.message}`)
  process.exit(1)
})

const criadas: number[] = []
try {
  const ws = new WebSocket(`${base.replace(/^http/, "ws")}/ws`)
  await new Promise((resolver) => ws.addEventListener("open", resolver, { once: true }))
  const respondeu = new Promise<string>((resolver) => {
    let texto = ""
    ws.addEventListener("message", (ev) => {
      const msg = JSON.parse(String(ev.data))
      if (msg.tipo === "chunk") texto += msg.texto
      if (msg.tipo === "fim") resolver(texto)
      if (msg.tipo === "erro") resolver(`erro: ${msg.mensagem}`)
    })
  })
  ws.send(
    JSON.stringify({
      tipo: "nova",
      perfil: "alfred",
      texto: `Me lembra de "${MARCA} beber água" daqui a 1 minuto.`,
    }),
  )
  console.log(`  Alfred: ${(await respondeu).trim()}`)

  const viaAlfred = await esperar("lembrete pedido ao Alfred", (l) => l.tipo === "lembrete" && l.titulo?.includes(MARCA))
  criadas.push(viaAlfred.alvo.tarefaId)
  ok(`aviso do lembrete pedido em conversa: tarefa #${viaAlfred.alvo.tarefaId}, ${viaAlfred.corpo}`)
  const etiquetas = ((await tarefa(viaAlfred.alvo.tarefaId)).tags as { name: string }[]).map((t) => t.name)
  if (!etiquetas.includes("lembrete")) throw new Error(`tarefa sem a etiqueta lembrete: ${etiquetas}`)
  ok("tarefa criada com a etiqueta lembrete")

  const adiada = await acao(viaAlfred.id, { acao: "adiar", adiarPara: "1h", aparelho: "smoke" })
  if (adiada.status !== 200) throw new Error(`adiar devolveu ${adiada.status}: ${await adiada.text()}`)
  const depois = await tarefa(viaAlfred.alvo.tarefaId)
  const esperado = horaLocal(new Date(Date.now() + 60 * 60_000))
  ok(`adiada pelo aviso: agora ${depois.scheduled_date} ${depois.scheduled_time} (esperado perto de ${esperado})`)

  const daqui = new Date(Date.now() + 60_000)
  const direta = (await chamarTickTask("create_task", {
    name: `${MARCA} direto`,
    scheduled_date: dataLocal(daqui),
    scheduled_time: horaLocal(daqui),
    tags: ["lembrete"],
  })) as { task?: { id: number }; id?: number }
  const idDireto = direta.task?.id ?? direta.id!
  criadas.push(idDireto)
  const aviso = await esperar("lembrete criado direto", (l) => l.tipo === "lembrete" && l.alvo?.tarefaId === idDireto)
  ok(`aviso do lembrete criado direto no TickTask: ${aviso.corpo}`)

  const concluida = await acao(aviso.id, { acao: "concluir", aparelho: "smoke" })
  if (concluida.status !== 200) throw new Error(`concluir devolveu ${concluida.status}: ${await concluida.text()}`)
  const status = (await tarefa(idDireto)).status
  if (status !== "finalizada") throw new Error(`tarefa ficou ${status}`)
  ok("concluída pelo aviso e finalizada no TickTask")

  const repetida = await acao(aviso.id, { acao: "concluir" })
  if (repetida.status !== 409) throw new Error(`segunda ação devolveu ${repetida.status}`)
  ok("segunda ação recusada (409)")
  console.log("smoke dos lembretes passou")
} finally {
  await finalizar(criadas).catch((erro: Error) => console.error(`não finalizei ${criadas}: ${erro.message}`))
  if (criadas.length) console.log(`  tarefas de teste finalizadas (apague à mão no TickTask): ${criadas.join(", ")}`)
  process.exit(0)
}
