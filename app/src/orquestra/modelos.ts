import { join } from "node:path"
import { mkdir, readdir, rm } from "node:fs/promises"
import {
  ARQUIVO_DE_TEXTO,
  CAMPOS_DE_TEXTO,
  caminhoDaEquipe,
  caminhoDoWorkflow,
  gravarEquipe,
  lerExcluidas,
  textosEmArquivo,
} from "./elenco"
import {
  CASA,
  comPersonaNaCasa,
  idDoNome,
  personaIdValido,
  slugValido,
  validarEquipe,
  validarPersona,
  type Capacidade,
  type Equipe,
  type Persona,
  type Posicao,
} from "./equipe"
import { validarRotina, type Rotina } from "./rotinas"
import { DONO_CASA, lerSkillMd, montarSkillMd, nomeDoPlugin, pastaDoDono, skillIdValido } from "./skills"
import { validarWorkflow, type Saidas, type Workflow } from "./workflow"

export const FORMATO_DO_MODELO = "control-tower/modelo"
export const VERSAO_DO_MODELO = 1
export const LIMITE_DO_MODELO = 5 * 1024 * 1024
export const EXTENSAO_DO_MODELO = ".ctmodelo.json"
const ARQUIVOS_POR_SKILL = 50
const NIVEIS_DA_SKILL = 4
const SEGMENTO = /^[A-Za-z0-9_-][A-Za-z0-9._-]*$/

export type ConteudoDeArquivo = string | { base64: string }

export interface SkillDoModelo {
  id: string
  arquivos: Record<string, ConteudoDeArquivo>
}

export interface PersonaDoModelo {
  persona: Persona
  perfil: string
  ritmo?: unknown
  skills: SkillDoModelo[]
}

export interface WorkflowDoModelo {
  workflow: Record<string, unknown>
  textos: Record<string, string>
}

export interface PosicaoDoModelo {
  id: string
  titulo: string
  capacidades: Capacidade[]
}

interface Cabecalho {
  formato: typeof FORMATO_DO_MODELO
  versao: number
  nome: string
  exportadoEm: string
}

export interface ModeloDeEquipe extends Cabecalho {
  tipo: "equipe"
  equipe: Record<string, unknown>
  personas: PersonaDoModelo[]
  skills: SkillDoModelo[]
  workflows: WorkflowDoModelo[]
  rotinas: Record<string, unknown>[]
}

export interface ModeloDeWorkflow extends Cabecalho {
  tipo: "workflow"
  posicoes: PosicaoDoModelo[]
  workflows: WorkflowDoModelo[]
}

export type Modelo = ModeloDeEquipe | ModeloDeWorkflow

// ── exportar ───────────────────────────────────────────────────────

export interface DadosDaEquipe {
  equipe: Equipe
  personas: PersonaDoModelo[]
  skillsDaCasa: SkillDoModelo[]
  workflows: WorkflowDoModelo[]
  rotinas: Rotina[]
}

export interface OpcoesDeExportacao {
  personas: boolean
  rotinas: boolean
}

function semDiretorio(p: Posicao): Posicao {
  const { diretorio: _d, ...resto } = p
  return resto
}

function personaParaModelo(p: Persona): Persona {
  const { orcamentoMensalUSD: _u, orcamentoMensalTokens: _t, protegida: _p, ...resto } = p
  return resto
}

export function exportarEquipe(dados: DadosDaEquipe, opcoes: OpcoesDeExportacao, agora: Date = new Date()): ModeloDeEquipe {
  const posicoes = dados.equipe.posicoes.map((p) => {
    const sem = semDiretorio(p)
    return opcoes.personas ? sem : { ...sem, persona: null }
  })
  const ocupantes = new Set(posicoes.map((p) => p.persona).filter((p): p is string => p !== null))
  const personas = opcoes.personas
    ? dados.personas.filter((p) => ocupantes.has(p.persona.id)).map((p) => ({ ...p, persona: personaParaModelo(p.persona) }))
    : []
  const usadas = new Set([...posicoes.flatMap((p) => p.skills ?? []), ...personas.flatMap((p) => p.persona.skills ?? [])])
  return {
    formato: FORMATO_DO_MODELO,
    versao: VERSAO_DO_MODELO,
    tipo: "equipe",
    nome: dados.equipe.nome,
    exportadoEm: agora.toISOString(),
    equipe: { ...dados.equipe, posicoes },
    personas,
    skills: dados.skillsDaCasa.filter((s) => usadas.has(s.id)),
    workflows: dados.workflows,
    rotinas: opcoes.rotinas ? dados.rotinas.map((r) => ({ ...r })) : [],
  }
}

export function posicoesCitadas(workflow: Pick<Workflow, "nos">): string[] {
  const ids = new Set<string>()
  for (const no of workflow.nos) {
    if (no.tipo === "executar") ids.add(no.posicao)
    if ((no.tipo === "revisar" || no.tipo === "aprovar") && "posicao" in no.por) ids.add(no.por.posicao)
  }
  return [...ids]
}

export function exportarWorkflow(equipe: Equipe, workflow: Workflow, cru: WorkflowDoModelo, agora: Date = new Date()): ModeloDeWorkflow {
  const citadas = new Set(posicoesCitadas(workflow))
  return {
    formato: FORMATO_DO_MODELO,
    versao: VERSAO_DO_MODELO,
    tipo: "workflow",
    nome: workflow.nome,
    exportadoEm: agora.toISOString(),
    posicoes: equipe.posicoes
      .filter((p) => citadas.has(p.id))
      .map((p) => ({ id: p.id, titulo: p.titulo, capacidades: [...p.capacidades] })),
    workflows: [cru],
  }
}

