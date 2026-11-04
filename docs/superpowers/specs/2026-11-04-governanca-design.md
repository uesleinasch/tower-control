# Fase 5 do orquestrador: governança

TickTask #503, subtarefa 5 da #496. Parte das seções 1, 4, 5 e 10 da spec-mãe
(`2026-10-07-orquestrador-personas-design.md`) e não reabre nada dela. Sem rodada de
perguntas: o que ficou em aberto foi decidido aqui e está marcado como
**(decisão desta fase)**.

## Para que serve

Até a fase 4, nada roda sem o Ueslei: toda tarefa nasce à mão e a subtarefa delegada fica no
backlog. As próximas fases (execution policy, rotinas e workflows) fazem as personas
trabalharem em cadeia sem ninguém olhando, e esta fase põe os freios antes disso: quanto
cada persona pode gastar, como parar uma persona ou tudo de uma vez, quando exigir um plano
aprovado antes de executar e o registro de quem fez o quê.

Uso que fecha a fase: o Ueslei dá ao Alfred um limite de US$ 5 por mês. O Alfred trabalha
até 80% do limite, o Ueslei recebe um aviso, e ao passar de 100% as tarefas dele param na
fila com outro aviso, até o Ueslei subir o limite ou o mês virar. No meio disso, o Ueslei
pausa tudo pelo celular, e nada novo começa.

## Objetivos

- Orçamento mensal por persona, com aviso em 80% e parada em 100%.
- Pausar e retomar uma persona, e pausar e retomar tudo de uma vez.
- Aprovação de plano antes de executar, por posição.
- Delegação que roda sem passar pelo Ueslei, por posição, com limites contra cascata.
- Trilha de auditoria das ações sobre o orquestrador.

## Fora desta fase

- Orçamento por workflow e por projeto. Workflow é da fase 9, e projeto não existe.
- Tela de auditoria com filtros. Nesta fase, a trilha aparece só como lista simples
  ("Atividade", seção 7); filtros e a visão de atenção ficam para o painel (fase 8).
- Rollback de configuração pela interface. O git dos dados já guarda cada mudança de
  definição; desfazer continua sendo `git revert` na pasta de dados.
- Mudar a aprovação de comando do Alfred. Ela já passa pelo mesmo canal de aprovação e
  aviso desde a fase 3, e não muda aqui.

## Anti-objetivos

- Barrar o chat. O orçamento e a pausa valem para o trabalho autônomo; conversar com uma
  persona pausada ou sem orçamento continua funcionando **(decisão desta fase)**.
- Cortar uma execução no meio por causa do orçamento. O custo só é conhecido no fim de cada
  execução, e cortar no meio deixaria a tarefa em estado incerto. O limite de 60 turnos da
  fase 3 segura o pior caso.
- Cascata de delegação: subtarefa que cria subtarefa sem fim.

## 1. Orçamento

**O que conta:** o gasto das execuções de tarefa da persona (uso do tipo `tarefa`) no mês
corrente, no fuso da máquina **(decisão desta fase)**. Chat, consolidação, sonho e geração de
perfil não entram no limite, mas o gasto total do mês aparece ao lado, para informação.

**De onde vem:** `uso.jsonl`, com a mesma regra de `custosPorConsulta` (diferença do custo
acumulado da sessão). Na subida, o servidor lê o arquivo uma vez e monta o gasto por
persona e mês em memória; cada registro novo de uso atualiza a soma
(`uso.ts` ganha um ouvinte de registros gravados). Núcleo puro: `gastoDoMes(registros, persona,
mes)`.

**Limites:** dois, independentes, em `persona.json`: `orcamentoMensalUSD` (já existia) e
`orcamentoMensalTokens` (inteiro), pedido do Ueslei para ter controles distintos. Sem o campo,
aquela dimensão não tem limite. Zero significa que ela não roda tarefa nenhuma. O que estourar
primeiro segura as tarefas, e cada dimensão tem os próprios avisos de 80% e 100%. Tokens
contam entrada, saída, escrita e leitura de cache, ou seja, tudo o que o modelo processou
**(decisão desta fase)**; a leitura de cache costuma ser a maior parte, então os limites em
tokens tendem a ser números grandes.

