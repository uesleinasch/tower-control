# Conversa natural das personas ("Mimic Human") — design

TickTask #446. Data: 2026-09-30.

## Objetivo

Os conselheiros (Poe, Nati, Lucas, Pami) devem escrever como gente escreve num chat de
mensagens, e não como um assistente que quebra um documento em balões. Ao mesmo tempo,
devem gastar menos tokens e desenvolver, cada um, a própria identidade de fala.

Ficam fora: Alfred, board (parecer e síntese), UI e o atraso do "digitando".

## Decisões tomadas

- O corpus de referência (`conversas/`, exports do WhatsApp) contribui **só com a forma**.
  Nenhum texto dele entra em prompt ou no git: dele saem apenas números agregados.
- Cada persona tem **ritmo base próprio** dentro da faixa humana e **evolui** o vocabulário
  e os tiques na memória `jeito/`, a partir das próprias falas e das reações do Ueslei.
- Controle por **orçamento por turno** calculado sem LLM, com um normalizador que nunca
  corta conteúdo. Nada de teto rígido de tokens nem de segunda passada de LLM.

## O que o corpus mostrou

Cerca de 8.000 mensagens em 5 conversas. Na resposta típica há 2 balões e cerca de 8
palavras no total, e 90% das respostas ficam abaixo de 25 palavras. Esse número quase
não muda com o tamanho ou o tipo da mensagem recebida. Menos de 5% dos balões terminam
em ponto final. Reação de uma palavra e risada ("kkkk") são comuns.

Consequência: o orçamento tem um padrão forte e uma única saída, o pedido explícito de
profundidade.

## Componentes

### `scripts/extrair-ritmo.ts` (offline, roda à mão)

Lê `conversas/*.txt` no formato de export do WhatsApp (`dd/mm/aaaa hh:mm - Nome: texto`,
com ou sem vírgula e segundos, e mensagens de várias linhas). Descarta mídia oculta,
mensagem apagada e linhas vazias. Agrupa mensagens consecutivas do mesmo autor em
rajadas (uma rajada = uma "resposta") e grava `app/modelos/ritmo-corpus.json`:

- quantis p10/p50/p90 de `palavrasPorBalao`, `baloesPorResposta` e `palavrasPorResposta`;
- taxas de traço: `reacaoCurta` (balão de até 2 palavras), `risada`, `pontoFinal`,
  `inicioMinusculo` e `perguntaSolta`;
- `fonte`: quantidade de conversas e de mensagens, mais a data de geração. Nenhum nome.

O parser é puro (`app/src/ritmo-corpus.ts`) e testado. `conversas/` entra no `.gitignore`.

### Ritmo por persona: `app/modelos/profiles/<p>/ritmo.json`

```json
{ "baloes": 1.2, "palavras": 1.0, "risada": "as-vezes", "minusculas": true, "pontoFinal": false }
```

- `baloes` e `palavras` são multiplicadores sobre o corpus, limitados a [0,5; 2].
- `risada` vale `"nunca" | "rara" | "as-vezes"`.
- Bases iniciais (ajustáveis pelo Ueslei):
  - Poe: balões 1,2, palavras 1,0, risada às vezes, minúsculas, sem ponto final.
  - Nati: balões 0,7, palavras 1,5, risada nunca, maiúsculas, ponto final permitido.
  - Lucas: balões 0,8, palavras 1,3, risada rara, maiúsculas, sem ponto final.
  - Pami: balões 1,0, palavras 1,2, risada rara, minúsculas, sem ponto final.

Carregamento: primeiro a pasta de dados (`profiles/<p>/ritmo.json`, editável), depois o
modelo embutido no código. JSON ausente ou inválido cai no ritmo neutro (tudo 1,0) e
nunca derruba o turno. O `ritmo-corpus.json` é importado estaticamente e vai junto no
`bun build --compile`.

### Núcleo puro: `app/src/ritmo.ts`

- `classificar(mensagem)` devolve `"padrao" | "profundidade"`. É profundidade quando há
  pedido explícito (explica, detalha, aprofunda, compara, prós e contras, passo a passo,
  analisa) ou quando a mensagem tem mais de 60 palavras e pelo menos 2 perguntas.
- `orcamento(situacao, ritmo, corpus)` devolve `{ baloes: [min, max], palavrasPorBalao }`.
  - Padrão: `max = round(p50 × baloes) + 1`, limitado a [1, p90]; palavras =
    `round(p90 × palavras)`.
  - Profundidade: 3 a 6 balões, com o triplo das palavras do padrão.
- `blocoDeEscrita(orcamento, ritmo, situacao)` gera o texto de ~5 linhas que **substitui
  as `POLITICA_*`** dos conselheiros em `prompt.ts`. A política do Alfred continua igual.
- `normalizar(texto, parcial?)` transforma parágrafo em balão (linha `---`) e trata linha
  `---` do próprio modelo como separador. Fora de bloco de código, tira `#` de título,
  marcador de lista e `**`/`__`. Não corta conteúdo e é idempotente. No modo `parcial`,
  segura o trecho final ambíguo (quebras de linha pendentes, `*` solto, início de linha
  curto que pode virar marcador).
