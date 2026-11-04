export type PersonaId = string
export type Capacidade = "arquivos" | "comandos" | "ticktask" | "memoria" | "board"
export type PoliticaDeAprovacao = "sempre" | "sensiveis" | "auto"

export const CAPACIDADES: readonly Capacidade[] = ["arquivos", "comandos", "ticktask", "memoria", "board"]
export const POLITICAS: readonly PoliticaDeAprovacao[] = ["sempre", "sensiveis", "auto"]
export const CASA = "casa"

export interface Persona {
  id: PersonaId
  nome: string
  modelo?: string
  protegida?: boolean
  orcamentoMensalUSD?: number
  orcamentoMensalTokens?: number
  cor?: string
}

export interface Posicao {
  id: string
  titulo: string
  persona: PersonaId | null
  respondeA: string | null
  capacidades: Capacidade[]
  aprovacao: PoliticaDeAprovacao
  diretorio?: string
  aprovarPlano?: boolean
  delegaDireto?: boolean
}

export interface Equipe {
  id: string
  nome: string
  posicoes: Posicao[]
  layout: Record<string, { x: number; y: number }>
}

// O id da persona entra no id da conversa (store.ts) e vira caminho de arquivo.
const PADRAO_PERSONA = /^[a-z]{2,24}$/
const PADRAO_SLUG = /^[a-z][a-z0-9-]{0,47}$/

export function personaIdValido(id: unknown): id is PersonaId {
  return typeof id === "string" && PADRAO_PERSONA.test(id)
}

export function slugValido(id: unknown): id is string {
  return typeof id === "string" && PADRAO_SLUG.test(id)
}

const PADRAO_COR = /^#[0-9a-f]{6}$/i
const PALETA = ["#e0a458", "#9a6ee8", "#4fae7c", "#e06a8a", "#58b7c9", "#c9a227", "#5b8def", "#d9774b", "#7fb069", "#b56cc4"]

export function corDaPersona(persona: Pick<Persona, "id" | "cor">): string {
  if (persona.cor) return persona.cor
  let hash = 0
  for (const c of persona.id) hash = (hash * 31 + c.charCodeAt(0)) >>> 0
  return PALETA[hash % PALETA.length]!
}

export function idDoNome(nome: string): PersonaId {
  const id = nome
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z]/g, "")
  if (!personaIdValido(id)) throw new Error("o nome precisa ter de 2 a 24 letras")
  return id
}

function objeto(bruto: unknown, oQue: string): Record<string, unknown> {
  if (!bruto || typeof bruto !== "object" || Array.isArray(bruto)) throw new Error(`${oQue}: não é um objeto`)
  return bruto as Record<string, unknown>
}

function texto(valor: unknown, oQue: string): string {
  if (typeof valor !== "string" || !valor.trim()) throw new Error(`${oQue}: texto obrigatório`)
  return valor.trim()
}

export function validarPersona(bruto: unknown): Persona {
  const p = objeto(bruto, "persona")
  if (!personaIdValido(p.id)) throw new Error(`persona: id inválido (${String(p.id)})`)
  const persona: Persona = { id: p.id, nome: texto(p.nome, `persona ${p.id}: nome`) }
  if (p.modelo !== undefined) persona.modelo = texto(p.modelo, `persona ${p.id}: modelo`)
  if (p.protegida === true) persona.protegida = true
  if (p.cor !== undefined) {
    if (typeof p.cor !== "string" || !PADRAO_COR.test(p.cor)) throw new Error(`persona ${p.id}: cor inválida (use #rrggbb)`)
    persona.cor = p.cor.toLowerCase()
  }
  if (p.orcamentoMensalUSD !== undefined) {
    if (typeof p.orcamentoMensalUSD !== "number" || !(p.orcamentoMensalUSD >= 0)) {
      throw new Error(`persona ${p.id}: orçamento inválido`)
    }
    persona.orcamentoMensalUSD = p.orcamentoMensalUSD
  }
  if (p.orcamentoMensalTokens !== undefined) {
    if (typeof p.orcamentoMensalTokens !== "number" || !Number.isInteger(p.orcamentoMensalTokens) || p.orcamentoMensalTokens < 0) {
      throw new Error(`persona ${p.id}: orçamento de tokens inválido (use um número inteiro)`)
    }
    persona.orcamentoMensalTokens = p.orcamentoMensalTokens
  }
  return persona
}

