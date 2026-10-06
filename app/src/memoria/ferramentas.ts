import { createSdkMcpServer, tool } from "@anthropic-ai/claude-agent-sdk"
import { z } from "zod"
import type { Conselheiro } from "../tipos"
import { dataLocal, slug } from "../texto"
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

export const FERRAMENTAS_MEMORIA_CONSOLIDACAO = [
  ...FERRAMENTAS_MEMORIA,
  "mcp__memoria__atualizar_lembranca",
  "mcp__memoria__fundir_lembrancas",
]

const INDISPONIVEL = "Memória indisponível agora. Siga a conversa sem ela."

function hoje(): string {
  return dataLocal()
}

export function caminhoNovo(tipo: TipoLembranca, titulo: string, data: string = hoje()): string {
  const base = slug(titulo) || "lembranca"
  return `${prefixoDe(tipo)}${tipo === "episodio" ? `${data}-` : ""}${base}.md`
}

export interface Placar {
  gravacoes: number
  indisponivel: number
}

export function placarVazio(): Placar {
  return { gravacoes: 0, indisponivel: 0 }
}

// O projeto nunca vem do modelo: é fixado aqui, na criação, e nenhuma ação aceita outro.
export function acoesDaPersona(m: Memoria, persona: Conselheiro, origem: string, placar: Placar = placarVazio()) {
  const tags = [`origem:${origem}`]

  async function protegido(acao: () => Promise<string>): Promise<string> {
    try {
      return await acao()
    } catch (erro) {
      if (erro instanceof MemoriaIndisponivel) {
        placar.indisponivel++
        return INDISPONIVEL
      }
      return `Não deu certo: ${(erro as Error).message}`
    }
  }

  async function gravar(pagina: Parameters<Memoria["gravar"]>[1]): Promise<void> {
    await m.gravar(persona, pagina)
    placar.gravacoes++
  }

  async function caminhoLivre(tipo: TipoLembranca, titulo: string): Promise<string> {
    const base = caminhoNovo(tipo, titulo)
    if (!(await m.ler(persona, base))) return base
    for (let n = 2; n < 100; n++) {
      const alternativo = base.replace(/\.md$/, `-${n}.md`)
      if (!(await m.ler(persona, alternativo))) return alternativo
    }
    throw new Error(`já existem lembranças demais com o título "${titulo}"`)
  }

  return {
    recordar: ({ consulta }: { consulta: string }) =>
      protegido(async () => {
        const [proprios, coletivo] = await Promise.all([
          m.buscar(persona, consulta, 8),
          m.buscar(COLETIVO, consulta, 5),
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
        const path = await caminhoLivre(tipo, titulo)
        await gravar({
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
        await gravar({ path: caminho, corpo, tier: tierDe(tipo), pinned: tipo === "jeito", tags })
        return `Atualizado ${caminho}.`
      }),

    // A original vira um aviso que expira na hora: some da busca e do conjunto frio, e a
    // versão anterior continua no histórico do ai-memory.
    fundirLembrancas: ({ destino, titulo, texto, origens }: { destino: string; titulo: string; texto: string; origens: string[] }) =>
      protegido(async () => {
        const tipo = tipoDoCaminho(destino)
        if (!caminhoValido(destino) || !tipo) return `Caminho inválido: ${destino}`
        const invalidas = origens.filter((o) => !caminhoValido(o) || !tipoDoCaminho(o))
        if (invalidas.length) return `Caminho inválido: ${invalidas.join(", ")}`
        const outras = [...new Set(origens)].filter((o) => o !== destino)
        const existentes = await Promise.all(outras.map((o) => m.ler(persona, o)))
        const ausentes = outras.filter((_, i) => !existentes[i])
        if (ausentes.length) return `Não existem lembranças suas em: ${ausentes.join(", ")}`
        await gravar({
          path: destino,
          corpo: `# ${titulo.trim()}\n\n${texto.trim()}\n`,
          tier: tierDe(tipo),
          pinned: tipo === "jeito",
          tags,
        })
        const agora = new Date().toISOString()
        for (const origem of outras) {
          await gravar({
            path: origem,
            corpo: `# Fundida em ${destino}\n\nEsta lembrança foi fundida em ${destino}.\n`,
            tier: tierDe(tipoDoCaminho(origem)!),
            pinned: false,
            tags,
            expiraEm: agora,
          })
        }
        return `Fundidas ${outras.length} lembrança(s) em ${destino}.`
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
  opcoes: { atualizar: boolean; placar?: Placar } = { atualizar: false },
) {
  const acoes = acoesDaPersona(m, persona, origem, opcoes.placar)
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
      tool(
        "fundir_lembrancas",
        "Junta várias lembranças suas numa só, em destino. As originais deixam de aparecer; a versão antiga fica guardada.",
        {
          destino: z.string().min(1),
          titulo: z.string().min(1),
          texto: z.string().min(1),
          origens: z.array(z.string().min(1)).min(1),
        },
        async (args) => resposta(await acoes.fundirLembrancas(args)),
      ),
    )
  }
  return createSdkMcpServer({ name: "memoria", version: "1.0.0", tools: ferramentas })
}
