import { Client } from "@modelcontextprotocol/sdk/client/index.js"
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js"
import {
  MemoriaIndisponivel,
  WORKSPACE,
  type Memoria,
  type NovaPagina,
  type Pagina,
  type Projeto,
  type Resumo,
  type Trecho,
} from "./tipos"

export const URL_PADRAO = process.env.CT_MEMORIA_URL ?? "http://127.0.0.1:49374"

export function limparTrecho(snippet: string): string {
  return snippet.replace(/<\/?mark>/g, "").replace(/\s+/g, " ").trim()
}

function caminhoNaUrl(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/")
}

export function memoriaHttp(url: string = URL_PADRAO): Memoria {
  let conexao: Promise<Client> | null = null

  function conectar(): Promise<Client> {
    conexao ??= (async () => {
      const cliente = new Client({ name: "control-tower", version: "1.0.0" })
      await cliente.connect(new StreamableHTTPClientTransport(new URL("/mcp", url)))
      return cliente
    })()
    return conexao
  }

  async function chamar<T>(nome: string, args: Record<string, unknown>): Promise<T> {
    let resultado
    try {
      const cliente = await conectar()
      resultado = await cliente.callTool({ name: nome, arguments: args })
    } catch (erro) {
      const antiga = conexao
      conexao = null
      void antiga?.then((c) => c.close()).catch(() => {})
      throw new MemoriaIndisponivel((erro as Error).message)
    }
    const conteudo = (resultado.content as { type: string; text?: string }[] | undefined) ?? []
    const texto = conteudo.find((c) => c.type === "text")?.text ?? ""
    if (resultado.isError) throw new Error(`${nome}: ${texto}`)
    return JSON.parse(texto) as T
  }

  async function rest<T>(caminho: string): Promise<T | null> {
    let resposta: Response
    try {
      resposta = await fetch(new URL(caminho, url))
    } catch (erro) {
      throw new MemoriaIndisponivel((erro as Error).message)
    }
    if (resposta.status === 404) return null
    if (!resposta.ok) throw new Error(`${caminho}: HTTP ${resposta.status}`)
    return (await resposta.json()) as T
  }

  const base = (projeto: Projeto) =>
    `/api/v1/workspaces/${encodeURIComponent(WORKSPACE)}/projects/${encodeURIComponent(projeto)}/pages`

  return {
    async buscar(projeto, consulta, limite) {
      const r = await chamar<{ hits?: { path: string; title?: string; snippet?: string }[] }>("memory_query", {
        query: consulta,
        limit: limite,
        workspace: WORKSPACE,
        project: projeto,
      })
      return (r.hits ?? []).map<Trecho>((h) => ({
        path: h.path,
        titulo: h.title ?? h.path,
        trecho: limparTrecho(h.snippet ?? ""),
      }))
    },

    async listar(projeto) {
      const r = await rest<{ pages?: { path: string; title?: string; tier?: string; updated_at?: string }[] }>(
        base(projeto),
      )
      return (r?.pages ?? []).map<Resumo>((p) => ({
        path: p.path,
        titulo: p.title ?? p.path,
        tier: p.tier ?? "",
        atualizadaEm: p.updated_at ?? "",
      }))
    },

    async ler(projeto, path) {
      const r = await rest<{ path: string; title?: string; body?: string; tier?: string; pinned?: boolean }>(
        `${base(projeto)}/${caminhoNaUrl(path)}`,
      )
      if (!r) return null
      return {
        path: r.path,
        titulo: r.title ?? r.path,
        corpo: r.body ?? "",
        tier: r.tier ?? "",
        pinned: r.pinned === true,
      } satisfies Pagina
    },

    async gravar(projeto, pagina: NovaPagina) {
      await chamar("memory_write_page", {
        workspace: WORKSPACE,
        project: projeto,
        path: pagina.path,
        body: pagina.corpo,
        tier: pagina.tier,
        pinned: pagina.pinned,
        tags: pagina.tags,
      })
    },

    async frias(projeto, limite) {
      const r = await chamar<{ evicted?: { path: string }[] }>("memory_forget_sweep", {
        workspace: WORKSPACE,
        project: projeto,
        dry_run: true,
      })
      return (r.evicted ?? []).map((e) => e.path).slice(0, limite)
    },
  }
}