export function nomeDoArquivo(modelo: Modelo): string {
  const base = modelo.tipo === "equipe" ? String(modelo.equipe.id ?? "equipe") : String(modelo.workflows[0]?.workflow.id ?? "workflow")
  return `${base}${EXTENSAO_DO_MODELO}`
}

// ── ler ────────────────────────────────────────────────────────────

function objeto(bruto: unknown, onde: string): Record<string, unknown> {
  if (!bruto || typeof bruto !== "object" || Array.isArray(bruto)) throw new Error(`${onde}: não é um objeto`)
  return bruto as Record<string, unknown>
}

function lista(bruto: unknown, onde: string): unknown[] {
  if (bruto === undefined) return []
  if (!Array.isArray(bruto)) throw new Error(`${onde}: precisa ser uma lista`)
  return bruto
}

export function caminhoDeSkillValido(caminho: string): boolean {
  const partes = caminho.split("/")
  return partes.length <= NIVEIS_DA_SKILL && partes.every((p) => SEGMENTO.test(p) && p !== "..")
}

function lerSkillDoModelo(bruto: unknown, onde: string): SkillDoModelo {
  const s = objeto(bruto, onde)
  if (!skillIdValido(s.id)) throw new Error(`${onde}: id de skill inválido (${String(s.id)})`)
  const aqui = `${onde} ${s.id}`
  const arquivos = objeto(s.arquivos, `${aqui}: arquivos`)
  const nomes = Object.keys(arquivos)
  if (nomes.length > ARQUIVOS_POR_SKILL) throw new Error(`${aqui}: mais de ${ARQUIVOS_POR_SKILL} arquivos`)
  if (!nomes.includes("SKILL.md")) throw new Error(`${aqui}: falta o SKILL.md`)
  const lidos: Record<string, ConteudoDeArquivo> = {}
  for (const nome of nomes) {
    if (!caminhoDeSkillValido(nome)) throw new Error(`${aqui}: caminho de arquivo inválido (${nome})`)
    const valor = arquivos[nome]
    if (typeof valor === "string") lidos[nome] = valor
    else if (valor && typeof valor === "object" && typeof (valor as { base64?: unknown }).base64 === "string") {
      lidos[nome] = { base64: (valor as { base64: string }).base64 }
    } else throw new Error(`${aqui}: conteúdo inválido em ${nome}`)
  }
  if (typeof lidos["SKILL.md"] !== "string") throw new Error(`${aqui}: o SKILL.md precisa ser texto`)
  return { id: s.id, arquivos: lidos }
}

function lerWorkflowDoModelo(bruto: unknown, onde: string): WorkflowDoModelo {
  const w = objeto(bruto, onde)
  const workflow = objeto(w.workflow, `${onde}: workflow`)
  const textos: Record<string, string> = {}
  for (const [nome, texto] of Object.entries(w.textos === undefined ? {} : objeto(w.textos, `${onde}: textos`))) {
    if (!ARQUIVO_DE_TEXTO.test(`@${nome}`)) throw new Error(`${onde}: nome de texto inválido (${nome})`)
    if (typeof texto !== "string") throw new Error(`${onde}: o texto ${nome} não é texto`)
    textos[nome] = texto
  }
  return { workflow, textos }
}

export function lerModelo(texto: string): Modelo {
  if (texto.length > LIMITE_DO_MODELO) throw new Error("o modelo passa de 5 MB")
  let bruto: unknown
  try {
    bruto = JSON.parse(texto)
  } catch {
    throw new Error("o arquivo não é um JSON válido")
  }
  const m = objeto(bruto, "modelo")
  if (m.formato !== FORMATO_DO_MODELO) throw new Error("o arquivo não é um modelo do control-tower")
  if (typeof m.versao !== "number" || !Number.isInteger(m.versao) || m.versao < 1) throw new Error("modelo sem versão")
  if (m.versao > VERSAO_DO_MODELO) throw new Error("modelo de uma versão mais nova do control-tower")
  const cabecalho: Cabecalho = {
    formato: FORMATO_DO_MODELO,
    versao: m.versao,
    nome: typeof m.nome === "string" && m.nome.trim() ? m.nome.trim() : "sem nome",
    exportadoEm: typeof m.exportadoEm === "string" ? m.exportadoEm : "",
  }
  const workflows = lista(m.workflows, "workflows").map((w, i) => lerWorkflowDoModelo(w, `workflow ${i + 1}`))
  if (m.tipo === "workflow") {
    if (workflows.length !== 1) throw new Error("o modelo de workflow precisa ter um workflow só")
    const posicoes = lista(m.posicoes, "posicoes").map((b, i) => {
      const p = objeto(b, `posição ${i + 1}`)
      if (!slugValido(p.id)) throw new Error(`posição ${i + 1}: id inválido (${String(p.id)})`)
      return {
        id: p.id,
        titulo: typeof p.titulo === "string" ? p.titulo : p.id,
        capacidades: Array.isArray(p.capacidades) ? (p.capacidades.filter((c) => typeof c === "string") as Capacidade[]) : [],
      }
    })
    return { ...cabecalho, tipo: "workflow", posicoes, workflows }
  }
  if (m.tipo !== "equipe") throw new Error(`tipo de modelo desconhecido (${String(m.tipo)})`)
  const personas = lista(m.personas, "personas").map((b, i) => {
    const p = objeto(b, `persona ${i + 1}`)
    const persona = objeto(p.persona, `persona ${i + 1}`)
    if (!personaIdValido(persona.id)) throw new Error(`persona ${i + 1}: id inválido (${String(persona.id)})`)
    if (typeof p.perfil !== "string") throw new Error(`persona ${persona.id}: falta o perfil`)
    const lida: PersonaDoModelo = {
      persona: persona as unknown as Persona,
      perfil: p.perfil,
      skills: lista(p.skills, `persona ${persona.id}: skills`).map((s) => lerSkillDoModelo(s, `persona ${persona.id}: skill`)),
    }
    if (p.ritmo !== undefined && p.ritmo !== null) lida.ritmo = objeto(p.ritmo, `persona ${persona.id}: ritmo`)
    return lida
  })
  return {
    ...cabecalho,
    tipo: "equipe",
    equipe: objeto(m.equipe, "equipe"),
    personas,
    skills: lista(m.skills, "skills").map((s) => lerSkillDoModelo(s, "skill")),
    workflows,
    rotinas: lista(m.rotinas, "rotinas").map((r, i) => objeto(r, `rotina ${i + 1}`)),
  }
}

