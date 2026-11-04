# Fase 3 do orquestrador: runtime de execução

TickTask #500, subtarefa 3 da #496. Parte da seção 4 da spec-mãe
(`2026-10-07-orquestrador-personas-design.md`) e não reabre nada dela. O que estava em aberto
lá foi decidido aqui pelo construtor, sem rodada de perguntas, e está marcado como
**(decisão desta fase)** para o Ueslei conferir.

## Para que serve

Hoje a tarefa da Casa é um cartão: o Ueslei cria, muda o status e comenta, e nenhuma persona
faz nada com ela. Ao fim desta fase, a tarefa atribuída a uma posição ocupada é executada
sozinha pela persona daquela posição. O Ueslei vê na tela da tarefa o que ela está fazendo
(log), quanto custou, aprova comandos pelo aviso e recebe a entrega para revisar.

Uso que fecha a fase: o Ueslei cria uma tarefa para a posição `executor` da Casa ("rode os
testes do control-tower e me diga o que falhou"), o Alfred acorda, roda pedindo aprovação,
entrega o resultado e a tarefa para em `em_revisao` com log e custo à vista.

## Objetivos

- Fila persistente de acordar, com coalescência por tarefa.
- Execução rastreada: id, gatilho, persona, sessão do SDK, log, custo, resultado.
- Concorrência limitada: uma execução por persona e um teto global.
- Sobreviver a restart e a falha limitada; quando não dá, bloquear a tarefa e avisar.
- Execução ao vivo na tela da tarefa, na web e no app.

## Fora desta fase

- Workflow, revisão por outra persona, execution policy (fase 6). A revisão aqui é sempre do
  Ueslei.
- Orçamento por persona e pausa (fase 5). O status `pausada_orcamento` não é usado.
- Persona criando tarefa ou subtarefa (a spec-mãe diz que até a fase 5 toda tarefa nasce à
  mão do Ueslei). Não existe ferramenta `criar_subtarefa` nesta fase.
- Rotinas e timer (fase 7). A agenda de memória e a `filaPorChave` do chat continuam como
  estão; a fila desta fase é só de tarefas.
- Painel de execuções (fase 8). Aqui a execução aparece dentro da tarefa.
- Mudar o chat direto para a resolução de capacidades nova. O chat continua chamando
  `conversar()` como hoje.
- Consolidar na memória o que a persona fez numa tarefa. O conselheiro que executa tarefa
  recebe o brief e as ferramentas `memoria`, e lembra só o que ele mesmo pedir para lembrar.

## Anti-objetivos

- Rodar comando sem ninguém para aprovar. Os invariantes do hook valem igual em tarefa.
- Execução que gasta sem aparecer: toda execução tem registro de uso e aparece na tarefa.
- Laço de tentativas: falha repetida para a tarefa, nunca repete para sempre.

## 1. Gatilhos de acordar

Um acordar é uma execução no status `na_fila` (ver seção 2). Enfileiram:

| gatilho | quando |
|---|---|
| `atribuicao` | a tarefa entra em `a_fazer` (criação ou mudança de status) |
| `comentario` | o Ueslei comenta numa tarefa em `a_fazer`, `em_andamento`, `em_revisao` ou `bloqueada` |
| `dependencia` | uma tarefa vai para `concluida`; acorda as que dependem dela e estão em `a_fazer` |
| `retomada` | a subida encontra execução `rodando` (seção 5) |
| `nova_tentativa` | uma execução falhou e ainda cabe tentativa (seção 5) |

Coalescência: no máximo uma execução `na_fila` por tarefa, garantida por índice único
parcial no SQLite. Enfileirar com uma já na fila não cria outra; o gatilho que chegou depois
vira um registro na tarefa ("acordar juntado: comentário"), e a execução guarda o primeiro.

Comentário do Ueslei em tarefa `em_revisao` ou `bloqueada` devolve a tarefa para `a_fazer`
e enfileira **(decisão desta fase)**: é assim que ele pede mudança antes da fase 6. Para
isso a máquina de estados ganha `em_revisao → a_fazer`, espelhada em `app.js` e em
`cliente/lib/nucleo/tarefas.dart`. Comentário em tarefa `em_andamento` com execução viva
enfileira, e a próxima execução lê o comentário quando a atual terminar.

Comentário de persona (pela ferramenta) nunca acorda ninguém.

## 2. Execução e fila (`orquestra.db`, esquema versão 2)

A fila é a própria tabela de execuções. A migração de `user_version` 1 para 2 cria:

```
execucoes(
  id INTEGER PRIMARY KEY,
  tarefa INTEGER NOT NULL REFERENCES tarefas(id),
  posicao TEXT NOT NULL,
  persona TEXT,             -- resolvida ao começar; null enquanto na fila
  gatilho TEXT NOT NULL,
  status TEXT NOT NULL,     -- na_fila | rodando | concluida | falhou | interrompida
  tentativa INTEGER NOT NULL DEFAULT 1,
  nao_antes TEXT,           -- espera da nova tentativa
  session_id TEXT,
  modelo TEXT,
  criada_em TEXT NOT NULL,
  inicio TEXT,
  fim TEXT,
  resultado TEXT,           -- texto final da persona
  erro TEXT,
  custo_usd REAL
)
UNIQUE INDEX uma_na_fila ON execucoes(tarefa) WHERE status = 'na_fila'

eventos(
  id INTEGER PRIMARY KEY,
  execucao INTEGER NOT NULL REFERENCES execucoes(id),
  tipo TEXT NOT NULL,       -- texto | ferramenta | comando | aprovacao | erro
  conteudo TEXT NOT NULL,   -- truncado em 4.000 caracteres
  em TEXT NOT NULL
)
```

`Registro.tipo` ganha `entrega` (o resultado de uma execução) e `ajuda` (a persona pediu
ajuda).

Máquina de estados da execução (núcleo puro, `orquestra/execucao.ts`):
`na_fila → rodando | interrompida`, `rodando → concluida | falhou | interrompida`. As três
finais não saem.

O dono da tarefa no checkout passa a ser `execucao:<id>`. Comentário e entrega feitos pela
persona têm a persona como autor.

## 3. Despachante

Adaptador em `orquestra/runtime.ts`, com a escolha em função pura. Ele roda quando algo
enfileira, quando uma execução termina, na subida e a cada 30 s como rede de segurança (a
espera de `nao_antes` depende disso).

Para cada execução `na_fila`, da mais antiga para a mais nova, com `nao_antes` vencido:

1. Tarefa fora de `a_fazer`, ou com dependência não concluída: a execução vira `interrompida`
   com o erro "nada a fazer" e sai da fila. O gatilho `dependencia` a traz de volta.
2. Posição vaga: continua na fila (espera alguém ocupar).
3. Persona já tem execução `rodando`, ou o teto global foi atingido: continua na fila.
4. Senão, numa transação: checkout da tarefa com dono `execucao:<id>`, persona e modelo
   gravados, status `rodando`, `inicio`. Se o checkout perde a disputa, a execução vira
   `interrompida`.

Teto global em `CT_EXECUCOES_SIMULTANEAS`, padrão 2. Conversa no chat não conta como
execução **(decisão desta fase)**: o Alfred pode conversar enquanto executa uma tarefa, em
sessões diferentes.

## 4. Rodar

Uma função nova em `sessions.ts`, `trabalhar()`, ao lado de `conversar()`, que reaproveita o
`hookDeComando`, as listas de ferramentas e todos os invariantes de `sessions.ts` (seção 4 da
spec-mãe).

**Opções a partir da posição** (núcleo puro, `orquestra/capacidades.ts`), seção 5 da
spec-mãe: `arquivos` dá Read/Write/Edit/Grep/Glob auto-aprovadas; `comandos` acrescenta Bash
às nativas, o hook e o prompt em streaming, e Bash nunca entra em `allowedTools`; `memoria`
dá o brief e o MCP `memoria` da persona; `ticktask` dá o MCP do TickTask; o MCP
`orquestra` (abaixo) vem sempre. `cwd` é `posicao.diretorio` ou a pasta de dados. Com
`comandos`, `permissionMode` é `default`; sem, `acceptEdits`.

**Política de aprovação:** `sempre` pede todo comando; `sensiveis` e `auto` pedem só o que
`exigeAprovacaoSempre` marca. A spec-mãe descreve as duas do mesmo jeito; a diferença entre
elas fica para a fase 5.

**Modelo:** `persona.modelo` ou `MODELO_PADRAO` **(decisão desta fase)**. A troca para o
Opus do modo auto continua só no chat. Para o Alfred trabalhar no modelo forte, basta pôr
`"modelo"` no `persona.json` dele.

**Sessão:** uma por par (tarefa, persona). A execução nova procura a última execução do mesmo
par com `session_id` e passa `resume`.

**System prompt:** o de hoje (`montarSystemPrompt`). Nada da tarefa vai nele.

**Mensagem:** um bloco `<tarefa>` no começo, depois o brief `<memória>` quando a posição tem
`memoria`. O bloco traz o id, o título, a descrição, o porquê, a cadeia de tarefas-pai
(título e porquê de cada uma) e os comentários e mudanças de status desde a última execução
dessa persona na tarefa (todos, na primeira). Traz também as regras do modo tarefa:

- Ninguém está olhando a conversa. Não pergunte no texto: se faltar algo que muda o
  resultado, use `pedir_ajuda` e pare.
- A última resposta é a entrega. Escreva-a para o Ueslei ler depois, com o que foi feito e
  o que ficou de fora.
- Use `comentar` só para registrar progresso que vale ler mesmo se a execução cair.

**MCP `orquestra`** (in-process, como o `memoria`, preso à execução na criação e sem
argumento de tarefa):

- `comentar(texto)`: registro `comentario` na tarefa.
- `pedir_ajuda(motivo)`: registro `ajuda`, a tarefa vai para `bloqueada` ao fim da execução
  e sai um aviso.

**Fim com sucesso:** o texto final vira `resultado` e um registro `entrega`. A tarefa vai para
`em_revisao`, a menos que `pedir_ajuda` tenha sido chamado (aí vai para `bloqueada`). Sai um
aviso nos dois casos. A entrega como fim natural, e não como ferramenta, é **decisão desta
fase**: a persona não tem como esquecer de entregar.

**Comandos em tarefa:** o pedido de aprovação vai para todos os sockets abertos (mensagem
`permissao` com `tarefaId` no lugar de `conversaId`) e sempre vira aviso, porque não existe
"conversa visível" para tarefa. Prazo de 10 minutos **(decisão desta fase)**, contra 2 no
chat: execução autônoma raramente tem alguém olhando na hora. Sem socket aberto e sem
ninguém escutando `/avisos`, o comando é negado, como hoje. Comando negado faz a persona
parar (o texto do hook já diz isso), e a entrega relata a recusa.

**Log:** o laço do SDK grava em `eventos` cada bloco de texto completo, cada chamada de
ferramenta (nome e entrada resumida), cada comando com o resultado da aprovação e o erro
final. Cada evento gravado vai para todos os sockets. Não há stream de deltas de texto
**(decisão desta fase)**: num trabalho autônomo o bloco inteiro chega rápido o bastante, e
evita um segundo caminho de streaming.

**Uso:** `TipoDeUso` ganha `tarefa`, e `RegistroDeUso` ganha `tarefaId` e `execucaoId`. O
`custo_usd` da execução é calculado ao terminar pela mesma regra de `custosPorConsulta`
(diferença do custo acumulado da sessão) e gravado na linha.

## 5. Falha, queda e parada

- **Erro do SDK** (exceção ou `result` sem sucesso): execução `falhou`, com o erro. A
  tarefa volta para `a_fazer` e entra uma `nova_tentativa` com `nao_antes` em 1 minuto.
- **Queda:** na subida, toda execução `rodando` vira `interrompida`, a tarefa dela volta de
  `em_andamento` para `a_fazer` e entra uma `retomada`. A sessão é retomada com `resume`.
- **Limite:** a tentativa conta falhas e interrupções seguidas da mesma tarefa. Na terceira
  que seria criada (ou seja, depois de duas seguidas), não enfileira: a tarefa vai para
  `bloqueada`, com registro do motivo e aviso. Uma execução `concluida` zera a contagem.
- **Parada pelo Ueslei:** mudar o status de uma tarefa `em_andamento` com execução viva
  aborta a execução (`abortController` do SDK). Ela vira `interrompida` sem nova tentativa,
  e a tarefa fica no status que o Ueslei escolheu. Tarefa cancelada também tira da fila a
  execução `na_fila` dela.

Toda transição de execução e de tarefa acontece numa transação do SQLite.

## 6. Avisos

`TipoDeAviso` ganha `tarefa`, com `alvo.tarefaId` e sem ações: tocar abre a tarefa. Os
textos são montados em `avisos/fontes.ts`, fora do `server.ts`:

- "Alfred entregou #12" com o começo da entrega.
- "Alfred pediu ajuda em #12" com o motivo.
- "#12 bloqueada" com "falhou duas vezes seguidas" e o último erro.

O aviso de aprovação ganha a variante com `tarefaId` ("Alfred quer rodar um comando em #12").
O app Flutter já lê `alvo.tarefaId`; falta levar o destino de `tarefa` para a tela da
tarefa.

## 7. Protocolo e telas

Tipos novos em `docs/protocolo.json`, no `server.ts`, no `app.js` e no codec Dart:

- servidor→cliente `execucao`: `{ execucao, eventos? }`. Vai para todos quando o status de
  uma execução muda, e para quem pediu com os eventos completos.
- servidor→cliente `execucao-evento`: `{ execucaoId, tarefaId, evento }`, para todos.
- cliente→servidor `execucao`: `{ id }`, pede a execução com o log inteiro.

A mensagem `tarefa` passa a levar `execucoes` (resumo de todas as da tarefa, sem eventos) e
`custoUSD` (soma). `permissao` ganha o campo opcional `tarefaId`.

**Web e app:** na tela da tarefa, abaixo dos registros, a lista de execuções (número,
gatilho, persona, status, duração, custo) e o log da mais recente, que cresce ao vivo
enquanto ela roda. O cartão de aprovação aparece ali quando a `permissao` traz o `tarefaId`
da tarefa aberta. Na lista de tarefas, a tarefa com execução `rodando` ganha um indicador, e
o custo total aparece no cabeçalho da tarefa. O registro `entrega` aparece destacado, e o
`ajuda` também. Não há botão de parar: mudar o status já para (seção 5).

## 8. Testes

Núcleo puro e repositório em memória (`bun test`):

- coalescência: enfileirar duas vezes a mesma tarefa deixa uma só `na_fila`;
- escolha do despachante: posição vaga espera, persona ocupada espera, teto global,
  `nao_antes`, tarefa fora de `a_fazer` sai da fila;
- máquina de estados da execução e a transição nova `em_revisao → a_fazer`;
- recuperação na subida: `rodando` vira `interrompida`, a tarefa volta para `a_fazer` e entra
  `retomada`; duas seguidas bloqueiam;
- opções a partir das capacidades: nenhuma combinação põe Bash em `allowedTools`, e
  `comandos` sempre traz o hook;
- montagem do bloco `<tarefa>` com a cadeia de pais e os registros desde a última execução;
- o teste de protocolo existente cobra os tipos novos.

`flutter test`: o codec dos tipos novos e o espelho da máquina de estados.

## O que fica com quem implementa

Nomes internos, a forma do resumo de entrada de ferramenta no log, o layout exato das telas,
o texto exato das regras do modo tarefa e se `trabalhar()` compartilha código com
`conversar()` ou só os helpers. A ordem sugerida é: esquema e núcleo puro, despachante e
`trabalhar()`, avisos, protocolo e web, app.
