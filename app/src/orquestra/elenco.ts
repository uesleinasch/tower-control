import { join } from "node:path"
import { mkdir, readdir, rm } from "node:fs/promises"
import {
  CASA,
  Elenco,
  casaInicial,
  completarLayout,
  elencoLegado,
  personaIdValido,
  personaInicial,
  validarEquipe,
  validarPersona,
  type Equipe,
  type Persona,
} from "./equipe"
import { validarRotina, type Rotina } from "./rotinas"
import { validarWorkflow, type Saidas, type Workflow } from "./workflow"
import type { RotinaDaEquipe } from "./agendador"

let atual = elencoLegado()

export function elenco(): Elenco {
  return atual
}

export function definirElenco(novo: Elenco): void {
  atual = novo
}

export function caminhoDaPersona(raiz: string, id: string): string {
  return join(raiz, "profiles", id, "persona.json")
}

export function caminhoDaEquipe(raiz: string, id: string): string {
  return join(raiz, "equipes", id, "equipe.json")
}

async function perfisNoDisco(raiz: string): Promise<string[]> {
  try {
    const entradas = await readdir(join(raiz, "profiles"), { withFileTypes: true })
    return entradas.filter((e) => e.isDirectory() && personaIdValido(e.name)).map((e) => e.name).sort()
  } catch {
    return []
  }
}

async function gravarJson(caminho: string, valor: unknown): Promise<void> {
  await mkdir(join(caminho, ".."), { recursive: true })
  await Bun.write(caminho, `${JSON.stringify(valor, null, 2)}\n`)
}

// Uma vez só por pasta de dados: a Casa já gravada é do Ueslei e nunca é recriada.
export async function migrarParaPersonas(raiz: string): Promise<boolean> {
  const casa = Bun.file(caminhoDaEquipe(raiz, CASA))
  if (await casa.exists()) return false
  const ids = await perfisNoDisco(raiz)
  for (const id of ids) {
    const arquivo = Bun.file(caminhoDaPersona(raiz, id))
    if (!(await arquivo.exists())) await gravarJson(caminhoDaPersona(raiz, id), personaInicial(id))
  }
  await gravarJson(caminhoDaEquipe(raiz, CASA), casaInicial(ids))
  return true
}

export async function lerElenco(raiz: string): Promise<Elenco> {
  const personas: Persona[] = []
  for (const id of await perfisNoDisco(raiz)) {
    const arquivo = Bun.file(caminhoDaPersona(raiz, id))
    if (!(await arquivo.exists())) continue
    const persona = validarPersona(await arquivo.json())
    if (persona.id !== id) throw new Error(`profiles/${id}/persona.json: id diferente da pasta (${persona.id})`)
    personas.push(persona)
  }
  const ids = new Set(personas.map((p) => p.id))
  const casa: Equipe = validarEquipe(await Bun.file(caminhoDaEquipe(raiz, CASA)).json(), ids)
  const outras: Equipe[] = []
  for (const id of await equipesNoDisco(raiz)) {
    if (id === CASA) continue
    const equipe = validarEquipe(await Bun.file(caminhoDaEquipe(raiz, id)).json(), ids)
    if (equipe.id !== id) throw new Error(`equipes/${id}/equipe.json: id diferente da pasta (${equipe.id})`)
    outras.push(equipe)
  }
  return new Elenco(personas, casa, outras)
}

async function equipesNoDisco(raiz: string): Promise<string[]> {
  try {
    const entradas = await readdir(join(raiz, "equipes"), { withFileTypes: true })
    const ids: string[] = []
    for (const e of entradas) {
      if (e.isDirectory() && (await Bun.file(caminhoDaEquipe(raiz, e.name)).exists())) ids.push(e.name)
    }
    return ids.sort()
  } catch {
    return []
  }
}

export async function gravarEquipe(raiz: string, equipe: Equipe): Promise<Equipe> {
  const completa = completarLayout(equipe)
  await gravarJson(caminhoDaEquipe(raiz, equipe.id), completa)
  return completa
}

export async function apagarEquipe(raiz: string, id: string): Promise<void> {
  if (id === CASA) throw new Error("a Casa não pode ser excluída")
  await rm(join(raiz, "equipes", id), { recursive: true, force: true })
}

export function caminhoDaRotina(raiz: string, equipe: string, id: string): string {
  return join(raiz, "equipes", equipe, "rotinas", `${id}.json`)
}

