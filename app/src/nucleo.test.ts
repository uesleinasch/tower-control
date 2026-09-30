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
import {
  MemoriaIndisponivel,
  caminhoValido,
  prefixoDe,
  tierDe,
  tipoDoCaminho,
  type Memoria,
  type NovaPagina,
  type Projeto,
} from "./memoria/tipos"
import { limparTrecho } from "./memoria/cliente"
import { LIMITE_BRIEF, LIMITE_JEITO, comporBrief, montarBrief } from "./memoria/recuperacao"
import { acoesDaPersona, caminhoNovo } from "./memoria/ferramentas"
import { consolidacaoPendente, sonhoDevido } from "./memoria/agenda"
import { montarPedidoSonho, precisaSonhar } from "./memoria/sonho"
import { montarPedidoConsolidacao } from "./memoria/consolidacao"
import { espelharColetivo, paginaDoColetivo } from "./memoria/coletivo"
import { itensDaMemoria, itensNaoCobertos } from "./memoria/migracao"
import type { Mensagem, MetaConversa } from "./tipos"
import type { Pagina } from "./memoria/tipos"

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

  test("o conselheiro recebe as tools de memória e o registro de decisão", async () => {
    const raiz = join(import.meta.dir, "..", "..")
    const poe = await montarSystemPrompt(raiz, "poe")
    expect(poe).toContain("decisions/AAAA-MM-DD")
    expect(poe).toContain("use a ferramenta recordar")
    expect(poe).not.toContain("memory.md")
  })

  test("o brief entra entre o perfil e as instruções da casa", async () => {
    const raiz = join(import.meta.dir, "..", "..")
    const poe = await montarSystemPrompt(raiz, "poe", undefined, "# Minha memória\n\nBRIEF-DE-TESTE")
    const perfil = poe.indexOf("# ")
    const brief = poe.indexOf("BRIEF-DE-TESTE")
    const casa = poe.indexOf("# Instruções da casa")
    expect(perfil).toBeLessThan(brief)
    expect(brief).toBeLessThan(casa)
  })

  test("o executor não recebe brief", async () => {
    const raiz = join(import.meta.dir, "..", "..")
    const alfred = await montarSystemPrompt(raiz, "alfred", undefined, "BRIEF-DE-TESTE")
    expect(alfred).not.toContain("BRIEF-DE-TESTE")
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

// ── memória ─────────────────────────────────────────────────────────

function memoriaFalsa(inicial: Partial<Record<Projeto, NovaPagina[]>> = {}) {
  const paginas = new Map<string, NovaPagina & { atualizadaEm: string }>()
  const gravacoes: { projeto: Projeto; pagina: NovaPagina }[] = []
  let relogio = 0
  const chave = (p: Projeto, path: string) => `${p}::${path}`
  const guardar = (projeto: Projeto, pagina: NovaPagina) => {
    relogio++
    paginas.set(chave(projeto, pagina.path), { ...pagina, atualizadaEm: `2026-09-30T00:00:${String(relogio).padStart(2, "0")}Z` })
  }
  for (const [projeto, lista] of Object.entries(inicial)) for (const p of lista ?? []) guardar(projeto as Projeto, p)
  const doProjeto = (projeto: Projeto) =>
    [...paginas.entries()].filter(([k]) => k.startsWith(`${projeto}::`)).map(([, v]) => v)
  const titulo = (corpo: string, path: string) => /^#\s+(.*)/.exec(corpo)?.[1] ?? path
  const memoria: Memoria = {
    async buscar(projeto, consulta) {
      const termo = consulta.toLowerCase()
      return doProjeto(projeto)
        .filter((p) => p.corpo.toLowerCase().includes(termo))
        .map((p) => ({ path: p.path, titulo: titulo(p.corpo, p.path), trecho: p.corpo.slice(0, 80) }))
    },
    async listar(projeto) {
      return doProjeto(projeto).map((p) => ({ path: p.path, titulo: titulo(p.corpo, p.path), tier: p.tier, atualizadaEm: p.atualizadaEm }))
    },
    async ler(projeto, path) {
      const p = paginas.get(chave(projeto, path))
      return p ? { path, titulo: titulo(p.corpo, path), corpo: p.corpo, tier: p.tier, pinned: p.pinned } : null
    },
    async gravar(projeto, pagina) {
      gravacoes.push({ projeto, pagina })
      guardar(projeto, pagina)
    },
    async frias() {
      return []
    },
  }
  return { memoria, gravacoes }
}

const fora: Memoria = {
  buscar: () => Promise.reject(new MemoriaIndisponivel("recusado")),
  listar: () => Promise.reject(new MemoriaIndisponivel("recusado")),
  ler: () => Promise.reject(new MemoriaIndisponivel("recusado")),
  gravar: () => Promise.reject(new MemoriaIndisponivel("recusado")),
  frias: () => Promise.reject(new MemoriaIndisponivel("recusado")),
}

function pagina(path: string, corpo: string, tier: NovaPagina["tier"] = "semantic"): NovaPagina {
  return { path, corpo, tier, pinned: path.startsWith("jeito/"), tags: [] }
}

describe("caminhos de memória", () => {
  test("aceita só os prefixos conhecidos, em slug, terminando em .md", () => {
    expect(caminhoValido("fatos/trabalho-na-jacto.md")).toBe(true)
    expect(caminhoValido("episodios/2026-09-30-conversa.md")).toBe(true)
    expect(caminhoValido("decisoes/2026-08-22-arquitetura-do-control-tower.md")).toBe(true)
    expect(caminhoValido("../poe/fatos/x.md")).toBe(false)
    expect(caminhoValido("fatos/../../x.md")).toBe(false)
    expect(caminhoValido("/etc/passwd")).toBe(false)
    expect(caminhoValido("fatos/x")).toBe(false)
    expect(caminhoValido("outros/x.md")).toBe(false)
    expect(caminhoValido("fatos/Maiúscula.md")).toBe(false)
  })

  test("tipo decide prefixo e tier", () => {
    expect(prefixoDe("jeito")).toBe("jeito/")
    expect(tierDe("jeito")).toBe("procedural")
    expect(tierDe("episodio")).toBe("episodic")
    expect(tierDe("fato")).toBe("semantic")
    expect(tipoDoCaminho("fatos/a.md")).toBe("fato")
    expect(tipoDoCaminho("decisoes/a.md")).toBeNull()
  })

  test("caminho novo de episódio leva a data, o de fato não", () => {
    expect(caminhoNovo("episodio", "Conversa sobre o pai", "2026-09-30")).toBe("episodios/2026-09-30-conversa-sobre-o-pai.md")
    expect(caminhoNovo("fato", "Trabalha na Jacto")).toBe("fatos/trabalha-na-jacto.md")
    expect(caminhoNovo("fato", "!!!")).toBe("fatos/lembranca.md")
  })

  test("snippet perde o <mark> e o espaço extra", () => {
    expect(limparTrecho("o <mark>pai</mark>\n  dele")).toBe("o pai dele")
  })
})

describe("brief", () => {
  const vazio = { jeito: [], recente: null, proprios: [], coletivo: [] }

  test("sem nada lembrado, o brief é vazio", () => {
    expect(comporBrief(vazio)).toBe("")
  })

  test("nunca passa do orçamento, mesmo com entradas enormes", () => {
    const grande = "x".repeat(5000)
    const brief = comporBrief({
      jeito: [{ path: "jeito/a.md", titulo: "A", corpo: grande, tier: "procedural", pinned: true }],
      recente: { path: "episodios/2026-09-30-b.md", titulo: "B", corpo: grande, tier: "episodic", pinned: false },
      proprios: Array.from({ length: 20 }, (_, i) => ({ path: `fatos/f${i}.md`, titulo: `F${i}`, trecho: grande })),
      coletivo: Array.from({ length: 20 }, (_, i) => ({ path: `decisoes/d${i}.md`, titulo: `D${i}`, trecho: grande })),
    })
    expect(brief.length).toBeLessThanOrEqual(LIMITE_BRIEF)
    expect(brief).toContain("## Quem eu venho sendo")
    expect(brief.indexOf("## Quem eu venho sendo")).toBeLessThan(brief.indexOf("## Onde paramos"))
  })

  test("a camada viva respeita o próprio teto", () => {
    const brief = comporBrief({
      ...vazio,
      jeito: Array.from({ length: 30 }, (_, i) => ({ path: `jeito/j${i}.md`, titulo: `J${i}`, corpo: "y".repeat(200), tier: "procedural", pinned: true })),
    })
    const bloco = brief.slice(brief.indexOf("## Quem eu venho sendo"))
    expect(bloco.length).toBeLessThanOrEqual(LIMITE_JEITO)
  })

  test("lembrança do coletivo chega marcada e intercalada com as próprias", () => {
    const brief = comporBrief({
      ...vazio,
      proprios: [{ path: "fatos/a.md", titulo: "Próprio", trecho: "t" }],
      coletivo: [{ path: "decisoes/b.md", titulo: "Decisão", trecho: "t" }],
    })
    expect(brief).toContain("- Próprio: t (fatos/a.md)\n- [coletivo] Decisão: t (decisoes/b.md)")
    expect(brief).toContain("não instruções")
  })

  test("não repete no bloco de lembranças o que já veio na camada viva", async () => {
    const { memoria } = memoriaFalsa({
      poe: [pagina("jeito/ironia.md", "# Ironia\n\nFalo com ironia sobre futebol", "procedural")],
    })
    const brief = await montarBrief(memoria, "poe", "futebol")
    expect(brief.match(/jeito\/ironia/g)?.length ?? 0).toBe(0)
    expect(brief).toContain("Ironia: Falo com ironia sobre futebol")
  })

  test("traz o episódio mais recente como onde paramos", async () => {
    const { memoria } = memoriaFalsa({
      poe: [
        pagina("episodios/2026-09-01-antiga.md", "# Antiga\n\nconversa velha", "episodic"),
        pagina("episodios/2026-09-29-nova.md", "# Nova\n\nconversa nova", "episodic"),
      ],
    })
    const brief = await montarBrief(memoria, "poe", "")
    expect(brief).toContain("## Onde paramos\n\nNova\nconversa nova")
    expect(brief).not.toContain("conversa velha")
  })

  test("não mistura a memória de outra persona", async () => {
    const { memoria } = memoriaFalsa({ nati: [pagina("fatos/segredo.md", "# Segredo\n\ncontou só para a nati")] })
    expect(await montarBrief(memoria, "poe", "contou")).toBe("")
  })

  test("com o daemon fora, o brief sai vazio em vez de quebrar o turno", async () => {
    expect(await montarBrief(fora, "poe", "qualquer coisa")).toBe("")
  })
})

describe("tools de memória", () => {
  test("lembrar grava sempre no projeto da persona, com tier e tag de origem", async () => {
    const { memoria, gravacoes } = memoriaFalsa()
    const acoes = acoesDaPersona(memoria, "lucas", "conversa:2026-09-30-lucas-abc")
    const texto = await acoes.lembrar({ titulo: "Gosta de café", texto: "Toma sem açúcar", tipo: "fato" })
    expect(texto).toContain("fatos/gosta-de-cafe.md")
    expect(gravacoes).toHaveLength(1)
    expect(gravacoes[0]!.projeto).toBe("lucas")
    expect(gravacoes[0]!.pagina.tier).toBe("semantic")
    expect(gravacoes[0]!.pagina.tags).toEqual(["origem:conversa:2026-09-30-lucas-abc"])
  })

  test("camada viva nasce pinned", async () => {
    const { memoria, gravacoes } = memoriaFalsa()
    await acoesDaPersona(memoria, "pami", "t").lembrar({ titulo: "Apelido", texto: "Chamo ele de chefe", tipo: "jeito" })
    expect(gravacoes[0]!.pagina.pinned).toBe(true)
    expect(gravacoes[0]!.pagina.tier).toBe("procedural")
  })

  test("recordar lê a persona e o coletivo, nunca outra persona", async () => {
    const { memoria } = memoriaFalsa({
      poe: [pagina("fatos/a.md", "# A\n\nfala de viagem")],
      nati: [pagina("fatos/b.md", "# B\n\nviagem secreta")],
      coletivo: [pagina("decisoes/c.md", "# C\n\nviagem aprovada")],
    })
    const texto = await acoesDaPersona(memoria, "poe", "t").recordar({ consulta: "viagem" })
    expect(texto).toContain("fatos/a.md")
    expect(texto).toContain("[coletivo] C")
    expect(texto).not.toContain("secreta")
  })

  test("ler_lembranca recusa caminho fora do formato antes de ir ao daemon", async () => {
    const { memoria } = memoriaFalsa()
    expect(await acoesDaPersona(memoria, "poe", "t").lerLembranca({ caminho: "../nati/fatos/b.md" })).toContain("Caminho inválido")
  })

  test("atualizar só mexe em lembrança da própria persona que já existe", async () => {
    const { memoria, gravacoes } = memoriaFalsa({ coletivo: [pagina("decisoes/c.md", "# C\n\nx")] })
    const acoes = acoesDaPersona(memoria, "poe", "t")
    expect(await acoes.atualizarLembranca({ caminho: "decisoes/c.md", texto: "mudei" })).toContain("Caminho inválido")
    expect(await acoes.atualizarLembranca({ caminho: "fatos/nao-existe.md", texto: "y" })).toContain("Não existe")
    expect(gravacoes).toHaveLength(0)
  })

  test("atualizar mantém o título quando o texto novo não traz um", async () => {
    const { memoria, gravacoes } = memoriaFalsa({ poe: [pagina("fatos/a.md", "# Mora em Pompeia\n\nvelho")] })
    await acoesDaPersona(memoria, "poe", "t").atualizarLembranca({ caminho: "fatos/a.md", texto: "mudou para Marília" })
    expect(gravacoes[0]!.pagina.corpo).toBe("# Mora em Pompeia\n\nmudou para Marília\n")
  })

  test("daemon fora vira resposta para o modelo, não exceção", async () => {
    const texto = await acoesDaPersona(fora, "poe", "t").lembrar({ titulo: "x", texto: "y", tipo: "fato" })
    expect(texto).toContain("Memória indisponível")
  })
})

describe("fundir lembranças", () => {
  test("grava o destino e transforma as origens em aviso que expira", async () => {
    const { memoria, gravacoes } = memoriaFalsa({
      poe: [
        pagina("episodios/2026-09-01-transito.md", "# Trânsito\n\nreclamou da BR", "episodic"),
        pagina("episodios/2026-09-08-transito-de-novo.md", "# Trânsito de novo\n\nBR de novo", "episodic"),
      ],
    })
    const texto = await acoesDaPersona(memoria, "poe", "sonho:2026-09-30").fundirLembrancas({
      destino: "fatos/transito-na-br.md",
      titulo: "Trânsito na BR",
      texto: "Toda semana ele pega trânsito na BR e isso o irrita.",
      origens: ["episodios/2026-09-01-transito.md", "episodios/2026-09-08-transito-de-novo.md"],
    })
    expect(texto).toContain("Fundidas 2")
    expect(gravacoes.map((g) => g.pagina.path)).toEqual([
      "fatos/transito-na-br.md",
      "episodios/2026-09-01-transito.md",
      "episodios/2026-09-08-transito-de-novo.md",
    ])
    expect(gravacoes[1]!.pagina.expiraEm).toBeTruthy()
    expect(gravacoes[0]!.pagina.expiraEm).toBeUndefined()
    expect(gravacoes.every((g) => g.projeto === "poe")).toBe(true)
  })

  test("recusa fundir o que não é da persona", async () => {
    const { memoria, gravacoes } = memoriaFalsa({ nati: [pagina("fatos/x.md", "# X\n\nx")] })
    const texto = await acoesDaPersona(memoria, "poe", "t").fundirLembrancas({
      destino: "fatos/y.md",
      titulo: "Y",
      texto: "y",
      origens: ["fatos/x.md"],
    })
    expect(texto).toContain("Não existem")
    expect(gravacoes).toHaveLength(0)
  })

  test("o aviso de fusão não volta no brief", async () => {
    const { memoria } = memoriaFalsa({
      poe: [pagina("jeito/velho.md", "# Fundida em jeito/novo.md\n\nEsta lembrança foi fundida.", "procedural")],
    })
    expect(await montarBrief(memoria, "poe", "")).toBe("")
  })
})

describe("agenda", () => {
  const meta = (extra: Partial<MetaConversa> = {}): MetaConversa => ({
    id: "2026-09-30-poe-abc",
    perfil: "poe",
    titulo: "t",
    criadaEm: "2026-09-30T10:00:00Z",
    ...extra,
  })
  const msg = (ts: string): Mensagem => ({ role: "user", texto: "oi", ts, perfil: "poe" })

  test("consolida só depois de 30 minutos parada e com trecho novo", () => {
    const mensagens = [msg("2026-09-30T10:00:00Z"), msg("2026-09-30T10:05:00Z")]
    expect(consolidacaoPendente(meta(), mensagens, new Date("2026-09-30T10:20:00Z"))).toBe(false)
    expect(consolidacaoPendente(meta(), mensagens, new Date("2026-09-30T10:35:00Z"))).toBe(true)
    expect(consolidacaoPendente(meta({ consolidadoAte: 2 }), mensagens, new Date("2026-09-30T12:00:00Z"))).toBe(false)
  })

  test("máquina desligada a noite toda ainda consolida na subida", () => {
    expect(consolidacaoPendente(meta(), [msg("2026-09-29T23:00:00Z")], new Date("2026-09-30T09:00:00Z"))).toBe(true)
  })

  test("marcador maior que a conversa não dispara nada", () => {
    expect(consolidacaoPendente(meta({ consolidadoAte: 9 }), [msg("2026-09-29T23:00:00Z")], new Date("2026-09-30T09:00:00Z"))).toBe(false)
  })

  test("o alfred nunca consolida", () => {
    expect(consolidacaoPendente(meta({ perfil: "alfred" }), [msg("2026-09-29T23:00:00Z")], new Date("2026-09-30T09:00:00Z"))).toBe(false)
  })

  const local = (dia: number, h: number, m = 0) => new Date(2026, 8, dia, h, m)

  test("sonha depois do horário se houve atividade desde o último sonho", () => {
    const ultimo = local(29, 7, 35).toISOString()
    const atividade = local(29, 22).toISOString()
    expect(sonhoDevido(ultimo, atividade, local(30, 7, 0), "07:30")).toBe(false)
    expect(sonhoDevido(ultimo, atividade, local(30, 7, 31), "07:30")).toBe(true)
  })

  test("não repete o sonho no mesmo dia", () => {
    const ultimo = local(30, 7, 40).toISOString()
    expect(sonhoDevido(ultimo, local(30, 9).toISOString(), local(30, 23), "07:30")).toBe(false)
  })

  test("sem atividade desde o último sonho, não sonha", () => {
    expect(sonhoDevido(local(28, 8).toISOString(), local(28, 7).toISOString(), local(30, 9), "07:30")).toBe(false)
  })

  test("máquina desligada no horário sonha na primeira subida depois dele", () => {
    const ultimo = local(28, 7, 31).toISOString()
    expect(sonhoDevido(ultimo, local(28, 20).toISOString(), local(30, 14), "07:30")).toBe(true)
  })

  test("sem nenhuma atividade registrada, nunca sonha", () => {
    expect(sonhoDevido(undefined, undefined, local(30, 9))).toBe(false)
  })
})

describe("sonho", () => {
  const p = (path: string, corpo: string): Pagina => ({ path, titulo: path, corpo, tier: "episodic", pinned: false })

  test("só sonha com pelo menos duas frias ou jeito acima do teto", () => {
    expect(precisaSonhar([p("episodios/a.md", "a")], [])).toBe(false)
    expect(precisaSonhar([p("episodios/a.md", "a"), p("episodios/b.md", "b")], [])).toBe(true)
    expect(precisaSonhar([], [p("jeito/a.md", "x".repeat(2000))], 1500)).toBe(true)
  })

  test("o pedido mostra as frias e avisa quando o jeito passou do teto", () => {
    const pedido = montarPedidoSonho([p("episodios/a.md", "reclamou do trânsito")], [p("jeito/j.md", "x".repeat(2000))], 1500)
    expect(pedido).toContain("### episodios/a.md\n\nreclamou do trânsito")
    expect(pedido).toContain("ACIMA do teto")
  })
})

describe("consolidação", () => {
  test("o pedido traz a conversa com autor e hora e o que ela já lembra", () => {
    const pedido = montarPedidoConsolidacao(
      "nati",
      { id: "2026-09-30-nati-abc", perfil: "nati", titulo: "Deploy", criadaEm: "" },
      [
        { role: "user", texto: "o deploy caiu", ts: "2026-09-30T10:00:00Z", perfil: "nati" },
        { role: "assistant", texto: "que log apareceu?", ts: "2026-09-30T10:01:00Z", perfil: "nati" },
      ],
      [{ path: "fatos/deploy.md", titulo: "Deploy", trecho: "usa GitLab" }],
    )
    expect(pedido).toContain("[2026-09-30 10:00] Ueslei: o deploy caiu")
    expect(pedido).toContain("[2026-09-30 10:01] Nati: que log apareceu?")
    expect(pedido).toContain("- Deploy: usa GitLab (fatos/deploy.md)")
  })
})

describe("coletivo", () => {
  test("decisão vira página sem frontmatter, com título e detalhes", () => {
    const nova = paginaDoColetivo(
      "decisao",
      "2026-08-22-arquitetura.md",
      "---\nid: x\ndate: 2026-08-22\ntitle: Arquitetura\nstatus: aceita\ntags: [a, b]\n---\n\n## Contexto\n\ntexto",
    )
    expect(nova?.path).toBe("decisoes/2026-08-22-arquitetura.md")
    expect(nova?.tier).toBe("semantic")
    expect(nova?.corpo).toBe("# Arquitetura\n\n2026-08-22 · aceita · a, b\n\n## Contexto\n\ntexto\n")
  })

  test("ata vai para atas/ como episódio, sem mexer no corpo", () => {
    const nova = paginaDoColetivo("ata", "2026-09-01-pauta.md", "# Ata do board\n\ncorpo")
    expect(nova?.path).toBe("atas/2026-09-01-pauta.md")
    expect(nova?.tier).toBe("episodic")
    expect(nova?.corpo).toBe("# Ata do board\n\ncorpo")
  })

  test("arquivo com nome fora do formato não é espelhado", () => {
    expect(paginaDoColetivo("ata", "Ata Estranha.md", "x")).toBeNull()
  })

  test("espelha decisões e atas no coletivo, fora o INDEX", async () => {
    const raiz = await mkdtemp(join(tmpdir(), "tower-coletivo-"))
    await mkdir(join(raiz, "decisions"), { recursive: true })
    await mkdir(join(raiz, "board", "minutes"), { recursive: true })
    await Bun.write(join(raiz, "decisions", "INDEX.md"), "# Índice")
    await Bun.write(join(raiz, "decisions", "2026-08-22-a.md"), "---\ntitle: A\n---\ncorpo")
    await Bun.write(join(raiz, "board", "minutes", "2026-09-01-b.md"), "# B")
    const { memoria, gravacoes } = memoriaFalsa()
    expect(await espelharColetivo(raiz, memoria)).toBe(2)
    expect(gravacoes.every((g) => g.projeto === "coletivo")).toBe(true)
    await rm(raiz, { recursive: true, force: true })
  })
})

describe("migração", () => {
  const md = `# Memória do Lucas

Atualizada pelo próprio Lucas. Contexto de negócio.

## Contexto

- Ueslei é desenvolvedor na Jacto e mantém projetos pessoais
  em paralelo.
- O control-tower nasceu como ferramenta pessoal.

## Posições que defendi

_(vazio por enquanto)_
`

  test("separa itens, juntando linhas quebradas, sem título, nota nem vazio", () => {
    expect(itensDaMemoria(md)).toEqual([
      "- Ueslei é desenvolvedor na Jacto e mantém projetos pessoais em paralelo.",
      "- O control-tower nasceu como ferramenta pessoal.",
    ])
  })

  test("item copiado literalmente conta como coberto, mesmo com outra quebra de linha", () => {
    const corpos = [
      "# Trabalho\n\nUeslei é desenvolvedor na Jacto e mantém\nprojetos pessoais em paralelo.",
      "# Origem\n\nO control-tower **nasceu** como ferramenta pessoal.",
    ]
    expect(itensNaoCobertos(md, corpos)).toEqual([])
  })

  test("item resumido ou esquecido aparece como faltando", () => {
    expect(itensNaoCobertos(md, ["# Trabalho\n\nUeslei trabalha na Jacto."])).toEqual([
      "- Ueslei é desenvolvedor na Jacto e mantém projetos pessoais em paralelo.",
      "- O control-tower nasceu como ferramenta pessoal.",
    ])
  })

  test("todas as memory.md reais se decompõem em itens", async () => {
    const raiz = join(import.meta.dir, "..", "..")
    for (const persona of CONSELHEIROS) {
      const arquivo = Bun.file(join(raiz, "profiles", persona, "memory.md"))
      if (!(await arquivo.exists())) continue
      const itens = itensDaMemoria(await arquivo.text())
      expect(itens.length).toBeGreaterThan(0)
      expect(itens.some((i) => i.startsWith("#"))).toBe(false)
    }
  })
})
