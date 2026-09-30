import { join, resolve } from "node:path"
import { randomUUID } from "node:crypto"
import type { ServerWebSocket } from "bun"
import { PERFIS, ehConselheiro, type Anexo, type Perfil } from "./tipos"
import { gravarAnexo, lerAnexo, lerAnexos, mimeDeEntrega, montarBlocoDeAnexos } from "./anexos"
import { carregarAtalhos } from "./atalhos"
import { conversar } from "./sessions"
import { convocarBoard } from "./board"
import { enderecos, respostaEnderecos } from "./rede"
import { lerDecisoes, lerDecisao } from "./decisions"
import { apagarSessao } from "./sessao-sdk"
import { memoriaHttp } from "./memoria/cliente"
import { espelharColetivo } from "./memoria/coletivo"
import { iniciarAgenda } from "./memoria/agenda"
import { consolidarConversa, conversasPendentes } from "./memoria/consolidacao"
import { sonhar } from "./memoria/sonho"
import {
  criarConversa,
  atualizarMeta,
  lerMeta,
  anexarMensagem,
  lerMensagens,
  listarConversas,
  excluirConversa,
} from "./store"

const RAIZ = resolve(import.meta.dir, "..", "..")
const PORTA = Number(process.env.TOWER_PORTA ?? 7878)
const MEMORIA = memoriaHttp()

function espelharEmSegundoPlano(): void {
  void espelharColetivo(RAIZ, MEMORIA).catch((erro: Error) =>
    console.warn(`[memoria] espelho do coletivo falhou — ${erro.message}`),
  )
}

const ESTATICOS: Record<string, string> = {
  "/": "index.html",
  "/index.html": "index.html",
  "/app.js": "app.js",
  "/style.css": "style.css",
  "/manifest.webmanifest": "manifest.webmanifest",
  "/icone.svg": "icone.svg",
  "/icone-192.png": "icone-192.png",
  "/icone-512.png": "icone-512.png",
}

type Cliente = ServerWebSocket<undefined>

function mandar(ws: Cliente, msg: Record<string, unknown>): void {
  ws.send(JSON.stringify(msg))
}

// ── permissão de comando do executor ───────────────────────────────

const PRAZO_PERMISSAO = 120_000

interface Pendente {
  ws: Cliente
  resolver: (permitido: boolean) => void
  prazo: ReturnType<typeof setTimeout>
}

const pendentes = new Map<string, Pendente>()

function resolverPermissao(id: string, permitido: boolean): void {
  const pendente = pendentes.get(id)
  if (!pendente) return
  clearTimeout(pendente.prazo)
  pendentes.delete(id)
  pendente.resolver(permitido)
}

// Em modo auto o comando não é barrado, mas aparece no chat: senão o auto seria caixa
// preta e o Ueslei descobriria o que rodou pelo efeito colateral.
function tratarComando(ws: Cliente, comando: string, aprovar: boolean): Promise<boolean> {
  if (!aprovar) {
    mandar(ws, { tipo: "comando", comando })
    return Promise.resolve(true)
  }
  const id = randomUUID()
  return new Promise((resolver) => {
    // Sem prazo, uma aba fechada deixaria o executor esperando para sempre.
    const prazo = setTimeout(() => resolverPermissao(id, false), PRAZO_PERMISSAO)
    pendentes.set(id, { ws, resolver, prazo })
    mandar(ws, { tipo: "permissao", id, comando })
  })
}