export async function lerRotinas(
  raiz: string,
  equipes: Equipe[],
  entradaDoWorkflow: (equipe: string, id: string) => Saidas | undefined = () => undefined,
): Promise<RotinaDaEquipe[]> {
  const lidas: RotinaDaEquipe[] = []
  for (const equipe of equipes) {
    let nomes: string[]
    try {
      nomes = (await readdir(join(raiz, "equipes", equipe.id, "rotinas"))).filter((n) => n.endsWith(".json")).sort()
    } catch {
      continue
    }
    for (const nome of nomes) {
      const caminho = join(raiz, "equipes", equipe.id, "rotinas", nome)
      let rotina: Rotina
      try {
        rotina = validarRotina(await Bun.file(caminho).json(), equipe, (id) => entradaDoWorkflow(equipe.id, id))
      } catch (erro) {
        throw new Error(`${caminho}: ${(erro as Error).message}`)
      }
      if (`${rotina.id}.json` !== nome) throw new Error(`${caminho}: o id ${rotina.id} não bate com o nome do arquivo`)
      lidas.push({ equipe: equipe.id, rotina })
    }
  }
  return lidas
}

export async function gravarRotina(raiz: string, equipe: string, rotina: Rotina): Promise<void> {
  await gravarJson(caminhoDaRotina(raiz, equipe, rotina.id), rotina)
}

export async function apagarRotina(raiz: string, equipe: string, id: string): Promise<void> {
  await rm(caminhoDaRotina(raiz, equipe, id), { force: true })
}

export function caminhoDoWorkflow(raiz: string, equipe: string, id: string): string {
  return join(raiz, "equipes", equipe, "workflows", `${id}.json`)
}

const CAMPOS_DE_TEXTO = ["instrucao", "criterio", "pergunta", "pauta"]
const ARQUIVO_DE_TEXTO = /^@([a-z0-9][a-z0-9-]{0,63}\.md)$/

// "@plano.md" num texto de caixa vira o conteúdo de workflows/<id>/plano.md; o nome é restrito porque vira caminho.
async function comTextos(raiz: string, equipe: string, id: string, bruto: unknown): Promise<unknown> {
  if (!bruto || typeof bruto !== "object" || !Array.isArray((bruto as { nos?: unknown }).nos)) return bruto
  const w = bruto as { nos: Record<string, unknown>[] }
  const nos = await Promise.all(
    w.nos.map(async (no) => {
      const copia = { ...no }
      for (const campo of CAMPOS_DE_TEXTO) {
        const valor = copia[campo]
        const m = typeof valor === "string" ? ARQUIVO_DE_TEXTO.exec(valor.trim()) : null
        if (!m) continue
        const arquivo = Bun.file(join(raiz, "equipes", equipe, "workflows", id, m[1]!))
        if (!(await arquivo.exists())) throw new Error(`caixa ${String(no.id)}: ${campo} aponta para ${m[1]}, que não existe`)
        copia[campo] = await arquivo.text()
      }
      return copia
    }),
  )
  return { ...w, nos }
}

export async function lerWorkflows(raiz: string, equipes: Equipe[]): Promise<{ equipe: string; workflow: Workflow }[]> {
  const lidos: { equipe: string; workflow: Workflow }[] = []
  for (const equipe of equipes) {
    let nomes: string[]
    try {
      nomes = (await readdir(join(raiz, "equipes", equipe.id, "workflows"))).filter((n) => n.endsWith(".json")).sort()
    } catch {
      continue
    }
    for (const nome of nomes) {
      const caminho = join(raiz, "equipes", equipe.id, "workflows", nome)
      let workflow: Workflow
      try {
        const bruto = (await Bun.file(caminho).json()) as { id?: unknown }
        workflow = validarWorkflow(await comTextos(raiz, equipe.id, String(bruto.id ?? ""), bruto), equipe)
      } catch (erro) {
        throw new Error(`${caminho}: ${(erro as Error).message}`)
      }
      if (`${workflow.id}.json` !== nome) throw new Error(`${caminho}: o id ${workflow.id} não bate com o nome do arquivo`)
      lidos.push({ equipe: equipe.id, workflow })
    }
  }
  return lidos
}

export async function validarWorkflowDaEquipe(raiz: string, equipe: Equipe, bruto: unknown): Promise<Workflow> {
  const id = String((bruto as { id?: unknown } | null)?.id ?? "")
  return validarWorkflow(await comTextos(raiz, equipe.id, id, bruto), equipe)
}

