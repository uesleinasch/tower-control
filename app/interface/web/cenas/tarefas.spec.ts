import { expect, test } from "@playwright/test"
import {
  ambiente,
  conferirSemRegra,
  esperarStatus,
  pedidos,
  roteiro,
  subirCena,
  turnos,
  ws,
  type Conexao,
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

test("cena 4: tarefa criada na web volta em revisão com a entrega, e o comentário devolve", async ({ page }) => {
  const titulo = "conferir o backup da semana"
  await roteiro("tarefa", [
    { nome: "alfred-refaz", quando: { sistema: "# Alfred", mensagem: "Ueslei comentou: refaça" }, responde: [{ texto: "entrega 2" }] },
    { nome: "alfred-entrega", quando: { sistema: "# Alfred", mensagem: `## Tarefa #1: ${titulo}` }, responde: [{ texto: "entrega 1" }] },
  ])
  await page.goto(ambiente().servidor)
  await page.locator("#botao-tarefas").click()
  const form = page.locator("form.nova-tarefa")
  await form.locator('select[name="posicao"]').selectOption("executor")
  await form.locator('input[name="titulo"]').fill(titulo)
  await form.locator('button[type="submit"]').click()

  await page.locator("#mensagens li", { hasText: titulo }).click()
  const documento = page.locator("#mensagens .msg.documento")
  await expect(documento).toContainText("Status: em revisão")
  await expect(page.locator("#mensagens .msg.entrega")).toHaveCount(1)
  await expect(page.locator("#mensagens .msg.entrega").last()).toContainText("entrega 1")
  const primeira = await esperarStatus(conexao, 1, "em_revisao")
  expect(primeira.registros.filter((r: any) => r.tipo === "entrega").map((r: any) => r.texto)).toEqual(["entrega 1"])

  await page.locator("#entrada").fill("refaça")
  await page.locator("#entrada").press("Enter")
  await expect(page.locator("#mensagens .msg.entrega")).toHaveCount(2)
  await expect(page.locator("#mensagens .msg.entrega").last()).toContainText("entrega 2")
  await expect(documento).toContainText("Status: em revisão")
  const segunda = await esperarStatus(conexao, 1, "em_revisao")
  expect(segunda.registros.filter((r: any) => r.tipo === "entrega").map((r: any) => r.texto)).toEqual(["entrega 1", "entrega 2"])

  const doAlfred = turnos(await pedidos("tarefa"), "# Alfred")
  expect(doAlfred).toHaveLength(2)
  const bloco = doAlfred[1]!.ultimaMensagem.match(/<tarefa>[\s\S]*<\/tarefa>/)?.[0] ?? ""
  expect(bloco).toContain("refaça")
})
