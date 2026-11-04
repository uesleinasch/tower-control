# Fase 6 do orquestrador: execution policy linear

TickTask #518, subtarefa 6 da #496. Parte da seção 6 da spec-mãe
(`2026-10-07-orquestrador-personas-design.md`) e não reabre nada dela. Sem rodada de
perguntas: o que ficou em aberto foi decidido aqui e está marcado como
**(decisão desta fase)**.

## Para que serve

Até a fase 5, toda entrega cai em `em_revisao` esperando o Ueslei. Ele lê, comenta ou move
para `concluida`. Esta fase deixa a entrega passar por outras personas antes de chegar a ele:
a executora entrega, uma revisora lê e aprova ou pede mudança, e só então o aprovador final
(uma persona ou o Ueslei) fecha a tarefa. É o fluxo linear do Paperclip, antes do grafo da
fase 9.

Uso que fecha a fase: na Casa, a posição `executor` (Alfred) ganha a política "revisão da
Nati, depois aprovação do Ueslei". O Ueslei cria uma tarefa para o Alfred. O Alfred entrega,
a Nati lê a entrega e pede uma mudança, o Alfred refaz na mesma sessão, a entrega volta
direto para a Nati (não para o começo), ela aprova, e o Ueslei recebe o aviso "#12 espera sua
aprovação", aprova pelo celular e a tarefa fica concluída. Uma segunda tarefa usa o board da
Casa como revisão no lugar da Nati.

## Objetivos

- Política por posição: depois da entrega, uma sequência de etapas de revisão e de aprovação.
- Revisão por uma posição (persona) ou pelo board da equipe; aprovação por uma posição ou
  pelo Ueslei.
- Pedido de mudança volta à executora original e, refeito, retorna à mesma etapa.
- A executora nunca revisa nem aprova o próprio trabalho.
- Cada decisão vira registro na tarefa.

## Fora desta fase

- Política escolhida por tarefa na criação. A tarefa usa a política da posição dona; mudar
  de política é mudar a posição **(decisão desta fase)**.
- Etapas em paralelo, condições e desvios. São nós do grafo (fase 9).
- Editar a política na web e no celular. Como o resto da equipe, a edição é só no desktop; web
  e celular mostram a política e agem nas etapas do Ueslei.

## Anti-objetivos

- Pingue-pongue sem fim entre executora e revisora gastando o orçamento sem ninguém olhando.
- Revisora que conserta o trabalho em vez de revisar: a revisão é só leitura.
- Mudar o comportamento de quem não configurou política. Posição sem política continua
  exatamente como na fase 5.

## 1. A política

`Posicao` ganha `politica?: Etapa[]`:

```ts
type Etapa =
  | { tipo: "revisao"; por: { posicao: string } | { board: true } }
  | { tipo: "aprovacao"; por: { posicao: string } | { ueslei: true } }
```

- Lista vazia ou ausente = sem política (fase 5: entrega vai para `em_revisao` com o Ueslei).
- Zero ou mais revisões e no máximo uma aprovação, sempre a última.
- Sem aprovação no fim, a última revisão aprovada conclui a tarefa sozinha
  **(decisão desta fase)**. Quem quiser a palavra final põe a aprovação do Ueslei.
- A posição citada precisa existir na mesma equipe. O board exige ao menos uma posição da
  equipe com a capacidade `board` e persona.

**Validação** (`validarEquipe`, núcleo puro, espelhada em `organograma.dart` contra os mesmos
casos): posição inexistente, board sem membro, aprovação fora do fim, mais de uma aprovação
e etapa cuja posição tem a mesma persona da posição dona são recusados, com o erro na
posição. `exigirMudancaDeEquipe` também recusa remover uma posição citada pela política de
uma tarefa aberta.

**Retrato na tarefa:** na criação, a tarefa copia a política da posição para a coluna
`politica` **(decisão desta fase)**, como a spec-mãe faz com a versão do workflow: editar a
equipe não muda o caminho de uma tarefa que já está andando. Subtarefa delegada copia a
política da posição que a recebe.

## 2. Onde a tarefa está

A tarefa ganha duas colunas:

- `etapa`: índice da etapa atual na política, ou `null` enquanto está com a executora;
- `retorno`: índice da etapa que recebe a próxima entrega, ou `null` para começar da
  primeira.

O status continua o mesmo: com a executora, a tarefa segue `a_fazer`/`em_andamento`; em
qualquer etapa, fica `em_revisao`. A máquina de estados de `tarefa.ts` ganha só
`em_revisao → bloqueada` (voltas demais, autorrevisão e falhas seguidas na revisão), espelhada
em `app.js` e `tarefas.dart`. A coluna `voltas` guarda quantos pedidos de mudança a etapa de
`retorno` já fez. As regras ficam puras, num `politica.ts`:

- `aposEntrega(politica, retorno)` → `{ etapa: retorno ?? 0 }`, ou `ueslei` quando não há
  política (comportamento da fase 5);