**Quando checa:**

- Antes de começar uma execução, no despachante: persona com gasto do mês maior ou igual ao
  limite não começa. A execução fica `na_fila` e não é descartada.
- Depois de cada execução: se o gasto passou de 80% pela primeira vez no mês, sai um aviso;
  se passou de 100%, sai o aviso de parada.

Os avisos de 80% e 100% saem uma vez por persona por mês. A marca de "já avisado" fica em
`orquestra.db`.

**Voltar a rodar:** subir o limite, tirar o limite ou virar o mês. O despachante roda de
novo quando o orçamento muda, e o relógio de 30 s cobre a virada do mês.

**Mudar o limite:** cliente→servidor `persona-salvar`: `{ id, orcamentoMensalUSD?,
orcamentoMensalTokens?, modelo?, cor?, nome? }`. Grava `persona.json`, commita ("orçamento de Alfred: US$ 5") e manda
`personas` para todos. `null` em `orcamentoMensalUSD` tira o limite.

A mensagem `personas` ganha `orcamentoMensalUSD`, `orcamentoMensalTokens`, `gastoMesUSD` e
`tokensMes` (tarefas), `gastoTotalMesUSD` e `tokensTotalMes` (tudo) e `pausa` (seção 2).

## 2. Pausar e retomar

Pausa é estado de operação, não definição: fica em `orquestra.db`, numa tabela `pausas`
(`alvo` = `*` para tudo ou o id da persona, `motivo` = `ueslei` ou `orcamento`, `em`), e não
gera commit **(decisão desta fase)**.

- **Pausar uma persona:** a execução dela que está rodando é interrompida sem contar como
  falha (como a parada pelo Ueslei da fase 3), e as que estão na fila esperam. Os pedidos
  de comando pendentes dela são negados.
- **Pausar tudo:** o mesmo para todas as personas. O despachante não começa nada.
- **Retomar:** apaga a pausa, e o despachante roda.

O orçamento estourado não grava pausa: ele é recalculado a cada despacho. Na mensagem
`personas`, `pausa` traz `{ motivo: "ueslei" | "orcamento" | "tudo" }` ou `null`, e o
cliente mostra o motivo.

Cliente→servidor `pausar` e `retomar`: `{ alvo }`, com `alvo` = `"*"` ou um id de persona.
Servidor→cliente `orquestra`: `{ pausadoTudo }`, mandado na abertura do socket e a cada
mudança.

## 3. Aprovação de plano

`Posicao` ganha `aprovarPlano?: boolean`. Numa posição com ele ligado:

1. A primeira execução de uma tarefa é de **plano**: as mesmas opções da posição, mas só com
   Read, Grep e Glob (nada de Write, Edit ou Bash) e a regra no bloco `<tarefa>`: "Não
   execute nada. Escreva o plano: o que vai fazer, em que ordem, que comandos pretende
   rodar e o que pode dar errado." **(decisão desta fase)**: restringir as ferramentas é
   determinístico, e o modo `plan` do SDK depende de uma aprovação interativa que o runtime
   não tem.
2. O texto final vira o registro `plano` (em vez de `entrega`), e a tarefa vai para
   `em_revisao` com aviso "Alfred propôs um plano para #12".
3. O Ueslei aprova (cliente→servidor `tarefa-aprovar-plano`: `{ id }`), o que grava o
   registro `plano-aprovado` e devolve a tarefa para `a_fazer`. A próxima execução é normal,
   na mesma sessão, com o plano aprovado no bloco ("Execute o plano aprovado acima").
4. Se o Ueslei comentar em vez de aprovar, a tarefa volta para `a_fazer` como na fase 3, e a
   próxima execução é de plano de novo, com o comentário.