async function responderNaConversa(
  ws: Cliente,
  id: string,
  texto: string,
  citacao?: string,
  modelo?: string,
  anexos: Anexo[] = [],
  auto?: boolean,
): Promise<void> {
  let meta = await lerMeta(RAIZ, id)
  if (modelo !== undefined && modelo !== (meta.modelo ?? "")) {
    meta = await atualizarMeta(RAIZ, id, { modelo: modelo || undefined })
  }
  if (auto !== undefined && auto !== (meta.auto ?? false)) {
    meta = await atualizarMeta(RAIZ, id, { auto })
  }
  const agora = new Date().toISOString()
  await anexarMensagem(RAIZ, id, {
    role: "user",
    texto,
    ts: agora,
    perfil: meta.perfil,
    citacao,
    anexos: anexos.length ? anexos : undefined,
  })

  const textoParaModelo = [
    montarBlocoDeAnexos(anexos, RAIZ),
    citacao ? `[Estou respondendo especificamente a este trecho seu: "${citacao}"]` : "",
    texto,
  ]
    .filter(Boolean)
    .join("\n\n")

  const resposta = await conversar({
    raiz: RAIZ,
    perfil: meta.perfil,
    texto: textoParaModelo,
    sessionId: meta.sessionId,
    modelo: meta.modelo,
    auto: meta.auto,
    foco: meta.foco,
    memoria: MEMORIA,
    conversaId: id,
    consulta: texto,
    onChunk: (pedaco) => mandar(ws, { tipo: "chunk", conversaId: id, perfil: meta.perfil, texto: pedaco }),
    onComando: (comando, aprovar) => tratarComando(ws, comando, aprovar),
  })

  await anexarMensagem(RAIZ, id, {
    role: "assistant",
    texto: resposta.texto,
    ts: new Date().toISOString(),
    perfil: meta.perfil,
  })
  if (resposta.sessionId && resposta.sessionId !== meta.sessionId) {
    await atualizarMeta(RAIZ, id, { sessionId: resposta.sessionId })
  }
  mandar(ws, { tipo: "fim", conversaId: id })
  if (ehConselheiro(meta.perfil)) espelharEmSegundoPlano()
}

async function resolverAnexos(ws: Cliente, ids: unknown): Promise<Anexo[]> {
  if (!Array.isArray(ids) || !ids.length) return []
  const pedidos = ids.map(String)
  const achados = await lerAnexos(RAIZ, pedidos)
  const perdidos = pedidos.length - achados.length
  if (perdidos > 0) {
    mandar(ws, { tipo: "aviso", texto: `${perdidos} anexo(s) não encontrado(s) e ignorado(s).` })
  }
  return achados
}

async function tratar(ws: Cliente, bruto: string): Promise<void> {
  const msg = JSON.parse(bruto) as Record<string, unknown>

  switch (msg.tipo) {
    case "listar": {
      mandar(ws, { tipo: "conversas", lista: await listarConversas(RAIZ) })
      return
    }
    case "nova": {
      const perfil = msg.perfil as Perfil
      const texto = String(msg.texto ?? "").trim()
      const anexos = await resolverAnexos(ws, msg.anexos)
      if (!PERFIS.includes(perfil)) throw new Error("perfil inválido")
      if (!texto && !anexos.length) throw new Error("mensagem vazia")
      const base = texto || anexos[0]!.nome
      const titulo = base.length > 48 ? `${base.slice(0, 48)}…` : base
      const modelo = msg.modelo ? String(msg.modelo) : undefined
      const meta = await criarConversa(RAIZ, perfil, titulo, modelo, {
        auto: msg.auto === true ? true : undefined,
        foco: msg.foco === "ticktask" ? "ticktask" : undefined,
      })
      mandar(ws, { tipo: "criada", meta })
      await responderNaConversa(
        ws,
        meta.id,
        texto,
        msg.citacao ? String(msg.citacao) : undefined,
        undefined,
        anexos,
      )
      return
    }
    case "mensagem": {
      const id = String(msg.conversaId ?? "")
      const texto = String(msg.texto ?? "").trim()
      const anexos = await resolverAnexos(ws, msg.anexos)
      if (!id) throw new Error("conversa inválida")
      if (!texto && !anexos.length) throw new Error("mensagem vazia")
      await responderNaConversa(
        ws,
        id,
        texto,
        msg.citacao ? String(msg.citacao) : undefined,
        msg.modelo !== undefined ? String(msg.modelo) : undefined,
        anexos,
        msg.auto !== undefined ? msg.auto === true : undefined,
      )
      return
    }
    case "permissao-resposta": {
      resolverPermissao(String(msg.id ?? ""), Boolean(msg.permitido))
      return
    }
    case "excluir": {
      const id = String(msg.conversaId ?? "")
      const sessionId = await excluirConversa(RAIZ, id)
      await apagarSessao(RAIZ, sessionId)
      mandar(ws, { tipo: "excluida", id })
      mandar(ws, { tipo: "conversas", lista: await listarConversas(RAIZ) })
      return
    }
    case "abrir": {
      const id = String(msg.conversaId ?? "")
      const meta = await lerMeta(RAIZ, id)
      mandar(ws, { tipo: "conversa", meta, mensagens: await lerMensagens(RAIZ, id) })
      return
    }
    case "board": {
      const pauta = String(msg.pauta ?? "").trim()
      if (!pauta) throw new Error("pauta vazia")
      const contexto = msg.contexto ? String(msg.contexto) : undefined
      const resultado = await convocarBoard(RAIZ, pauta, contexto, (texto) =>
        mandar(ws, { tipo: "board-status", texto }),
        MEMORIA,
      )
      espelharEmSegundoPlano()
      mandar(ws, { tipo: "board-sintese", texto: resultado.sintese, ata: resultado.ata })
      return
    }
    case "decisoes": {
      mandar(ws, { tipo: "decisoes", lista: await lerDecisoes(RAIZ) })
      return
    }
    case "decisao": {
      const id = String(msg.id ?? "")
      const conteudo = await lerDecisao(RAIZ, id)
      if (conteudo === null) throw new Error(`decisão "${id}" não encontrada`)
      mandar(ws, { tipo: "decisao", id, conteudo })
      return
    }
    default:
      throw new Error(`tipo de mensagem desconhecido: ${String(msg.tipo)}`)
  }
}

