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