// ── planejar a importação ──────────────────────────────────────────

export interface EstadoAtual {
  personas: Persona[]
  excluidas: string[]
  equipes: Equipe[]
  skillsDaCasa: SkillDoModelo[]
  workflows: Record<string, string[]>
}

export type AcaoDePersona = { acao: "usar"; persona: string } | { acao: "criar"; nome?: string } | { acao: "vaga" }
export type AcaoDeSkill = { acao: "usar" } | { acao: "importar"; id: string }

export interface Escolhas {
  equipe?: { id: string; nome: string }
  personas?: Record<string, AcaoDePersona>
  skills?: Record<string, AcaoDeSkill>
  posicoes?: Record<string, string | null>
  workflow?: { id: string }
}

export interface Resumo {
  tipo: Modelo["tipo"]
  nome: string
  exportadoEm: string
  posicoes: number
  personas: number
  workflows: number
  rotinas: number
  skills: number
}

export interface Escrita {
  caminho: string
  conteudo: string | { base64: string }
}

export interface Plano {
  resumo: Resumo
  personasDoModelo: { id: string; nome: string; traz: boolean }[]
  posicoesDoModelo: { id: string; titulo: string }[]
  entra: string[]
  escolhas: Escolhas
  avisos: string[]
  erros: string[]
  escritas: Escrita[]
  novos: string[]
  casa?: Equipe
  equipe: string
  workflow?: string
  mensagem: string
}

const textoOuVazio = (v: unknown) => (typeof v === "string" ? v : "")

export function lerEscolhas(bruto: unknown): Escolhas {
  const e = (bruto && typeof bruto === "object" && !Array.isArray(bruto) ? bruto : {}) as Record<string, unknown>
  const escolhas: Escolhas = {}
  const equipe = e.equipe as Record<string, unknown> | undefined
  if (equipe && typeof equipe === "object") escolhas.equipe = { id: textoOuVazio(equipe.id), nome: textoOuVazio(equipe.nome) }
  if (e.personas && typeof e.personas === "object") {
    escolhas.personas = {}
    for (const [id, a] of Object.entries(e.personas as Record<string, unknown>)) {
      const acao = (a && typeof a === "object" ? a : {}) as Record<string, unknown>
      if (acao.acao === "usar") escolhas.personas[id] = { acao: "usar", persona: textoOuVazio(acao.persona) }
      else if (acao.acao === "criar") escolhas.personas[id] = textoOuVazio(acao.nome) ? { acao: "criar", nome: textoOuVazio(acao.nome) } : { acao: "criar" }
      else if (acao.acao === "vaga") escolhas.personas[id] = { acao: "vaga" }
    }
  }
  if (e.skills && typeof e.skills === "object") {
    escolhas.skills = {}
    for (const [id, a] of Object.entries(e.skills as Record<string, unknown>)) {
      const acao = (a && typeof a === "object" ? a : {}) as Record<string, unknown>
      if (acao.acao === "usar") escolhas.skills[id] = { acao: "usar" }
      else if (acao.acao === "importar") escolhas.skills[id] = { acao: "importar", id: textoOuVazio(acao.id) }
    }
  }
  if (e.posicoes && typeof e.posicoes === "object") {
    escolhas.posicoes = {}
    for (const [id, alvo] of Object.entries(e.posicoes as Record<string, unknown>)) {
      escolhas.posicoes[id] = typeof alvo === "string" && alvo ? alvo : null
    }
  }
  const workflow = e.workflow as Record<string, unknown> | undefined
  if (workflow && typeof workflow === "object") escolhas.workflow = { id: textoOuVazio(workflow.id) }
  return escolhas
}

function livre(base: string, ocupado: (id: string) => boolean, separador = "-"): string {
  if (!ocupado(base)) return base
  for (let n = 2; ; n++) if (!ocupado(`${base}${separador}${n}`)) return `${base}${separador}${n}`
}

function json(valor: unknown): string {
  return `${JSON.stringify(valor, null, 2)}\n`
}

function mesmoConteudo(a: SkillDoModelo, b: SkillDoModelo): boolean {
  const ka = Object.keys(a.arquivos).sort()
  const kb = Object.keys(b.arquivos).sort()
  return ka.length === kb.length && ka.every((k, i) => k === kb[i] && JSON.stringify(a.arquivos[k]) === JSON.stringify(b.arquivos[k]))
}

