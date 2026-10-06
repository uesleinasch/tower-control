import { join } from "node:path"
import { randomUUID } from "node:crypto"
import { appendFile, mkdir, rename } from "node:fs/promises"

export type TipoDeAviso = "resposta" | "aprovacao" | "lembrete" | "resumo" | "atrasada"
export type Acao = "aprovar" | "negar" | "concluir" | "adiar" | "responder"
export type Como = "aprovado" | "negado" | "concluida" | "adiada" | "respondido" | "lido" | "expirado"

export interface Aviso {
  id: string
  seq: number
  tipo: TipoDeAviso
  titulo: string
  corpo: string
  alvo: { conversaId?: string; permissaoId?: string; tarefaId?: number }
  acoes: Acao[]
  criadoEm: string
  expiraEm?: string
}

export interface Resolvido {
  tipo: "resolvido"
  id: string
  seq: number
  como: Como
  em: string
  aparelho?: string
}

export type Linha = Aviso | Resolvido
export type NovoAviso = Omit<Aviso, "id" | "seq" | "criadoEm"> & { id?: string }

const DIAS_DE_GUARDA = 7

export const ehResolvido = (linha: Linha): linha is Resolvido => linha.tipo === "resolvido"

export function caminhoDosAvisos(raiz: string): string {
  return join(raiz, "conversations", "avisos.jsonl")
}

export function lerLinhas(texto: string): Linha[] {
  return texto.split("\n").flatMap((linha) => {
    if (!linha.trim()) return []
    try {
      const valor = JSON.parse(linha) as Linha
      return typeof valor?.seq === "number" && typeof valor.id === "string" ? [valor] : []
    } catch {
      return []
    }
  })
}

// A última linha fica sempre: é ela que guarda o maior seq, e um contador que recomeçasse
// do zero deixaria mudo o cliente que reconecta pedindo `desde` alto.
export function podar(linhas: Linha[], agora: Date): Linha[] {
  const limite = agora.getTime() - DIAS_DE_GUARDA * 86_400_000
  return linhas.filter((linha, i) => {
    if (i === linhas.length - 1) return true
    const quando = ehResolvido(linha) ? linha.em : linha.criadoEm
    return Date.parse(quando) >= limite
  })
}

export function backlog(linhas: Linha[], desde: number): Linha[] {
  const maior = linhas.at(-1)?.seq ?? 0
  if (desde > maior) return linhas
  return linhas.filter((linha) => linha.seq > desde)
}

export function abertos(linhas: Linha[]): Aviso[] {
  const resolvidos = new Set(linhas.filter(ehResolvido).map((l) => l.id))
  return linhas.filter((l): l is Aviso => !ehResolvido(l) && !resolvidos.has(l.id))
}

export const linhaNdjson = (linha: Linha | Record<string, never>): string => `${JSON.stringify(linha)}\n`

export type Recusa = { recusado: "inexistente" } | { recusado: "resolvido"; resolucao: Resolvido }

export class CentralDeAvisos {
  private linhas: Linha[] = []
  private readonly ouvintes = new Set<(linha: Linha) => void>()
  private gravacao: Promise<unknown> = Promise.resolve()

  constructor(
    private readonly arquivo: string,
    private readonly relogio: () => Date = () => new Date(),
  ) {}

  async carregar(): Promise<void> {
    const arquivo = Bun.file(this.arquivo)
    const lidas = (await arquivo.exists()) ? lerLinhas(await arquivo.text()) : []
    this.linhas = podar(lidas, this.relogio())
    if (this.linhas.length !== lidas.length) {
      await mkdir(join(this.arquivo, ".."), { recursive: true })
      const temporario = `${this.arquivo}.${randomUUID()}.tmp`
      await Bun.write(temporario, this.linhas.map(linhaNdjson).join(""))
      await rename(temporario, this.arquivo)
    }
    // Nenhuma permissão sobrevive a um restart: o executor que esperava por ela morreu junto.
    for (const aviso of abertos(this.linhas)) {
      if (aviso.tipo === "aprovacao") await this.resolver(aviso.id, "expirado")
    }
  }

  get escutando(): number {
    return this.ouvintes.size
  }

  assinar(ouvinte: (linha: Linha) => void): () => void {
    this.ouvintes.add(ouvinte)
    return () => this.ouvintes.delete(ouvinte)
  }

  desde(seq: number): Linha[] {
    return backlog(this.linhas, seq)
  }

  abertos(): Aviso[] {
    return abertos(this.linhas)
  }

  obter(id: string): Aviso | undefined {
    return this.linhas.find((l): l is Aviso => !ehResolvido(l) && l.id === id)
  }

  resolucao(id: string): Resolvido | undefined {
    return this.linhas.find((l): l is Resolvido => ehResolvido(l) && l.id === id)
  }

  async criar(novo: NovoAviso): Promise<Aviso> {
    const aviso: Aviso = {
      ...novo,
      id: novo.id ?? randomUUID(),
      seq: this.proximoSeq(),
      criadoEm: this.relogio().toISOString(),
    }
    await this.registrar(aviso)
    return aviso
  }

  async resolver(id: string, como: Como, aparelho?: string): Promise<Resolvido | Recusa> {
    if (!this.obter(id)) return { recusado: "inexistente" }
    const anterior = this.resolucao(id)
    if (anterior) return { recusado: "resolvido", resolucao: anterior }
    const evento: Resolvido = {
      tipo: "resolvido",
      id,
      seq: this.proximoSeq(),
      como,
      em: this.relogio().toISOString(),
      ...(aparelho ? { aparelho } : {}),
    }
    await this.registrar(evento)
    return evento
  }

  private proximoSeq(): number {
    return (this.linhas.at(-1)?.seq ?? 0) + 1
  }

  private async registrar(linha: Linha): Promise<void> {
    this.linhas.push(linha)
    for (const ouvinte of this.ouvintes) ouvinte(linha)
    const gravar = async () => {
      await mkdir(join(this.arquivo, ".."), { recursive: true })
      await appendFile(this.arquivo, linhaNdjson(linha))
    }
    this.gravacao = this.gravacao.then(gravar, gravar)
    await this.gravacao
  }
}
