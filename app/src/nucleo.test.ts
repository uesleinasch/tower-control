import { join } from "node:path"
import { tmpdir } from "node:os"
import { mkdir, mkdtemp, rm } from "node:fs/promises"
import { describe, expect, test } from "bun:test"
import { parseFrontmatter, linhaIndice } from "./decisions"
import { montarPautaParecer, montarSystemPrompt, politicaDeTamanho } from "./prompt"
import { slug } from "./board"
import { lerAtalhos } from "./atalhos"
import { tiposEmitidos, tiposTratados, type Protocolo } from "./protocolo"
import { respostaEnderecos } from "./rede"
import { CONSELHEIROS, PERFIS, ehConselheiro } from "./tipos"
import { anexarMensagem, atualizarMeta, criarConversa, excluirConversa, idValido } from "./store"
import { apagarSessao, diretorioDeSessoes } from "./sessao-sdk"
import type { Anexo } from "./tipos"
import {
  classificarAnexo,
  extensaoSegura,
  formatarTamanho,
  mimeDeEntrega,
  montarBlocoDeAnexos,
  nomeExibivel,
} from "./anexos"

describe("parseFrontmatter", () => {
  test("extrai campos simples e listas", () => {
    const campos = parseFrontmatter(
      "---\nid: 2026-08-22-x\ntitle: Título com acento\nstatus: aceita\ntags: [a, b]\n---\ncorpo",
    )
    expect(campos.id).toBe("2026-08-22-x")
    expect(campos.title).toBe("Título com acento")
    expect(campos.tags).toEqual(["a", "b"])
  })

  test("sem frontmatter retorna vazio", () => {
    expect(parseFrontmatter("# só corpo")).toEqual({})
  })
})

test("linhaIndice segue o formato do INDEX.md", () => {
  const linha = linhaIndice({
    id: "2026-08-22-x",
    date: "2026-08-22",
    title: "Decisão X",
    status: "proposta",
    tags: ["a", "b"],
    projeto: "p",
    participantes: [],
    arquivo: "2026-08-22-x.md",
  })
  expect(linha).toBe("- 2026-08-22 · proposta · [Decisão X](2026-08-22-x.md) · a, b")
})

test("slug remove acentos e caracteres inválidos", () => {
  expect(slug("Migração p/ Órbita — v2!")).toBe("migracao-p-orbita-v2")
})

test("montarPautaParecer inclui contexto só quando existe", () => {
  expect(montarPautaParecer("Pauta A")).not.toContain("Contexto fornecido")
  expect(montarPautaParecer("Pauta A", "ctx")).toContain("## Contexto fornecido\n\nctx")
})

describe("lerAtalhos", () => {
  test("separa rótulo do texto no ::", () => {
    expect(lerAtalhos("- breve :: seja breve, só a conclusão")).toEqual([
      { rotulo: "breve", texto: "seja breve, só a conclusão" },
    ])
  })

  test("sem :: o texto serve de rótulo", () => {
    expect(lerAtalhos("- valeu")).toEqual([{ rotulo: "valeu", texto: "valeu" }])
  })

  test("ignora prosa, título e linha sem texto", () => {
    const md = [
      "# Atalhos",
      "",
      "Um por linha, no formato `- rótulo :: texto`.",
      "- breve :: seja breve",
      "- vazio ::",
      "",
    ].join("\n")
    expect(lerAtalhos(md)).toEqual([{ rotulo: "breve", texto: "seja breve" }])
  })

  test("rótulo vazio cai para o texto", () => {
    expect(lerAtalhos("-  :: qual o risco?")).toEqual([
      { rotulo: "qual o risco?", texto: "qual o risco?" },
    ])
  })
})

describe("politicaDeTamanho", () => {
  test("o Poe ganha piso curto; os outros seguem a regra antiga", () => {
    expect(politicaDeTamanho("poe")).toContain("é sempre o menor")
    expect(politicaDeTamanho("poe")).toContain("Cinco palavras")
    expect(politicaDeTamanho("nati")).not.toContain("é sempre o menor")
  })

  test("os três perfis sem política própria compartilham a mesma", () => {
    expect(politicaDeTamanho("nati")).toBe(politicaDeTamanho("lucas"))
    expect(politicaDeTamanho("nati")).toBe(politicaDeTamanho("pami"))
  })
})

test("montarSystemPrompt injeta a política do perfil", async () => {
  const raiz = join(import.meta.dir, "..", "..")
  const system = await montarSystemPrompt(raiz, "poe")
  expect(system).toContain("## Tamanho da resposta")
  expect(system).toContain("é sempre o menor")
})