function scripts(skill: SkillDoModelo): string[] {
  return Object.keys(skill.arquivos).filter((n) => n !== "SKILL.md").sort()
}

function escritasDaSkill(pasta: string, skill: SkillDoModelo, id: string, erros: string[], onde: string): Escrita[] {
  const original = skill.arquivos["SKILL.md"] as string
  let skillMd: string
  try {
    const lido = lerSkillMd(original, skill.id)
    skillMd = id === skill.id ? original : montarSkillMd({ id, descricao: lido.descricao, corpo: lido.corpo }, original)
  } catch (erro) {
    erros.push(`${onde}: ${(erro as Error).message}`)
    return []
  }
  return Object.entries(skill.arquivos).map(([nome, conteudo]) => ({
    caminho: `${pasta}/${id}/${nome}`,
    conteudo: nome === "SKILL.md" ? skillMd : conteudo,
  }))
}

function manifesto(pasta: string, dono: string): Escrita {
  return { caminho: `${pasta}/.claude-plugin/plugin.json`, conteudo: json({ name: nomeDoPlugin(dono), skills: "./" }) }
}

function comTextosDoModelo(w: WorkflowDoModelo, onde: string): Record<string, unknown> {
  const nos = Array.isArray(w.workflow.nos) ? w.workflow.nos : []
  return {
    ...w.workflow,
    nos: nos.map((no) => {
      if (!no || typeof no !== "object") return no
      const copia = { ...(no as Record<string, unknown>) }
      for (const campo of CAMPOS_DE_TEXTO) {
        const valor = copia[campo]
        const m = typeof valor === "string" ? ARQUIVO_DE_TEXTO.exec(valor.trim()) : null
        if (!m) continue
        const texto = w.textos[m[1]!]
        if (texto === undefined) throw new Error(`${onde}, caixa ${String(copia.id)}: ${campo} aponta para ${m[1]}, que não veio no modelo`)
        copia[campo] = texto
      }
      return copia
    }),
  }
}

function escritasDoWorkflow(equipe: string, id: string, w: WorkflowDoModelo, cru: Record<string, unknown>): Escrita[] {
  const usados = new Set(Object.values(textosEmArquivo(cru)).flatMap((c) => Object.values(c)))
  return [
    { caminho: `equipes/${equipe}/workflows/${id}.json`, conteudo: json(cru) },
    ...Object.entries(w.textos)
      .filter(([nome]) => usados.has(nome))
      .map(([nome, texto]) => ({ caminho: `equipes/${equipe}/workflows/${id}/${nome}`, conteudo: texto })),
  ]
}

function validarWorkflowDoModelo(
  w: WorkflowDoModelo,
  cru: Record<string, unknown>,
  equipe: Equipe,
  onde: string,
  erros: string[],
): Workflow | undefined {
  try {
    return validarWorkflow(comTextosDoModelo({ ...w, workflow: cru }, onde), equipe)
  } catch (erro) {
    const msg = (erro as Error).message
    erros.push(msg.startsWith(onde) ? msg : `${onde}: ${msg}`)
    return undefined
  }
}

function avisosDasPosicoes(posicoes: Posicao[], equipe: string): string[] {
  const avisos: string[] = []
  for (const p of posicoes) {
    if (p.capacidades.includes("comandos")) {
      avisos.push(
        p.aprovacao === "auto"
          ? `a posição ${p.titulo} (${equipe}) roda comandos SEM pedir aprovação (auto)`
          : `a posição ${p.titulo} (${equipe}) roda comandos, com aprovação ${p.aprovacao === "sempre" ? "sempre" : "só nos sensíveis"}`,
      )
    }
    if (p.diretorio) avisos.push(`a posição ${p.titulo} (${equipe}) trabalha no diretório ${p.diretorio}`)
  }
  return avisos
}

export function planejar(modelo: Modelo, atual: EstadoAtual, escolhas: Escolhas = {}, destino?: string): Plano {
  return modelo.tipo === "equipe" ? planejarEquipe(modelo, atual, escolhas) : planejarWorkflow(modelo, atual, escolhas, destino)
}

