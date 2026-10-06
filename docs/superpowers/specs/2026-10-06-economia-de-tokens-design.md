# Economia de tokens: medir e estabilizar o cache

TickTask #454. Primeiro medir onde o consumo está; depois cortar o maior desperdício que a
medição já mostra. Fora de escopo, por decisão: painel na UI (o relatório é um script),
compactação do histórico no resume, troca do modelo de consolidação/sonho e qualquer
mudança no board, que é one-shot e não se beneficia de cache entre turnos.

## Linha de base (06/10/2026)

Tirada das 23 transcrições do SDK em `~/.claude/projects/<slug da pasta de dados>/`, que
trazem o `usage` de cada chamada à API e um `cost-state` com o custo estimado por modelo.

- **Ferramentas já foram o maior corte.** Sessões de antes do `17ffdc2e` abriam com 21–38 mil
  tokens de contexto; as de depois, com 5–13 mil. A #488 tirou ainda as ferramentas e
  instruções dos conectores da conta claude.ai que chegavam no meio da sessão.
- **A escrita de cache domina.** No Haiku foram 154 mil tokens escritos em cache contra 10
  mil de entrada comum. O Claude Code grava com TTL de 1 hora, cuja escrita custa o dobro
  da entrada; a leitura custa um décimo.
- **O brief quebra o cache a cada turno.** Na conversa `ebb1c822` do Poe a leitura de cache
  fica parada em 17.972 (Haiku) e 24.080 (Sonnet) tokens, que são as ferramentas e o
  boilerplate, enquanto a escrita cresce a cada turno: 14k, 15k, 17k, 18k, 20k e, no
  Sonnet, de 30k a 50k. O system prompt é remontado a cada turno com o brief, que muda com
  a mensagem; como o cache é de prefixo, tudo o que vem depois dele (o histórico inteiro)
  é regravado. Na sessão `144dc3ae` da Pami, que tem uma página de memória e por isso um
  brief que não muda, a escrita por turno fica em 200–350 tokens e a leitura cresce: é o
  comportamento esperado. O desperdício aumenta conforme a memória da persona cresce.
- Opus nos chats da Pami e do Lucas e Sonnet no do Alfred vieram do seletor de modelo da
  conversa, não de bug.

## 1. Registro de uso

Cada `query()` do SDK grava uma linha em `conversations/uso.jsonl`, na pasta de dados
(fora do git, como as conversas):

```json
{"ts":"…","tipo":"chat","perfil":"poe","conversaId":"…","sessionId":"…","modelo":"haiku",
 "chamadas":3,"entrada":30,"escritaCache":812,"leituraCache":52310,"saida":640,
 "custoAcumuladoUSD":0.1834,"retomada":true,"duracaoMs":8123}
```

- `tipo`: `chat`, `board-parecer`, `board-sintese`, `consolidacao`, `sonho`, `migracao`.
- Os tokens são **desta query**: soma do `message.usage` de cada mensagem `assistant` do
  stream, contando cada `message.id` uma vez (blocos da mesma resposta repetem o usage).
- `custoAcumuladoUSD` é o `total_cost_usd` do `result`, que o SDK acumula na sessão e já
  inclui as chamadas auxiliares do Claude Code (título etc.). O custo de um turno é a
  diferença para o registro anterior da mesma sessão; sem registro anterior, só vale
  quando `retomada` é falso.
- Gravar nunca derruba o turno: falha de escrita vira aviso no log. Turno que termina em
  erro também grava, com o que houver.

Um único coletor (`app/src/uso.ts`) recebe as mensagens do stream e devolve a linha; as
três chamadas de `query` (`conversar`, `perguntarUmaVez`, `rodarPersona`) o alimentam.

## 2. Relatório

`bun run scripts/relatorio-uso.ts [--desde AAAA-MM-DD]` agrega o `uso.jsonl` por tipo,
perfil e modelo: número de queries, custo (pelas diferenças do acumulado), tokens de
entrada, escrita e leitura de cache, saída e a **taxa de acerto do cache**
(`leitura / (entrada + escrita + leitura)`), que é o indicador do item 3.

## Correção da premissa (descoberta na implementação)

A quebra de cache do item acima é do Claude Code **2.1.239**, a versão daquela conversa. No
**2.1.286** (SDK 0.3.286, o instalado hoje) o comportamento é outro: o system prompt fica
**congelado no da primeira chamada da sessão** e o `systemPrompt` novo do resume é ignorado.
Teste direto: system pedindo para terminar com ALFA, depois BRAVO, depois CHARLIE, e o
modelo terminou com ALFA nas três, lendo do cache todo o turno anterior.

Então, na versão atual, o cache já funciona, e o problema é de funcionamento, não de custo:

- o conselheiro só via o brief da **primeira** mensagem da conversa (teste com `conversar`
  e uma memória que devolve ALFA no turno 1 e BRAVO no turno 2: a resposta do turno 2 era
  ALFA antes da mudança e BRAVO depois);
- o modo `profundidade` pedido no meio da conversa não mudava o "Como escrever";
- o foco TickTask ligado ou desligado no meio da conversa do Alfred (#442) não mudava as
  instruções.

O item 3 resolve as duas versões: no 2.1.239 evita regravar o histórico; no 2.1.286 faz o
que muda por turno chegar ao modelo. A regra passa a ser: **nada que mude de um turno para
outro vai no system prompt**.

## 3. System prompt estável nos conselheiros

O brief sai do system prompt e vai para a mensagem do turno, antes do texto do Ueslei,
marcado como bastidor:

```
<memória>
# Minha memória
…brief…
</memória>

<texto do Ueslei>

<lembrete de forma>
```

- O system prompt dos conselheiros fica com `profile.md` e as instruções da casa, com o
  bloco "Como escrever" sempre no modo `padrao`. O modo do turno (`profundidade` quando
  pedido) chega pelo lembrete de forma, que já ia na mensagem.
- O Alfred segue a mesma regra: o foco TickTask sai das instruções do executor e vai num
  bloco `<modo>` no começo da mensagem enquanto estiver ligado; no turno em que é
  desligado, o bloco avisa que o modo acabou, porque o histórico ainda guarda as instruções.
- As instruções da casa ganham uma linha dizendo que o bloco `<memória>` é dela mesma, não
  fala do Ueslei, e que ela não o cita nem comenta.
- Custo aceito: o brief de cada turno passa a ficar no histórico da sessão (até 4.000
  caracteres por turno). Mesmo assim, ler esse histórico do cache custa um décimo de
  regravá-lo inteiro a cada turno, que é o que acontece hoje.
- O board não muda: `montarSystemPromptParecer` é one-shot.
- Esta mudança altera o que o CLAUDE.md descreve em "System prompt" e "Ritmo de escrita";
  os dois trechos são atualizados junto.

### Como validar

Antes e depois, rodar três turnos com o Poe (memória mais rica) no Haiku, numa sessão
descartável, com uma `Memoria` que lê o daemon real mas não grava. Esperado depois: do
segundo turno em diante, a escrita de cache por turno fica na ordem do turno novo (centenas
a poucos milhares de tokens) e a leitura cresce com o histórico. Em produção, o relatório
deve mostrar a taxa de acerto do cache dos chats de conselheiro subindo.