export async function lerWorkflowDoDisco(raiz: string, equipe: string, id: string): Promise<Record<string, unknown> | null> {
  const arquivo = Bun.file(caminhoDoWorkflow(raiz, equipe, id))
  if (!(await arquivo.exists())) return null
  return (await arquivo.json()) as Record<string, unknown>
}

export function versaoNoDisco(disco: Record<string, unknown> | null): number {
  if (!disco) return 0
  return typeof disco.versao === "number" && Number.isInteger(disco.versao) && disco.versao > 0 ? disco.versao : 1
}

export function conferirVersao(disco: Record<string, unknown> | null, id: string, base: unknown): void {
  const noDisco = versaoNoDisco(disco)
  const aberta = typeof base === "number" && Number.isInteger(base) && base > 0 ? base : 0
  if (noDisco && !aberta) throw new Error(`já existe um workflow com o id ${id}`)
  if (!noDisco && aberta) throw new Error(`o workflow ${id} não existe mais`)
  if (noDisco !== aberta) throw new Error(`o workflow ${id} mudou desde que você abriu (versão ${noDisco} no disco, ${aberta} no editor)`)
}

// O cliente recebe o texto lido do @arquivo.md e devolve texto: o que era arquivo continua arquivo.
export function devolverAosArquivos(
  disco: Record<string, unknown> | null,
  novo: Record<string, unknown>,
): { json: Record<string, unknown>; arquivos: { nome: string; texto: string }[] } {
  const antigas = new Map<string, Record<string, unknown>>()
  for (const no of Array.isArray(disco?.nos) ? disco.nos : []) {
    if (no && typeof no === "object") antigas.set(String((no as { id?: unknown }).id), no as Record<string, unknown>)
  }
  const arquivos: { nome: string; texto: string }[] = []
  const nos = (Array.isArray(novo.nos) ? novo.nos : []).map((no) => {
    if (!no || typeof no !== "object") return no
    const copia = { ...(no as Record<string, unknown>) }
    const antiga = antigas.get(String(copia.id))
    for (const campo of CAMPOS_DE_TEXTO) {
      const era = antiga?.[campo]
      const m = typeof era === "string" ? ARQUIVO_DE_TEXTO.exec(era.trim()) : null
      const valor = copia[campo]
      if (!m || typeof valor !== "string" || ARQUIVO_DE_TEXTO.test(valor.trim())) continue
      arquivos.push({ nome: m[1]!, texto: valor.endsWith("\n") ? valor : `${valor}\n` })
      copia[campo] = `@${m[1]}`
    }
    return copia
  })
  return { json: { ...novo, nos }, arquivos }
}

export async function gravarWorkflow(
  raiz: string,
  equipe: string,
  bruto: Record<string, unknown>,
  disco: Record<string, unknown> | null = null,
): Promise<void> {
  const id = String(bruto.id)
  const { json, arquivos } = devolverAosArquivos(disco, bruto)
  for (const { nome, texto } of arquivos) await Bun.write(join(raiz, "equipes", equipe, "workflows", id, nome), texto)
  await gravarJson(caminhoDoWorkflow(raiz, equipe, id), json)
}

export async function apagarWorkflow(raiz: string, equipe: string, id: string): Promise<void> {
  await rm(caminhoDoWorkflow(raiz, equipe, id), { force: true })
}

export async function gravarPersona(raiz: string, persona: Persona): Promise<void> {
  await gravarJson(caminhoDaPersona(raiz, persona.id), persona)
}

export function caminhoDasExcluidas(raiz: string): string {
  return join(raiz, "profiles", "excluidas.json")
}

export async function lerExcluidas(raiz: string): Promise<string[]> {
  const arquivo = Bun.file(caminhoDasExcluidas(raiz))
  if (!(await arquivo.exists())) return []
  const lista = await arquivo.json().catch(() => [])
  return Array.isArray(lista) ? lista.filter((id): id is string => typeof id === "string") : []
}

export async function reservarExcluida(raiz: string, id: string): Promise<void> {
  const lista = await lerExcluidas(raiz)
  if (!lista.includes(id)) await gravarJson(caminhoDasExcluidas(raiz), [...lista, id].sort())
}

export async function carregarElenco(raiz: string): Promise<Elenco> {
  const novo = await lerElenco(raiz)
  definirElenco(novo)
  return novo
}
