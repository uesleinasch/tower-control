import { describe, expect, test } from "bun:test"
import { parseFrontmatter, linhaIndice } from "./decisions"
import { montarPautaParecer } from "./prompt"
import { slug } from "./board"

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
