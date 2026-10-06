import { join } from "node:path"
import { rm } from "node:fs/promises"
import { CONSELHEIROS, type Conselheiro } from "../tipos"
import { alterarEstado, lerEstado } from "./agenda"
import { lerPerfil } from "../prompt"
import { instrucoesDeBastidor, rodarPersona } from "./sessao"
import type { Memoria, Pagina } from "./tipos"

export const ORIGEM_MIGRACAO = "migracao"

const TAREFA = `Tarefa: mudar de casa. Até hoje sua memória era um arquivo único; agora cada
lembrança é uma página. Você vai receber o arquivo antigo inteiro.

1. Cada item do arquivo (cada tópico de lista ou parágrafo) vai para uma página, com o
   tipo certo: fato, episodio ou jeito. Itens do mesmo assunto podem ir juntos.
2. Copie o texto de cada item LITERALMENTE no corpo da página, do jeito que está. Você
   pode acrescentar título e uma frase de contexto, mas não reescreva nem resuma o item:
   depois alguém confere, item por item, que nada se perdeu.
3. Seções vazias e marcadores como "(vazio por enquanto)" não viram página.
4. Aqui não há o que atualizar: use só lembrar.`

function normalizar(texto: string): string {
  return texto
    .toLowerCase()
    .replace(/[*_`>]/g, "")
    .replace(/^\s*[-+]\s+/gm, "")
    .replace(/\s+/g, " ")
    .trim()
}

export function itensDaMemoria(memoriaMd: string): string[] {
  const itens: string[] = []
  let atual: string[] = []
  let depoisDoTitulo = false
  let notaPulada = false
  const fechar = () => {
    const texto = atual.join(" ").trim()
    atual = []
    if (!texto) return
    if (depoisDoTitulo && !notaPulada) {
      notaPulada = true
      return
    }
    if (/^_?\(.*\)_?$/.test(texto)) return
    itens.push(texto)
  }
  for (const linha of memoriaMd.split("\n")) {
    if (/^#\s/.test(linha)) {
      fechar()
      depoisDoTitulo = true
      continue
    }
    if (/^#{2,}\s/.test(linha)) {
      fechar()
      notaPulada = true
      continue
    }
    if (!linha.trim()) {
      fechar()
      continue
    }
    if (/^\s*[-+*]\s/.test(linha)) fechar()
    atual.push(linha.trim())
  }
  fechar()
  return itens
}

export function itensNaoCobertos(memoriaMd: string, corpos: string[]): string[] {
  const tudo = normalizar(corpos.join("\n"))
  return itensDaMemoria(memoriaMd).filter((item) => !tudo.includes(normalizar(item)))
}

export function montarPedidoMigracao(memoriaMd: string): string {
  return `## Seu arquivo de memória antigo\n\n${memoriaMd.trim()}\n\nFaça a mudança.`
}

export async function migrarPersona(raiz: string, m: Memoria, persona: Conselheiro, memoriaMd: string): Promise<void> {
  const perfil = await lerPerfil(raiz, persona)
  await rodarPersona({
    raiz,
    persona,
    system: [perfil, instrucoesDeBastidor(persona, TAREFA)].filter(Boolean).join("\n\n---\n\n"),
    prompt: montarPedidoMigracao(memoriaMd),
    memoria: m,
    exigirGravacao: true,
    origem: ORIGEM_MIGRACAO,
  })
}

export async function corposDaPersona(m: Memoria, persona: Conselheiro): Promise<string[]> {
  const resumos = await m.listar(persona)
  const paginas = await Promise.all(resumos.map((r) => m.ler(persona, r.path)))
  return paginas.filter((p): p is Pagina => p !== null).map((p) => p.corpo)
}

export type ResultadoMigracao = "sem-arquivo" | "migrada" | { faltando: string[] }

export async function migrarUma(
  raiz: string,
  m: Memoria,
  persona: Conselheiro,
  opcoes: { soVerificar?: boolean } = {},
): Promise<ResultadoMigracao> {
  const caminho = join(raiz, "profiles", persona, "memory.md")
  const arquivo = Bun.file(caminho)
  if (!(await arquivo.exists())) return "sem-arquivo"
  const memoriaMd = await arquivo.text()
  let faltando = itensNaoCobertos(memoriaMd, await corposDaPersona(m, persona))
  if (faltando.length && !opcoes.soVerificar) {
    const nenhumCoberto = faltando.length === itensDaMemoria(memoriaMd).length
    await migrarPersona(raiz, m, persona, nenhumCoberto ? memoriaMd : faltando.join("\n"))
    faltando = itensNaoCobertos(memoriaMd, await corposDaPersona(m, persona))
  }
  if (faltando.length) return { faltando }
  if (!opcoes.soVerificar) await rm(caminho)
  return "migrada"
}

// Refazer sozinho uma migração incompleta duplicaria páginas; quem resolve é o script.
export async function migrarPendentes(raiz: string, m: Memoria): Promise<void> {
  const estado = await lerEstado(raiz)
  for (const persona of CONSELHEIROS) {
    if (estado.migracaoBloqueada?.[persona]) continue
    const resultado = await migrarUma(raiz, m, persona)
    if (resultado === "migrada") console.log(`[memoria] memory.md de ${persona} migrado e removido`)
    if (typeof resultado === "object") {
      await alterarEstado(raiz, (e) => {
        e.migracaoBloqueada = { ...e.migracaoBloqueada, [persona]: resultado.faltando }
      })
      console.warn(
        `[memoria] migração de ${persona} incompleta; memory.md mantido. Resolva com scripts/migrar-memoria.ts. Faltou: ${resultado.faltando.join(" | ")}`,
      )
    }
  }
}
