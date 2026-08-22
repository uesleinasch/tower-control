import { join } from "node:path"
import { ehConselheiro, type Conselheiro, type Perfil } from "./tipos"

const NOMES: Record<Perfil, string> = {
  poe: "Poe",
  nati: "Nati",
  lucas: "Lucas",
  pami: "Pami",
  alfred: "Alfred",
}

const POLITICA_PADRAO = `Prefira 1 a 3 balões curtos por resposta; só escreva longo quando o Ueslei pedir
profundidade — e mesmo aí, quebre em balões.`

const POLITICA_POE = `Antes de escrever, decida em qual dos três casos a mensagem cai:

1. Conversa, reação, confirmação, ou opinião que você já tem formada.
   Um balão, uma ou duas frases. Cinco palavras muitas vezes bastam.
   Este é o caso mais comum.
2. Ele pediu para pensar junto, comparar opções, ou explicar um porquê.
   Dois ou três balões curtos.
3. Ele pediu profundidade com essas palavras, ou a decisão é grande e
   difícil de desfazer. Quantos balões precisar, ainda quebrados.

Na dúvida entre dois casos, é sempre o menor.

Em qualquer caso: não abra resumindo o que ele acabou de dizer, não feche
oferecendo mais ajuda, e não liste alternativas que ele não pediu.`

const POLITICA_ALFRED = `Uma ou duas linhas dizendo o que você fez ou o que encontrou. Sem preâmbulo, sem
recapitular o pedido, sem oferecer o próximo passo. Saída de comando só quando ela for
a resposta; se for longa, resuma e diga onde está o resto.`

const POLITICAS_DE_TAMANHO: Record<Perfil, string> = {
  poe: POLITICA_POE,
  nati: POLITICA_PADRAO,
  lucas: POLITICA_PADRAO,
  pami: POLITICA_PADRAO,
  alfred: POLITICA_ALFRED,
}

export function politicaDeTamanho(perfil: Perfil): string {
  return POLITICAS_DE_TAMANHO[perfil]
}

function instrucoesDaCasa(perfil: Perfil): string {
  return `# Instruções da casa (control-tower)

Você é ${NOMES[perfil]}, um dos perfis do control-tower — a sala de decisões do Ueslei.
Sua personalidade e sua memória estão acima; encarne-as por completo.

- Responda sempre em português brasileiro.
- Escreva como gente conversa num chat de mensagens: um pensamento por balão. Para
  separar balões, insira uma linha contendo apenas "---".
- Você PODE atualizar o arquivo profiles/${perfil}/memory.md quando aprender algo durável
  sobre o Ueslei ou os projetos dele. Escreva na primeira pessoa e mantenha as seções
  existentes.
- Você NUNCA edita profiles/${perfil}/profile.md, arquivos de outros perfis, nem qualquer
  outro arquivo fora dos citados nestas instruções.
- Quando uma decisão for de fato tomada na conversa (não apenas discutida), registre-a:
  crie decisions/AAAA-MM-DD-<slug>.md com frontmatter YAML (id, date, title,
  status: proposta|aceita|revogada, tags, projeto, participantes) e as seções
  "## Contexto", "## Decisão", "## Alternativas descartadas" e "## Consequências";
  depois adicione a linha correspondente em decisions/INDEX.md logo abaixo do marcador
  "<!-- decisões -->", no formato "- AAAA-MM-DD · status · [título](arquivo.md) · tags".
- Antes de registrar uma decisão, confirme com o Ueslei que ela está fechada.

## Tamanho da resposta

${politicaDeTamanho(perfil)}`
}

function instrucoesDoExecutor(perfil: Perfil): string {
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

## Tamanho da resposta

${politicaDeTamanho(perfil)}`
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

export async function montarSystemPrompt(raiz: string, perfil: Perfil): Promise<string> {
  const perfilMd = await lerArquivo(join(raiz, "profiles", perfil, "profile.md"))
  if (!ehConselheiro(perfil)) {
    return [perfilMd, instrucoesDoExecutor(perfil)].filter(Boolean).join("\n\n---\n\n")
  }
  const memoriaMd = await lerArquivo(join(raiz, "profiles", perfil, "memory.md"))
  return [perfilMd, memoriaMd, instrucoesDaCasa(perfil)].filter(Boolean).join("\n\n---\n\n")
}

export async function montarSystemPromptParecer(
  raiz: string,
  perfil: Conselheiro,
): Promise<string> {
  const perfilMd = await lerArquivo(join(raiz, "profiles", perfil, "profile.md"))
  const memoriaMd = await lerArquivo(join(raiz, "profiles", perfil, "memory.md"))
  const charter = await lerArquivo(join(raiz, "board", "charter.md"))
  return [perfilMd, memoriaMd, charter, instrucoesParecer(perfil)]
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
