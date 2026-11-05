# Fase 9 do orquestrador: workflows em grafo

TickTask #501, subtarefa 9 da #496. Parte da seção 6 da spec-mãe
(`2026-10-07-orquestrador-personas-design.md`) e do pedido do Ueslei nas notas da #501 (caixas
de ação e de decisão como no construtor de automação do SendPulse). Não reabre nada das
fases anteriores. Sem rodada de perguntas: o que ficou em aberto foi decidido aqui e está
marcado como **(decisão desta fase)**.

## Para que serve

A execution policy da fase 6 é uma linha: executar, revisar, aprovar. O trabalho real tem
caminhos: um plano de risco alto pede a palavra do Ueslei antes de seguir, duas personas
trabalham em paralelo e o resultado só anda quando as duas terminam, uma etapa repete até
ficar boa. Esta fase traz o motor desses caminhos: o workflow é um grafo de caixas, cada caixa
faz uma coisa, e a saída de uma alimenta as seguintes.

Esta fase é o motor, o formato e a visualização. O editor visual nó a nó é a fase 10 (#520):
até lá, o workflow é escrito em JSON na pasta de dados, à mão ou com ajuda do Claude, e
validado pelo servidor ao subir e ao salvar.

Uso que fecha a fase: na Casa, o workflow "Mudança com plano" recebe um pedido em texto.
1. A Nati escreve o plano e devolve o plano e o risco ("baixo" ou "alto").
2. Uma condição olha o risco. Se for alto, o Ueslei decide no painel entre "seguir" e
   "parar".
3. Seguindo, o Alfred executa o plano, e a Pami escreve a nota de mudança ao mesmo tempo.
4. A Nati revisa a execução do Alfred, que volta para ele se ela pedir mudança.
5. Quando as duas pontas terminam, o workflow acaba com as devolutivas registradas.

O painel mostra o grafo com as caixas ativas, e, se o servidor cair no meio, o workflow
continua de onde parou.

## Objetivos

- Formato JSON versionado de workflow, por equipe, com caixas e ligações.
- As caixas da spec-mãe: executar (a "caixa de ação"), revisar, aprovar, decisão humana,
  condição (a "caixa de decisão"), paralelo, junção, laço, espera, board e fim.
- Saídas tipadas: a caixa declara o que devolve, e as seguintes usam esses valores no texto e
  nas condições, com a validação conferindo nomes e tipos.
- Motor que guarda cada passo no SQLite e retoma exatamente de onde parou.
- Prazo por caixa, com aviso quando passa.
- Visualização do grafo com as caixas ativas na web, no desktop e no celular.
- Rotina que dispara workflow (o destino que a fase 7 deixou para cá).

## Fora desta fase

- O editor visual (fase 10). Aqui, o desktop só desenha o grafo, sem editar.
- Espera por evento vindo de fora (webhook de workflow). A espera por evento desta fase é
  sinalizada à mão, pelo painel **(decisão desta fase)**.
- Subworkflow (um workflow chamando outro).
- Validação espelhada no Flutter: ela entra com o editor, na fase 10.

## Anti-objetivos

- Um segundo runtime. A caixa de ação vira uma tarefa comum, que passa pelo mesmo runtime,
  governança e execution policy das fases 3 a 6.
- Workflow que gasta sem parar: laço sem limite, fan-out sem fim, cascata de caixas.
- Estado só em memória: queda no meio de um passo não pode perder nem repetir uma caixa.

## 1. O arquivo

`equipes/<equipe>/workflows/<id>.json`, versionado no git dos dados:

```json
{
  "id": "mudanca-com-plano",
  "nome": "Mudança com plano",
  "versao": 3,
  "entrada": { "pedido": "texto" },
  "inicio": "plano",
  "nos": [
    { "id": "plano", "tipo": "executar", "posicao": "conselho-nati",
      "instrucao": "Escreva um plano para: {{entrada.pedido}}",
      "criterio": "Passos numerados e os riscos.",
      "saidas": { "plano": "texto", "risco": { "escolha": ["baixo", "alto"] } } },
    { "id": "risco", "tipo": "condicao",
      "regras": [{ "campo": "plano.risco", "op": "igual", "valor": "alto", "saida": "alto" }] },
    { "id": "ok", "tipo": "decisao_humana", "pergunta": "Risco alto. Seguir?", "opcoes": ["seguir", "parar"] },
    { "id": "frente", "tipo": "paralelo" },
    { "id": "executa", "tipo": "executar", "posicao": "executor", "instrucao": "Execute: {{plano.plano}}" },
    { "id": "revisa", "tipo": "revisar", "de": "executa", "por": { "posicao": "conselho-nati" } },
    { "id": "nota", "tipo": "executar", "posicao": "conselho-pami", "instrucao": "Escreva a nota de mudança de: {{plano.plano}}" },
    { "id": "junta", "tipo": "juncao" },
    { "id": "fim", "tipo": "fim" },
    { "id": "parou", "tipo": "fim", "resultado": "cancelado pelo Ueslei" }
  ],
  "arestas": [
    { "de": "plano", "para": "risco" },
    { "de": "risco", "para": "ok", "quando": "alto" },
    { "de": "risco", "para": "frente", "quando": "senao" },
    { "de": "ok", "para": "frente", "quando": "seguir" },
    { "de": "ok", "para": "parou", "quando": "parar" },
    { "de": "frente", "para": "executa" },
    { "de": "frente", "para": "nota" },
    { "de": "executa", "para": "revisa" },
    { "de": "revisa", "para": "junta", "quando": "aprovado" },
    { "de": "nota", "para": "junta" },
    { "de": "junta", "para": "fim" }
  ],
  "layout": {}
}
```

Textos longos podem ir num arquivo ao lado: `"instrucao": "@plano.md"` lê
`equipes/<equipe>/workflows/<id>/plano.md`. A `versao` sobe a cada gravação pelo servidor.
Uma execução em andamento continua na versão em que começou, porque guarda a definição inteira
(seção 4). JSON inválido derruba a subida com o erro, como equipe e rotina.

## 2. As caixas

| `tipo` | O que faz | Saídas | Ligações que saem (`quando`) |
|---|---|---|---|
| `inicio` (campo do workflow) | aponta a primeira caixa | `entrada.*` | — |
| `executar` | cria uma tarefa para a posição, com `instrucao` e `criterio` | `devolutiva: texto` e as de `saidas` | uma, sem `quando` |
| `revisar` | revisão da tarefa de `de` por posição ou board (fase 6) | `parecer: texto` | `aprovado` |
| `aprovar` | aprovação da tarefa de `de` por posição ou Ueslei (fase 6) | `parecer: texto` | `aprovado` |
| `decisao_humana` | pergunta ao Ueslei, com opções | `opcao`, `comentario: texto` | uma por opção |
| `condicao` | primeira regra verdadeira escolhe a saída | — | uma por `saida` das regras, mais `senao` |
| `paralelo` | segue por todas as ligações ao mesmo tempo | — | duas ou mais, sem `quando` |
| `juncao` | espera chegar uma vez por cada ligação que entra | — | uma, sem `quando` |
| `laco` | repete enquanto a regra valer, até `maxVoltas` | `voltas: numero` | `repetir` e `sair` |
| `espera` | espera uma duração, um horário ou um sinal | `motivo` (`pronto` ou `prazo`) | `pronto` e, se tiver prazo, `prazo` |
| `board` | deliberação do board da equipe sobre uma `pauta` | `sintese: texto`, `decisao` | uma por opção, ou uma sem `quando` |
| `fim` | encerra o caminho | — | nenhuma |

**Executar (caixa de ação).** É o pedido do chefe para a subordinada nas notas da #501:
`instrucao` (o que fazer e o contexto), `criterio` (o que se espera e o formato da
devolutiva) e `saidas` (os campos que voltam). A tarefa nasce na posição, com a descrição
montada desses textos, já com as referências trocadas pelos valores. Ela segue o runtime
normal, inclusive o plano da fase 5, e o "porquê" da tarefa é o nome do workflow. Com
`saidas`, a persona ganha a ferramenta `devolver`, com um campo por saída e o tipo de cada
um (texto, número, sim/não ou uma das escolhas). Terminar sem devolver conta como falha,
como a revisão sem decisão da fase 6. A última resposta vira `devolutiva`.

**Revisar e aprovar** reaproveitam a fase 6 inteira. Quando a tarefa de `de` entrega, o motor
junta a corrente de revisões e aprovações ligadas por `aprovado` que vêm logo depois dela e a
grava como a `politica` da tarefa. A partir daí, o runtime da fase 6 cuida de tudo: revisão
só de leitura, pedido de mudança que volta à mesma executora e retorna à mesma revisora,
limite de voltas, board e aprovação do Ueslei. Quando a tarefa é concluída pela política, o
motor segue pela ligação `aprovado` da última caixa da corrente **(decisão desta fase)**. A
ligação `mudanca` não existe no arquivo: a volta é da tarefa, não do grafo.

**Decisão humana (caixa de decisão).** Fica esperando, aparece no "Precisa de você" do painel
com um botão por opção e um campo de comentário opcional, e gera aviso. Cliente→servidor
`workflow-decidir`: `{ execucao, ficha, opcao, comentario? }`.

**Condição (caixa de decisão automática).** `regras`: `{ campo, op, valor?, saida }`, com `op`
em `igual`, `diferente`, `contem`, `maior`, `menor`, `vazio` e `preenchido`. O `campo` é uma
referência (`no.saida` ou `entrada.campo`). A primeira regra verdadeira escolhe a ligação;
nenhuma verdadeira, `senao`.

**Laço.** `maxVoltas` (de 1 a 20, obrigatório) e `enquanto` (uma regra como as da condição).
Cada passagem conta uma volta: com a regra verdadeira e voltas abaixo do máximo, segue por
`repetir`; senão, por `sair`. Uma caixa `executar` dentro do laço vira uma tarefa nova a cada
volta, com a devolutiva da volta anterior disponível nas referências.

**Espera.** Uma de três: `duracao` (`"30m"`, `"2h"`, `"1d"`), `ate` (`"HH:MM"`, o próximo
horário) ou `sinal` (um nome). O sinal é dado pelo painel (cliente→servidor `workflow-sinal`:
`{ execucao, ficha }`). Com `prazo` (duração), a espera que passa do prazo sai por `prazo`.

**Board.** `pauta` (texto com referências) e `opcoes` opcionais. Usa o board de tarefa da fase
6 (membros com `board` na equipe, cada um no próprio modelo e orçamento, síntese em Sonnet). Com
opções, a síntese termina em `DECISÃO: <opção>`, e sem a linha conta como falha.

**Fim.** `resultado` opcional (texto). O workflow termina quando não sobra caixa ativa. Se
algum caminho chegou num `fim` com resultado, o resultado é o do último.

## 3. Referências e tipos

Texto de `instrucao`, `criterio`, `pauta` e `pergunta` aceita `{{entrada.campo}}` e
`{{no.saida}}`. Os tipos são `texto`, `numero`, `booleano` e `{ "escolha": [...] }`. Toda caixa
de persona tem a saída implícita do quadro acima (`devolutiva`, `parecer`, `sintese`).

A validação (núcleo puro, `orquestra/workflow.ts`) recusa:

- ligação para caixa inexistente, `quando` que não é do tipo da caixa, opção ou saída sem
  ligação, e caixa que não seja `fim` sem saída;
- caixa inalcançável a partir do `inicio`;
- ciclo que não passa por um `laco` **(decisão desta fase)**; e `paralelo` ou `juncao` dentro
  de laço, porque contar chegadas a cada volta complica sem ganho agora;
- `juncao` com menos de duas ligações entrando;
- referência a caixa que não vem sempre antes (precisa haver caminho dela até a caixa que a
  usa), a saída não declarada ou a campo de entrada inexistente;
- regra com `op` que não serve ao tipo (`maior` e `menor` só em número; `valor` fora das
  escolhas de uma escolha);
- posição inexistente; `revisar` ou `aprovar` cujo `de` não é um `executar`, ou que não vem
  logo depois dele (ou de outra revisão do mesmo `de`); revisão pela mesma persona que executa
  (regra da fase 6); `board` sem membros;
- `laco` sem `maxVoltas` entre 1 e 20; `espera` sem exatamente um de `duracao`, `ate` e `sinal`.

## 4. O motor

`orquestra/fluxo.ts` (núcleo puro: dado o estado e um evento, devolve os passos a gravar) e
`orquestra/motor.ts` (adaptador com o SQLite e o runtime). Em `orquestra.db` (versão 6):

- `fluxos`: `id`, `equipe`, `workflow`, `versao`, `definicao` (o JSON inteiro da versão),
  `entrada`, `status` (`rodando`, `concluido`, `falhou`, `cancelado`), `resultado`,
  `criadoPor` (`ueslei` ou `rotina:<equipe>/<id>`), `criadoEm`, `atualizadoEm`, `erro`;
- `fichas`: `id`, `fluxo`, `no`, `status` (`ativa`, `esperando`, `concluida`, `cancelada`),
  `tarefa`, `voltas`, `acordaEm`, `prazoEm`, `saidas` (JSON), `veioDe` (a ficha anterior),
  `criadaEm`, `concluidaEm`;
- `tarefas` ganha `fluxo` e `ficha`.

**Fichas.** Cada caixa ativa é uma ficha. O paralelo cria uma ficha por ligação. A junção
guarda as chegadas e só cria a ficha seguinte quando chegou uma por ligação de entrada. Toda
mudança de ficha acontece numa transação: concluir a ficha atual, gravar as saídas, criar as
seguintes e, para `executar`, criar a tarefa. Por isso uma queda no meio não perde nem repete
caixa **(decisão desta fase)**.

**Caixas instantâneas** (condição, paralelo, junção, laço e fim) andam na hora, na mesma
transação de quem as alcançou. **Caixas que esperam** (executar, revisar e aprovar via tarefa,
decisão humana, espera, board) ficam `esperando` até o evento delas.

**Eventos que fazem o motor andar:**

- tarefa de ficha entregue (o runtime chama o motor em vez de mandar a entrega ao Ueslei):
  grava as saídas e entra nas revisões, ou conclui a tarefa e segue;
- tarefa de ficha concluída pela política ou à mão: segue pela ligação `aprovado` da corrente;
- tarefa de ficha cancelada à mão: o fluxo inteiro é cancelado, com as outras tarefas abertas
  dele **(decisão desta fase)**;
- `workflow-decidir`, `workflow-sinal`, a resposta do board;
- o relógio de 30 s: esperas vencidas, prazos e o vigia.

**Retomada.** Na subida, o motor relê as fichas `ativa` (o passo instantâneo que não chegou a
gravar) e as processa de novo. As tarefas das fichas que esperam seguem com a retomada do
runtime da fase 3.

**Prazo e vigia.** Toda caixa aceita `prazo` (duração). Passado o prazo, sai um aviso e um item
no "Precisa de você" (`atrasada`). A ficha não é cancelada sozinha **(decisão desta fase)**.

**Freios.** No máximo 20 fichas vivas e 200 fichas criadas por fluxo. Passou disso, o fluxo
para em `falhou` com aviso. A pausa geral e as pausas de persona valem para as tarefas do fluxo
como para qualquer tarefa. Com tudo pausado, decisões e sinais ainda são aceitos, mas as
tarefas novas esperam na fila.

**Cancelar.** Cliente→servidor `workflow-cancelar`: `{ execucao }` cancela as fichas e as
tarefas abertas do fluxo. Entra na auditoria.

## 5. Iniciar

- **À mão:** cliente→servidor `workflow-iniciar`: `{ equipe, id, entrada }`, com a entrada
  validada contra os tipos declarados. Vale na web, no desktop e no celular, com um formulário
  pelos campos da entrada.
- **Por rotina:** a rotina da fase 7 ganha `workflow` (id de workflow da mesma equipe), no
  lugar de `tarefa`. O disparo inicia um fluxo, com `{{entrada.dados}}` recebendo o corpo do
  webhook quando o workflow declara `dados: texto`. A concorrência da rotina passa a olhar o
  fluxo aberto mais recente que ela criou: `pular` não inicia outro; `enfileirar` inicia
  quando o anterior termina; `substituir` cancela o anterior **(decisão desta fase)**.

## 6. Visualização

- **Web:** Equipes ganha a lista "Workflows" da equipe, com "Iniciar" e o desenho do grafo em
  SVG próprio, só leitura (o mesmo jeito do organograma). O painel ganha a seção "Workflows",
  com os fluxos rodando: nome, há quanto tempo, as caixas ativas e um botão que abre o grafo
  com as caixas concluídas, as ativas e o caminho percorrido.
- **Desktop e celular:** as mesmas duas coisas. O desktop desenha o grafo com o componente do
  organograma (fase 4), sem editar. O celular mostra o grafo em lista, caixa por caixa, na ordem
  do caminho, porque o desenho não cabe **(decisão desta fase)**.
- **Painel, "Precisa de você":** três tipos novos: `decisao` (botão por opção), `sinal` (botão
  "Sinalizar") e `atrasada` (abrir).
- **Tarefa de fluxo:** o detalhe diz "caixa <nome> do workflow <nome>" e abre o grafo.

## 7. Protocolo

- cliente→servidor: `workflows` (pede a lista), `workflow-iniciar`, `workflow-decidir`,
  `workflow-sinal`, `workflow-cancelar` e, só no desktop, `workflow-salvar` e
  `workflow-excluir` (o servidor já valida e grava; quem usa é o editor da fase 10);
- servidor→cliente: `workflows` (`{ definicoes, fluxos }`, com as fichas dos fluxos abertos e
  dos 20 últimos fechados), mandado a todos a cada mudança;
- o retrato do painel ganha `workflows` e os três tipos de atenção novos.

## 8. Testes

`bun test`:

- validação: cada recusa da seção 3, e o workflow de exemplo da seção 1 aceito;
- referências: troca no texto, tipo conferido, valor de escolha fora da lista;
- motor, com runtime falso: o exemplo inteiro nos dois caminhos do risco; paralelo e junção
  esperando as duas pontas; laço parando no máximo; espera por duração, horário, sinal e prazo;
  `devolver` com os tipos e a falha sem devolver;
- revisão: a corrente vira a política da tarefa, a mudança volta à mesma executora e o fluxo
  segue por `aprovado`;
- retomada: uma queda entre gravar a ficha e processar a caixa instantânea retoma sem repetir;
  o fluxo continua na versão em que começou depois de o arquivo mudar;
- freios: o limite de fichas vivas e criadas; cancelar uma tarefa cancela o fluxo;
- rotina com workflow e a concorrência sobre fluxos;
- o teste de protocolo cobra os tipos novos.

`flutter test`: o codec dos tipos novos, o grafo em lista na ordem do caminho e as ações dos
itens de atenção novos.

## O que fica com quem implementa

Nomes internos, o texto exato que a tarefa de uma caixa recebe, o desenho do grafo e das
caixas e a ordem dos commits. A ordem sugerida é: formato e validação; referências e tipos;
motor puro com as caixas instantâneas; caixas que esperam ligadas ao runtime, com `devolver` e
a corrente de revisão; espera, decisão, sinal, prazo e freios; retomada; rotina com workflow;
protocolo, painel e telas.
