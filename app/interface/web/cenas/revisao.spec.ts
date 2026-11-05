import { expect, test } from "@playwright/test"
import { join } from "node:path"
import {
  ambiente,
  conferirSemRegra,
  criarTarefa,
  esperarArquivo,
  esperarStatus,
  mudarPosicao,
  pedidos,
  roteiro,
  subirCena,
  turnos,
  ws,
  type Conexao,
  type Regra,
} from "../apoio"

let descer: (() => Promise<void>) | undefined
let conexao: Conexao

test.beforeAll(async () => {
  descer = await subirCena()
  conexao = await ws()
})

test.afterAll(async () => {
  conexao?.fechar()
  await descer?.()
})

test.afterEach(async () => {
  await conferirSemRegra()
})

const fimDaDecisao = (nome: string, cabecalho: string, ferramenta: string): Regra => ({
  nome,
  quando: { sistema: cabecalho, resultadoDe: ferramenta },
  responde: [{ texto: "decidido" }],
  fundo: true,
})

test("cena 6: mudança volta à executora e a nova entrega volta à mesma revisora", async ({ page }) => {
  await roteiro("revisao", [
    fimDaDecisao("poe-encerra", "# Poe", "mcp__orquestra__aprovar"),
    fimDaDecisao("nati-encerra-aprovando", "# Nati", "mcp__orquestra__aprovar"),
    fimDaDecisao("nati-encerra-pedindo", "# Nati", "mcp__orquestra__pedir_mudanca"),
    { nome: "alfred-refaz", quando: { sistema: "# Alfred", mensagem: "pediu mudança: falta o teste" }, responde: [{ texto: "entrega 2 com o teste" }] },
    { nome: "alfred-entrega", quando: { sistema: "# Alfred", mensagem: ": escrever o relatório" }, responde: [{ texto: "entrega 1" }] },
    {
      nome: "poe-aprova",
      quando: { sistema: "# Poe", mensagem: "revisando a entrega" },
      responde: [{ ferramenta: "mcp__orquestra__aprovar", entrada: { parecer: "o texto está claro" } }],
      vezes: 2,
    },
    {
      nome: "nati-pede-mudanca",
      quando: { sistema: "# Nati", mensagem: "revisando a entrega" },
      responde: [{ ferramenta: "mcp__orquestra__pedir_mudanca", entrada: { o_que_mudar: "falta o teste" } }],
    },
    {
      nome: "nati-aprova",
      quando: { sistema: "# Nati", mensagem: "revisando a entrega" },
      responde: [{ ferramenta: "mcp__orquestra__aprovar", entrada: { parecer: "agora tem o teste" } }],
    },
  ])
  await mudarPosicao(conexao, "executor", (p) => {
    p.politica = [
      { tipo: "revisao", por: { posicao: "conselho-poe" } },
      { tipo: "revisao", por: { posicao: "conselho-nati" } },
    ]
  })
  await page.goto(ambiente().servidor)
  await page.locator("#botao-tarefas").click()
  const tarefa = await criarTarefa(conexao, "escrever o relatório")
  await page.locator("#mensagens li", { hasText: "escrever o relatório" }).click()

  await expect(page.locator("#mensagens .msg.mudanca")).toContainText("falta o teste")
  await expect(page.locator("#mensagens .msg.entrega").last()).toContainText("entrega 2 com o teste")
  await expect(page.locator("#mensagens .msg.documento")).toContainText("Status: concluída")
  await expect(page.locator("#mensagens .msg.aprovado")).toHaveCount(2)

  const detalhe = await esperarStatus(conexao, tarefa.id, "concluida")
  const decisoes = detalhe.registros
    .filter((r: any) => ["entrega", "aprovado", "mudanca"].includes(r.tipo))
    .map((r: any) => `${r.autor}:${r.tipo}`)
  expect(decisoes).toEqual(["alfred:entrega", "poe:aprovado", "nati:mudanca", "alfred:entrega", "nati:aprovado"])

  const lista = await pedidos("revisao")
  expect(turnos(lista, "# Nati")).toHaveLength(2)
  expect(turnos(lista, "# Poe")).toHaveLength(1)
  expect(turnos(lista, "# Alfred")).toHaveLength(2)

  await mudarPosicao(conexao, "executor", (p) => {
    delete p.politica
  })
})

test("cena 6: board como revisão decide pela síntese", async ({ page }) => {
  const parecer = (nome: string): Regra => ({
    nome: `parecer-${nome}`,
    quando: { sistema: `# ${nome}`, mensagem: "Emita seu parecer" },
    responde: [{ texto: `${nome}: a entrega pode seguir.` }],
  })
  await roteiro("board", [
    { nome: "alfred-entrega", quando: { sistema: "# Alfred", mensagem: ": organizar as fotos" }, responde: [{ texto: "fotos organizadas" }] },
    parecer("Lucas"),
    parecer("Nati"),
    parecer("Pami"),
    parecer("Poe"),
    {
      nome: "sintese",
      quando: { sistema: "Você é o moderador neutro", mensagem: "Produza a síntese" },
      responde: [{ texto: "## Síntese do board\n\nConsenso: a entrega segue.\n\nDECISÃO: aprovar" }],
    },
  ])
  await mudarPosicao(conexao, "executor", (p) => {
    p.politica = [{ tipo: "revisao", por: { board: true } }]
  })
  await page.goto(ambiente().servidor)
  await page.locator("#botao-tarefas").click()
  const tarefa = await criarTarefa(conexao, "organizar as fotos")
  await page.locator("#mensagens li", { hasText: "organizar as fotos" }).click()

  await expect(page.locator("#mensagens .msg.aprovado")).toContainText("DECISÃO: aprovar")
  await expect(page.locator("#mensagens .msg.documento")).toContainText("Status: concluída")

  const detalhe = await esperarStatus(conexao, tarefa.id, "concluida")
  const aprovacao = detalhe.registros.find((r: any) => r.tipo === "aprovado")
  expect(aprovacao.autor).toBe("board")
  const ata = aprovacao.texto.match(/Ata: (board\/minutes\/\S+\.md)/)?.[1]
  expect(ata).toBeTruthy()
  await esperarArquivo(join(ambiente().dados, ata), "DECISÃO: aprovar")

  const lista = await pedidos("board")
  for (const nome of ["Lucas", "Nati", "Pami", "Poe"]) expect(turnos(lista, `# ${nome}`)).toHaveLength(1)
  expect(lista.filter((p) => p.ultimaMensagem.includes("Produza a síntese"))).toHaveLength(1)

  await mudarPosicao(conexao, "executor", (p) => {
    delete p.politica
  })
})
