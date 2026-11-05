# Fase 8 do orquestrador: painel de controle

TickTask #505, subtarefa 8 da #496. Parte das seções 7 e 10 da spec-mãe
(`2026-10-07-orquestrador-personas-design.md`) e fecha o que a fase 5 deixou para cá (filtros
da atividade e a visão de atenção). Não reabre nada das fases anteriores. Sem rodada de
perguntas: o que ficou em aberto foi decidido aqui e está marcado como
**(decisão desta fase)**.

## Para que serve

Até a fase 7, o estado do orquestrador está espalhado: tarefas numa tela, personas e gasto em
Equipes, rotinas em outra aba, comandos e entregas nos avisos. Com rotinas criando trabalho
sozinho e revisões entre personas, o Ueslei precisa de um lugar só para responder a duas
perguntas: "preciso fazer alguma coisa?" e "o que está acontecendo agora?".

Uso que fecha a fase: de manhã, o Ueslei abre o Painel no celular. No topo, "Precisa de você
(3)": a entrega do Plano do dia esperando a aprovação dele, um comando do Alfred esperando
liberação e a Nati parada por orçamento. Ele aprova a entrega ali mesmo, nega o comando e
vê, logo abaixo, a revisão da Nati em outra tarefa rodando ao vivo, com a última ferramenta
usada. Depois filtra a atividade por "Alfred" para ver o que ele fez ontem.

## Objetivos

- Uma tela "Painel" na web, no desktop e no celular, atualizada ao vivo.
- "Precisa de você": tudo o que espera o Ueslei, com a ação ali mesmo.
- "Agora": execuções rodando e o que está na fila, com o motivo da espera.
- Personas num relance: o que cada uma está fazendo, o gasto do mês e a pausa.
- Atividade recente com filtros por persona e por tipo.

## Fora desta fase

- Workflows em grafo no painel: entram com a fase 9.
- Gráficos de gasto ao longo do tempo. O `relatorio-uso.ts` continua sendo o lugar dos
  números detalhados; o painel mostra só o mês corrente **(decisão desta fase)**.
- Dispensar um item de atenção à mão. Um item some quando o que o causou é resolvido
  **(decisão desta fase)**.
- Substituir os avisos. O painel é o que o Ueslei abre, e o aviso é o que o chama. Os dois
  continuam.

## Anti-objetivos

- Painel que precisa de recarregar para ficar certo.
- Item de atenção que não diz o que fazer, ou que obriga a abrir três telas para agir.
- Um segundo jeito de fazer cada ação: o painel manda as mesmas mensagens que as telas de
  hoje já mandam.

## 1. O retrato

O servidor monta um retrato só (`orquestra/painel.ts`, núcleo puro que recebe os dados já
lidos e devolve o retrato) e o manda a quem está com o painel aberto:

```ts
interface Retrato {
  em: string
  pausadoTudo: boolean
  atencao: ItemDeAtencao[]
  agora: { rodando: ExecucaoViva[]; naFila: Espera[] }
  personas: CartaoDePersona[]
  tarefas: Record<string, Partial<Record<StatusTarefa, number>>>   // por equipe
  gasto: { mes: string; tarefasUSD: number; totalUSD: number; tokensTarefas: number; tokensTotal: number }
  proximasRotinas: { equipe: string; id: string; nome: string; proximo: string }[]   // até 5
  atividade: ItemDeAtividade[]   // até 100, mais recente primeiro
}
```

## 2. Precisa de você

`ItemDeAtencao`: `{ tipo, titulo, detalhe, desde, acoes, tarefaId?, permissaoId?, persona?,
equipe?, rotina? }`, em ordem de prioridade e, dentro dela, do mais antigo para o mais novo:

| Prioridade | `tipo` | Quando | `acoes` |
|---|---|---|---|
| 1 | `comando` | pedido de comando pendente (tarefa ou chat) | `aprovar`, `negar` |
| 2 | `aprovacao` | tarefa na etapa de aprovação do Ueslei (fase 6) | `aprovar`, `pedir-mudanca` |
| 3 | `plano` | plano esperando aprovação (fase 5) | `aprovar-plano`, `abrir` |
| 4 | `entrega` | entrega em revisão sem política (com você) | `concluir`, `abrir` |
| 5 | `bloqueada` | tarefa bloqueada (ajuda, falhas, voltas, autorrevisão) | `abrir` |
| 6 | `backlog` | subtarefa delegada esperando ser liberada | `liberar`, `abrir` |
| 7 | `orcamento` | persona com orçamento estourado e tarefa esperando | `abrir` |
| 8 | `rotina` | rotina cujo último disparo falhou | `abrir` |
| 9 | `vaga` | tarefa a fazer numa posição vaga | `abrir` |

O `detalhe` é curto (até 180 caracteres): o comando, o começo da entrega, o motivo do
bloqueio (o último registro de ajuda ou de status do orquestrador), o gasto contra o limite.
Orçamento em 80% não entra, porque não pede ação **(decisão desta fase)**.

Cada ação manda uma mensagem que já existe:

