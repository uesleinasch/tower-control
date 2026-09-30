import { join } from "node:path"
import { rename } from "node:fs/promises"
import { CONSELHEIROS, type Conselheiro } from "./tipos"
import { montarSystemPromptParecer, montarPautaParecer, montarPromptSintese } from "./prompt"
import { perguntarUmaVez } from "./sessions"
import { slug } from "./texto"
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
        const texto = await perguntarUmaVez({ raiz, system, prompt: pautaFormatada, permitirLeitura: true })
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
  const sintese = await perguntarUmaVez({ raiz, system, prompt })

  const ata = await gravarAta(raiz, pauta, pareceres, sintese)
  return { sintese, ata }
}

async function gravarAta(
  raiz: string,
  pauta: string,
  pareceres: { perfil: Conselheiro; texto: string }[],
  sintese: string,
): Promise<string> {
  const data = new Date().toISOString().slice(0, 10)
  const nome = `${data}-${slug(pauta) || "convocacao"}.md`
  const caminho = join(raiz, "board", "minutes", nome)
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
  const temporario = `${caminho}.tmp`
  await Bun.write(temporario, corpo)
  await rename(temporario, caminho)
  return `board/minutes/${nome}`
}
