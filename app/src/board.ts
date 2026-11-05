import { join } from "node:path"
import { randomUUID } from "node:crypto"
import { link, rm } from "node:fs/promises"
import { doBoard, type Conselheiro } from "./tipos"
import { montarSystemPromptParecer, montarPautaParecer, montarPromptSintese } from "./prompt"
import { perguntarUmaVez } from "./sessions"
import { dataLocal, slug } from "./texto"
import type { Memoria } from "./memoria/tipos"
import { montarBrief } from "./memoria/recuperacao"
import { decisaoDaSintese, type Decisao } from "./orquestra/politica"

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

  const convocados = doBoard()
  const pareceres = await Promise.all(
    convocados.map(async (perfil) => {
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
  onStatus(`Pareceres recebidos (${validos.length}/${convocados.length}) — sintetizando…`)

  const { system, prompt } = montarPromptSintese(pauta, pareceres)
  const sintese = await perguntarUmaVez({ raiz, system, prompt, uso: { tipo: "board-sintese" } })

  const ata = await gravarAta(raiz, pauta, pareceres, sintese)
  return { sintese, ata }
}

export interface RevisaoDoBoard {
  titulo: string
  pauta: string
  membros: Conselheiro[]
  modelo: (persona: Conselheiro) => string
  tarefaId: number
  execucaoId: number
  controle?: AbortController
  memoria?: Memoria
}

export interface ResultadoDaRevisao {
  sintese: string
  ata: string
  decisao: Decisao["tipo"] | null
}

const MODELO_DA_SINTESE_EM_TAREFA = "sonnet"

const REGRA_DA_DECISAO = `Esta pauta é a revisão de uma entrega numa tarefa. Termine a síntese com uma linha
sozinha, exatamente "DECISÃO: aprovar" se a entrega pode seguir como está, ou "DECISÃO: mudança"
se ela precisa voltar à executora; nesse caso, a Recomendação final diz o que mudar e por quê.`

export async function revisarComBoard(raiz: string, pedido: RevisaoDoBoard): Promise<ResultadoDaRevisao> {
  const { sintese, ata } = await pareceresESintese(raiz, pedido, REGRA_DA_DECISAO)
  return { sintese, ata, decisao: decisaoDaSintese(sintese) }
}

export interface DeliberacaoDoBoard {
  titulo: string
  pauta: string
  membros: Conselheiro[]
  modelo: (persona: Conselheiro) => string
  opcoes?: string[]
  memoria?: Memoria
}

export function opcaoDaSintese(sintese: string, opcoes: string[]): string | null {
  const linhas = [...sintese.matchAll(/^[\s*_#>-]*DECIS[AÃ]O:\s*\**\s*(.+?)\s*\**\s*$/gim)]
  const dita = linhas.at(-1)?.[1]?.trim().toLowerCase()
  return dita ? (opcoes.find((o) => o.toLowerCase() === dita) ?? null) : null
}

export async function deliberarComBoard(raiz: string, pedido: DeliberacaoDoBoard): Promise<{ sintese: string; ata: string; decisao: string | null }> {
  const regra = pedido.opcoes?.length
    ? `Termine a síntese com uma linha sozinha, exatamente "DECISÃO: <opção>", escolhendo uma destas opções: ${pedido.opcoes.join(", ")}.`
    : ""
  const { sintese, ata } = await pareceresESintese(raiz, pedido, regra)
  return { sintese, ata, decisao: pedido.opcoes?.length ? opcaoDaSintese(sintese, pedido.opcoes) : null }
}

async function pareceresESintese(
  raiz: string,
  pedido: Pick<RevisaoDoBoard, "titulo" | "pauta" | "membros" | "modelo" | "controle" | "memoria"> & { tarefaId?: number; execucaoId?: number },
  regra: string,
): Promise<{ sintese: string; ata: string }> {
  const uso = { tipo: "tarefa" as const, tarefaId: pedido.tarefaId, execucaoId: pedido.execucaoId }
  const pareceres = await Promise.all(
    pedido.membros.map(async (perfil) => {
      const brief = pedido.memoria ? await montarBrief(pedido.memoria, perfil, pedido.titulo) : ""
      const system = await montarSystemPromptParecer(raiz, perfil, brief)
      const modelo = pedido.modelo(perfil)
      try {
        const texto = await perguntarUmaVez({
          raiz,
          system,
          prompt: montarPautaParecer(pedido.pauta),
          permitirLeitura: true,
          modelo,
          uso: { ...uso, perfil, modelo },
          controle: pedido.controle,
        })
        return { perfil, texto }
      } catch (erro) {
        if (pedido.controle?.signal.aborted) throw erro
        return { perfil, texto: `_(parecer indisponível: ${(erro as Error).message})_` }
      }
    }),
  )
  if (!pareceres.some((p) => !p.texto.startsWith("_(parecer indisponível"))) throw new Error("nenhum membro do board conseguiu emitir parecer")
  const { system, prompt } = montarPromptSintese(pedido.pauta, pareceres)
  const sintese = await perguntarUmaVez({
    raiz,
    system: regra ? `${system}\n\n${regra}` : system,
    prompt,
    modelo: MODELO_DA_SINTESE_EM_TAREFA,
    uso: { ...uso, modelo: MODELO_DA_SINTESE_EM_TAREFA },
    controle: pedido.controle,
  })
  const ata = await gravarAta(raiz, pedido.pauta, pareceres, sintese, pedido.titulo)
  return { sintese, ata }
}

async function gravarAta(
  raiz: string,
  pauta: string,
  pareceres: { perfil: Conselheiro; texto: string }[],
  sintese: string,
  titulo = pauta,
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
  const nome = await gravarSemSobrescrever(join(raiz, "board", "minutes"), `${data}-${slug(titulo) || "convocacao"}`, corpo)
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