function planejarEquipe(modelo: ModeloDeEquipe, atual: EstadoAtual, pedidas: Escolhas): Plano {
  const erros: string[] = []
  const avisos: string[] = []
  const entra: string[] = []
  const escritas: Escrita[] = []
  const novos: string[] = []
  const equipeBruta = modelo.equipe
  const posicoesBrutas = (Array.isArray(equipeBruta.posicoes) ? equipeBruta.posicoes : []) as Record<string, unknown>[]
  const resumo: Resumo = {
    tipo: "equipe",
    nome: modelo.nome,
    exportadoEm: modelo.exportadoEm,
    posicoes: posicoesBrutas.length,
    personas: modelo.personas.length,
    workflows: modelo.workflows.length,
    rotinas: modelo.rotinas.length,
    skills: modelo.skills.length,
  }

  const equipesAqui = new Map(atual.equipes.map((e) => [e.id, e]))
  const nomesAqui = new Set(atual.equipes.map((e) => e.nome.toLowerCase()))
  const idBase = slugValido(equipeBruta.id) ? equipeBruta.id : "equipe"
  const nomeBase = typeof equipeBruta.nome === "string" && equipeBruta.nome.trim() ? equipeBruta.nome.trim() : modelo.nome
  const equipeEscolhida = {
    id: pedidas.equipe?.id?.trim() || livre(idBase, (id) => equipesAqui.has(id)),
    nome: pedidas.equipe?.nome?.trim() || livre(nomeBase, (n) => nomesAqui.has(n.toLowerCase()), " "),
  }
  const eid = equipeEscolhida.id
  if (!slugValido(eid)) erros.push(`equipe: id inválido (${eid}): letras minúsculas, números e hífen`)
  else if (equipesAqui.has(eid)) erros.push(`equipe: já existe uma equipe com o id ${eid}`)

  const personasAqui = new Map(atual.personas.map((p) => [p.id, p]))
  const excluidas = new Set(atual.excluidas)
  const doModelo = new Map(modelo.personas.map((p) => [p.persona.id, p]))
  const citadas = [...new Set(posicoesBrutas.map((p) => (typeof p.persona === "string" ? p.persona : null)).filter((p): p is string => p !== null))]
  const acoes: Record<string, AcaoDePersona> = {}
  const mapaDePersonas = new Map<string, string | null>()
  const criadas: { origem: PersonaDoModelo; id: string; nome: string }[] = []
  for (const id of citadas) {
    const padrao: AcaoDePersona = personasAqui.has(id)
      ? { acao: "usar", persona: id }
      : excluidas.has(id) || !doModelo.has(id)
        ? { acao: "vaga" }
        : { acao: "criar" }
    const acao = pedidas.personas?.[id] ?? padrao
    acoes[id] = acao
    const nomeNoModelo = doModelo.get(id)?.persona.nome ?? id
    if (acao.acao === "vaga") {
      mapaDePersonas.set(id, null)
    } else if (acao.acao === "usar") {
      const alvo = acao.persona || id
      if (!personasAqui.has(alvo)) erros.push(`persona ${nomeNoModelo}: não existe a persona ${alvo} aqui`)
      mapaDePersonas.set(id, alvo)
    } else {
      const origem = doModelo.get(id)
      if (!origem) {
        erros.push(`persona ${id}: o modelo não traz essa persona, então não dá para criar`)
        continue
      }
      let novoId = id
      const nome = acao.nome?.trim() || String(origem.persona.nome ?? id)
      if (acao.nome?.trim()) {
        try {
          novoId = idDoNome(acao.nome)
        } catch (erro) {
          erros.push(`persona ${nomeNoModelo}: ${(erro as Error).message}`)
          continue
        }
      }
      if (personasAqui.has(novoId)) erros.push(`persona ${nomeNoModelo}: já existe uma persona com o id ${novoId}; use a daqui ou escolha outro nome`)
      else if (excluidas.has(novoId)) erros.push(`persona ${nomeNoModelo}: o id ${novoId} foi de uma persona excluída; escolha outro nome`)
      else if (criadas.some((c) => c.id === novoId)) erros.push(`persona ${nomeNoModelo}: outra persona do modelo também vira ${novoId}`)
      mapaDePersonas.set(id, novoId)
      criadas.push({ origem, id: novoId, nome })
    }
  }

  const skillsAqui = new Map(atual.skillsDaCasa.map((s) => [s.id, s]))
  const skillsDoModelo = new Map(modelo.skills.map((s) => [s.id, s]))
  const precisa = new Set([
    ...posicoesBrutas.flatMap((p) => (Array.isArray(p.skills) ? (p.skills as unknown[]).filter((s): s is string => typeof s === "string") : [])),
    ...criadas.flatMap((c) => c.origem.persona.skills ?? []),
  ])
  const acoesDeSkill: Record<string, AcaoDeSkill> = {}
  const mapaDeSkills = new Map<string, string>()
  const importadas: { skill: SkillDoModelo; id: string }[] = []
  for (const id of [...precisa].sort()) {
    const doPacote = skillsDoModelo.get(id)
    const daqui = skillsAqui.get(id)
    if (!doPacote) {
      if (daqui) mapaDeSkills.set(id, id)
      else erros.push(`skill ${id}: é usada pela equipe, mas não veio no modelo e não existe aqui`)
      continue
    }
    if (!daqui) {
      mapaDeSkills.set(id, id)
      importadas.push({ skill: doPacote, id })
      continue
    }
    if (mesmoConteudo(doPacote, daqui)) {
      mapaDeSkills.set(id, id)
      continue
    }
    const acao = pedidas.skills?.[id] ?? { acao: "usar" }
    acoesDeSkill[id] = acao
    if (acao.acao === "usar") {
      mapaDeSkills.set(id, id)
      avisos.push(`a skill ${id} daqui é diferente da do modelo; fica a daqui`)
      continue
    }
    const novo = acao.id?.trim() || livre(`${id}-2`, (s) => skillsAqui.has(s))
    acoesDeSkill[id] = { acao: "importar", id: novo }
    if (!skillIdValido(novo)) erros.push(`skill ${id}: id inválido (${novo})`)
    else if (skillsAqui.has(novo) || importadas.some((i) => i.id === novo)) erros.push(`skill ${id}: o id ${novo} já está em uso`)
    mapaDeSkills.set(id, novo)
    importadas.push({ skill: doPacote, id: novo })
  }
  const trocarSkills = (ids: unknown) =>
    Array.isArray(ids) ? ids.map((s) => (typeof s === "string" ? (mapaDeSkills.get(s) ?? s) : s)) : ids

  const personasFinais = new Set([...personasAqui.keys(), ...criadas.map((c) => c.id)])
  const skillsFinais = new Set([...skillsAqui.keys(), ...importadas.map((i) => i.id)])
  const posicoesFinais = posicoesBrutas.map((p) => {
    const copia: Record<string, unknown> = { ...p }
    if (typeof p.persona === "string") copia.persona = mapaDePersonas.get(p.persona) ?? null
    if (p.skills !== undefined) copia.skills = trocarSkills(p.skills)
    return copia
  })
  let equipe: Equipe | undefined
  try {
    equipe = validarEquipe({ ...equipeBruta, id: slugValido(eid) ? eid : "x", nome: equipeEscolhida.nome, posicoes: posicoesFinais }, personasFinais, skillsFinais)
  } catch (erro) {
    erros.push((erro as Error).message)
  }

  for (const c of criadas) {
    const pasta = `profiles/${c.id}`
    const { orcamentoMensalUSD: _u, orcamentoMensalTokens: _t, protegida: _p, ...resto } = c.origem.persona
    try {
      const persona = validarPersona({ ...resto, id: c.id, nome: c.nome, skills: trocarSkills(resto.skills) }, skillsFinais)
      escritas.push({ caminho: `${pasta}/persona.json`, conteudo: json(persona) })
    } catch (erro) {
      erros.push((erro as Error).message)
    }
    escritas.push({ caminho: `${pasta}/profile.md`, conteudo: c.origem.perfil.endsWith("\n") ? c.origem.perfil : `${c.origem.perfil}\n` })
    if (c.origem.ritmo !== undefined) escritas.push({ caminho: `${pasta}/ritmo.json`, conteudo: json(c.origem.ritmo) })
    if (c.origem.skills.length) escritas.push(manifesto(`${pasta}/skills`, c.id))
    for (const s of c.origem.skills) {
      escritas.push(...escritasDaSkill(`${pasta}/skills`, s, s.id, erros, `persona ${c.nome}, skill ${s.id}`))
      const extras = scripts(s)
      if (extras.length) avisos.push(`a skill ${s.id} de ${c.nome} traz arquivos que a persona pode rodar: ${extras.join(", ")}`)
    }
    novos.push(pasta)
    entra.push(`persona nova ${c.nome} (${c.id})`)
  }
  const mesmas: string[] = []
  for (const [id, alvo] of mapaDePersonas) {
    if (!alvo || criadas.some((c) => c.id === alvo)) continue
    const daqui = personasAqui.get(alvo)?.nome ?? alvo
    if (alvo === id) mesmas.push(daqui)
    else entra.push(`a posição de ${doModelo.get(id)?.persona.nome ?? id} fica com ${daqui}, daqui`)
  }
  if (mesmas.length) entra.push(`${mesmas.length === 1 ? "persona daqui" : "personas daqui"} nas posições: ${mesmas.join(", ")}`)
  const nomeDaCasa = atual.equipes.find((e) => e.id === CASA)?.nome ?? "Casa"
  for (const { skill, id } of importadas) {
    escritas.push(...escritasDaSkill("skills", skill, id, erros, `skill ${skill.id}`))
    novos.push(`skills/${id}`)
    entra.push(id === skill.id ? `skill ${id} na ${nomeDaCasa}` : `skill ${skill.id} na ${nomeDaCasa} como ${id}`)
    const extras = scripts(skill)
    if (extras.length) avisos.push(`a skill ${id} traz arquivos que as personas podem rodar: ${extras.join(", ")}`)
  }

  let casa: Equipe | undefined
  if (criadas.length) {
    const casaAqui = atual.equipes.find((e) => e.id === CASA)
    if (!casaAqui) erros.push("a Casa não foi encontrada")
    else {
      let nova = casaAqui
      for (const c of criadas) {
        const titulo = equipe?.posicoes.find((p) => p.persona === c.id)?.titulo ?? "conselho"
        nova = comPersonaNaCasa(nova, c.id, titulo)
      }
      try {
        casa = validarEquipe(nova, personasFinais, skillsFinais)
      } catch (erro) {
        erros.push((erro as Error).message)
      }
    }
  }

  const entradas = new Map<string, Saidas>()
  const vistos = new Set<string>()
  if (equipe) {
    escritas.unshift({ caminho: `equipes/${eid}/equipe.json`, conteudo: json(equipe) })
    novos.unshift(`equipes/${eid}`)
    entra.unshift(`equipe ${equipe.nome} (${eid}) com ${equipe.posicoes.length} posições`)
    avisos.push(...avisosDasPosicoes(equipe.posicoes, equipe.nome))
    for (const w of modelo.workflows) {
      const id = String(w.workflow.id ?? "")
      const onde = `workflow ${id || "sem id"}`
      if (!slugValido(id)) {
        erros.push(`${onde}: id inválido`)
        continue
      }
      if (vistos.has(id)) erros.push(`${onde}: id repetido no modelo`)
      vistos.add(id)
      const cru = { ...w.workflow, versao: 1 }
      const validado = validarWorkflowDoModelo(w, cru, equipe, onde, erros)
      if (!validado) continue
      entradas.set(id, validado.entrada)
      escritas.push(...escritasDoWorkflow(eid, id, w, cru))
      entra.push(`workflow ${validado.nome}`)
    }
    const rotinasVistas = new Set<string>()
    for (const bruta of modelo.rotinas) {
      try {
        const rotina = validarRotina({ ...bruta, ativa: false }, equipe, (w) => entradas.get(w))
        if (rotinasVistas.has(rotina.id)) throw new Error(`rotina ${rotina.id}: id repetido no modelo`)
        rotinasVistas.add(rotina.id)
        escritas.push({ caminho: `equipes/${eid}/rotinas/${rotina.id}.json`, conteudo: json(rotina) })
        const gatilho = [rotina.cron ? `cron ${rotina.cron}` : "", rotina.webhook ? "webhook" : ""].filter(Boolean).join(" e ") || "só manual"
        entra.push(`rotina ${rotina.nome}, desligada (${gatilho})`)
      } catch (erro) {
        erros.push((erro as Error).message)
      }
    }
    if (rotinasVistas.size) avisos.push(`${rotinasVistas.size === 1 ? "a rotina entra desligada" : `as ${rotinasVistas.size} rotinas entram desligadas`}: ligue no desktop quando quiser`)
  }

  return {
    resumo,
    personasDoModelo: citadas.map((id) => ({ id, nome: String(doModelo.get(id)?.persona.nome ?? id), traz: doModelo.has(id) })),
    posicoesDoModelo: [],
    entra,
    escolhas: { equipe: equipeEscolhida, personas: acoes, skills: acoesDeSkill },
    avisos,
    erros,
    escritas,
    novos,
    ...(casa ? { casa } : {}),
    equipe: eid,
    mensagem: `importa o modelo ${modelo.nome} como a equipe ${eid}`,
  }
}

