import { mkdtemp, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { subirAmbiente } from "./ambiente"

const pasta = process.argv[2] ?? (await mkdtemp(join(tmpdir(), "ct-interface-")))
const ambiente = await subirAmbiente(pasta)

await writeFile(
  join(pasta, "ambiente.json"),
  JSON.stringify({
    dados: ambiente.dados,
    servidor: ambiente.servidor,
    porta: ambiente.porta,
    modelo: ambiente.modelo,
    ticktask: ambiente.ticktask,
    logServidor: ambiente.log.servidor,
    pid: process.pid,
  }),
)

const sair = () => void ambiente.encerrar().finally(() => process.exit(0))
process.on("SIGTERM", sair)
process.on("SIGINT", sair)
console.log(`ambiente pronto em ${pasta}`)
setInterval(() => {}, 1 << 30)
