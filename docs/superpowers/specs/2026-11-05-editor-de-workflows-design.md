# Fase 10 do orquestrador: editor visual de workflows

TickTask #520, subtarefa 10 da #496. Parte da seção 7 da spec-mãe
(`2026-10-07-orquestrador-personas-design.md`), do formato e do motor da fase 9
(`2026-11-05-workflows-em-grafo-design.md`) e da referência pedida pelo Ueslei nas notas da #520
(o construtor de automação do SendPulse). O organograma do título da #520 já foi entregue na
fase 4; esta fase cuida só dos workflows. Sem rodada de perguntas: o que ficou em aberto foi
decidido aqui e está marcado como **(decisão desta fase)**.

## Para que serve

Desde a fase 9 o motor roda workflows, mas montar um é escrever JSON na pasta de dados, com ids,
ligações e `quando` digitados à mão, e descobrir o erro só quando o servidor recusa. O editor
traz isso para o desktop: uma paleta de caixas que se arrastam para o canvas, ligações puxadas de
uma caixa para outra, um painel em que se escreve o que o chefe passa para a subordinada, o que
esperar e o que ela devolve, e a validação apontando o problema na caixa enquanto se monta.

Uso que fecha a fase: no desktop, o Ueslei abre a Casa, cria o workflow "Mudança com plano" da
seção 1 da fase 9 do zero, só com mouse e teclado, sem tocar no JSON. Salva, o arquivo aparece em
`equipes/casa/workflows/mudanca-com-plano.json` com commit no git dos dados, ele inicia o
workflow pelo próprio editor e acompanha as caixas acendendo no mesmo desenho.

## Objetivos

- Editor de workflow no app desktop, dentro de Equipes, construído sobre o canvas da fase 4 (pan,
  zoom, "ajustar à tela", "+" que cria ou liga, clique na linha que desfaz, aviso com "Desfazer",
  "Organizar", painel lateral que abre e fecha, rascunho com Salvar e Descartar).
- Paleta com as onze caixas da fase 9.
- Ligações com rótulo: cada saída nomeada da caixa (as opções da decisão, as saídas da condição,
  `repetir` e `sair` do laço) é um ponto de onde se puxa a ligação, e o `quando` vem dele.
- Painel da caixa com os campos de cada tipo, saídas tipadas e inserção de referências
  `{{caixa.saida}}` só entre as que valem naquele ponto.
- Validação espelhada no núcleo do Flutter, com o erro marcado na caixa, e conferida pelos mesmos
  casos dos dois lados.
- Gravação pelo `workflow-salvar` que já existe, preservando o que o editor não conhece.

## Fora desta fase

- Editor na web ou no celular. Os dois continuam só visualizando e agindo (iniciar, decidir,
  sinalizar, cancelar), como na fase 9. O editor web segue no backlog.
- Mudanças no formato do arquivo e no motor. O editor escreve o mesmo JSON da fase 9.
- Simulação ou execução de teste de um workflow sem rodar as personas.
- Subworkflow e espera por evento de fora (continuam fora, como na fase 9).
- Edição colaborativa ou bloqueio entre dois editores abertos ao mesmo tempo; basta não
  sobrescrever sem saber (seção 6).

## Anti-objetivos

- Um segundo formato. O JSON salvo pelo editor é o mesmo que se escreve à mão, legível e
  editável depois. Nada de chaves só do editor além de `layout`.
- Perder o que foi escrito à mão: campo que o editor não conhece e texto em `@arquivo.md`
  sobrevivem a abrir e salvar.
- Validação que diverge do servidor: o editor aceitar o que o servidor recusa, ou o contrário.
- Lógica na tela. Modelo, operações e regras ficam em `cliente/lib/nucleo/`, testados; a tela só
  desenha e repassa gestos.

## 1. Onde fica

Equipes, lista "Workflows" da equipe (fase 9), ganha no desktop: "Novo workflow", "Editar" e
"Duplicar" em cada cartão, além do "Iniciar" que já existe. "Editar" troca a área de Equipes
pelo editor, com o topo mostrando o nome do workflow, a versão, "Salvar", "Descartar" e
"Fechar". No celular, os botões de edição não aparecem, pela mesma regra de "edição só no
desktop" da fase 4.

