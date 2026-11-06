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

// O servidor também republica o painel num setInterval de 30 s. Dois retratos seguidos a 30 s um
// do outro marcam esse relógio; clicar logo depois põe o próximo tique longe da aprovação.
async function tiqueDoRelogio(conexao: Conexao): Promise<any> {
  const limite = Date.now() + 95_000
  let anterior: number | null = null
  while (true) {
    const m = await conexao.esperar("painel", undefined, Math.max(1, limite - Date.now()))
    const em = Date.parse(m.retrato.em)
    if (anterior !== null && Math.abs(em - anterior - 30_000) < 1_500) return m
    anterior = em
  }
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
  await encontroDaConjunta("conjunta-2:pronto", "web", true)

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
  await encontroDaConjunta("conjunta-8:pronto", "web", true)

  await pedir(conexao, { tipo: "painel", ativo: true }, "painel")
  const tique = await tiqueDoRelogio(conexao)
  expect(tique.retrato.atencao.some((i: any) => i.tarefaId === tarefa.id)).toBe(true)
  const semOItem = conexao.esperar("painel", (m) => !m.retrato.atencao.some((i: any) => i.tarefaId === tarefa.id), 45_000)

  await item.getByRole("button", { name: "Aprovar" }).click()
  const { registros } = await esperarStatus(conexao, tarefa.id, "concluida")
  await encontroDaConjunta("conjunta-8:resolvido", "web")
  const { retrato } = await semOItem
  conexao.mandar({ tipo: "painel", ativo: false })
  await expect(item).toHaveCount(0, { timeout: 45_000 })
  const aprovado = [...registros].reverse().find((r: any) => r.tipo === "aprovado")
  const atraso = Date.parse(retrato.em) - Date.parse(aprovado.em)
  expect(atraso, `o painel só perdeu o item ${atraso} ms depois da aprovação: veio do relógio de 30 s, e não da resolução`).toBeLessThan(5_000)

  await encontroDaConjunta("conjunta-8:fim", "web")
})
