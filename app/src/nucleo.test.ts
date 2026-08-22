import { describe, expect, test } from "bun:test"
import { parseFrontmatter, linhaIndice } from "./decisions"
import { montarPautaParecer } from "./prompt"
import { slug } from "./board"
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