async function receberAnexo(req: Request): Promise<Response> {
  let arquivo: FormDataEntryValue | null
  try {
    arquivo = (await req.formData()).get("arquivo")
  } catch {
    return Response.json({ erro: "corpo inválido" }, { status: 400 })
  }
  if (!(arquivo instanceof File)) {
    return Response.json({ erro: 'mande o arquivo no campo "arquivo"' }, { status: 400 })
  }
  try {
    const anexo = await gravarAnexo(RAIZ, arquivo.name, arquivo.type, await arquivo.arrayBuffer())
    return Response.json(anexo)
  } catch (erro) {
    return Response.json({ erro: (erro as Error).message }, { status: 400 })
  }
}

async function entregarAnexo(id: string): Promise<Response> {
  const anexo = await lerAnexo(RAIZ, id)
  if (!anexo) return new Response("anexo não encontrado", { status: 404 })
  return new Response(Bun.file(join(RAIZ, anexo.arquivo)), {
    headers: {
      "content-type": mimeDeEntrega(anexo),
      "content-disposition": `inline; filename*=UTF-8''${encodeURIComponent(anexo.nome)}`,
      "x-content-type-options": "nosniff",
      "cache-control": "no-store",
    },
  })
}

const servidor = Bun.serve({
  hostname: "0.0.0.0",
  port: PORTA,
  async fetch(req, server) {
    const url = new URL(req.url)
    if (url.pathname === "/ws") {
      return server.upgrade(req) ? undefined : new Response("upgrade falhou", { status: 400 })
    }
    if (url.pathname === "/enderecos") return Response.json(respostaEnderecos(PORTA))
    if (url.pathname === "/anexo" && req.method === "POST") return receberAnexo(req)
    if (url.pathname.startsWith("/anexo/")) {
      return entregarAnexo(decodeURIComponent(url.pathname.slice("/anexo/".length)))
    }
    const nome = ESTATICOS[url.pathname]
    if (nome) {
      // Sem isto o navegador do celular serve UI velha do cache e a edição
      // parece não ter surtido efeito.
      return new Response(Bun.file(join(import.meta.dir, "..", "web", nome)), {
        headers: { "cache-control": "no-store" },
      })
    }
    return new Response("não encontrado", { status: 404 })
  },
  websocket: {
    // Relido a cada conexão: editar atalhos.md e recarregar a página basta.
    open(ws: Cliente) {
      void carregarAtalhos(RAIZ).then((lista) => mandar(ws, { tipo: "atalhos", lista }))
    },
    message(ws: Cliente, dados) {
      void tratar(ws, String(dados)).catch((erro: Error) => {
        mandar(ws, { tipo: "erro", mensagem: erro.message })
      })
    },
    close(ws: Cliente) {
      for (const [id, pendente] of pendentes) {
        if (pendente.ws === ws) resolverPermissao(id, false)
      }
    },
  },
})

espelharEmSegundoPlano()
iniciarAgenda(RAIZ, {
  pendentes: (agora) => conversasPendentes(RAIZ, agora),
  consolidar: (meta) => consolidarConversa(RAIZ, MEMORIA, meta),
  sonhar: (persona) => sonhar(RAIZ, MEMORIA, persona),
})

const rede = enderecos()
console.log(`control-tower de pé (raiz: ${RAIZ})`)
console.log(`  local:     http://localhost:${servidor.port}`)
if (rede.lan) console.log(`  rede:      http://${rede.lan}:${servidor.port}`)
if (rede.tailscale) console.log(`  tailscale: http://${rede.tailscale}:${servidor.port}`)
