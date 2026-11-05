import { expect, test } from "@playwright/test"
import { join } from "node:path"
import { ambiente, conferirSemRegra, deQuem, esperarArquivo, pedidos, roteiro, subirCena } from "../apoio"

let descer: (() => Promise<void>) | undefined

test.beforeAll(async () => {
  descer = await subirCena()
})

test.afterAll(async () => {
  await descer?.()
})

test.afterEach(async () => {
  await conferirSemRegra()
})

test("cena 1: mensagem para a Nati vira balões e fica gravada", async ({ page }) => {
  await roteiro("chat-baloes", [
    { nome: "nati-responde", quando: { sistema: "# Nati", mensagem: "como vai o projeto?" }, responde: [{ texto: "um\n\n---\n\ndois" }] },
  ])
  await page.goto(ambiente().servidor)
  await page.locator('#lista-personas [data-perfil="nati"]').click()
  await page.locator("#entrada").fill("como vai o projeto?")
  await page.locator("#enviar").click()

  await expect(page.locator("#mensagens .msg.perfil-msg .corpo")).toHaveText(["um", "dois"])
  await expect(page.locator("#enviar")).toBeEnabled()

  const gravado = await esperarArquivo(join(ambiente().dados, "conversations", "*-nati-*.jsonl"), "dois")
  const resposta = gravado
    .trim()
    .split("\n")
    .map((linha) => JSON.parse(linha))
    .find((m) => m.role === "assistant")
  expect(resposta.texto.split(/\n\s*-{3,}\s*\n/)).toEqual(["um", "dois"])
})

test("cena 1: anexo chega ao modelo", async ({ page }) => {
  await roteiro("chat-anexo", [
    { nome: "nati-le-anexo", quando: { sistema: "# Nati", mensagem: "leia a nota" }, responde: [{ texto: "li a nota" }] },
  ])
  await page.goto(ambiente().servidor)
  await page.locator('#lista-personas [data-perfil="nati"]').click()

  const subida = page.waitForResponse((r) => r.url().endsWith("/anexo") && r.request().method() === "POST")
  const escolha = page.waitForEvent("filechooser")
  await page.locator("#clipe").click()
  await page.locator('#menu-anexo [data-fonte="arquivo"]').click()
  await (await escolha).setFiles({ name: "nota.txt", mimeType: "text/plain", buffer: Buffer.from("a reunião mudou para quinta\n") })
  const anexo = await (await subida).json()
  await expect(page.locator("#pendentes .chip")).toContainText("nota.txt")

  await page.locator("#entrada").fill("leia a nota")
  await page.locator("#enviar").click()
  await expect(page.locator("#mensagens .msg.perfil-msg .corpo")).toHaveText(["li a nota"])
  await expect(page.locator("#mensagens .msg.usuario .anexo-arquivo")).toContainText("nota.txt")

  const daNati = (await pedidos("chat-anexo")).filter((p) => deQuem(p, "# Nati"))
  expect(daNati.length).toBeGreaterThan(0)
  expect(daNati.at(-1)!.ultimaMensagem).toContain(join(ambiente().dados, "conversations", "anexos", anexo.id))
})
