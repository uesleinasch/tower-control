import { join } from "node:path"
import { mkdir, rename } from "node:fs/promises"
import { conselheiros, ehConselheiro, type Conselheiro, type Mensagem, type MetaConversa } from "../tipos"

export const OCIOSIDADE_MS = 30 * 60_000
export const HORARIO_SONHO = process.env.CT_HORARIO_SONHO ?? "07:30"
const INTERVALO_MS = 5 * 60_000

export interface EstadoMemoria {
  sonhos: Partial<Record<Conselheiro, string>>
  atividade: Partial<Record<Conselheiro, string>>
  migracaoBloqueada?: Partial<Record<Conselheiro, string[]>>
}

export function consolidacaoPendente(meta: MetaConversa, mensagens: Mensagem[], agora: Date): boolean {
  if (!ehConselheiro(meta.perfil)) return false
  const feitas = meta.consolidadoAte ?? 0
  if (mensagens.length <= feitas) return false
  const ultima = Date.parse(mensagens[mensagens.length - 1]!.ts)
  return Number.isFinite(ultima) && agora.getTime() - ultima >= OCIOSIDADE_MS
}

export function marcoDoSonho(agora: Date, horario: string = HORARIO_SONHO): Date {
  const [h, min] = horario.split(":").map(Number)
  const marco = new Date(agora)
  marco.setHours(h ?? 7, min ?? 30, 0, 0)
  if (marco.getTime() > agora.getTime()) marco.setDate(marco.getDate() - 1)
  return marco
}

export function sonhoDevido(
  ultimoSonho: string | undefined,
  ultimaAtividade: string | undefined,
  agora: Date,
  horario: string = HORARIO_SONHO,
): boolean {
  if (!ultimaAtividade) return false
  if (!ultimoSonho) return true
  const sonho = Date.parse(ultimoSonho)
  return sonho < marcoDoSonho(agora, horario).getTime() && Date.parse(ultimaAtividade) > sonho
}

function caminhoEstado(raiz: string): string {
  return join(raiz, "conversations", "memoria.json")
}

export async function lerEstado(raiz: string): Promise<EstadoMemoria> {
  try {
    const bruto = (await Bun.file(caminhoEstado(raiz)).json()) as Partial<EstadoMemoria>
    return { sonhos: bruto.sonhos ?? {}, atividade: bruto.atividade ?? {}, migracaoBloqueada: bruto.migracaoBloqueada }
  } catch {
    return { sonhos: {}, atividade: {} }
  }
}

let fila: Promise<unknown> = Promise.resolve()

export function alterarEstado(raiz: string, mudar: (estado: EstadoMemoria) => void): Promise<void> {
  const proxima = fila.then(async () => {
    const estado = await lerEstado(raiz)
    mudar(estado)
    await mkdir(join(raiz, "conversations"), { recursive: true })
    const temporario = `${caminhoEstado(raiz)}.tmp`
    await Bun.write(temporario, JSON.stringify(estado, null, 2))
    await rename(temporario, caminhoEstado(raiz))
  })
  fila = proxima.catch(() => {})
  return proxima
}

export function registrarAtividade(raiz: string, persona: Conselheiro, quando: Date = new Date()): Promise<void> {
  return alterarEstado(raiz, (e) => {
    e.atividade[persona] = quando.toISOString()
  })
}

export interface Trabalhos {
  migrar(): Promise<void>
  pendentes(agora: Date): Promise<MetaConversa[]>
  consolidar(meta: MetaConversa): Promise<void>
  guardadas(): Promise<void>
  sonhar(persona: Conselheiro): Promise<void>
}

const ESPERA_MAXIMA_MS = 6 * 60 * 60_000

export class Espera {
  private falhas = new Map<string, { vezes: number; ate: number }>()

  pode(chave: string, agora: Date): boolean {
    return (this.falhas.get(chave)?.ate ?? 0) <= agora.getTime()
  }

  falhou(chave: string, agora: Date): void {
    const vezes = (this.falhas.get(chave)?.vezes ?? 0) + 1
    const espera = Math.min(INTERVALO_MS * 2 ** (vezes - 1), ESPERA_MAXIMA_MS)
    this.falhas.set(chave, { vezes, ate: agora.getTime() + espera })
  }

  deuCerto(chave: string): void {
    this.falhas.delete(chave)
  }
}

async function tentar(espera: Espera, chave: string, agora: Date, acao: () => Promise<void>): Promise<void> {
  if (!espera.pode(chave, agora)) return
  try {
    await acao()
    espera.deuCerto(chave)
  } catch (erro) {
    espera.falhou(chave, agora)
    console.warn(`[memoria] ${chave} falhou — ${(erro as Error).message}`)
  }
}

export async function rodarUmaVez(
  raiz: string,
  trabalhos: Trabalhos,
  espera: Espera = new Espera(),
  agora: Date = new Date(),
): Promise<void> {
  await tentar(espera, "migração dos memory.md", agora, () => trabalhos.migrar())
  for (const meta of await trabalhos.pendentes(agora)) {
    await tentar(espera, `consolidação de ${meta.id}`, agora, () => trabalhos.consolidar(meta))
  }
  await tentar(espera, "consolidação das conversas apagadas", agora, () => trabalhos.guardadas())
  const estado = await lerEstado(raiz)
  for (const persona of conselheiros()) {
    if (!sonhoDevido(estado.sonhos[persona], estado.atividade[persona], agora)) continue
    await tentar(espera, `sonho de ${persona}`, agora, () => trabalhos.sonhar(persona))
  }
}
