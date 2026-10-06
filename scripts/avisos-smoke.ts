// Smoke da central de avisos contra um servidor de verdade:
//   bun run ../scripts/avisos-smoke.ts [http://127.0.0.1:7878] [--fechar-chat]
// Pede ao Alfred um comando, aprova pelo aviso (não pelo chat), confere o 409 da segunda
// ação, o aviso de resposta e o "lido" quando a conversa fica visível. Gasta uma consulta.
// Com --fechar-chat o socket do chat cai antes da aprovação, como no celular com a tela
// bloqueada: o comando tem de esperar o aviso em vez de ser negado.

const base = process.argv.slice(2).find((a) => a.startsWith("http")) ?? "http://127.0.0.1:7878"
const fecharChat = process.argv.includes("--fechar-chat")
const PRAZO_MS = 180_000

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

function ok(texto: string): void {
  console.log(`✓ ${texto}`)
}

void escutar().catch((erro: Error) => {
  console.error(`stream caiu: ${erro.message}`)
  process.exit(1)
})

async function abrirSocket(): Promise<WebSocket> {
  const socket = new WebSocket(`${base.replace(/^http/, "ws")}/ws`)
  await new Promise((resolver) => socket.addEventListener("open", resolver, { once: true }))
  return socket
}

let ws = await abrirSocket()
const criada = new Promise<string>((resolver) =>
  ws.addEventListener("message", (ev) => {
    const msg = JSON.parse(String(ev.data))
    if (msg.tipo === "criada") resolver(msg.meta.id)
    if (msg.tipo === "erro") console.error(`erro do servidor: ${msg.mensagem}`)
  }),
)
ws.send(
  JSON.stringify({
    tipo: "nova",
    perfil: "alfred",
    texto: "Rode exatamente o comando `date +%Y` uma vez e me diga só o resultado.",
  }),
)
const conversaId = await criada
ok(`conversa criada: ${conversaId}`)

const aprovacao = await esperar("aviso de aprovação", (l) => l.tipo === "aprovacao" && l.alvo?.conversaId === conversaId)
ok(`aviso de aprovação #${aprovacao.seq}: ${aprovacao.corpo}`)

if (fecharChat) {
  ws.close()
  await Bun.sleep(1_500)
  if (recebidas.some((l) => l.tipo === "resolvido" && l.id === aprovacao.id)) {
    throw new Error("fechar o chat resolveu a aprovação mesmo com o stream escutando")
  }
  ok("chat fechado e a aprovação continua aberta")
  ws = await abrirSocket()
}

const acao = (corpo: Record<string, unknown>) =>
  fetch(`${base}/avisos/${aprovacao.id}/acao`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(corpo),
  })

const primeira = await acao({ acao: "aprovar", aparelho: "smoke" })
if (primeira.status !== 200) throw new Error(`aprovar devolveu ${primeira.status}: ${await primeira.text()}`)
ok("aprovado pelo aviso (200)")

const resolvido = await esperar("evento resolvido", (l) => l.tipo === "resolvido" && l.id === aprovacao.id)
if (resolvido.como !== "aprovado" || resolvido.aparelho !== "smoke") throw new Error(`resolvido inesperado: ${JSON.stringify(resolvido)}`)
ok("evento resolvido com aparelho")

const segunda = await acao({ acao: "negar", aparelho: "outro" })
const corpoSegunda = await segunda.json()
if (segunda.status !== 409 || corpoSegunda.aparelho !== "smoke") throw new Error(`segunda ação: ${segunda.status} ${JSON.stringify(corpoSegunda)}`)
ok("segunda ação recusada (409) dizendo quem resolveu")

const resposta = await esperar("aviso de resposta", (l) => l.tipo === "resposta" && l.alvo?.conversaId === conversaId)
ok(`aviso de resposta #${resposta.seq}: ${resposta.corpo}`)

ws.send(JSON.stringify({ tipo: "visivel", conversaId }))
await esperar("resposta lida", (l) => l.tipo === "resolvido" && l.id === resposta.id && l.como === "lido")
ok("abrir a conversa marca a resposta como lida")

console.log("smoke dos avisos passou")
process.exit(0)
