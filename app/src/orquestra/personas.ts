import { join } from "node:path"
import { rm } from "node:fs/promises"
import { comPersonaNaCasa, idDoNome, semPersona, validarPersona, type Persona, type PersonaId } from "./equipe"
import { carregarElenco, elenco, gravarEquipe, gravarPersona, lerExcluidas, reservarExcluida } from "./elenco"
import { exigirPerfilExcluivel } from "../tipos"
import { perguntarUmaVez } from "../sessions"

export interface PedidoDePersona {
  nome: string
  base: string
  titulo: string
  modelo?: string
  cor?: string
}

const LIMITE_DA_BASE = 4_000
const MODELO_DO_PERFIL = "sonnet"

function texto(valor: unknown, limite: number): string {
  return typeof valor === "string" ? valor.trim().slice(0, limite) : ""
}

export function lerPedidoDePersona(bruto: unknown): PedidoDePersona {
  const p = (bruto && typeof bruto === "object" ? bruto : {}) as Record<string, unknown>
  const nome = texto(p.nome, 40)
  const base = texto(p.base, LIMITE_DA_BASE)
  if (!nome) throw new Error("a persona precisa de um nome")
  if (!base) throw new Error("descreva a persona: quem é, que papel tem e qual é o jeito dela")
  const pedido: PedidoDePersona = { nome, base, titulo: texto(p.titulo, 60) || "conselho" }
  const modelo = texto(p.modelo, 60)
  if (modelo) pedido.modelo = modelo
  const cor = texto(p.cor, 7)
  if (cor) pedido.cor = cor
  return pedido
}

export function novaPersona(pedido: PedidoDePersona, existentes: ReadonlySet<string>, excluidas: ReadonlySet<string>): Persona {
  const id = idDoNome(pedido.nome)
  if (existentes.has(id)) throw new Error(`já existe uma persona com o id ${id}: escolha outro nome`)
  if (excluidas.has(id)) throw new Error(`o id ${id} foi de uma persona excluída e não pode ser reusado: escolha outro nome`)
  return validarPersona({ id, nome: pedido.nome, modelo: pedido.modelo, cor: pedido.cor })
}

export function perfilProvisorio(persona: Persona, base: string): string {
  return `# ${persona.nome}\n\n${base.trim()}\n`
}

export function pedidoDeGeracao(persona: Persona, base: string, exemplo: string): { system: string; prompt: string } {
  return {
    system: `Você escreve o profile.md de uma persona do control-tower, a sala de decisões do Ueslei. O profile.md é o
system prompt da persona: diz quem ela é, que papel tem com o Ueslei, como pensa, o que valoriza, como
fala e o que evita. Escreva em português brasileiro, em segunda pessoa ("Você é ..."), em Markdown, no
mesmo formato e na mesma profundidade do exemplo. Não invente fatos sobre o Ueslei. Responda só com o
conteúdo do arquivo, sem comentários antes ou depois.`,
    prompt: `## Exemplo de profile.md (de outra persona, só pelo formato)\n\n${exemplo.trim()}\n\n## A persona nova\n\nNome: ${persona.nome}\n\nDescrição do Ueslei:\n\n${base.trim()}\n\nEscreva o profile.md de ${persona.nome}.`,
  }
}

export async function criarPersona(raiz: string, pedido: PedidoDePersona): Promise<Persona> {
  const atual = elenco()
  const persona = novaPersona(pedido, new Set(atual.ids()), new Set(await lerExcluidas(raiz)))
  await gravarPersona(raiz, persona)
  await Bun.write(join(raiz, "profiles", persona.id, "profile.md"), perfilProvisorio(persona, pedido.base))
  await gravarEquipe(raiz, comPersonaNaCasa(atual.casa, persona.id, pedido.titulo))
  await carregarElenco(raiz)
  return persona
}

async function exemploDePerfil(raiz: string): Promise<string> {
  for (const id of ["nati", "poe", ...elenco().ids()]) {
    const arquivo = Bun.file(join(raiz, "profiles", id, "profile.md"))
    if (await arquivo.exists()) {
      const texto = (await arquivo.text()).trim()
      if (texto) return texto
    }
  }
  return ""
}

export async function gerarPerfil(raiz: string, persona: Persona, base: string): Promise<void> {
  const { system, prompt } = pedidoDeGeracao(persona, base, await exemploDePerfil(raiz))
  const perfil = (await perguntarUmaVez({ raiz, system, prompt, modelo: MODELO_DO_PERFIL, uso: { tipo: "persona", perfil: persona.id } })).trim()
  if (!perfil) throw new Error("a geração devolveu um perfil vazio")
  if (!elenco().existe(persona.id)) return
  await Bun.write(join(raiz, "profiles", persona.id, "profile.md"), `${perfil}\n`)
}

export async function excluirPersona(raiz: string, id: PersonaId, confirmacao: string): Promise<string> {
  const atual = elenco()
  if (!atual.existe(id)) throw new Error(`a persona ${id} não existe`)
  exigirPerfilExcluivel(id)
  const nome = atual.nome(id)
  if (confirmacao.trim() !== nome) throw new Error(`para excluir, digite o nome exato da persona (${nome})`)
  for (const equipe of atual.equipes()) {
    if (equipe.posicoes.some((p) => p.persona === id)) await gravarEquipe(raiz, semPersona(equipe, id))
  }
  await rm(join(raiz, "profiles", id), { recursive: true, force: true })
  await reservarExcluida(raiz, id)
  await carregarElenco(raiz)
  return nome
}