- `normalizadorDeStream(emitir)` recalcula `normalizar(acumulado, parcial)` a cada chunk
  e emite só o que cresceu. Como o modo parcial preserva prefixo, o que já saiu nunca
  muda. No fim, `finalizar()` emite o resto.
- `espelho(mensagens, ritmo, corpus)` monta o bloco de números para a consolidação
  (Seção "Evolução").

## Fluxo do turno

Em `conversar()` (`sessions.ts`), só para conselheiros:

1. `classificar(opcoes.consulta ?? opcoes.texto)`.
2. `orcamento(...)` com o ritmo da persona e o corpus.
3. `montarSystemPrompt(raiz, perfil, foco, brief, orcamento)`. O bloco ocupa o lugar de
   "## Tamanho da resposta". O system prompt já é remontado a cada turno por causa do
   brief, então o cache não piora.
4. O `onChunk` passa pelo `normalizadorDeStream`, e o texto devolvido (gravado no `.jsonl`)
   é `normalizar(acumulado)`. É necessário porque o evento `fim` não traz o texto final e
   a web mantém o que veio pelo stream.

Além do bloco, `lembreteDeForma(orcamento)` acrescenta uma linha entre parênteses ao fim
da mensagem enviada ao modelo. A mensagem gravada não muda. Medido: só com o bloco no
system prompt, o Haiku se alongava em pergunta de opinião (Poe com 44% no orçamento).
Com o lembrete, os quatro ficaram entre 89% e 100%.

O bloco proíbe título, lista e negrito, pede um pensamento por balão e diz que reação de
uma palavra conta como resposta. No modo profundidade, pede o assunto completo, ainda em
balões. Estouro de orçamento não é cortado, só medido.

## Evolução da identidade

A consolidação (30 min depois que a conversa para) recebe, no pedido, um bloco
`## Espelho da sua escrita` gerado por `espelho()`:

- **Suas falas:** mediana de palavras por balão e de balões por resposta comparadas ao
  alvo, e quantas respostas passaram do orçamento.
- **Reações do Ueslei logo depois de cada fala:** riu, mandou só "?" ou "não entendi",
  pediu para resumir ou encurtar, ou respondeu longo (15 palavras ou mais).

A tarefa de consolidação ganha um item: atualizar, ou criar se não existir, a lembrança
`jeito` com título **"Como eu escrevo"**, com expressões próprias, tiques, o que fez o
Ueslei rir e o que o fez pedir para encurtar. É a voz dela, não uma cópia da dele. Como
`jeito/` é fixado e entra no brief de todo turno, a evolução vale a partir da próxima
conversa. O sonho já compacta o `jeito/` acima do `LIMITE_JEITO`.

As personas não convergem para uma voz só porque os ritmos base são diferentes, a
memória é isolada por persona e o espelho mostra a reação do Ueslei a ela.

Não entra agora: a persona ajustar os números do próprio `ritmo.json` (ferramenta
`ajustar_ritmo` limitada a p10–p90). Fica para quando a métrica pedir.

## Avaliação

- `scripts/sonda-ritmo.txt` tem 12 mensagens fixas escritas para o teste: 9 do tipo
  padrão e 3 pedidos de profundidade.
- `scripts/sondar-ritmo.ts <rótulo> [persona...]` roda cada mensagem em cada conselheiro
  pelo `conversar()` real, sem memória, apaga a sessão do SDK e grava em
  `scripts/saida-sonda/<rótulo>/<persona>.jsonl` (fora do git).
- `scripts/medir-respostas.ts` passa a aceitar uma pasta de sonda e imprime, por persona,
  palavras por resposta, balões, formatação de documento e % dentro do orçamento,
  além da comparação `antes` × `depois`.

Critérios de sucesso:

1. No modo padrão, pelo menos 80% das respostas cabem no orçamento, e a mediana de
   palavras por resposta fica em até 1,5× o alvo da persona.
2. A saída média do modo padrão cai pelo menos 50% em relação ao `antes`.
3. Os pedidos de profundidade continuam recebendo resposta completa (conferência manual).
4. As quatro personas ficam distinguíveis nos números.
5. O Ueslei lê as saídas e conversa com o Poe no app. A naturalidade é validada por ele,
   não por teste.

### Resultado da sonda (2026-09-30, Haiku, sem memória)

Modo padrão, média de palavras por resposta e % no orçamento:

| persona | antes | depois | variação | no orçamento |
|---|---|---|---|---|
| Poe | 40 | 20 | -50% | 22% → 89% |
| Nati | 53 | 13 | -75% | 11% → 100% |
| Lucas | 54 | 24 | -56% | 33% → 89% |
| Pami | 59 | 18 | -69% | 22% → 100% |

No modo profundidade, o tamanho ficou parecido com o de antes (~190–250 palavras), sem
formatação de documento e em 4 a 6 balões. Os critérios 3 e 5 dependem da leitura do
Ueslei.

## Testes (`nucleo.test.ts`)

Parser do export (datas com e sem vírgula, mensagens de várias linhas, mídia oculta);
`classificar`; `orcamento` (limites); `blocoDeEscrita`; `normalizar` (idempotência,
parágrafo vira balão, bloco de código preservado, sem perder palavra);
`normalizadorDeStream` (qualquer divisão em chunks dá o mesmo resultado que
`normalizar`); `espelho` (risada, "?", pedido para encurtar); carregamento de ritmo
com fallback.