function validarPosicao(bruto: unknown, personas: ReadonlySet<string>, erros: string[]): Posicao | undefined {
  try {
    const p = objeto(bruto, "posição")
    if (!slugValido(p.id)) throw new Error(`posição: id inválido (${String(p.id)})`)
    const onde = `posição ${p.id}`
    const persona = p.persona === null || p.persona === undefined ? null : String(p.persona)
    if (persona !== null && !personas.has(persona)) throw new Error(`${onde}: persona desconhecida (${persona})`)
    const respondeA = p.respondeA === null || p.respondeA === undefined ? null : String(p.respondeA)
    if (!Array.isArray(p.capacidades)) throw new Error(`${onde}: capacidades precisam ser uma lista`)
    const capacidades = [...new Set(p.capacidades)]
    const estranha = capacidades.find((c) => !CAPACIDADES.includes(c as Capacidade))
    if (estranha !== undefined) throw new Error(`${onde}: capacidade desconhecida (${String(estranha)})`)
    const aprovacao = p.aprovacao ?? "sempre"
    if (!POLITICAS.includes(aprovacao as PoliticaDeAprovacao)) throw new Error(`${onde}: política de aprovação inválida`)
    const posicao: Posicao = {
      id: p.id,
      titulo: texto(p.titulo, `${onde}: título`),
      persona,
      respondeA,
      capacidades: capacidades as Capacidade[],
      aprovacao: aprovacao as PoliticaDeAprovacao,
    }
    if (p.diretorio !== undefined) posicao.diretorio = texto(p.diretorio, `${onde}: diretório`)
    if (p.aprovarPlano === true) posicao.aprovarPlano = true
    if (p.delegaDireto === true) posicao.delegaDireto = true
    return posicao
  } catch (erro) {
    erros.push((erro as Error).message)
    return undefined
  }
}

function temCiclo(posicoes: Posicao[]): string | undefined {
  const chefe = new Map(posicoes.map((p) => [p.id, p.respondeA]))
  for (const inicio of chefe.keys()) {
    const vistos = new Set<string>()
    for (let atual: string | null | undefined = inicio; atual; atual = chefe.get(atual)) {
      if (vistos.has(atual)) return inicio
      vistos.add(atual)
    }
  }
  return undefined
}

export function validarEquipe(bruto: unknown, personas: ReadonlySet<string>): Equipe {
  const e = objeto(bruto, "equipe")
  if (!slugValido(e.id)) throw new Error(`equipe: id inválido (${String(e.id)})`)
  const erros: string[] = []
  const nome = typeof e.nome === "string" && e.nome.trim() ? e.nome.trim() : (erros.push("equipe: nome obrigatório"), "")
  const brutas = Array.isArray(e.posicoes) ? e.posicoes : (erros.push("equipe: posições precisam ser uma lista"), [])
  const posicoes = brutas.map((p) => validarPosicao(p, personas, erros)).filter((p): p is Posicao => Boolean(p))
  const ids = new Set<string>()
  for (const p of posicoes) {
    if (ids.has(p.id)) erros.push(`posição ${p.id}: id repetido`)
    ids.add(p.id)
  }
  const ocupadas = new Set<string>()
  for (const p of posicoes) {
    if (p.respondeA !== null && !ids.has(p.respondeA)) erros.push(`posição ${p.id}: responde a posição inexistente (${p.respondeA})`)
    if (p.respondeA === p.id) erros.push(`posição ${p.id}: não pode responder a si mesma`)
    if (p.persona !== null) {
      if (ocupadas.has(p.persona)) erros.push(`persona ${p.persona}: ocupa mais de uma posição na mesma equipe`)
      ocupadas.add(p.persona)
    }
  }
  const ciclo = temCiclo(posicoes)
  if (ciclo) erros.push(`posição ${ciclo}: a cadeia de "responde a" forma um ciclo`)
  if (erros.length) throw new Error(`equipe ${e.id}: ${erros.join("; ")}`)
  const layout: Equipe["layout"] = {}
  if (e.layout && typeof e.layout === "object") {
    for (const [id, ponto] of Object.entries(e.layout as Record<string, unknown>)) {
      const xy = ponto as { x?: unknown; y?: unknown }
      if (ids.has(id) && typeof xy?.x === "number" && typeof xy.y === "number") layout[id] = { x: xy.x, y: xy.y }
    }
  }
  return { id: e.id, nome, posicoes, layout }
}