describe("conselheiro e executor", () => {
  test("alfred é perfil mas não é conselheiro", () => {
    expect(PERFIS).toContain("alfred")
    expect(CONSELHEIROS).not.toContain("alfred")
    expect(ehConselheiro("alfred")).toBe(false)
    expect(ehConselheiro("poe")).toBe(true)
  })

  test("o executor não recebe as instruções de conselheiro", async () => {
    const raiz = join(import.meta.dir, "..", "..")
    const alfred = await montarSystemPrompt(raiz, "alfred")
    expect(alfred).toContain("o executor do control-tower")
    expect(alfred).not.toContain("decisions/AAAA-MM-DD")
    expect(alfred).not.toContain("PODE atualizar")
  })

  test("o conselheiro segue recebendo memória e registro de decisão", async () => {
    const raiz = join(import.meta.dir, "..", "..")
    const poe = await montarSystemPrompt(raiz, "poe")
    expect(poe).toContain("decisions/AAAA-MM-DD")
    expect(poe).toContain("PODE atualizar")
  })
})

describe("classificarAnexo", () => {
  test("reconhece imagem, pdf e texto pelo mime", () => {
    expect(classificarAnexo("image/png", "a.png")).toBe("imagem")
    expect(classificarAnexo("application/pdf", "a.pdf")).toBe("pdf")
    expect(classificarAnexo("text/plain; charset=utf-8", "a.txt")).toBe("texto")
  })

  test("cai na extensão quando o navegador manda mime genérico", () => {
    expect(classificarAnexo("application/octet-stream", "erro.log")).toBe("texto")
    expect(classificarAnexo("", "server.ts")).toBe("texto")
  })

  test("recusa o que não é imagem, pdf nem texto", () => {
    expect(classificarAnexo("application/octet-stream", "instalador.exe")).toBeNull()
    expect(classificarAnexo("video/mp4", "clipe.mp4")).toBeNull()
  })
})

describe("extensaoSegura", () => {
  test("preserva extensão simples e normaliza caixa", () => {
    expect(extensaoSegura("relatorio.PDF")).toBe("pdf")
    expect(extensaoSegura("erro.log")).toBe("log")
  })

  test("nome com travessia de caminho não vira extensão", () => {
    expect(extensaoSegura("../../etc/passwd")).toBe("txt")
    expect(extensaoSegura("foto.png/../../x")).toBe("txt")
    expect(extensaoSegura("sem-ponto")).toBe("txt")
  })
})

test("nomeExibivel tira quebra de linha e limita o tamanho", () => {
  expect(nomeExibivel("a\nb\tc ")).toBe("a b c")
  expect(nomeExibivel("x".repeat(200))).toHaveLength(120)
  expect(nomeExibivel("   ")).toBe("arquivo")
})

test("formatarTamanho usa vírgula e não deixa decimal zerado", () => {
  expect(formatarTamanho(512)).toBe("512 B")
  expect(formatarTamanho(2048)).toBe("2 kB")
  expect(formatarTamanho(10 * 1024 * 1024)).toBe("10 MB")
  expect(formatarTamanho(2_202_010)).toBe("2,1 MB")
})

test("mimeDeEntrega nunca devolve html do cliente", () => {
  const base = { id: "x", nome: "x", bytes: 1, arquivo: "a" }
  expect(mimeDeEntrega({ ...base, tipo: "texto", mime: "text/html" })).toBe("text/plain; charset=utf-8")
  expect(mimeDeEntrega({ ...base, tipo: "imagem", mime: "image/webp" })).toBe("image/webp")
  expect(mimeDeEntrega({ ...base, tipo: "pdf", mime: "text/html" })).toBe("application/pdf")
})

describe("montarBlocoDeAnexos", () => {
  const anexo = {
    id: "mt4a-1b2c3d4e",
    nome: "erro-tela.png",
    tipo: "imagem" as const,
    mime: "image/png",
    bytes: 2_202_010,
    arquivo: "conversations/anexos/mt4a-1b2c3d4e.png",
  }

  test("lista caminho absoluto, tipo, nome e tamanho", () => {
    const bloco = montarBlocoDeAnexos([anexo], "/raiz")
    expect(bloco).toContain("ferramenta Read")
    expect(bloco).toContain('/raiz/conversations/anexos/mt4a-1b2c3d4e.png — imagem "erro-tela.png" (2,1 MB)')
  })

  test("sem anexo devolve vazio", () => {
    expect(montarBlocoDeAnexos([], "/raiz")).toBe("")
  })
})

