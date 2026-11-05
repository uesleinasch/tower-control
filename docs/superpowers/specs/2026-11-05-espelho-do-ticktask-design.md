# Fase 12 do orquestrador: espelho do TickTask

TickTask #519, subtarefa 12 da #496. Parte da spec-mãe (`2026-10-07-orquestrador-personas-design.md`)
e da decisão registrada nas notas da #496: o sistema de tarefas é interno, e o TickTask é um
espelho opcional, de mão única, só do que precisa do Ueslei. Sem rodada de perguntas: o que ficou
em aberto foi decidido aqui e está marcado como **(decisão desta fase)**.

## Para que serve

O "Precisa de você" do painel só ajuda quando o Ueslei abre o control-tower. A lista que ele olha
o dia inteiro é a do TickTask. O espelho põe lá uma tarefa para cada coisa que espera por ele:
entrega para aprovar, plano, decisão de workflow, sinal, tarefa bloqueada. Finalizar a tarefa no
TickTask faz a ação no control-tower, e resolver no control-tower finaliza a tarefa no TickTask.
O trabalho interno das personas não aparece lá.

Uso que fecha a fase: o Ueslei liga o espelho no desktop. Uma tarefa do Alfred cai na aprovação
dele, e em até um minuto aparece no TickTask "[CT] #12 espera sua aprovação", em "próximas", no
projeto Control Tower. Ele finaliza lá, e a tarefa é aprovada no control-tower. Uma decisão de
workflow aparece com uma subtarefa por opção; finalizar "seguir" faz o fluxo seguir. Uma entrega
concluída pelo painel finaliza sozinha a tarefa do TickTask. Com o TickTask fechado nada para: os
itens esperam e sobem quando ele volta.

## O que o teste mostrou

Rodado em 05/11/2026, só leitura: o servidor conecta direto no MCP do TickTask com o
`@modelcontextprotocol/sdk` que já é dependência (`StreamableHTTPClientTransport`, a URL e o token
de `enderecoTickTask()` em `ticktask.ts`), lista as ferramentas e chama `get_task` e
`server_info`. Não precisa de modelo no meio. `create_task` aceita nome, descrição, status,
projeto, tags e `parent_task_id`; `update_task` muda o status; `write_notes` acrescenta nota.

## Objetivos

- Espelho de mão única, ligado e desligado pelo Ueslei, que cria, acompanha e finaliza no TickTask
  as tarefas do que precisa dele.
- Finalizar no TickTask faz a ação do control-tower quando ela é inequívoca.
- Resolver no control-tower finaliza no TickTask.
- Nada para quando o TickTask está fechado; o espelho alcança quando ele volta.

## Fora desta fase

- Pedir mudança, negar comando ou escrever comentário pelo TickTask. Só pelo control-tower.
- Espelhar tarefas internas das personas, conversas ou o trabalho em andamento.
- Criar no TickTask uma tarefa que vire tarefa do control-tower (mão dupla de criação).
- Prazo e agenda no TickTask (`due_date`, `scheduled_date`) a partir dos prazos de workflow.
- Apagar tarefas no TickTask: o espelho só finaliza.

## Anti-objetivos

- O control-tower depender do TickTask: espelho fora do ar nunca atrasa tarefa, conversa ou
  workflow.
- Encher a lista pessoal: só o que espera pelo Ueslei, uma tarefa por item, e nada de recriar o
  que ele dispensou.
- Ação dupla ou fantasma: finalizar no TickTask não pode aprovar duas vezes nem agir sobre algo
  que já mudou no control-tower.
- Modelo de linguagem no caminho: o espelho fala com o MCP do TickTask direto.

## 1. O que sobe

A fonte é a mesma lista do "Precisa de você" (`itensDeAtencao` em `orquestra/painel.ts`), já
calculada pelo painel. Cada item tem uma chave estável **(decisão desta fase)**:

| Tipo | Chave | Sobe por padrão | Finalizar no TickTask faz |
|---|---|---|---|
| `aprovacao` | `aprovacao:<tarefa>` | sim | aprova a entrega (`tarefa-decidir` aprovar) |
| `plano` | `plano:<tarefa>` | sim | aprova o plano |
| `entrega` | `entrega:<tarefa>` | sim | conclui a tarefa |
| `decisao` | `decisao:<fluxo>:<ficha>` | sim | finalizar a subtarefa de uma opção escolhe essa opção |
| `sinal` | `sinal:<fluxo>:<ficha>` | sim | sinaliza |
| `bloqueada` | `bloqueada:<tarefa>` | sim | nada (só tira da lista) |
| `backlog` | `backlog:<tarefa>` | não | libera a subtarefa delegada |
| `atrasada` | `atrasada:<fluxo>:<ficha>` | não | nada |
| `orcamento` | `orcamento:<persona>` | não | nada |
| `rotina` | `rotina:<equipe>/<id>` | não | nada |
| `vaga` | `vaga:<tarefa>` | não | nada |
| `comando` | — | nunca | — |

O pedido de comando fica de fora porque expira em 10 minutos e já vira aviso no celular
**(decisão desta fase)**. Os tipos que sobem são configuráveis (seção 4).