function planejarWorkflow(modelo: ModeloDeWorkflow, atual: EstadoAtual, pedidas: Escolhas, destino?: string): Plano {
  const erros: string[] = []
  const w = modelo.workflows[0]!
  const resumo: Resumo = {
    tipo: "workflow",
    nome: modelo.nome,
    exportadoEm: modelo.exportadoEm,
    posicoes: modelo.posicoes.length,
    personas: 0,
    workflows: 1,
    rotinas: 0,
    skills: 0,
  }
  const equipe = atual.equipes.find((e) => e.id === destino)
  const posicoesDoModelo = modelo.posicoes.map((p) => ({ id: p.id, titulo: p.titulo }))
  const vazio = (motivo: string): Plano => ({
    resumo,
    personasDoModelo: [],
    posicoesDoModelo,
    entra: [],
    escolhas: {},
    avisos: [],
    erros: [motivo],
    escritas: [],
    novos: [],
    equipe: destino ?? "",
    mensagem: "",
  })
  if (!equipe) return vazio(destino ? `a equipe ${destino} não existe` : "escolha a equipe de destino")

  const porId = new Map(equipe.posicoes.map((p) => [p.id, p]))
  const porTitulo = new Map(equipe.posicoes.map((p) => [p.titulo.trim().toLowerCase(), p.id]))
  const ligacoes: Record<string, string | null> = {}
  for (const p of modelo.posicoes) {
    const padrao = porId.has(p.id) ? p.id : (porTitulo.get(p.titulo.trim().toLowerCase()) ?? null)
    const pedida = pedidas.posicoes && p.id in pedidas.posicoes ? pedidas.posicoes[p.id]! : padrao
    ligacoes[p.id] = pedida
    if (pedida === null) erros.push(`posição ${p.titulo}: escolha uma posição da equipe ${equipe.nome} para ela`)
    else if (!porId.has(pedida)) erros.push(`posição ${p.titulo}: a posição ${pedida} não existe na equipe ${equipe.nome}`)
  }

  const existentes = new Set(atual.workflows[equipe.id] ?? [])
  const idBase = slugValido(w.workflow.id) ? w.workflow.id : "workflow"
  const id = pedidas.workflow?.id?.trim() || livre(idBase, (i) => existentes.has(i))
  if (!slugValido(id)) erros.push(`workflow: id inválido (${id})`)
  else if (existentes.has(id)) erros.push(`workflow: já existe um workflow ${id} na equipe ${equipe.nome}`)

  const trocar = (p: unknown) => (typeof p === "string" && ligacoes[p] ? ligacoes[p] : p)
  const nos = (Array.isArray(w.workflow.nos) ? w.workflow.nos : []).map((bruto) => {
    if (!bruto || typeof bruto !== "object") return bruto
    const no = { ...(bruto as Record<string, unknown>) }
    if (no.tipo === "executar") no.posicao = trocar(no.posicao)
    if ((no.tipo === "revisar" || no.tipo === "aprovar") && no.por && typeof no.por === "object" && "posicao" in no.por) {
      no.por = { ...(no.por as Record<string, unknown>), posicao: trocar((no.por as { posicao: unknown }).posicao) }
    }
    return no
  })
  const cru = { ...w.workflow, id, versao: 1, nos }
  const escritas: Escrita[] = []
  const entra: string[] = []
  let nome = modelo.nome
  if (!erros.length) {
    const validado = validarWorkflowDoModelo(w, cru, equipe, `workflow ${id}`, erros)
    if (validado) {
      nome = validado.nome
      escritas.push(...escritasDoWorkflow(equipe.id, id, w, cru))
      entra.push(`workflow ${validado.nome} (${id}) na equipe ${equipe.nome}`)
      for (const [de, para] of Object.entries(ligacoes)) {
        const titulo = modelo.posicoes.find((p) => p.id === de)?.titulo ?? de
        if (para) entra.push(`${titulo} do modelo vira ${porId.get(para)?.titulo ?? para}`)
      }
    }
  }
  return {
    resumo,
    personasDoModelo: [],
    posicoesDoModelo,
    entra,
    escolhas: { posicoes: ligacoes, workflow: { id } },
    avisos: [],
    erros,
    escritas,
    novos: escritas.length ? [`equipes/${equipe.id}/workflows/${id}.json`, `equipes/${equipe.id}/workflows/${id}`] : [],
    equipe: equipe.id,
    workflow: id,
    mensagem: `importa o modelo ${nome} como o workflow ${id} da equipe ${equipe.nome}`,
  }
}