- `aprovar` e `negar` de comando: `permissao-resposta` `{ id, permitido }`;
- `aprovar` e `pedir-mudanca`: `tarefa-decidir` (com texto obrigatório na mudança);
- `aprovar-plano`: `tarefa-aprovar-plano`;
- `concluir`: `tarefa-status` para `concluida`; `liberar`: `tarefa-status` para `a_fazer`;
- `abrir`: navega para a tarefa, para a equipe (orçamento, vaga) ou para as rotinas, sem
  mensagem nova.

## 3. Agora

`ExecucaoViva`: `{ execucao, tarefaId, titulo, equipe, persona, papel, inicio, ultimoEvento }`.
`papel` é `"executa"`, `"revisa"` ou `"board"`; `persona` é o nome (`null` no board).
`ultimoEvento` é `{ tipo, conteudo, em }` do evento mais recente da execução (conteúdo cortado
em 180 caracteres) ou `null`.

`Espera`: `{ execucao, tarefaId, titulo, persona, motivo, desde }`. O `motivo` vem de uma regra
pura que repete as checagens do despachante, na mesma ordem: "tudo pausado", "<persona>
pausada", "<persona> sem orçamento", "posição vaga", "depende da #N", "nova tentativa às
HH:MM", "<persona> ocupada com a #N", "limite de N execuções ao mesmo tempo"
**(decisão desta fase)**.

## 4. Personas

`CartaoDePersona`: `{ id, nome, cor, estado, tarefaId?, gastoMesUSD, limiteUSD, tokensMes,
limiteTokens, abertas }`, com `estado` em `rodando`, `na_fila`, `ocioso`, `pausada` ou
`sem_orcamento`. `abertas` conta as tarefas não concluídas nem canceladas das posições da
persona em todas as equipes. Os cartões substituem o organograma no painel: o desenho da
equipe continua em Equipes **(decisão desta fase)**.

## 5. Atividade

`ItemDeAtividade`: `{ em, tipo, quem, texto, tarefaId?, equipe? }`, juntando três fontes:

- registros de tarefa dos tipos `entrega`, `plano`, `ajuda`, `aprovado`, `mudanca` e
  `comentario` (`tipo` igual ao do registro, com `aprovado` e `mudanca` como `decisao`);
- a tabela `auditoria` (`tipo` `auditoria`);
- os disparos de rotina (`tipo` `disparo`; `quem` é a rotina).

Os registros de status ficam de fora, porque são ruído **(decisão desta fase)**. Os filtros
(por persona e por tipo) são do cliente, sobre os 100 itens. É a forma final da lista
"Atividade" da fase 5, que sai da tela de Equipes.

## 6. Ao vivo

Cliente→servidor `painel`: `{ ativo: boolean }`. Com `true`, o socket passa a assinar o painel
e recebe o retrato na hora; com `false` (ou fechando o socket), deixa de assinar.
Servidor→cliente `painel`: `{ retrato }`.

O servidor remonta o retrato quando algo muda (tarefa publicada, execução publicada, evento
de execução, rotinas, personas, pausa, pedido de comando criado ou resolvido), no máximo uma
vez por segundo, e só se alguém está assinando **(decisão desta fase)**. Um relógio de 30 s
também remonta, para os horários relativos e o "nova tentativa às" andarem sozinhos.

## 7. Telas

- **Web:** botão "Painel" na barra, ao lado de Tarefas e Equipes. As seções vêm uma embaixo
  da outra: "Precisa de você" (com o número), "Agora", "Personas", "Tarefas" (contagem por
  status da equipe escolhida, cada número abrindo a lista filtrada), "Próximas rotinas" e
  "Atividade" (com os filtros). Seção vazia diz que está vazia ("Nada esperando você").
- **Desktop e celular:** aba "Painel" com as mesmas seções. No celular, "Precisa de você"
  fica no topo e os botões de ação ficam no próprio item. "Pedir mudança" abre o campo de
  texto, como no detalhe da tarefa.
- **Atividade em Equipes:** sai, já que mudou para o painel.

O painel não vira a tela inicial: cada cliente continua abrindo onde abre hoje
**(decisão desta fase)**.

## 8. Protocolo

- cliente→servidor: `painel` (`{ ativo }`);
- servidor→cliente: `painel` (`{ retrato }`).

Os dois entram nos três clientes. A mensagem `auditoria` (nas duas direções) sai do servidor,
dos clientes e do `protocolo.json`, porque a atividade do painel a substitui
**(decisão desta fase)**.

## 9. Testes

`bun test`:

- atenção: cada tipo da tabela entra quando deve e sai quando o motivo some, na ordem de
  prioridade e de idade, com as ações certas;
- o motivo da espera repete o despachante (pausa, orçamento, vaga, dependência, nova
  tentativa, persona ocupada, teto);
- estado de cada persona e as tarefas abertas contando todas as equipes;
- atividade: junta as três fontes, tira os registros de status, ordena e corta em 100;
- só remonta e manda o retrato para quem assina, no máximo uma vez por segundo;
- o teste de protocolo cobra o tipo novo.

`flutter test`: o codec do retrato, com padrões seguros para campos ausentes, e o mapa de cada
ação para a mensagem que ela manda.

## O que fica com quem implementa

Nomes internos, o desenho das seções e dos cartões e a ordem dos commits. A ordem sugerida é:
o retrato puro com a atenção, a espera e a atividade; a assinatura e o ritmo no servidor; a
web; o app.