interface Legado {
  nome: string
  titulo: string
  executor?: boolean
}

// Os perfis que existiam fixos no código antes do orquestrador; a migração usa isto para
// montar a Casa exatamente como o uso de hoje.
export const LEGADO: Record<string, Legado> = {
  poe: { nome: "Poe", titulo: "o amigo" },
  nati: { nome: "Nati", titulo: "engenheira sênior" },
  lucas: { nome: "Lucas", titulo: "o gestor" },
  pami: { nome: "Pami", titulo: "a projetista" },
  alfred: { nome: "Alfred", titulo: "executor de tarefas", executor: true },
}

function nomeProprio(id: string): string {
  return id.charAt(0).toUpperCase() + id.slice(1)
}

export function personaInicial(id: PersonaId): Persona {
  const legado = LEGADO[id]
  return legado?.executor
    ? { id, nome: legado.nome, protegida: true }
    : { id, nome: legado?.nome ?? nomeProprio(id) }
}

export function casaInicial(ids: PersonaId[]): Equipe {
  const posicoes: Posicao[] = ids.map((id) =>
    LEGADO[id]?.executor
      ? {
          id: ids.filter((i) => LEGADO[i]?.executor).length > 1 ? `executor-${id}` : "executor",
          titulo: LEGADO[id]!.titulo,
          persona: id,
          respondeA: null,
          capacidades: ["arquivos", "comandos", "ticktask"],
          aprovacao: "sempre",
        }
      : {
          id: `conselho-${id}`,
          titulo: LEGADO[id]?.titulo ?? "conselho",
          persona: id,
          respondeA: null,
          capacidades: ["arquivos", "memoria", "board"],
          aprovacao: "sempre",
        },
  )
  const layout: Equipe["layout"] = {}
  posicoes.forEach((p, i) => (layout[p.id] = { x: i * 280, y: 0 }))
  return { id: CASA, nome: "Casa", posicoes, layout }
}

export class Elenco {
  private readonly porId: Map<PersonaId, Persona>
  private readonly todas: Map<string, Equipe>

  constructor(
    personas: Persona[],
    readonly casa: Equipe,
    outras: Equipe[] = [],
  ) {
    this.porId = new Map(personas.map((p) => [p.id, p]))
    this.todas = new Map([casa, ...outras.filter((e) => e.id !== casa.id)].map((e) => [e.id, e]))
  }

  equipes(): Equipe[] {
    return [...this.todas.values()]
  }

  equipe(id: string): Equipe | undefined {
    return this.todas.get(id)
  }

  personas(): Persona[] {
    return [...this.porId.values()]
  }

  ids(): PersonaId[] {
    return [...this.porId.keys()]
  }

  existe(id: unknown): id is PersonaId {
    return typeof id === "string" && this.porId.has(id)
  }

  persona(id: PersonaId): Persona | undefined {
    return this.porId.get(id)
  }

  nome(id: PersonaId): string {
    return this.porId.get(id)?.nome ?? nomeProprio(id)
  }

  posicaoNaCasa(id: PersonaId): Posicao | undefined {
    return this.casa.posicoes.find((p) => p.persona === id)
  }

  tem(id: PersonaId, capacidade: Capacidade): boolean {
    return this.posicaoNaCasa(id)?.capacidades.includes(capacidade) ?? false
  }

  comCapacidade(capacidade: Capacidade): PersonaId[] {
    return this.ids().filter((id) => this.tem(id, capacidade))
  }

  excluivel(id: PersonaId): boolean {
    return !this.porId.get(id)?.protegida
  }
}

export function elencoLegado(): Elenco {
  const ids = Object.keys(LEGADO)
  return new Elenco(ids.map(personaInicial), casaInicial(ids))
}

export const DISTANCIA_X = 280
export const DISTANCIA_Y = 160

