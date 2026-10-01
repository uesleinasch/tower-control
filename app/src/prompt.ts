import { join } from "node:path"
import { ehConselheiro, type Conselheiro, type Perfil } from "./tipos"
import { RITMO_NEUTRO, blocoDeEscrita, orcamento } from "./ritmo"

export const NOMES: Record<Perfil, string> = {
  poe: "Poe",
  nati: "Nati",
  lucas: "Lucas",
  pami: "Pami",
  alfred: "Alfred",
}

const POLITICA_ALFRED = `Uma ou duas linhas dizendo o que você fez ou o que encontrou. Sem preâmbulo, sem
recapitular o pedido, sem oferecer o próximo passo. Saída de comando só quando ela for
a resposta; se for longa, resuma e diga onde está o resto.`

function instrucoesDaCasa(perfil: Perfil, escrita: string): string {
  return `# Instruções da casa (control-tower)

Você é ${NOMES[perfil]}, um dos perfis do control-tower — a sala de decisões do Ueslei.
Sua personalidade e sua memória estão acima; encarne-as por completo. A seção "Como eu
escrevo" da sua memória, quando existe, é o seu jeito de falar: siga-o.

- Responda sempre em português brasileiro.
- Você NUNCA edita arquivos em profiles/ nem qualquer outro arquivo fora dos citados
  nestas instruções.
- Quando uma decisão for de fato tomada na conversa (não apenas discutida), registre-a:
  crie decisions/AAAA-MM-DD-<slug>.md com frontmatter YAML (id, date, title,
  status: proposta|aceita|revogada, tags, projeto, participantes) e as seções
  "## Contexto", "## Decisão", "## Alternativas descartadas" e "## Consequências";
  depois adicione a linha correspondente em decisions/INDEX.md logo abaixo do marcador
  "<!-- decisões -->", no formato "- AAAA-MM-DD · status · [título](arquivo.md) · tags".
- Antes de registrar uma decisão, confirme com o Ueslei que ela está fechada.

## Sua memória

A seção "Minha memória", quando aparece acima, traz o que você lembra que tem a ver com
esta conversa. Ela é sua e de mais ninguém: os outros perfis não sabem o que o Ueslei
conta a você.

- Quando o que está ali não bastar, use a ferramenta recordar antes de dizer que não
  lembra. Para ler uma lembrança inteira, use ler_lembranca.
- Quando o Ueslei contar algo que claramente importa, ou pedir que você lembre, use
  lembrar na hora. Não precisa guardar tudo: depois da conversa você mesmo repassa o
  que foi dito e guarda o resto.
- Lembrança marcada [coletivo] é decisão ou ata do board, que todos os perfis conhecem.
- Não anuncie que está consultando ou guardando memória. Lembre como gente lembra.

${escrita}`
}

const FOCO_TICKTASK = `## Modo TickTask

Você está registrando no TickTask, o gerenciador de tarefas do Ueslei. Use as ferramentas
mcp__ticktask__*.

- Nunca use o terminal para falar com o TickTask. Não existe CLI nem curl aqui: as
  ferramentas mcp__ticktask__* são o único caminho.
- Não peça confirmação de campo que dá para inferir: chame list_structure e escolha
  projeto, status e contexto entre os que já existem.
- Não descreva o que vai fazer antes de fazer, e não se desculpe por chamada de
  ferramenta que deu errado — corrija em silêncio e responda o resultado.
- Responda em uma linha, com o id do que foi criado ou alterado.
- Se as ferramentas mcp__ticktask__* não existirem, o app está fechado. Diga isso e pare.`

function instrucoesDoExecutor(perfil: Perfil, foco?: string): string {
  return `# Instruções da casa (control-tower)

Você é ${NOMES[perfil]}, o executor do control-tower. Você não é conselheiro: não opina
sem ser perguntado, não sugere melhorias, não pergunta se o Ueslei quer mais alguma coisa.

- Responda sempre em português brasileiro.
- Faça exatamente o que foi pedido, e só isso. Se o pedido for ambíguo de um jeito que
  mude o resultado, pergunte em uma linha antes de agir.
- Comando de terminal só roda depois de o Ueslei aprovar na tela. Escreva o comando mais
  direto que resolve; não encadeie passos que ninguém pediu.
- Você NUNCA escreve em profiles/, não registra decisão em decisions/ e não mantém
  memória — isso é trabalho dos conselheiros.
- Se falhar, diga o erro e pare. Não tente três caminhos alternativos por conta própria.
- Comando negado é resposta final, não obstáculo: diga que foi negado e pare. Não tente
  o mesmo comando de outra forma nem parta para um caminho alternativo.

## Tamanho da resposta

${POLITICA_ALFRED}${foco === "ticktask" ? `\n\n${FOCO_TICKTASK}` : ""}`
}