// ── disco ──────────────────────────────────────────────────────────

const decodificador = new TextDecoder("utf-8", { fatal: true })

async function lerArquivosDaSkill(pasta: string): Promise<Record<string, ConteudoDeArquivo>> {
  const entradas = await readdir(pasta, { recursive: true, withFileTypes: true }).catch(() => [])
  const arquivos: Record<string, ConteudoDeArquivo> = {}
  for (const e of entradas) {
    if (!e.isFile()) continue
    const caminho = join(e.parentPath, e.name).slice(pasta.length + 1)
    if (!caminhoDeSkillValido(caminho)) continue
    const bytes = new Uint8Array(await Bun.file(join(pasta, caminho)).arrayBuffer())
    try {
      arquivos[caminho] = decodificador.decode(bytes)
    } catch {
      arquivos[caminho] = { base64: Buffer.from(bytes).toString("base64") }
    }
  }
  return Object.fromEntries(Object.entries(arquivos).sort(([a], [b]) => a.localeCompare(b)))
}

export async function lerSkillsParaModelo(raiz: string, dono: string): Promise<SkillDoModelo[]> {
  const pasta = pastaDoDono(raiz, dono)
  const entradas = await readdir(pasta, { withFileTypes: true }).catch(() => [])
  const skills: SkillDoModelo[] = []
  for (const e of entradas.filter((e) => e.isDirectory() && skillIdValido(e.name)).sort((a, b) => a.name.localeCompare(b.name))) {
    const arquivos = await lerArquivosDaSkill(join(pasta, e.name))
    if (typeof arquivos["SKILL.md"] === "string") skills.push({ id: e.name, arquivos })
  }
  return skills
}