export function completarLayout(equipe: Equipe): Equipe {
  const layout = { ...equipe.layout }
  const ids = new Set(equipe.posicoes.map((p) => p.id))
  const filhos = (chefe: string | null) =>
    equipe.posicoes.filter((p) => (p.respondeA !== null && ids.has(p.respondeA) ? p.respondeA : null) === chefe)
  const ocupado = new Set(Object.values(layout).map((xy) => `${xy.x}:${xy.y}`))
  const livre = (x: number, y: number) => {
    let atual = x
    while (ocupado.has(`${atual}:${y}`)) atual += DISTANCIA_X
    ocupado.add(`${atual}:${y}`)
    return atual
  }
  const descer = (chefe: string | null, y: number, xBase: number) => {
    filhos(chefe).forEach((p, i) => {
      if (!layout[p.id]) layout[p.id] = { x: livre(xBase + i * DISTANCIA_X, y), y }
      descer(p.id, layout[p.id]!.y + DISTANCIA_Y, layout[p.id]!.x)
    })
  }
  descer(null, 0, 0)
  return { ...equipe, layout }
}

export function subordinadas(equipe: Equipe, posicao: string): Posicao[] {
  return equipe.posicoes.filter((p) => p.respondeA === posicao)
}

export interface TarefasDaPosicao {
  abertas: number
  emAndamento: number
}

export function exigirMudancaDeEquipe(
  antes: Equipe | undefined,
  depois: Equipe,
  tarefas: (posicao: string) => TarefasDaPosicao,
): void {
  if (!antes) return
  const erros: string[] = []
  if (antes.id === CASA && depois.nome !== antes.nome) erros.push("a Casa não pode ser renomeada")
  for (const velha of antes.posicoes) {
    const nova = depois.posicoes.find((p) => p.id === velha.id)
    const { abertas, emAndamento } = tarefas(velha.id)
    if (!nova && abertas > 0) erros.push(`posição ${velha.id}: tem ${abertas} tarefa(s) aberta(s) e não pode sair`)
    else if (nova && nova.persona !== velha.persona && emAndamento > 0) {
      erros.push(`posição ${velha.id}: tem tarefa em andamento e não pode trocar de persona agora`)
    }
  }
  if (erros.length) throw new Error(`equipe ${depois.id}: ${erros.join("; ")}`)
}

export function resumoDaMudanca(antes: Equipe | undefined, depois: Equipe): string {
  if (!antes) return `equipe ${depois.nome} criada`
  const partes: string[] = []
  for (const p of depois.posicoes) {
    const velha = antes.posicoes.find((v) => v.id === p.id)
    if (!velha) {
      partes.push(`+${p.id}`)
      continue
    }
    if (velha.persona !== p.persona) partes.push(`${p.id} com ${p.persona ?? "vaga"}`)
    if (velha.respondeA !== p.respondeA) partes.push(`${p.id} responde a ${p.respondeA ?? "Ueslei"}`)
    if (
      velha.capacidades.join() !== p.capacidades.join() ||
      velha.aprovacao !== p.aprovacao ||
      Boolean(velha.aprovarPlano) !== Boolean(p.aprovarPlano) ||
      Boolean(velha.delegaDireto) !== Boolean(p.delegaDireto)
    ) {
      partes.push(`${p.id}: capacidades`)
    }
    if (velha.titulo !== p.titulo || velha.diretorio !== p.diretorio) partes.push(`${p.id}: dados`)
  }
  for (const v of antes.posicoes) if (!depois.posicoes.some((p) => p.id === v.id)) partes.push(`-${v.id}`)
  if (antes.nome !== depois.nome) partes.push(`renomeada para ${depois.nome}`)
  return `equipe ${depois.nome}: ${partes.length ? partes.join(", ") : "layout"}`
}

export function comPersonaNaCasa(casa: Equipe, persona: PersonaId, titulo: string): Equipe {
  const id = `conselho-${persona}`
  if (casa.posicoes.some((p) => p.id === id || p.persona === persona)) return casa
  const posicao: Posicao = { id, titulo, persona, respondeA: null, capacidades: ["arquivos", "memoria"], aprovacao: "sempre" }
  return completarLayout({ ...casa, posicoes: [...casa.posicoes, posicao] })
}

export function semPersona(equipe: Equipe, persona: PersonaId): Equipe {
  return { ...equipe, posicoes: equipe.posicoes.map((p) => (p.persona === persona ? { ...p, persona: null } : p)) }
}
