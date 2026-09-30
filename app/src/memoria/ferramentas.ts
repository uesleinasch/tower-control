import { createSdkMcpServer, tool } from "@anthropic-ai/claude-agent-sdk"
import { z } from "zod"
import type { Conselheiro } from "../tipos"
import { slug } from "../texto"
import {
  COLETIVO,
  MemoriaIndisponivel,
  caminhoValido,
  prefixoDe,
  tierDe,
  tipoDoCaminho,
  type Memoria,
  type TipoLembranca,
} from "./tipos"

export const FERRAMENTAS_MEMORIA = [
  "mcp__memoria__recordar",
  "mcp__memoria__ler_lembranca",
  "mcp__memoria__lembrar",
]

export const FERRAMENTAS_MEMORIA_CONSOLIDACAO = [...FERRAMENTAS_MEMORIA, "mcp__memoria__atualizar_lembranca"]

const INDISPONIVEL = "Memória indisponível agora. Siga a conversa sem ela."

function hoje(): string {
  return new Date().toISOString().slice(0, 10)
}

export function caminhoNovo(tipo: TipoLembranca, titulo: string, data: string = hoje()): string {
  const base = slug(titulo) || "lembranca"
  return `${prefixoDe(tipo)}${tipo === "episodio" ? `${data}-` : ""}${base}.md`
}

async function protegido(acao: () => Promise<string>): Promise<string> {
  try {
    return await acao()
  } catch (erro) {
    if (erro instanceof MemoriaIndisponivel) return INDISPONIVEL
    return `Não deu certo: ${(erro as Error).message}`
  }
}

// O projeto nunca vem do modelo: é fixado aqui, na criação, e nenhuma ação aceita outro.
export function acoesDaPersona(m: Memoria, persona: Conselheiro, origem: string) {
  const tags = [`origem:${origem}`]

  return {
    recordar: ({ consulta }: { consulta: string }) =>
      protegido(async () => {
        const [proprios, coletivo] = await Promise.all([
          m.buscar(persona, consulta, 8),
          m.buscar(COLETIVO, consulta, 5).catch(() => []),
        ])
        const linhas = [
          ...proprios.map((t) => `- ${t.titulo}: ${t.trecho} (${t.path})`),
          ...coletivo.map((t) => `- [coletivo] ${t.titulo}: ${t.trecho} (${t.path})`),
        ]
        return linhas.length ? linhas.join("\n") : "Nada encontrado."
      }),

    lerLembranca: ({ caminho }: { caminho: string }) =>
      protegido(async () => {
        if (!caminhoValido(caminho)) return `Caminho inválido: ${caminho}`
        const pagina = (await m.ler(persona, caminho)) ?? (await m.ler(COLETIVO, caminho))
        return pagina ? pagina.corpo : `Não existe lembrança em ${caminho}.`
      }),

    lembrar: ({ titulo, texto, tipo }: { titulo: string; texto: string; tipo: TipoLembranca }) =>
      protegido(async () => {
        const path = caminhoNovo(tipo, titulo)
        await m.gravar(persona, {
          path,
          corpo: `# ${titulo.trim()}\n\n${texto.trim()}\n`,
          tier: tierDe(tipo),
          pinned: tipo === "jeito",
          tags,
        })
        return `Guardado em ${path}.`
      }),

    atualizarLembranca: ({ caminho, texto }: { caminho: string; texto: string }) =>
      protegido(async () => {
        const tipo = tipoDoCaminho(caminho)
        if (!caminhoValido(caminho) || !tipo) return `Caminho inválido: ${caminho}`
        const atual = await m.ler(persona, caminho)
        if (!atual) return `Não existe lembrança sua em ${caminho}. Use lembrar para criar.`
        const corpo = /^#\s/.test(texto.trim()) ? `${texto.trim()}\n` : `# ${atual.titulo}\n\n${texto.trim()}\n`
        await m.gravar(persona, { path: caminho, corpo, tier: tierDe(tipo), pinned: tipo === "jeito", tags })
        return `Atualizado ${caminho}.`
      }),
  }
}

const TIPO = z
  .enum(["fato", "episodio", "jeito"])
  .describe("fato: algo verdadeiro sobre o Ueslei ou o mundo dele; episodio: algo que aconteceu; jeito: algo sobre quem você é com ele (opinião, jeito de falar, piada interna)")

function resposta(texto: string) {
  return { content: [{ type: "text" as const, text: texto }] }
}

export function servidorDeMemoria(
  m: Memoria,
  persona: Conselheiro,
  origem: string,
  opcoes: { atualizar: boolean } = { atualizar: false },
) {
  const acoes = acoesDaPersona(m, persona, origem)
  const ferramentas = [
    tool(
      "recordar",
      "Busca nas suas lembranças e nas decisões e atas do coletivo.",
      { consulta: z.string().min(1) },
      async (args) => resposta(await acoes.recordar(args)),
    ),
    tool(
      "ler_lembranca",
      "Lê a lembrança inteira pelo caminho que apareceu na busca.",
      { caminho: z.string().min(1) },
      async (args) => resposta(await acoes.lerLembranca(args)),
    ),
    tool(
      "lembrar",
      "Guarda uma lembrança nova na sua memória.",
      { titulo: z.string().min(1), texto: z.string().min(1), tipo: TIPO },
      async (args) => resposta(await acoes.lembrar(args)),
    ),
  ]
  if (opcoes.atualizar) {
    ferramentas.push(
      tool(
        "atualizar_lembranca",
        "Reescreve uma lembrança sua que já existe. A versão anterior fica guardada.",
        { caminho: z.string().min(1), texto: z.string().min(1) },
        async (args) => resposta(await acoes.atualizarLembranca(args)),
      ),
    )
  }
  return createSdkMcpServer({ name: "memoria", version: "1.0.0", tools: ferramentas })
}