**A tarefa no TickTask.**
- **Nome:** `[CT] <título do item>`.
- **Descrição:** o detalhe do item, o que finalizar faz ("Finalizar aqui aprova a entrega"; "Para
  pedir mudança, abra o control-tower") e o endereço do control-tower.
- **Onde fica:** status `proximas`, no projeto e com a tag da configuração.
- **Decisão:** a tarefa-mãe tem a pergunta e uma subtarefa por opção (`[CT] seguir`, `[CT] parar`).

## 2. O ciclo de um item

Tabela `espelho` em `orquestra.db` (versão 7): `id`, `chave`, `tipo`, `ticktask` (id lá, nulo até
criar), `opcoes` (JSON: opção → id da subtarefa), `estado`, `acao` (o que finalizar faz, com os
ids do control-tower), `criadoEm`, `atualizadoEm`, `erro`. No máximo uma linha aberta por chave
(índice parcial).

Estados: `criar` (falta subir), `aberto`, `fechar` (resolvido aqui, falta finalizar lá),
`resolvido_aqui`, `resolvido_la`, `dispensado` (finalizado lá sem ação, ou a tarefa sumiu lá).

**Uma volta do espelho** (núcleo puro decide, o adaptador executa):

1. **Comparar.** Item desejado sem linha aberta vira linha `criar`. Linha `aberto` ou `criar`
   cuja chave saiu da lista vira `fechar`; se nunca subiu, vai direto a `resolvido_aqui`.
2. **Subir.** Para cada `criar`: `create_task` (e as subtarefas da decisão), grava o id e passa a
   `aberto`. Para cada `fechar`: `update_task` para `finalizada` com a nota "Resolvido no
   control-tower em <data>.", e passa a `resolvido_aqui`.
3. **Puxar.** Para cada `aberto`: `get_task`. Finalizada lá (ou, na decisão, uma subtarefa
   finalizada): confere se o item ainda está na lista do painel com a mesma chave; se está, faz a
   ação pelo mesmo caminho do painel, registra na auditoria "via TickTask" e passa a
   `resolvido_la`; se não está, passa a `resolvido_aqui`. Finalizada sem ação possível (tipo
   informativo, ou a mãe da decisão sem subtarefa) passa a `dispensado`. Tarefa apagada lá passa
   a `dispensado`.

**Quando roda.** A cada 30 segundos e logo depois de cada remontagem do painel que mude a lista,
uma volta por vez (fila). Sem o TickTask (sem config, app fechado ou erro de rede), a volta para
no primeiro erro, guarda a mensagem e tenta de novo na próxima; as linhas `criar` e `fechar`
esperam **(decisão desta fase)**.

**Sem ação dupla.** A ação só roda se a chave ainda está na lista do painel no momento. Item que
já foi resolvido no app vira `resolvido_aqui` sem agir. Item que volta depois de resolvido (uma
tarefa que volta a `em_revisao`) é outra linha e outra tarefa no TickTask.

**Dispensado não volta.** Enquanto a chave continuar na lista, uma linha `dispensado` impede criar
outra **(decisão desta fase)**. Quando a chave sai e volta, ela sobe de novo.

## 3. Ações

As ações usam os mesmos caminhos do painel (`ORQUESTRA.decidir`, aprovar plano, concluir,
liberar, `MOTOR.decidir`, `MOTOR.sinalizar`), com `ueslei` como autor e "via TickTask" na
auditoria. Erro na ação (a tarefa mudou entre a leitura e a ação) vira `erro` na linha e
`resolvido_aqui`, e a nota da tarefa no TickTask diz que não deu para agir.

## 4. Configuração

Arquivo `ticktask.json` na pasta de dados, versionado no git dela:

```json
{ "ativo": false, "projeto": "Control Tower", "tag": "control-tower", "tipos": ["aprovacao", "plano", "entrega", "decisao", "sinal", "bloqueada"] }
```

Começa desligado **(decisão desta fase)**. O projeto é o nome (ou id) de um projeto do TickTask; se
não existir, a criação falha com o erro na linha e o estado mostra o problema. A tag é criada pelo
próprio TickTask quando não existe. Desligar para as voltas e não mexe no que já está lá; religar
continua da tabela.

## 5. Telas e protocolo

- cliente→servidor: `espelho` (pede o estado); só no desktop, `espelho-salvar`
  (`{ config }`) e `espelho-sincronizar` (uma volta agora);
- servidor→cliente: `espelho` (`{ config, estado: { conectado, ultimaVolta, erro, abertos,
  pendentes } }`), mandado a todos quando muda.
- **Desktop:** a Configuração ganha "Espelho no TickTask": ligar e desligar, projeto, tag, os tipos
  que sobem (caixas de marcar) e o estado: conectado ou não, última volta, quantos itens estão lá,
  quantos esperam para subir ou fechar, último erro, e "Sincronizar agora".
- **Web e celular:** nada de novo. O painel continua sendo a fonte.

## 6. Testes

`bun test`:

- chave de cada tipo e o mapa tipo → ação;
- a volta pura: item novo vira `criar`; item que saiu vira `fechar` ou `resolvido_aqui`;
  `dispensado` com a chave na lista não recria; chave que sai e volta recria;
- o puxar com um TickTask falso: finalizada com o item ainda na lista age uma vez; sem o item,
  não age; subtarefa da decisão escolhe a opção; mãe sem subtarefa vira `dispensado`; tarefa
  apagada vira `dispensado`; erro de rede deixa `criar` e `fechar` esperando;
- a configuração: tipos desconhecidos recusados, desligado não faz volta;
- o teste de protocolo cobra os tipos novos.

`flutter test`: o codec dos tipos novos e a configuração.

Ponta a ponta num servidor isolado, contra um servidor MCP falso que imita as ferramentas do
TickTask (para não sujar a lista do Ueslei): aprovação subindo, finalizada lá e aprovada aqui;
decisão com subtarefas; entrega concluída pelo painel finalizando lá; TickTask fora do ar e
voltando. Por último, com a permissão do Ueslei, uma volta contra o TickTask de verdade num
projeto de teste.

## O que fica com quem implementa

Nomes internos, o texto exato da descrição e das notas, o desenho da seção na Configuração e a
ordem dos commits. A ordem sugerida é: núcleo puro (chaves, ações, a volta); tabela e adaptador
MCP; ligação com o painel e o relógio; configuração e protocolo; tela do desktop.