export async function lerWorkflowParaModelo(raiz: string, equipe: string, id: string): Promise<WorkflowDoModelo> {
  const workflow = (await Bun.file(caminhoDoWorkflow(raiz, equipe, id)).json()) as Record<string, unknown>
  const textos: Record<string, string> = {}
  for (const campos of Object.values(textosEmArquivo(workflow))) {
    for (const nome of Object.values(campos)) {
      textos[nome] = await Bun.file(join(raiz, "equipes", equipe, "workflows", id, nome)).text()
    }
  }
  return { workflow, textos }
}

export async function lerParaExportar(
  raiz: string,
  equipe: Equipe,
  personas: Persona[],
  workflows: string[],
  rotinas: Rotina[],
): Promise<DadosDaEquipe> {
  const ocupantes = new Set(equipe.posicoes.map((p) => p.persona).filter((p): p is string => p !== null))
  const dasPersonas: PersonaDoModelo[] = []
  for (const persona of personas.filter((p) => ocupantes.has(p.id))) {
    const pasta = join(raiz, "profiles", persona.id)
    const perfil = Bun.file(join(pasta, "profile.md"))
    const ritmo = Bun.file(join(pasta, "ritmo.json"))
    const lida: PersonaDoModelo = {
      persona,
      perfil: (await perfil.exists()) ? await perfil.text() : `# ${persona.nome}\n`,
      skills: await lerSkillsParaModelo(raiz, persona.id),
    }
    if (await ritmo.exists()) lida.ritmo = await ritmo.json()
    dasPersonas.push(lida)
  }
  return {
    equipe,
    personas: dasPersonas,
    skillsDaCasa: await lerSkillsParaModelo(raiz, DONO_CASA),
    workflows: await Promise.all(workflows.map((id) => lerWorkflowParaModelo(raiz, equipe.id, id))),
    rotinas,
  }
}

export async function estadoAtual(
  raiz: string,
  personas: Persona[],
  equipes: Equipe[],
  workflows: Record<string, string[]>,
): Promise<EstadoAtual> {
  return {
    personas,
    excluidas: await lerExcluidas(raiz),
    equipes,
    skillsDaCasa: await lerSkillsParaModelo(raiz, DONO_CASA),
    workflows,
  }
}

export async function aplicar(raiz: string, plano: Plano): Promise<() => Promise<void>> {
  if (plano.erros.length) throw new Error(plano.erros.join("; "))
  for (const novo of plano.novos) {
    if (await Bun.file(join(raiz, novo)).exists()) throw new Error(`${novo} já existe: algo mudou desde a prévia`)
    if (await readdir(join(raiz, novo)).catch(() => null)) throw new Error(`${novo} já existe: algo mudou desde a prévia`)
  }
  const casaAntes = plano.casa ? await Bun.file(caminhoDaEquipe(raiz, CASA)).text() : null
  const desfazer = async () => {
    for (const novo of plano.novos) await rm(join(raiz, novo), { recursive: true, force: true })
    if (casaAntes !== null) await Bun.write(caminhoDaEquipe(raiz, CASA), casaAntes)
  }
  try {
    for (const e of plano.escritas) {
      const caminho = join(raiz, e.caminho)
      await mkdir(join(caminho, ".."), { recursive: true })
      await Bun.write(caminho, typeof e.conteudo === "string" ? e.conteudo : Buffer.from(e.conteudo.base64, "base64"))
    }
    if (plano.casa) await gravarEquipe(raiz, plano.casa)
  } catch (erro) {
    await desfazer()
    throw erro
  }
  return desfazer
}