"Excluir" fica no topo do editor e usa o `workflow-excluir` da fase 9, com confirmação simples; o
servidor já recusa excluir workflow rodando ou disparado por rotina, e o erro aparece como aviso.

**Novo workflow** pede só o nome. O id sai do nome (`slugDe` da fase 4, `idLivre` se repetir) e
não muda depois, porque é o nome do arquivo e as rotinas apontam para ele **(decisão desta
fase)**. O rascunho começa com uma caixa `executar` como início, ligada a um `fim`.

**Duplicar** abre o editor com uma cópia: nome "<nome> (cópia)", id novo, versão zerada.

## 2. O canvas

O desenho é o do grafo da fase 9 (caixas com tipo, título e detalhe; linhas com o rótulo do
`quando`), agora editável. Do canvas da fase 4 vêm: pan arrastando o fundo, Ctrl + roda e pinça,
botões de zoom, "ajustar à tela", "Organizar" (o `layoutCalculado` da fase 9, por níveis a partir
do início) e o painel lateral que flutua quando a janela é estreita. Um só componente de grafo
para os dois editores, como pede a spec-mãe; como chegar a isso a partir do `CanvasDoOrganograma`
e do `CanvasDoGrafo` atuais fica com quem implementa.

- **Paleta.** Uma coluna à esquerda com as onze caixas, cada uma com ícone, nome e uma linha do
  que faz. Arrastar para o canvas cria a caixa onde soltou; clicar cria no centro da vista. As
  caixas de persona (executar, revisar, aprovar, board) e as de decisão (decisão humana,
  condição) vêm primeiro, depois as de fluxo (paralelo, junção, laço, espera, fim).
- **Pontos de saída.** Embaixo de cada caixa, um ponto por ligação que ela pode ter, com o rótulo
  do `quando`: nenhum no `fim`; um sem rótulo em executar e junção; `aprovado` em revisar e
  aprovar; um por opção na decisão humana e no board com opções; um por saída das regras mais
  `senao` na condição; `repetir` e `sair` no laço; `pronto` e, com prazo, `prazo` na espera. O
  paralelo tem um ponto só, que aceita várias ligações. A lista vem do espelho de `quandosDoNo`.
- **Ligar.** Como o "+" da fase 4: clicar num ponto livre cria a caixa seguinte abaixo e já liga
  (abrindo a paleta em forma de menu para escolher o tipo); arrastar até outra caixa liga, com o
  destino realçado. Ponto que já tem ligação (fora do paralelo) fica preenchido, e arrastar dele
  troca o destino **(decisão desta fase)**.
- **Revisar e aprovar.** Ligar uma revisão ou aprovação logo depois de um `executar` (ou de outra
  revisão do mesmo `executar`) preenche o `de` sozinho. O painel ainda deixa trocar.
- **Início.** A caixa de início tem uma marca. "Definir como início" fica no menu da caixa.
- **Selecionar e remover.** Clique seleciona e abre o painel da caixa. Delete remove a caixa
  selecionada com as ligações dela; clique na linha remove a ligação. Toda mudança mostra o aviso
  com "Desfazer", e Ctrl+Z e Ctrl+Shift+Z andam numa pilha de desfazer do rascunho **(decisão
  desta fase)**.
- **Mover.** Arrastar a caixa grava a posição no `layout` do rascunho.

## 3. O painel da caixa

Comum a todas: título, id, prazo (duração, como `30m`, `2h`, `1d`) e a lista dos erros da caixa.

| Caixa | Campos |
|---|---|
| executar | posição (lista das posições da equipe, com a persona), instrução, critério, saídas |
| revisar | `de` (lista das caixas executar), por: posição ou board |
| aprovar | `de`, por: posição ou Ueslei |
| decisão humana | pergunta, opções (lista que se reordena) |
| condição | regras em ordem: campo, operação, valor, saída |
| laço | máximo de voltas (1 a 20) e a regra do "enquanto" |
| espera | uma de: duração, horário (`HH:MM`) ou sinal (nome); prazo de espera opcional |
| board | pauta, opções opcionais |
| fim | resultado opcional |
| paralelo, junção | só os campos comuns |