describe("excluirConversa", () => {
  const anexo: Anexo = {
    id: "abc12345",
    nome: "log.txt",
    tipo: "texto",
    mime: "text/plain",
    bytes: 1,
    arquivo: join("conversations", "anexos", "abc12345.txt"),
  }

  async function conversaComAnexo() {
    const raiz = await mkdtemp(join(tmpdir(), "tower-"))
    const meta = await criarConversa(raiz, "poe", "conversa de teste")
    await atualizarMeta(raiz, meta.id, { sessionId: "11111111-2222-3333-4444-555555555555" })
    await mkdir(join(raiz, "conversations", "anexos"), { recursive: true })
    await Bun.write(join(raiz, anexo.arquivo), "conteúdo")
    await Bun.write(join(raiz, "conversations", "anexos", "abc12345.json"), JSON.stringify(anexo))
    await anexarMensagem(raiz, meta.id, {
      role: "user",
      texto: "olha o log",
      ts: new Date().toISOString(),
      perfil: "poe",
      anexos: [anexo],
    })
    return { raiz, id: meta.id }
  }

  const existe = (caminho: string) => Bun.file(caminho).exists()

  test("apaga transcrição, meta e anexos, e devolve o sessionId", async () => {
    const { raiz, id } = await conversaComAnexo()
    const sessionId = await excluirConversa(raiz, id)
    expect(sessionId).toBe("11111111-2222-3333-4444-555555555555")
    expect(await existe(join(raiz, "conversations", `${id}.jsonl`))).toBe(false)
    expect(await existe(join(raiz, "conversations", `${id}.meta.json`))).toBe(false)
    expect(await existe(join(raiz, anexo.arquivo))).toBe(false)
    expect(await existe(join(raiz, "conversations", "anexos", "abc12345.json"))).toBe(false)
    await rm(raiz, { recursive: true, force: true })
  })

  test("não encosta na memória do perfil", async () => {
    const { raiz, id } = await conversaComAnexo()
    await mkdir(join(raiz, "profiles", "poe"), { recursive: true })
    await Bun.write(join(raiz, "profiles", "poe", "memory.md"), "o que o Poe aprendeu")
    await excluirConversa(raiz, id)
    expect(await Bun.file(join(raiz, "profiles", "poe", "memory.md")).text()).toBe(
      "o que o Poe aprendeu",
    )
    await rm(raiz, { recursive: true, force: true })
  })

  test("id fora do formato não vira caminho de arquivo", async () => {
    expect(idValido("2026-08-22-poe-mt49tr4j")).toBe(true)
    expect(idValido("../../etc/passwd")).toBe(false)
    expect(idValido("2026-08-22-poe-mt4/../x")).toBe(false)
    await expect(excluirConversa("/tmp", "../../etc/passwd")).rejects.toThrow("conversa inválida")
  })
})

describe("apagarSessao", () => {
  test("o slug do diretório troca não-alfanuméricos por hífen", () => {
    expect(diretorioDeSessoes("/home/ana/meu.projeto")).toEndWith(
      join(".claude", "projects", "-home-ana-meu-projeto"),
    )
  })

  test("sessionId fora do formato UUID não apaga nada", async () => {
    expect(await apagarSessao("/tmp", undefined)).toBe(false)
    expect(await apagarSessao("/tmp", "../../../etc/passwd")).toBe(false)
    expect(await apagarSessao("/tmp", "nao-e-uuid")).toBe(false)
  })
})

describe("contrato do protocolo", () => {
  const raiz = join(import.meta.dir, "..", "..")
  const ler = (caminho: string) => Bun.file(join(raiz, caminho)).text()

  test("server.ts trata e emite exatamente os tipos de docs/protocolo.json", async () => {
    const protocolo = (await Bun.file(join(raiz, "docs", "protocolo.json")).json()) as Protocolo
    const servidor = await ler("app/src/server.ts")
    expect(tiposTratados(servidor)).toEqual([...protocolo["cliente→servidor"]].sort())
    expect(tiposEmitidos(servidor)).toEqual([...protocolo["servidor→cliente"]].sort())
  })

  test("app.js envia e trata exatamente os tipos de docs/protocolo.json", async () => {
    const protocolo = (await Bun.file(join(raiz, "docs", "protocolo.json")).json()) as Protocolo
    const web = await ler("app/web/app.js")
    expect(tiposEmitidos(web)).toEqual([...protocolo["cliente→servidor"]].sort())
    expect(tiposTratados(web)).toEqual([...protocolo["servidor→cliente"]].sort())
  })

  test("extrai tipos só do switch de mensagens", () => {
    const fonte = 'case "antes"\nswitch (msg.tipo) {\ncase "a": case "b-c":\n}\nmandar({ tipo: "x" })'
    expect(tiposTratados(fonte)).toEqual(["a", "b-c"])
    expect(tiposEmitidos(fonte)).toEqual(["x"])
  })
})

describe("respostaEnderecos", () => {
  test("junta os endereços com a porta e omite interface ausente", () => {
    expect(respostaEnderecos(7878, { lan: "192.168.0.5" })).toEqual({ lan: "192.168.0.5", porta: 7878 })
    expect(respostaEnderecos(7878, {})).toEqual({ porta: 7878 })
  })
})
