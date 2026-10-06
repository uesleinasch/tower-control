import { join } from "node:path"
import { randomUUID } from "node:crypto"
import { link, rm } from "node:fs/promises"
import { CONSELHEIROS, type Conselheiro } from "./tipos"
import { montarSystemPromptParecer, montarPautaParecer, montarPromptSintese } from "./prompt"
import { perguntarUmaVez } from "./sessions"
import { dataLocal, slug } from "./texto"
import type { Memoria } from "./memoria/tipos"
import { montarBrief } from "./memoria/recuperacao"

export { slug }

interface ResultadoBoard {
  sintese: string
  ata: string
}

export async function convocarBoard(
  raiz: string,
  pauta: string,
  contexto: string | undefined,
  onStatus: (texto: string) => void,
  memoria?: Memoria,
): Promise<ResultadoBoard> {
  const pautaFormatada = montarPautaParecer(pauta, contexto)

  const pareceres = await Promise.all(
    CONSELHEIROS.map(async (perfil) => {
      const brief = memoria ? await montarBrief(memoria, perfil, pauta) : ""
      const system = await montarSystemPromptParecer(raiz, perfil, brief)
      try {
        const texto = await perguntarUmaVez({
          raiz,
          system,
          prompt: pautaFormatada,
          permitirLeitura: true,
          uso: { tipo: "board-parecer", perfil },
        })
        return { perfil, texto }
      } catch (erro) {
        return { perfil, texto: `_(parecer indisponível: ${(erro as Error).message})_` }
      }
    }),
  )

  const validos = pareceres.filter((p) => !p.texto.startsWith("_(parecer indisponível"))
  if (!validos.length) throw new Error("nenhum perfil conseguiu emitir parecer")
  onStatus(`Pareceres recebidos (${validos.length}/${CONSELHEIROS.length}) — sintetizando…`)

  const { system, prompt } = montarPromptSintese(pauta, pareceres)
  const sintese = await perguntarUmaVez({ raiz, system, prompt, uso: { tipo: "board-sintese" } })

  const ata = await gravarAta(raiz, pauta, pareceres, sintese)
  return { sintese, ata }
}

async function gravarAta(
  raiz: string,
  pauta: string,
  pareceres: { perfil: Conselheiro; texto: string }[],
  sintese: string,
): Promise<string> {
  const data = dataLocal()
  const corpo = [
    `# Ata do board — ${data}`,
    ``,
    `## Pauta`,
    ``,
    pauta.trim(),
    ``,
    ...pareceres.flatMap((p) => [`## Parecer — ${p.perfil}`, ``, p.texto.trim(), ``]),
    sintese.trim(),
    ``,
  ].join("\n")
  const nome = await gravarSemSobrescrever(join(raiz, "board", "minutes"), `${data}-${slug(pauta) || "convocacao"}`, corpo)
  return `board/minutes/${nome}`
}

export async function gravarSemSobrescrever(dir: string, base: string, conteudo: string): Promise<string> {
  const temporario = join(dir, `.${base}.${randomUUID()}.tmp`)
  await Bun.write(temporario, conteudo)
  try {
    for (let n = 1; ; n++) {
      const nome = n === 1 ? `${base}.md` : `${base}-${n}.md`
      try {
        await link(temporario, join(dir, nome))
        return nome
      } catch (erro) {
        if ((erro as NodeJS.ErrnoException).code !== "EEXIST") throw erro
      }
    }
  } finally {
    await rm(temporario, { force: true })
  }
}