**Saídas tipadas** (executar). Uma linha por saída: nome e tipo (texto, número, sim/não ou
escolha, que abre a lista de valores). As saídas implícitas (`devolutiva`, `parecer`, `sintese`,
`opcao`, `voltas`...) aparecem em cinza, só para leitura.

**Referências.** Os campos de texto (instrução, critério, pergunta, pauta) têm um botão "Inserir
valor" que lista só as referências válidas naquele ponto: os campos da entrada e as saídas das
caixas que a validação aceita como anteriores, agrupadas por caixa, com o tipo ao lado. Escolher
insere `{{caixa.saida}}` no cursor. Nas regras da condição e do laço, o campo é a mesma lista; a
operação mostra só as que servem ao tipo; o valor vira lista quando o tipo é escolha e
sim/não quando é booleano.

**Id.** Sai do título na criação (ou do tipo, `executar-2`), no formato que as referências aceitam
(`[a-z][a-z0-9-]*`). Pode ser editado: renomear troca o id nas ligações, no `inicio`, no `layout`,
nos `de` de revisões e aprovações, nos campos das regras e em toda referência `{{id.…}}` dos
textos, numa operação só do núcleo **(decisão desta fase)**.

**Textos em arquivo.** Campo que no disco é `@arquivo.md` aparece com o texto do arquivo e uma
etiqueta "em plano.md"; edita-se normalmente (seção 6 explica a gravação).

**Workflow.** Sem caixa selecionada, o painel mostra o do workflow: nome, os campos da entrada
(nome e tipo, como as saídas) e, só leitura, a versão, as rotinas que disparam este workflow e os
fluxos abertos dele.

## 4. Validação no editor

`cliente/lib/nucleo/` ganha o espelho de `validarWorkflow` (`app/src/orquestra/workflow.ts`): as
mesmas recusas da seção 3 da fase 9, com a equipe do editor para posições, persona da revisão e
membros do board. A diferença é a saída: em vez de uma lista de textos, os erros vêm presos à
caixa (ou ao workflow, quando não são de uma caixa), para o canvas marcar a caixa em vermelho e o
painel listá-los. Um contador "N problemas" no topo abre a lista; clicar num erro seleciona a
caixa e centraliza a vista nela.

Valida a cada mudança do rascunho. "Salvar" fica desligado enquanto houver erro, e o servidor
valida de novo ao gravar (o erro dele aparece como aviso, como hoje).

**Os mesmos casos dos dois lados (decisão desta fase).** Um arquivo de casos compartilhado,
`docs/workflows-casos.json`, como o `protocolo.json`: cada caso tem uma equipe mínima, um
workflow e a lista do que precisa ser recusado (`"workflow"` ou o id da caixa), vazia quando é
aceito. O `bun test` roda os casos no `validarWorkflow` e confere que cada erro esperado aparece
com `caixa <id>` (ou sem caixa, para `"workflow"`); o `flutter test` roda os mesmos casos no
espelho e confere as caixas com erro. Cada recusa da seção 3 da fase 9 tem pelo menos um caso, e
o exemplo da seção 1 dela entra como aceito. Uma recusa nova no servidor sem caso quebra o
espelho só quando alguém acrescentar o caso; por isso a regra fica escrita aqui e no `CLAUDE.md`:
mudar `validarWorkflow` exige um caso novo e o espelho.

## 5. Durante a execução

O editor abre o desenho do workflow salvo, não de um fluxo. Quando o workflow tem fluxos
abertos, o topo avisa "N execuções em andamento seguem na versão em que começaram" e lista os
fluxos. Escolher um fluxo da mesma versão do rascunho sem alterações sobrepõe ao desenho as
caixas concluídas, as ativas e o caminho percorrido da fase 9; um fluxo de outra versão abre a
vista de execução da fase 9, com o grafo da própria versão. Fora do editor, a visão de execução
da fase 9 continua a mesma na web, no desktop e no celular.

Depois de salvar, "Iniciar" no topo do editor abre o formulário de entrada da fase 9.

## 6. Gravação

