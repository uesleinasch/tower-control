import { spawn } from "node:child_process"
import { closeSync, openSync } from "node:fs"
import { mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { createServer } from "node:net"
import { join } from "node:path"
import { servirModeloFalso } from "./falsos/modelo"
import { servirTickTaskFalso } from "./falsos/ticktask"

export interface Ambiente {
  pasta: string
  dados: string
  servidor: string
  porta: number
  modelo: string
  ticktask: string
  pidDoServidor: number
  log: { servidor: string }
  encerrar(): Promise<void>
}

const HERDADAS = ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "USER", "SHELL"]

export function ambienteDoServidor(base: Record<string, string | undefined>, extras: Record<string, string>): Record<string, string> {
  const herdadas: Record<string, string> = {}
  for (const nome of HERDADAS) {
    const valor = base[nome]
    if (valor !== undefined) herdadas[nome] = valor
  }
  return { ...herdadas, ...extras }
}

async function fimDoLog(log: string): Promise<string> {
  const texto = await readFile(log, "utf8").catch(() => "")
  return texto.split("\n").slice(-40).join("\n")
}

const RAIZ_DO_APP = join(import.meta.dir, "..")

function portaLivre(): Promise<number> {
  return new Promise((ok, falha) => {
    const socket = createServer()
    socket.once("error", falha)
    socket.listen(0, "127.0.0.1", () => {
      const { port } = socket.address() as { port: number }
      socket.close(() => ok(port))
    })
  })
}

async function esperarEnderecos(servidor: string, processo: { exitCode: number | null }, log: string): Promise<void> {
  const prazo = Date.now() + 30_000
  while (Date.now() < prazo) {
    if (processo.exitCode !== null) throw new Error(`servidor de teste saiu com ${processo.exitCode}, veja ${log}`)
    try {
      const resposta = await fetch(`${servidor}/enderecos`)
      if (resposta.ok) return
    } catch {}
    await Bun.sleep(100)
  }
  throw new Error(`servidor de teste não respondeu em 30 s, veja ${log}`)
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

// O claude do SDK herda o grupo do servidor e sobrevive a um SIGTERM só no bun:
// o grupo inteiro precisa sumir antes do rm, senão ele recria a pasta.
export async function encerrarGrupo(pid: number, prazoMs = 10_000): Promise<void> {
  if (!grupoVivo(pid)) return
  process.kill(-pid, "SIGTERM")
  const limite = Date.now() + prazoMs
  while (Date.now() < limite) {
    if (!grupoVivo(pid)) return
    await Bun.sleep(100)
  }
  process.kill(-pid, "SIGKILL")
  while (grupoVivo(pid)) await Bun.sleep(50)
}

export async function subirAmbiente(pasta: string, aoIniciar?: (encerrar: () => Promise<void>) => void): Promise<Ambiente> {
  const dados = join(pasta, "dados")
  const claude = join(pasta, "claude")
  await mkdir(dados, { recursive: true })
  await mkdir(claude, { recursive: true })

  const modelo = servirModeloFalso()
  const ticktask = servirTickTaskFalso()
  const porta = await portaLivre()
  const portaMemoria = await portaLivre()
  const configTickTask = join(pasta, "ticktask.json")
  await writeFile(configTickTask, JSON.stringify({ enabled: true, port: ticktask.porta, token: ticktask.token }))

  const logServidor = join(pasta, "servidor.log")
  const descritorDoLog = openSync(logServidor, "a")
  const processo = spawn("bun", ["run", "src/server.ts"], {
    cwd: RAIZ_DO_APP,
    detached: true,
    stdio: ["ignore", descritorDoLog, descritorDoLog],
    env: ambienteDoServidor(process.env, {
      CT_DADOS: dados,
      TOWER_PORTA: String(porta),
      CT_TICKTASK_CONFIG: configTickTask,
      CT_MEMORIA_URL: `http://127.0.0.1:${portaMemoria}`,
      CLAUDE_CONFIG_DIR: claude,
      ANTHROPIC_BASE_URL: `http://127.0.0.1:${modelo.porta}`,
      ANTHROPIC_API_KEY: "sk-falsa",
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
    }),
  })
  closeSync(descritorDoLog)

  const servidor = `http://127.0.0.1:${porta}`
  let encerrado = false
  const encerrar = async () => {
    if (encerrado) return
    encerrado = true
    await encerrarGrupo(processo.pid!)
    modelo.fechar()
    ticktask.fechar()
    await rm(pasta, { recursive: true, force: true })
  }

  aoIniciar?.(encerrar)

  try {
    await esperarEnderecos(servidor, processo, logServidor)
  } catch (erro) {
    const fim = await fimDoLog(logServidor)
    await encerrar()
    throw new Error(`${(erro as Error).message}\n--- fim do servidor.log ---\n${fim}`)
  }

  return {
    pasta,
    dados,
    servidor,
    porta,
    modelo: `http://127.0.0.1:${modelo.porta}`,
    ticktask: `http://127.0.0.1:${ticktask.porta}`,
    log: { servidor: logServidor },
    pidDoServidor: processo.pid!,
    encerrar,
  }
}