A regra fica pura: `precisaDePlano(posicao, registros)` é verdadeiro quando a posição exige
plano e não há `plano-aprovado` depois do último `plano`.

## 4. Delegação sem passar pelo Ueslei

`Posicao` ganha `delegaDireto?: boolean`. A subtarefa que uma posição com ele ligado delega
nasce em `a_fazer` e roda sozinha, dentro do orçamento da persona que a recebe. Sem ele,
continua nascendo em `backlog`, como na fase 4.

Limites contra cascata, valendo sempre **(decisão desta fase)**:

- profundidade: no máximo 3 níveis de subtarefa abaixo da tarefa criada pelo Ueslei;
- largura: no máximo 5 subtarefas abertas por tarefa-mãe.

Passou do limite, a ferramenta `delegar` recusa e explica o motivo à persona, que deve
entregar ou pedir ajuda.

## 5. Trilha de auditoria

Tabela `auditoria` em `orquestra.db`: `id`, `em`, `quem` (`ueslei`, uma persona ou
`execucao:<id>`), `acao`, `alvo` e `detalhe`. Entram as ações que mudam o orquestrador e não
deixam registro em tarefa nem commit:

- pausar e retomar;
- aprovar plano;
- aprovar e negar comando de tarefa;
- avisos de orçamento (80% e 100%);
- delegação automática (`delegaDireto`).

Mudanças de definição já viram commit, e mudanças de tarefa já viram registro, então não se
duplicam aqui. Cliente→servidor `auditoria`: `{ desde? }` devolve as últimas 200 linhas.
Servidor→cliente `auditoria`: `{ lista }`.

## 6. Telas

- **Web e app, personas** (tela de Equipes): cada persona mostra o gasto do mês, o limite
  numa barra, a pausa e o botão Pausar ou Retomar. No desktop e na web, o limite é editável
  ali.
- **Pausar tudo:** botão no topo das telas de Tarefas e de Equipes, na web e no app, celular
  incluído. Com tudo pausado, uma faixa avisa no topo dessas telas.
- **Tarefa com plano:** o registro `plano` aparece destacado, com o botão "Aprovar plano"
  quando a tarefa está em revisão aguardando aprovação. No celular também.
- **Editor do desktop:** o painel da posição ganha "Exigir plano aprovado" e "Delegação roda
  sem aprovação".

## 7. Protocolo

- cliente→servidor: `persona-salvar`, `pausar`, `retomar`, `tarefa-aprovar-plano`,
  `auditoria`;
- servidor→cliente: `orquestra`, `auditoria`.

Todos entram nos três clientes. Para isso, a tela de Equipes da web e do app ganha
"Atividade", que pede `auditoria` e mostra a lista simples (quando, quem, ação e alvo).
O painel da fase 8 dá a forma final **(decisão desta fase)**.

## 8. Testes

`bun test`:

- `gastoDoMes` soma só tarefas da persona no mês e usa a diferença do acumulado da sessão;
- o despachante não começa execução de persona pausada, com tudo pausado ou sem orçamento,
  e não descarta a execução;
- os avisos de 80% e 100% saem uma vez por mês;
- `precisaDePlano` e a execução de plano com ferramentas só de leitura (nenhuma combinação
  põe Write, Edit ou Bash no plano);
- `delegar` respeita profundidade e largura, e `delegaDireto` cria em `a_fazer`;
- pausar uma persona interrompe a execução dela sem contar falha;
- o teste de protocolo cobra os tipos novos.

`flutter test`: o codec dos tipos novos e os campos novos da posição no `organograma.dart`.

## O que fica com quem implementa

Nomes internos, o texto exato das regras de plano no bloco `<tarefa>`, o desenho da barra de
orçamento e a ordem dos commits. A ordem sugerida é: gasto e orçamento no núcleo e no
despachante; pausas; plano; delegação direta e limites; auditoria; protocolo e telas.