- `aposAprovar(politica, etapa)` → a próxima etapa, ou `concluida`;
- `aposMudanca(etapa)` → `{ etapa: null, retorno: etapa }`;
- `quemDecide(politica, etapa, equipe)` → a posição, o board ou o Ueslei.

Toda passagem de etapa grava um registro `status` legível ("revisão de Nati → aprovação do
Ueslei").

## 3. Execução de revisão

**Fila:** a execução ganha a coluna `etapa` (`null` = trabalho da executora). Ao entrar numa
etapa de posição ou de board, o runtime enfileira uma execução com aquela etapa e o gatilho
novo `revisao`. `escolher` aceita a execução de etapa quando a tarefa está `em_revisao`, na
mesma etapa e sem dono; senão descarta, como faz hoje com a de trabalho. A persona é a da
posição da etapa, não a da posição dona; posição vaga espera.

**Dono:** o checkout de revisão grava `dono = execucao:<id>` sem mudar o status
(`WHERE status = 'em_revisao' AND etapa = ? AND dono IS NULL`). Ao terminar, a execução
limpa o dono. Mudar o status de uma tarefa com revisão rodando interrompe a execução, como já
acontece com a de trabalho.

**Ferramentas:** só leitura (`Read`, `Grep`, `Glob`) e memória, se a posição tiver
**(decisão desta fase)**: nada de `Write`, `Edit`, `Bash` ou `delegar`, mesmo que a posição
da revisora tenha essas capacidades. O MCP `orquestra` da revisão troca `delegar` por:

- `aprovar(parecer)`: registra o parecer e aprova;
- `pedir_mudanca(o_que_mudar)`: registra o pedido e devolve à executora.

`comentar` continua; `pedir_ajuda` não entra na revisão **(decisão desta fase)**: a revisora
que acha que falta algo pede mudança dizendo o quê, e quem não decide cai na regra abaixo. A
sessão é a do par (tarefa, persona), então a revisora retoma a própria sessão na segunda
rodada.

**Bloco da tarefa:** a revisora recebe o bloco `<tarefa>` de sempre (descrição, porquê,
cadeia de pais, histórico desde a última execução dela) mais as regras de revisão: "Você
está revisando a entrega de Alfred. Não altere nada. Decida chamando `aprovar` ou
`pedir_mudanca`; se pedir mudança, diga o que muda e por quê." Na aprovação feita por
persona, o texto diz que ela é a aprovadora final.

**Terminou sem decidir:** conta como falha ("a revisão terminou sem decisão"), com nova
tentativa na mesma sessão e o lembrete no bloco. Duas seguidas bloqueiam a tarefa com aviso,
pelo mecanismo da fase 3 **(decisão desta fase)**.

**Executora:** volta a rodar na sessão dela com o gatilho novo `mudanca`. O pedido chega no
"Desde a sua última execução" do bloco, com o rótulo "Nati pediu mudança". A nova entrega
vai para a etapa de `retorno`.

## 4. O board como revisão

Etapa `{ tipo: "revisao", por: { board: true } }`:

- Os membros são as personas das posições da equipe com `board`, menos a executora.
- A pauta é o bloco da tarefa com a última entrega. Cada parecer é só leitura, como no board
  de hoje, no modelo de cada persona e contado no orçamento dela com uso `tarefa`
  **(decisão desta fase)**: o board do chat delibera no modelo forte, mas aqui ele roda sem
  ninguém pedir.
- A síntese roda em Sonnet e termina obrigatoriamente com a linha `DECISÃO: aprovar` ou
  `DECISÃO: mudança`. Sem a linha, conta como revisão sem decisão (seção 3).
- A ata vai para `board/minutes/` como hoje, e o registro na tarefa traz a síntese e o
  caminho da ata.

**Execução:** uma só, com `persona = null` e a chave de concorrência `board`. Ela ocupa uma
vaga do teto global, e só roda um board de tarefa por vez. Membro pausado ou sem orçamento
fica de fora; sem nenhum membro disponível, ou com tudo pausado, a execução espera na fila.

## 5. As etapas do Ueslei

Etapa `{ tipo: "aprovacao", por: { ueslei: true } }`: a tarefa fica `em_revisao` nessa
etapa, sem execução, e sai o aviso "#12 espera sua aprovação", com a entrega.

Cliente→servidor `tarefa-decidir`: `{ id, decisao: "aprovar" | "mudanca", texto? }`.
`mudanca` exige texto. Só vale quando a etapa atual é do Ueslei; no resto, o servidor recusa.
A decisão vai para a auditoria.

**Comentário do Ueslei numa tarefa em revisão:**

- etapa de persona ou de board: acorda a etapa (a revisora vê o comentário), não devolve à
  executora;
- etapa do Ueslei ou sem política: devolve à executora como hoje, valendo como pedido de
  mudança daquela etapa.

**Mover à mão:** `tarefa-status` continua livre. Mover para `concluida` ou `cancelada` pula o
resto da política e descarta a execução de etapa na fila; mover para `a_fazer` zera `etapa`
e `retorno`.

## 6. Limites e garantias

- **A executora não revisa o próprio trabalho.** Além da validação da seção 1 (que vê a
  persona no momento de salvar), o despachante confere na hora: se a persona da etapa é a
  autora da última entrega (a posição pode ter trocado de persona), a tarefa vai para
  `bloqueada` com aviso.
- **Voltas.** No máximo 3 pedidos de mudança por etapa e por tarefa **(decisão desta fase)**.
  O quarto bloqueia a tarefa com aviso "Nati e Alfred não convergiram em #12", com os
  pedidos no histórico. A contagem zera quando o Ueslei devolve a tarefa à mão.
- **Plano e ajuda.** A execução de plano (fase 5) e o pedido de ajuda não passam pela
  política: plano continua indo ao Ueslei, ajuda continua bloqueando. A política só começa
  com uma entrega.
- **Concluída pela política** acorda as dependentes, como a concluída à mão.

## 7. Registros e avisos

`Registro.tipo` ganha `aprovado` e `mudanca`, com o autor sendo a persona, `board` ou
`ueslei`, e o texto sendo o parecer ou o pedido. O bloco da tarefa os rotula ("Nati aprovou:
…", "o board pediu mudança: …").

Avisos novos, em `app/src/avisos/fontes.ts`:

- etapa do Ueslei: "#12 espera sua aprovação";
- concluída pela política: "Nati aprovou #12; tarefa concluída";
- bloqueio por voltas e por autorrevisão.

Revisão de persona e pedido de mudança entre personas não geram aviso: são trabalho interno,
visível na tarefa **(decisão desta fase)**. A entrega que vai para uma etapa de persona
também não gera mais o aviso de entrega; ele só sai quando a entrega cai no Ueslei.

## 8. Telas

- **Detalhe da tarefa (web e app):** a trilha da política numa linha ("Alfred executa →
  Nati revisa → Ueslei aprova"), com a etapa atual destacada e as etapas passadas marcadas.
  Registros `aprovado` e `mudanca` destacados. Na etapa do Ueslei, os botões "Aprovar" e
  "Pedir mudança" (com campo de texto). No celular também.
- **Lista de tarefas:** a tarefa em revisão mostra com quem está ("com Nati", "com o board",
  "com você").
- **Editor do desktop:** o painel da posição ganha "Depois da entrega", com a lista de
  etapas: adicionar revisão (posição da equipe ou board), adicionar aprovação (posição ou
  Ueslei), reordenar e remover, com os erros de validação ao lado.
- **Equipes na web e no celular:** a política aparece no detalhe da posição, só leitura.

## 9. Protocolo e dados

- cliente→servidor: `tarefa-decidir`;
- a tarefa nas mensagens `tarefas` e `tarefa` ganha `politica`, `etapa`, `retorno` e
  `comQuem` (rótulo pronto da seção 8);
- a posição em `equipes` ganha `politica`.

`orquestra.db` sobe para a versão 4: `tarefas` ganha `politica` (JSON), `etapa`, `retorno` e
`voltas`; `execucoes` ganha `etapa`. Tarefas antigas ficam com política vazia. A tarefa nas
mensagens também leva `voltas`, e os gatilhos `revisao` e `mudanca` entram nos nomes de
gatilho dos clientes.

## 10. Testes

`bun test`:

- validação da política: posição inexistente, board sem membro, aprovação fora do fim,
  duas aprovações e a mesma persona revisando a própria posição;
- `aposEntrega`, `aposAprovar`, `aposMudanca`: mudança volta à executora e a próxima entrega
  vai para a mesma etapa, não para a primeira;
- `escolher` aceita execução de etapa só em `em_revisao` na mesma etapa e sem dono, e resolve
  a persona pela posição da etapa;
- a revisão roda com ferramentas só de leitura (nenhuma combinação de capacidades põe
  `Write`, `Edit`, `Bash` ou `delegar` nela);
- revisão sem decisão conta como falha; a síntese do board sem a linha `DECISÃO` também;
- o quarto pedido de mudança na mesma etapa bloqueia;
- autorrevisão detectada no despacho bloqueia;
- `tarefa-decidir` só vale na etapa do Ueslei;
- o teste de protocolo cobra o tipo novo.

`flutter test`: o codec de `tarefa-decidir` e dos campos novos, e a validação da política em
`organograma.dart` contra os mesmos casos do servidor.

## O que fica com quem implementa

Nomes internos, o texto exato das regras de revisão e do pedido de síntese do board, o
desenho da trilha e a ordem dos commits. A ordem sugerida é: política e validação no núcleo;
colunas novas e regras de etapa no repositório; execução de revisão e ferramentas; board como
revisão; etapas do Ueslei e `tarefa-decidir`; protocolo e telas.
