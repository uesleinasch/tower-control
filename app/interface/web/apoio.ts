import { spawn, type ChildProcess } from "node:child_process"
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { readdir, readFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { basename, dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { expect, type Page } from "@playwright/test"
import type { PedidoRecebido, Regra } from "../falsos/roteiro"

export type { PedidoRecebido, Regra }

const RAIZ_DO_APP = join(dirname(fileURLToPath(import.meta.url)), "..", "..")
const PRAZO_PADRAO_MS = 60_000

export interface Ambiente {
  servidor: string
  modelo: string
  dados: string
  porta: number
}

export function ambiente(): Ambiente {
  const caminho = process.env.CT_AMBIENTE
  if (!caminho) throw new Error("CT_AMBIENTE não aponta para um ambiente.json: a cena não subiu o ambiente")
  return JSON.parse(readFileSync(caminho, "utf8"))
}

export async function esperarAte<T>(
  condicao: () => Promise<T | undefined | null | false> | T | undefined | null | false,
  descricao: string,
  prazoMs = PRAZO_PADRAO_MS,
): Promise<T> {
  const limite = Date.now() + prazoMs
  let ultimoErro: unknown
  while (Date.now() < limite) {
    try {
      const valor = await condicao()
      if (valor) return valor as T
    } catch (erro) {
      ultimoErro = erro
    }
    await new Promise((ok) => setTimeout(ok, 100))
  }
  const motivo = ultimoErro ? ` (último erro: ${(ultimoErro as Error).message})` : ""
  throw new Error(`prazo de ${prazoMs} ms estourado esperando ${descricao}${motivo}`)
}

function grupoVivo(pid: number): boolean {
  try {
    process.kill(-pid, 0)
    return true
  } catch (erro) {
    if ((erro as NodeJS.ErrnoException).code === "ESRCH") return false
    throw erro
  }
}

async function esperarGrupoSumir(pid: number, prazoMs: number): Promise<boolean> {
  const limite = Date.now() + prazoMs
  while (Date.now() < limite) {
    if (!grupoVivo(pid)) return true
    await new Promise((ok) => setTimeout(ok, 100))
  }
  return !grupoVivo(pid)
}

export async function subirCena(semear?: (amb: Ambiente) => Promise<void>): Promise<() => Promise<void>> {
  const pasta = mkdtempSync(join(tmpdir(), "ct-web-"))
  const arquivo = join(pasta, "ambiente.json")
  let saida = ""
  const processo: ChildProcess = spawn("bun", ["run", "interface/subir.ts", pasta], {
    cwd: RAIZ_DO_APP,
    detached: true,
    stdio: ["ignore", "pipe", "pipe"],
  })
  processo.stdout?.on("data", (d) => (saida += d))
  processo.stderr?.on("data", (d) => (saida += d))
  const pid = processo.pid!

  const descer = async () => {
    const pidDoServidor = existsSync(arquivo) ? Number(JSON.parse(readFileSync(arquivo, "utf8")).pidDoServidor) : NaN
    if (grupoVivo(pid)) {
      process.kill(-pid, "SIGTERM")
      if (await esperarGrupoSumir(pid, 25_000)) return
      process.kill(-pid, "SIGKILL")
    }
    if (Number.isInteger(pidDoServidor) && grupoVivo(pidDoServidor)) process.kill(-pidDoServidor, "SIGKILL")
    await esperarGrupoSumir(pid, 5_000)
    if (Number.isInteger(pidDoServidor)) await esperarGrupoSumir(pidDoServidor, 5_000)
    rmSync(pasta, { recursive: true, force: true })
  }

  try {
    await esperarAte(
      () => {
        if (processo.exitCode !== null) throw new Error(`subir.ts saiu com ${processo.exitCode}: ${saida}`)
        if (!existsSync(arquivo)) return false
        return JSON.parse(readFileSync(arquivo, "utf8")).servidor as string
      },
      `o ambiente.json em ${pasta}`,
    )
    process.env.CT_AMBIENTE = arquivo
    await semear?.(ambiente())
  } catch (erro) {
    await descer()
    throw new Error(`${(erro as Error).message}\n--- saída do subir.ts ---\n${saida}`)
  }
  return descer
}

async function controle(caminho: string, corpo?: unknown): Promise<unknown> {
  const resposta = await fetch(`${ambiente().modelo}${caminho}`, {
    method: corpo === undefined ? "GET" : "POST",
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  })
  if (!resposta.ok) throw new Error(`${caminho} respondeu ${resposta.status}: ${await resposta.text()}`)
  return resposta.json()
}

export async function roteiro(cena: string, regras: Regra[]): Promise<void> {
  await controle("/_controle/roteiro", { cena, regras })
}

export async function pedidos(cena: string): Promise<PedidoRecebido[]> {
  return (await controle(`/_controle/pedidos?cena=${encodeURIComponent(cena)}`)) as PedidoRecebido[]
}

export async function semRegra(): Promise<PedidoRecebido[]> {
  return (await controle("/_controle/sem-regra")) as PedidoRecebido[]
}

export async function conferirSemRegra(): Promise<void> {
  const soltos = await semRegra()
  if (!soltos.length) return
  const resumo = soltos.map((p) => `- sistema: ${p.sistema.slice(0, 160)} | mensagem: ${p.ultimaMensagem.slice(-300)}`)
  throw new Error(`${soltos.length} pedido(s) sem regra no modelo falso:\n${resumo.join("\n")}`)
}

export async function encontro(nome: string, lado: string, lados: string[]): Promise<void> {
  await controle("/_controle/encontro", { nome, lado, lados })
}

export function deQuem(pedido: PedidoRecebido, cabecalho: string): boolean {
  return pedido.sistema.includes(cabecalho)
}

export function turnos(lista: PedidoRecebido[], cabecalho: string): PedidoRecebido[] {
  return lista.filter((p) => deQuem(p, cabecalho) && p.resultadoDe === null)
}

function casaNome(padrao: string, nome: string): boolean {
  const regex = new RegExp(`^${padrao.split("*").map((p) => p.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*")}$`)
  return regex.test(nome)
}

export async function esperarArquivo(caminho: string, contendo?: string, prazoMs = PRAZO_PADRAO_MS): Promise<string> {
  const pasta = dirname(caminho)
  const padrao = basename(caminho)
  return esperarAte(
    async () => {
      const nomes = padrao.includes("*") ? (await readdir(pasta)).filter((n) => casaNome(padrao, n)) : [padrao]
      for (const nome of nomes) {
        const conteudo = await readFile(join(pasta, nome), "utf8").catch(() => null)
        if (conteudo !== null && (contendo === undefined || conteudo.includes(contendo))) return conteudo
      }
      return null
    },
    `o arquivo ${caminho}${contendo ? ` com "${contendo}"` : ""}`,
    prazoMs,
  )
}

export interface Conexao {
  mandar(m: object): void
  esperar(tipo: string, filtro?: (m: any) => boolean, prazoMs?: number): Promise<any>
  fechar(): void
}

export async function ws(): Promise<Conexao> {
  const socket = new WebSocket(`${ambiente().servidor.replace(/^http/, "ws")}/ws`)
  const ouvintes = new Set<(m: any) => void>()
  socket.onmessage = (evento) => {
    const mensagem = JSON.parse(String(evento.data))
    for (const ouvir of [...ouvintes]) ouvir(mensagem)
  }
  await new Promise<void>((ok, falha) => {
    socket.onopen = () => ok()
    socket.onerror = () => falha(new Error("o WebSocket do servidor de teste não abriu"))
  })
  return {
    mandar: (m) => socket.send(JSON.stringify(m)),
    esperar: (tipo, filtro = () => true, prazoMs = PRAZO_PADRAO_MS) =>
      new Promise((ok, falha) => {
        const prazo = setTimeout(() => {
          ouvintes.delete(ouvir)
          falha(new Error(`prazo de ${prazoMs} ms estourado esperando a mensagem "${tipo}"`))
        }, prazoMs)
        const ouvir = (m: any) => {
          if (m.tipo === "erro") {
            clearTimeout(prazo)
            ouvintes.delete(ouvir)
            falha(new Error(`o servidor recusou: ${m.mensagem}`))
          } else if (m.tipo === tipo && filtro(m)) {
            clearTimeout(prazo)
            ouvintes.delete(ouvir)
            ok(m)
          }
        }
        ouvintes.add(ouvir)
      }),
    fechar: () => socket.close(),
  }
}

export async function pedir(conexao: Conexao, mensagem: object, tipo: string, filtro?: (m: any) => boolean): Promise<any> {
  const resposta = conexao.esperar(tipo, filtro)
  conexao.mandar(mensagem)
  return resposta
}

export async function lerEquipe(): Promise<any> {
  return JSON.parse(await readFile(join(ambiente().dados, "equipes", "casa", "equipe.json"), "utf8"))
}

export async function mudarPosicao(conexao: Conexao, posicao: string, mudar: (p: any) => void): Promise<void> {
  const equipe = await lerEquipe()
  const alvo = equipe.posicoes.find((p: any) => p.id === posicao)
  if (!alvo) throw new Error(`a posição ${posicao} não existe na Casa`)
  mudar(alvo)
  await pedir(conexao, { tipo: "equipe-salvar", equipe }, "equipes")
  const gravada = (await lerEquipe()).posicoes.find((p: any) => p.id === posicao)
  for (const [chave, valor] of Object.entries(alvo)) {
    if (JSON.stringify(gravada?.[chave]) !== JSON.stringify(valor)) {
      throw new Error(`a posição ${posicao} não gravou ${chave}: ${JSON.stringify(gravada?.[chave])}`)
    }
  }
}

export async function criarTarefa(conexao: Conexao, titulo: string, posicao = "executor"): Promise<any> {
  const msg = await pedir(
    conexao,
    { tipo: "tarefa-criar", tarefa: { equipe: "casa", posicao, titulo, porque: "" } },
    "tarefa",
    (m) => m.tarefa?.titulo === titulo,
  )
  return msg.tarefa
}

export async function criarPelaTela(page: Page, conexao: Conexao, titulo: string, posicao = "executor"): Promise<any> {
  await page.locator("#botao-tarefas").click()
  const form = page.locator("form.nova-tarefa")
  await expect(form.locator(`select[name="posicao"] option[value="${posicao}"]`)).toHaveCount(1)
  const criada = conexao.esperar("tarefa", (m) => m.tarefa?.titulo === titulo)
  await form.locator('select[name="posicao"]').selectOption(posicao)
  await form.locator('input[name="titulo"]').fill(titulo)
  await form.locator('button[type="submit"]').click()
  return (await criada).tarefa
}

export async function desfazerSemeadura(conexao: Conexao): Promise<void> {
  const { lista } = await pedir(conexao, { tipo: "tarefas" }, "tarefas")
  for (const t of lista.filter((t: any) => t.status !== "concluida" && t.status !== "cancelada")) {
    await pedir(conexao, { tipo: "tarefa-status", id: t.id, status: "cancelada" }, "tarefa", (m) => m.tarefa.id === t.id && m.tarefa.status === "cancelada")
  }
  await pedir(conexao, { tipo: "retomar", alvo: "*" }, "orquestra", (m) => m.pausadoTudo === false)
  await pedir(conexao, { tipo: "retomar", alvo: "alfred" }, "personas")
  const { lista: personas } = await pedir(conexao, { tipo: "personas" }, "personas")
  const alfred = personas.find((p: any) => p.id === "alfred")
  if (alfred.orcamentoMensalUSD !== null || alfred.orcamentoMensalTokens !== null) {
    await pedir(
      conexao,
      { tipo: "persona-salvar", persona: { id: "alfred", orcamentoMensalUSD: null, orcamentoMensalTokens: null } },
      "personas",
      (m) => m.lista.some((p: any) => p.id === "alfred" && p.orcamentoMensalUSD === null && p.orcamentoMensalTokens === null),
    )
  }
  const executor = (await lerEquipe()).posicoes.find((p: any) => p.id === "executor")
  if ("aprovarPlano" in executor || "politica" in executor) {
    await mudarPosicao(conexao, "executor", (p) => {
      delete p.aprovarPlano
      delete p.politica
    })
    const gravada = (await lerEquipe()).posicoes.find((p: any) => p.id === "executor")
    if ("aprovarPlano" in gravada || "politica" in gravada) throw new Error("o executor continuou com aprovarPlano ou politica")
  }
}

export async function detalheDaTarefa(conexao: Conexao, id: number): Promise<any> {
  return pedir(conexao, { tipo: "tarefa", id }, "tarefa", (m) => m.pedida === true && m.tarefa.id === id)
}

export async function esperarStatus(conexao: Conexao, id: number, status: string, prazoMs = PRAZO_PADRAO_MS): Promise<any> {
  return esperarAte(
    async () => {
      const d = await detalheDaTarefa(conexao, id)
      return d.tarefa.status === status && !d.tarefa.rodando ? d : null
    },
    `a tarefa #${id} em ${status}`,
    prazoMs,
  )
}