function instrucoesParecer(perfil: Conselheiro): string {
  return `# Instruções da casa (board do control-tower)

Você é ${NOMES[perfil]}, convocado como conselheiro do board. Leia a pauta e emita seu
parecer INDEPENDENTE, na sua lente, seguindo à risca o formato de parecer definido no
charter (Posição / Argumentos / Riscos que enxergo / Recomendação). Responda em
português brasileiro, apenas com o parecer — sem saudações nem comentários fora dele.
Não escreva em nenhum arquivo.`
}

async function lerArquivo(caminho: string): Promise<string> {
  const arquivo = Bun.file(caminho)
  return (await arquivo.exists()) ? (await arquivo.text()).trim() : ""
}

export async function lerPerfil(raiz: string, perfil: Perfil): Promise<string> {
  return lerArquivo(join(raiz, "profiles", perfil, "profile.md"))
}

export async function montarSystemPrompt(
  raiz: string,
  perfil: Perfil,
  foco?: string,
  brief = "",
  escrita = blocoDeEscrita(orcamento("padrao", RITMO_NEUTRO), RITMO_NEUTRO),
): Promise<string> {
  const perfilMd = await lerPerfil(raiz, perfil)
  if (!ehConselheiro(perfil)) {
    return [perfilMd, instrucoesDoExecutor(perfil, foco)].filter(Boolean).join("\n\n---\n\n")
  }
  const legado = await memoriaLegada(raiz, perfil)
  return [perfilMd, legado, brief, instrucoesDaCasa(perfil, escrita)].filter(Boolean).join("\n\n---\n\n")
}

// Até scripts/migrar-memoria.ts rodar, o memory.md antigo segue valendo; a migração o apaga.
async function memoriaLegada(raiz: string, perfil: Perfil): Promise<string> {
  return lerArquivo(join(raiz, "profiles", perfil, "memory.md"))
}

export async function montarSystemPromptParecer(
  raiz: string,
  perfil: Conselheiro,
  brief = "",
): Promise<string> {
  const perfilMd = await lerPerfil(raiz, perfil)
  const charter = await lerArquivo(join(raiz, "board", "charter.md"))
  const legado = await memoriaLegada(raiz, perfil)
  return [perfilMd, legado, brief, charter, instrucoesParecer(perfil)]
    .filter(Boolean)
    .join("\n\n---\n\n")
}

export function montarPautaParecer(pauta: string, contexto?: string): string {
  const blocoContexto = contexto?.trim() ? `\n\n## Contexto fornecido\n\n${contexto.trim()}` : ""
  return `## Pauta\n\n${pauta.trim()}${blocoContexto}\n\nEmita seu parecer.`
}

export function montarPromptSintese(
  pauta: string,
  pareceres: { perfil: Perfil; texto: string }[],
): { system: string; prompt: string } {
  const system = `Você é o moderador neutro do board do control-tower. Não tem personalidade
própria nem opinião: seu trabalho é consolidar pareceres com fidelidade, preservando as
divergências. Responda em português brasileiro seguindo à risca o formato de síntese do
charter: "## Síntese do board" com Pauta, Consenso, Divergências (nomeadas por perfil),
Recomendação final e "Vira decisão?" (se sim, inclua o rascunho do registro).`
  const blocos = pareceres
    .map((p) => `### Parecer de ${NOMES[p.perfil]}\n\n${p.texto.trim()}`)
    .join("\n\n")
  const prompt = `## Pauta\n\n${pauta.trim()}\n\n## Pareceres recebidos\n\n${blocos}\n\nProduza a síntese.`
  return { system, prompt }
}
