import { Client } from "@modelcontextprotocol/sdk/client/index.js"
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js"
import { ErrorCode, McpError } from "@modelcontextprotocol/sdk/types.js"
import {
  MemoriaIndisponivel,
  WORKSPACE,
  type Memoria,
  type NovaPagina,
  type Pagina,
  type Resumo,
  type Trecho,
} from "./tipos"

export const URL_PADRAO = process.env.CT_MEMORIA_URL ?? "http://127.0.0.1:49374"

const FALHAS_DE_TRANSPORTE = new Set<number>([ErrorCode.ConnectionClosed, ErrorCode.RequestTimeout])

export function limparTrecho(snippet: string): string {
  return snippet.replace(/<\/?mark>/g, "").replace(/\s+/g, " ").trim()
}

const LIMITE_LISTAGEM = 100

export function ehAusente(erro: Error): boolean {
  return !(erro instanceof MemoriaIndisponivel) && /not found in (resolved scope|workspace)/.test(erro.message)
}

function ausenteComo<T>(vazio: T) {
  return (erro: Error): T => {
    if (ehAusente(erro)) return vazio
    throw erro
  }
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
      if (erro instanceof McpError && !FALHAS_DE_TRANSPORTE.has(erro.code)) {
        throw new Error(`${nome}: ${erro.message}`)
      }
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

  return {
    // Projeto que ainda não recebeu nenhuma página faz o memory_query falhar fechado;
    // para quem busca, isso é só "nada lembrado".
    async buscar(projeto, consulta, limite) {
      const r = await chamar<{ hits?: { path: string; title?: string; snippet?: string }[] }>("memory_query", {
        query: consulta,
        limit: limite,
        workspace: WORKSPACE,
        project: projeto,
      }).catch((erro: Error) => {
        if (erro instanceof MemoriaIndisponivel) throw erro
        return { hits: [] }
      })
      return (r.hits ?? []).map<Trecho>((h) => ({
        path: h.path,
        titulo: h.title ?? h.path,
        trecho: limparTrecho(h.snippet ?? ""),
      }))
    },

    // O memory_recent ordena por updated_at e não pagina: acima de 100 páginas a lista vem cortada.
    async listar(projeto) {
      const r = await chamar<{ hits?: { path: string; title?: string }[] }>("memory_recent", {
        limit: LIMITE_LISTAGEM,
        workspace: WORKSPACE,
        project: projeto,
      }).catch(ausenteComo({ hits: [] }))
      return (r.hits ?? []).map<Resumo>((h) => ({ path: h.path, titulo: h.title ?? h.path }))
    },

    async ler(projeto, path) {
      const r = await chamar<{
        path: string
        title?: string
        body?: string
        frontmatter?: { tier?: string; pinned?: boolean }
      } | null>("memory_read_page", { path, workspace: WORKSPACE, project: projeto }).catch(ausenteComo(null))
      if (!r) return null
      return {
        path: r.path,
        titulo: r.title ?? r.path,
        corpo: r.body ?? "",
        tier: r.frontmatter?.tier ?? "",
        pinned: r.frontmatter?.pinned === true,
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
        ...(pagina.expiraEm ? { expires_at: pagina.expiraEm } : {}),
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
