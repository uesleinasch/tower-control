import { join } from "node:path"
import { describe, expect, test } from "bun:test"
import { parseFrontmatter, linhaIndice } from "./decisions"
import { montarPautaParecer, montarSystemPrompt, politicaDeTamanho } from "./prompt"
import { slug } from "./board"
import { lerAtalhos } from "./atalhos"
import { CONSELHEIROS, PERFIS, ehConselheiro } from "./tipos"
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
