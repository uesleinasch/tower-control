import { join } from "node:path"
import { mkdir, readdir } from "node:fs/promises"
import {
  CASA,
  Elenco,
  casaInicial,
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
  const casa: Equipe = validarEquipe(await Bun.file(caminhoDaEquipe(raiz, CASA)).json(), new Set(personas.map((p) => p.id)))
  return new Elenco(personas, casa)
}

export async function carregarElenco(raiz: string): Promise<Elenco> {
  const novo = await lerElenco(raiz)
  definirElenco(novo)
  return novo
}