O editor manda o `workflow-salvar` da fase 9 com o workflow inteiro, `layout` incluído. Nenhum
tipo novo no protocolo.

- **Sem perder o que foi escrito à mão.** O editor parte do JSON que recebeu e só troca as chaves
  que edita; campos que ele não conhece, no workflow e nas caixas, voltam como vieram. Para isso
  o servidor manda nas `definicoes` o que leu do disco depois de validar, sem descartar chaves
  desconhecidas (hoje `validarWorkflow` devolve só as conhecidas). Como fazer isso sem afrouxar
  a validação fica com quem implementa.
- **Textos em arquivo (decisão desta fase).** O servidor manda os textos já lidos dos
  `@arquivo.md` (como hoje), e o editor devolve o texto. Ao gravar, o servidor relê o JSON do
  disco: todo campo que lá era `@arquivo.md` e que chegou como texto vai para o arquivo, e o JSON
  continua com `@arquivo.md`. Texto novo fica no próprio JSON. O commit leva os dois arquivos.
- **Versão como trava (decisão desta fase).** O editor manda a `versao` em que abriu. O servidor
  recusa se a do disco for outra ("o workflow mudou desde que você abriu"), e recusa criar um
  workflow novo com id que já existe. Hoje ele sobe a versão sem conferir, o que deixaria um
  salvamento apagar uma edição à mão feita no meio.
- **Sair do rascunho.** Como no editor de equipes da fase 4: o rascunho só some quando chega a
  definição com a versão nova; erro do servidor mantém o rascunho aberto.
- **Rascunho perdido.** Fechar ou trocar de tela com o rascunho alterado pergunta se descarta.
  O rascunho não sobrevive a fechar o app **(decisão desta fase)**.

## 7. Núcleo e telas

`cliente/lib/nucleo/` (puro, testado):

- o modelo editável do workflow, com ida e volta ao JSON preservando o desconhecido;
- operações que devolvem um workflow novo: criar caixa, remover caixa (com ligações e
  `layout`), mover, ligar pelo ponto de saída (com o `quando` e o `de` automático), trocar o
  destino, desligar, definir início, renomear id, editar campos, organizar;
- os pontos de saída de cada caixa (espelho de `quandosDoNo`) e o ponto livre;
- as referências válidas em cada caixa e as operações por tipo;
- a validação espelhada, com erros por caixa;
- a pilha de desfazer.

`cliente/lib/estado/` guarda o rascunho, a seleção e o envio. `cliente/lib/tela/` desenha a
paleta, o canvas, o painel e o topo.

## 8. Testes

`bun test`:

- os casos de `docs/workflows-casos.json` contra `validarWorkflow`;
- gravar com versão diferente da do disco e criar com id existente são recusados;
- campo `@arquivo.md` editado vai para o arquivo e o JSON continua com a referência;
- campo desconhecido sobrevive a validar, mandar ao cliente e gravar de volta.

`flutter test`:

- os mesmos casos contra o espelho da validação;
- ida e volta do JSON preservando o desconhecido;
- cada operação do editor, inclusive renomear um id que aparece em referências, regras, `de`,
  `inicio` e `layout`;
- pontos de saída de cada tipo e o `de` automático ao ligar uma revisão;
- referências válidas: só caixas anteriores, e uma caixa de um caminho paralelo não aparece;
- montar o exemplo "Mudança com plano" só com operações do núcleo e chegar a um workflow igual
  ao da seção 1 da fase 9 (fora `layout` e ordem das listas), aceito pela validação.

Visual e gestos do canvas ficam para a conferência do Ueslei no desktop e para os testes com
cliques reais da #534.

## O que fica com quem implementa

Nomes internos, ícones e cores das caixas, o desenho dos pontos de saída e do realce, como
unificar os dois canvas, o formato exato do arquivo de casos e a ordem dos commits. A ordem
sugerida é: arquivo de casos e ajustes do servidor (chaves desconhecidas, `@arquivo`, versão como
trava); modelo e operações do núcleo; validação espelhada; referências; canvas editável com
paleta e pontos de saída; painel da caixa e do workflow; topo, gravação e sobreposição de fluxo.
