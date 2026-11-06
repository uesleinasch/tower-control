import { readFile } from "node:fs/promises"
import { dirname, join } from "node:path"
import { expect, test } from "@playwright/test"
import {
  ambiente,
  conferirSemRegra,
  criarPelaTela,
  encontroDaConjunta,
  esperarStatus,
  ladosDaConjunta,
  pedidos,
  pedir,
  roteiro,
  subirCena,
  ws,
  type Conexao,
} from "../apoio"

const PRAZO_DA_CONJUNTA_MS = 15 * 60_000
const TITULO_DA_CENA_2 = "conjunta 2: grave o conjunta2.txt"
const TITULO_DA_CENA_8 = "conjunta 8: conferir pelo painel"

const equipeConjunta = {
  id: "conjunta",
  nome: "Conjunta",
  posicoes: [
    {
      id: "execucao",
      titulo: "execução",
      persona: "alfred",
      respondeA: null,
      capacidades: ["arquivos"],
      aprovacao: "sempre",
      politica: [{ tipo: "aprovacao", por: { ueslei: true } }],
    },
  ],
  layout: {},
}

let descer: (() => Promise<void>) | undefined
let conexao: Conexao

test.skip(ladosDaConjunta().length === 0, "só roda nas conjuntas, com CT_LADOS e o ambiente de pé")

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
    const { lista } = await pedir(conexao, { tipo: "tarefas" }, "tarefas")
    for (const t of lista.filter((t: any) => t.status !== "concluida" && t.status !== "cancelada")) {
      await pedir(conexao, { tipo: "tarefa-status", id: t.id, status: "cancelada" }, "tarefa", (m) => m.tarefa.id === t.id && m.tarefa.status === "cancelada")
    }
    const { lista: equipes } = await pedir(conexao, { tipo: "equipes" }, "equipes")
    if (equipes.some((e: any) => e.id === "conjunta")) {
      await pedir(conexao, { tipo: "equipe-excluir", id: "conjunta" }, "equipes", (m) => !m.lista.some((e: any) => e.id === "conjunta"))
    }
  } finally {
    await conferirSemRegra()
  }
})

test("conjunta: cena 2, comando de tarefa chega a todos e o desktop aprova", async ({ page }) => {
  test.setTimeout(PRAZO_DA_CONJUNTA_MS)
  const arquivo = join(dirname(ambiente().dados), "conjunta2.txt")
  const comando = `echo conjunta2 > ${arquivo} && cat ${arquivo}`
  await roteiro("conjunta-2", [
    { nome: "alfred-conclui", quando: { sistema: "# Alfred", resultadoDe: "Bash" }, responde: [{ texto: "gravei o conjunta2" }] },
    {
      nome: "alfred-pede",
      quando: { sistema: "# Alfred", mensagem: TITULO_DA_CENA_2 },
      responde: [{ ferramenta: "Bash", entrada: { command: comando, description: "grava o conjunta2" } }],
      vezes: 1,
    },
  ])
  await encontroDaConjunta("conjunta-2:pronto", "web")

  await page.goto(ambiente().servidor)
  const pedidoChegou = conexao.esperar("permissao", (m) => m.comando === comando, 120_000)
  const tarefa = await criarPelaTela(page, conexao, TITULO_DA_CENA_2)
  const pedido = await pedidoChegou
  expect(pedido.tarefaId).toBe(tarefa.id)
  const resolvida = await conexao.esperar("permissao-resolvida", (m) => m.id === pedido.id, PRAZO_DA_CONJUNTA_MS)
  expect(resolvida.como).toBe("aprovado")
  await esperarStatus(conexao, tarefa.id, "em_revisao")
  expect((await readFile(arquivo, "utf8")).trim()).toBe("conjunta2")
  const resultados = (await pedidos("conjunta-2")).filter((p) => p.resultadoDe === "Bash")
  expect(resultados).toHaveLength(1)
  expect(JSON.stringify(resultados[0].corpo)).not.toContain('"is_error":true')

  await encontroDaConjunta("conjunta-2:fim", "web")
})

test("conjunta: cena 8, item resolvido na web some do painel", async ({ page }) => {
  test.setTimeout(PRAZO_DA_CONJUNTA_MS)
  await roteiro("conjunta-8", [
    { nome: "alfred-entrega", quando: { sistema: "# Alfred", mensagem: TITULO_DA_CENA_8 }, responde: [{ texto: "conferido na conjunta" }] },
  ])
  await pedir(conexao, { tipo: "equipe-salvar", equipe: equipeConjunta }, "equipes", (m) => m.lista.some((e: any) => e.id === "conjunta"))
  const { tarefa } = await pedir(
    conexao,
    { tipo: "tarefa-criar", tarefa: { equipe: "conjunta", posicao: "execucao", titulo: TITULO_DA_CENA_8, porque: "" } },
    "tarefa",
    (m) => m.tarefa?.titulo === TITULO_DA_CENA_8,
  )
  await esperarStatus(conexao, tarefa.id, "em_revisao")

  await page.goto(ambiente().servidor)
  await page.locator("#botao-painel").click()
  const item = page.locator(".item-atencao", { hasText: `#${tarefa.id} espera sua aprovação` })
  await expect(item).toHaveCount(1)
  await encontroDaConjunta("conjunta-8:pronto", "web")

  await item.getByRole("button", { name: "Aprovar" }).click()
  await esperarStatus(conexao, tarefa.id, "concluida")
  await encontroDaConjunta("conjunta-8:resolvido", "web")
  await expect(item).toHaveCount(0, { timeout: 5_000 })

  await encontroDaConjunta("conjunta-8:fim", "web")
})
