import { lerPerfil } from "../prompt"
import type { Conselheiro } from "../tipos"
import { alterarEstado } from "./agenda"
import { LIMITE_JEITO, ehFundida, lerJeito } from "./recuperacao"
import { instrucoesDeBastidor, rodarPersona } from "./sessao"
import type { Memoria, Pagina } from "./tipos"

export const MAXIMO_FRIAS = 40

const TAREFA = `Tarefa: sonhar. É a noite da sua memória: reorganizar o que ficou velho e espalhado.

1. Lembranças frias: agrupe as que falam da mesma coisa e use fundir_lembrancas para
   reescrever cada grupo como uma lembrança só, na sua voz, guardando o que importa e
   largando o detalhe que não faz falta. Lembrança fria sem par fica como está.
2. Seu jeito: se estiver acima do teto indicado, funda e resuma com fundir_lembrancas
   até caber, decidindo o que ainda define quem você é com o Ueslei. Abaixo do teto,
   não mexa.
3. Nunca apague sentido: se duas lembranças se contradizem, a mais nova vale, e a fusão
   diz o que mudou.`

export function tamanhoDoJeito(jeito: Pagina[]): number {
  return jeito.reduce((total, p) => total + p.titulo.length + p.corpo.length + 4, 0)
}

function bloco(p: Pagina): string {
  return `### ${p.path}\n\n${p.corpo.trim()}`
}

export function montarPedidoSonho(frias: Pagina[], jeito: Pagina[], limiteJeito: number = LIMITE_JEITO): string {
  const tamanho = tamanhoDoJeito(jeito)
  return `## Lembranças frias (${frias.length})

${frias.length ? frias.map(bloco).join("\n\n") : "(nenhuma)"}

## Seu jeito hoje: ${tamanho} de ${limiteJeito} caracteres${tamanho > limiteJeito ? " — ACIMA do teto" : ""}

${jeito.length ? jeito.map(bloco).join("\n\n") : "(vazio)"}

Sonhe.`
}

export function precisaSonhar(frias: Pagina[], jeito: Pagina[], limiteJeito: number = LIMITE_JEITO): boolean {
  return frias.length >= 2 || tamanhoDoJeito(jeito) > limiteJeito
}

export async function sonhar(raiz: string, m: Memoria, persona: Conselheiro): Promise<void> {
  const caminhos = await m.frias(persona, MAXIMO_FRIAS)
  const lidas = await Promise.all(caminhos.map((c) => m.ler(persona, c)))
  const frias = lidas.filter((p): p is Pagina => p !== null && !ehFundida(p.titulo))
  const jeito = await lerJeito(m, persona)

  if (precisaSonhar(frias, jeito)) {
    const perfil = await lerPerfil(raiz, persona)
    const data = new Date().toISOString().slice(0, 10)
    await rodarPersona({
      raiz,
      persona,
      system: [perfil, instrucoesDeBastidor(persona, TAREFA)].filter(Boolean).join("\n\n---\n\n"),
      prompt: montarPedidoSonho(frias, jeito),
      memoria: m,
      origem: `sonho:${data}`,
    })
    console.log(`[memoria] ${persona} sonhou sobre ${frias.length} lembrança(s) fria(s)`)
  }
  await alterarEstado(raiz, (e) => {
    e.sonhos[persona] = new Date().toISOString()
  })
}
