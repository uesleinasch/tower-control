import { expect, test } from "@playwright/test"
import {
  ambiente,
  conferirSemRegra,
  criarPelaTela,
  desfazerSemeadura,
  detalheDaTarefa,
  esperarAte,
  esperarStatus,
  mudarPosicao,
  pedidos,
  pedir,
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
  try {
    await desfazerSemeadura(conexao)
  } finally {
    await conferirSemRegra()
  }
})

const alfredDe = (m: any) => m.lista.find((p: any) => p.id === "alfred")
const daTarefa = (id: number) => `## Tarefa #${id}:`

test("cena 5: orçamento estourado segura a fila e o painel diz por quê", async ({ page }) => {
  await roteiro("orcamento", [
    { nome: "alfred-gasta", quando: { sistema: "# Alfred", mensagem: ": gastar o orçamento" }, responde: [{ texto: "gastei" }] },
  ])
  await pedir(
    conexao,
    { tipo: "persona-salvar", persona: { id: "alfred", orcamentoMensalUSD: 0.000001 } },
    "personas",
    (m) => alfredDe(m)?.orcamentoMensalUSD === 0.000001,
  )
  await page.goto(ambiente().servidor)
  const gasta = await criarPelaTela(page, conexao, "gastar o orçamento")
  await esperarStatus(conexao, gasta.id, "em_revisao")
  await esperarAte(
    async () => alfredDe(await pedir(conexao, { tipo: "personas" }, "personas")).gastoMesUSD > 0.000001,
    "o gasto do Alfred em tarefas passar do orçamento",
  )

  const segura = await criarPelaTela(page, conexao, "esperar o orçamento")
  await page.locator("#botao-painel").click()
  await expect(page.locator("#mensagens ul.lista-decisoes li", { hasText: "esperar o orçamento" })).toContainText("na fila: Alfred sem orçamento")
  await expect(page.locator(".cartao-persona", { hasText: "Alfred" })).toContainText("sem orçamento")

  const detalhe = await detalheDaTarefa(conexao, segura.id)
  expect(detalhe.tarefa.status).toBe("a_fazer")
  expect(detalhe.execucoes.map((e: any) => e.status)).toEqual(["na_fila"])
  const doAlfred = turnos(await pedidos("orcamento"), "# Alfred")
  expect(doAlfred.filter((p) => p.ultimaMensagem.includes(daTarefa(segura.id)))).toHaveLength(0)
  expect(doAlfred).toHaveLength(1)
})

test("cena 5: pausar e retomar pelo painel", async ({ page }) => {
  await roteiro("pausa", [
    { nome: "alfred-depois-da-pausa", quando: { sistema: "# Alfred", mensagem: ": esperar a pausa" }, responde: [{ texto: "rodei depois da pausa" }] },
  ])
  await page.goto(ambiente().servidor)
  await page.locator("#botao-painel").click()
  const barra = page.locator(".barra-pausa")
  await expect(barra).toContainText("Personas trabalhando normalmente.")
  const pausado = conexao.esperar("orquestra", (m) => m.pausadoTudo === true)
  await barra.getByRole("button", { name: "Pausar tudo" }).click()
  await pausado
  await expect(barra).toContainText("Tudo pausado")

  const tarefa = await criarPelaTela(page, conexao, "esperar a pausa")
  await page.locator("#botao-painel").click()
  await expect(page.locator("#mensagens ul.lista-decisoes li", { hasText: "esperar a pausa" })).toContainText("na fila: tudo pausado")
  const parada = await detalheDaTarefa(conexao, tarefa.id)
  expect(parada.tarefa.status).toBe("a_fazer")
  expect(parada.execucoes.map((e: any) => e.status)).toEqual(["na_fila"])
  expect(turnos(await pedidos("pausa"), "# Alfred")).toHaveLength(0)

  await barra.getByRole("button", { name: "Retomar tudo" }).click()
  await expect(barra).toContainText("Personas trabalhando normalmente.")
  await esperarAte(async () => turnos(await pedidos("pausa"), "# Alfred").length === 1, "o pedido do Alfred depois de retomar")
  const retomada = await esperarStatus(conexao, tarefa.id, "em_revisao")
  expect(retomada.registros.filter((r: any) => r.tipo === "entrega").map((r: any) => r.texto)).toEqual(["rodei depois da pausa"])
})

test("cena 5: plano aprovado chega na execução seguinte", async ({ page }) => {
  await roteiro("plano", [
    { nome: "alfred-executa-o-plano", quando: { sistema: "# Alfred", mensagem: "Plano aprovado pelo Ueslei" }, responde: [{ texto: "executei o plano" }] },
    { nome: "alfred-planeja", quando: { sistema: "# Alfred", mensagem: "execução é de PLANO" }, responde: [{ texto: "plano X" }] },
  ])
  await mudarPosicao(conexao, "executor", (p) => {
    p.aprovarPlano = true
  })
  await page.goto(ambiente().servidor)
  const tarefa = await criarPelaTela(page, conexao, "trocar o disco do servidor")
  await page.locator("#mensagens li", { hasText: "trocar o disco do servidor" }).click()

  await expect(page.locator("#mensagens .msg.plano")).toContainText("plano X")
  await page.getByRole("button", { name: "Aprovar plano" }).click()
  await expect(page.locator("#mensagens .msg.entrega")).toContainText("executei o plano")
  const detalhe = await esperarStatus(conexao, tarefa.id, "em_revisao")
  expect(detalhe.registros.map((r: any) => r.tipo)).toEqual(expect.arrayContaining(["plano", "plano-aprovado", "entrega"]))

  const doAlfred = turnos(await pedidos("plano"), "# Alfred")
  expect(doAlfred).toHaveLength(2)
  expect(doAlfred[0]!.ultimaMensagem).toContain("execução é de PLANO")
  const bloco = doAlfred[1]!.ultimaMensagem.match(/<tarefa>[\s\S]*<\/tarefa>/)?.[0] ?? ""
  expect(bloco).toContain("plano X")
})
