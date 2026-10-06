export interface Mudanca {
  mostrada: string | null
  deixadas: string[]
}

export class Presenca<S> {
  private readonly visiveis = new Map<S, string>()

  estaVisivel(conversaId: string): boolean {
    for (const id of this.visiveis.values()) if (id === conversaId) return true
    return false
  }

  definir(socket: S, conversaId: string | null): Mudanca {
    const anterior = this.visiveis.get(socket) ?? null
    if (conversaId) this.visiveis.set(socket, conversaId)
    else this.visiveis.delete(socket)
    return {
      mostrada: conversaId && conversaId !== anterior ? conversaId : null,
      deixadas: anterior && anterior !== conversaId && !this.estaVisivel(anterior) ? [anterior] : [],
    }
  }

  remover(socket: S): Mudanca {
    return this.definir(socket, null)
  }
}
