# Fase 13 do orquestrador: modelos de equipe e de workflow

TickTask #506, subtarefa 13 da #496. Parte da spec-mãe (`2026-10-07-orquestrador-personas-design.md`):
"reaproveitar em outra equipe é por cópia (templates, fase 13)". O Ueslei dispensou a rodada de
perguntas. O que ficou em aberto foi decidido aqui e está marcado como **(decisão desta fase)**.

No código e na UI o nome é **modelo** (`modelos.ts`, "Exportar como modelo"). "Template" fica só
no título da tarefa.

## Para que serve

Hoje uma equipe montada no desktop (organograma, personas, workflows, rotinas, skills) só existe
na pasta de dados onde foi feita. Para ter outra parecida, é preciso montar tudo de novo à mão.
Para usar o mesmo workflow em outra equipe, é preciso redesenhar. O modelo é um arquivo que leva
uma equipe inteira, ou um workflow só, e que se importa de volta com conferência de colisões.
Ele serve para três coisas:

- copiar uma equipe para começar outra parecida;
- levar a organização para outra máquina;
- guardar times prontos para tipos de trabalho.

Uso que fecha a fase:

1. O Ueslei exporta a equipe "Work", com personas, workflows, rotinas e skills, num arquivo
   `work.ctmodelo.json`.
2. Ele importa esse arquivo como uma equipe nova "Work 2". A tela mostra o que entra. As personas
   que já existem são reaproveitadas, e as rotinas chegam desligadas. Ele confirma, e a equipe
   aparece no organograma com os workflows funcionando.
3. Ele exporta o workflow "initial" da Casa e o importa na equipe "Serafin". Cada posição do
   modelo é ligada a uma posição da Serafin, e o workflow aparece no editor da Serafin.

## Objetivos

- Exportar uma equipe num arquivo só, com ou sem as personas e com ou sem as rotinas.
- Exportar um workflow sozinho, para usar em outra equipe.
- Importar com prévia. O servidor diz o que entra, o que colide, o que pede atenção e o que impede
  a importação. Nada é gravado antes da confirmação.
- Resolver cada colisão por escolha, com um padrão sensato já preenchido.
- O modelo nunca leva memória, conversas, decisões, tarefas, tokens, orçamento nem caminhos da
  máquina.

## Fora desta fase

- Atualizar uma equipe que já existe a partir de um modelo, ou mesclar duas equipes. Importar
  sempre cria uma equipe nova, e a de workflow cria um workflow novo.
- Biblioteca de modelos dentro do app e modelos embutidos no pacote. Os arquivos são a
  biblioteca.
- Exportar ou importar pela web ou pelo celular. Fica só no desktop, como toda edição de equipe.
- Assinatura, origem confiável e compartilhamento online.
- Exportar uma persona sozinha, sem equipe.

## O que não pode acontecer

- Um modelo importado começar a rodar algo sozinho: rotina disparando, comando sem aprovação
  passando despercebido.
- Um modelo levar a memória de uma persona, o token de um webhook ou um caminho da máquina.
- A importação parar no meio e deixar meia equipe gravada.
- Um caminho dentro do modelo escrever fora da pasta de destino (`../`, caminho absoluto).

## O arquivo

É um JSON só, com extensão `.ctmodelo.json` **(decisão desta fase)**. Não precisa de zip nem de
dependência, dá para ler e versionar, e as skills são quase sempre texto. Limite de 5 MB.

```json
{
  "formato": "control-tower/modelo",
  "versao": 1,
  "tipo": "equipe",
  "nome": "Work",
  "exportadoEm": "2026-11-05T18:00:00.000Z",
  "equipe": { "id": "work", "nome": "Work", "posicoes": [ ... ], "layout": { ... } },
  "personas": [
    {
      "persona": { "id": "nati", "nome": "Nati", "modelo": "sonnet", "cor": "#9a6ee8", "skills": ["relatorio"] },
      "perfil": "conteúdo do profile.md",
      "ritmo": { ... },
      "skills": [ { "id": "revisao", "arquivos": { "SKILL.md": "...", "scripts/conta.sh": "..." } } ]
    }
  ],
  "skills": [ { "id": "relatorio", "arquivos": { "SKILL.md": "..." } } ],
  "workflows": [ { "workflow": { ... JSON cru, com "@plano.md" ... }, "textos": { "plano.md": "..." } } ],
  "rotinas": [ { ... rotina.json ... } ]
}
```

- `personas[].skills` são as skills próprias da persona (`profiles/<p>/skills/`). `skills` no topo
  são as da Casa que a equipe usa.
- Arquivo de skill que não é texto UTF-8 vai como `{ "base64": "..." }`.
- O workflow vai como está no disco, com as referências `@arquivo.md`, e os textos vão em
  `textos`. A importação grava os dois do mesmo jeito.
- `tipo: "workflow"` leva `workflows` com um item só e `posicoes`, uma lista de
  `{ id, titulo, capacidades }` com as posições que o workflow cita, para a prévia sugerir a
  ligação. Não leva equipe, personas, rotinas nem skills.

### O que entra na exportação da equipe

| Parte | Entra | Sai do que entra |
|---|---|---|
| Equipe | `equipe.json` | `diretorio` de cada posição (caminho da máquina) |
| Personas (opcional, ligado) | `persona.json`, `profile.md`, `ritmo.json`, skills próprias | `orcamentoMensalUSD`, `orcamentoMensalTokens`, `protegida`, `memory.md`, memória do ai-memory, conversas |
| Skills da Casa | as anexadas às posições e, com personas, às personas | `.claude-plugin/` (o servidor recria) |
| Workflows | todos da equipe, com os `@arquivo.md` | nada |
| Rotinas (opcional, ligado) | `rotinas/*.json` | token e marca (já ficam no `orquestra.db`, fora do arquivo) |

Sem personas, as posições saem vagas (`persona: null`) e as skills anexadas só às personas não vão.
Tarefas, fluxos, execuções, auditoria, decisões, board e a pasta `conversations/` nunca entram.

A Casa também pode ser exportada. Importar um modelo dela cria uma equipe comum com outro id.
Nunca substitui a Casa.

## Importação

### Prévia

O desktop lê o arquivo e manda o conteúdo para o servidor. O servidor monta um **plano** e devolve
a prévia. Toda mudança numa escolha pede outra prévia, porque a regra mora num lugar só, no servidor
**(decisão desta fase)**. O Dart só mostra e devolve as escolhas, sem espelhar a regra como no
editor de workflows.

A prévia tem:

- **Resumo**: o nome, o tipo, quando foi exportado e quantas posições, personas, workflows, rotinas
  e skills ele traz.
- **Escolhas**: as que o usuário mandou, completadas com os padrões. A prévia sempre devolve o
  conjunto inteiro, e o desktop renderiza a partir dele.
- **Avisos**: o que pede atenção, sem impedir.
- **Erros**: o que impede a importação. Com erro, o botão Importar fica desligado e o servidor
  recusa.

### Colisões e escolhas

**Equipe** (modelo de equipe). O id e o nome são editáveis. O padrão é o id do modelo ou, se ele
já existir, o primeiro livre entre `<id>-2`, `<id>-3` e assim por diante. O nome segue a mesma
regra, com " 2". Id inválido ou já existente dá erro.

**Cada persona do modelo** tem uma de quatro ações:

| Ação | Quando é o padrão | O que faz |
|---|---|---|
| `usar` | o id já existe aqui | as posições dela ficam com a persona daqui; o perfil, o ritmo e as skills próprias do modelo são ignorados |
| `criar` | o id não existe aqui e não foi de persona excluída | grava `persona.json`, `profile.md`, `ritmo.json` e as skills próprias, e põe a posição `conselho-<id>` na Casa como o `persona-criar` faz (sem `board`), com o título da posição dela na equipe importada |
| `criar` com outro nome | nunca é padrão | como `criar`, com o id tirado do nome novo (`idDoNome`); troca o id em todas as posições |
| `vaga` | o id foi de persona excluída | as posições dela ficam vagas |

`usar` também aceita outra persona daqui (`{ acao: "usar", persona: "alfred" }`). Assim a posição
"executor" do modelo pode ficar com o Alfred daqui, mesmo que lá fosse outra pessoa.

Erros nessa parte: `criar` com id que já existe ou que foi de persona excluída, e `usar` com
persona que não existe.

**Cada skill da Casa do modelo**:

- Se não existe aqui, entra com o mesmo id.
- Se existe com o mesmo conteúdo em todos os arquivos, é reaproveitada sem aparecer na prévia.
- Se existe com conteúdo diferente, o padrão é `usar` a daqui, com o aviso "conteúdo diferente"
  **(decisão desta fase)**. A outra opção é `importar` com outro id, com padrão `<id>-2`. Ela troca
  o id nas posições e nas personas que a anexam e reescreve o `name` do frontmatter.

As skills próprias de uma persona só entram com ela (`criar`) e não colidem, porque a pasta é dela.

**Modelo de workflow**:

- O destino é uma equipe que já existe, escolhida antes da prévia.
- Cada posição do modelo é ligada a uma posição da equipe de destino. O padrão é o mesmo id. Se o
  id não existir lá, vale o mesmo título. Se nada casar, fica sem ligação, e isso é erro.
- A ligação reescreve `executar.posicao`, `revisar.por.posicao` e `aprovar.por.posicao`.
- O id do workflow é editável. O padrão é o do modelo ou, se ele já existir na equipe,
  `<id>-2`. A `versao` volta para 1.
- O workflow reescrito passa pelo `validarWorkflow` contra a equipe de destino, e os erros dele
  viram erros da prévia.

### Validação do plano inteiro

Antes de devolver a prévia, o plano monta o estado que ficaria e passa tudo pelos validadores que
já existem:

- `validarPersona`, nas personas criadas;
- `validarEquipe`, na equipe nova e na Casa com as posições novas, com o conjunto final de
  personas e skills;
- `validarWorkflow`, em cada workflow contra a equipe final;
- `validarRotina`, em cada rotina;
- `lerSkillMd`, em cada `SKILL.md`.

Também confere os caminhos. Nomes de arquivo de skill:

- só segmentos `[A-Za-z0-9._-]+`;
- nenhum segmento começando com `.`;
- nada de `..` nem de caminho absoluto;
- no máximo 4 níveis e 50 arquivos por skill.

Os textos de workflow seguem o padrão de `@arquivo.md` que já existe. Qualquer falha vira erro com
o lugar dela: "workflow revisao, caixa plano: ...".

### Avisos

Os avisos ficam na prévia, sem impedir a importação **(decisão desta fase)**:

- posição com `comandos`, com a política de aprovação; `auto` aparece destacado;
- posição com `diretorio` (o exportador tira, mas um modelo feito à mão pode trazer);
- skill com arquivos além do `SKILL.md` (scripts que a persona pode rodar);
- skill da Casa com conteúdo diferente da daqui;
- rotinas, que sempre entram desligadas (`ativa: false`), com a lista de cron e webhook para
  ligar depois.

### Aplicação

`modelo-importar` refaz o plano com as escolhas recebidas, sem confiar na prévia anterior. Se o
plano tiver erro, recusa. Senão:

1. Confere que nenhum caminho novo já existe no disco. Se algum existir, alguém mexeu desde a
   prévia, e a importação recusa.
2. Grava os arquivos e as skills (com o manifesto, por `garantirManifesto`) e, por último, a Casa,
   se ela ganhou posições.
3. Recarrega o elenco, os workflows e as rotinas, como `equipe-salvar` e `workflow-salvar` já
   fazem.
4. Faz um commit só no git dos dados: "importa o modelo Work como a equipe work-2".

Se algo falhar nos passos 2 ou 3, apaga o que foi criado, devolve a Casa ao conteúdo anterior e
recarrega de novo. A falha volta como erro na tela.

## Protocolo

Três tipos de cliente para servidor, todos em "cliente→servidor" e em "cliente→servidor só no
desktop":

- `modelo-exportar { equipe, personas: bool, rotinas: bool }` exporta a equipe, e
  `{ equipe, workflow }` exporta só aquele workflow;
- `modelo-previa { conteudo, destino?, escolhas? }`, onde `conteudo` é o texto do arquivo e
  `destino` é a equipe, só para o modelo de workflow;
- `modelo-importar { conteudo, destino?, escolhas }`.

Três tipos de servidor para cliente, só para o socket que pediu:

- `modelo { nome, conteudo }`, com o nome de arquivo sugerido e o JSON do modelo;
- `modelo-previa { resumo, personasDoModelo, posicoesDoModelo, entra, escolhas, avisos, erros }`;
- `modelo-importado { equipe, workflow? }`.

O `protocolo.json` ganha a seção `"servidor→cliente só no desktop"`, e o teste da web desconta
esses tipos como já desconta os do outro sentido **(decisão desta fase)**. A web não ganha código
morto para tratar mensagem que nunca recebe. O codec Dart continua cobrindo todos os tipos.

As mensagens de mudança que já existem (`personas`, `equipes`, `skills` e as de workflows e
rotinas) vão para todos os sockets depois da importação, como em qualquer outra mudança.

## Desktop

- **Organograma**: no menu de cada equipe, "Exportar como modelo…" abre um diálogo com duas
  caixas, "Levar as personas" e "Levar as rotinas", ambas marcadas. O arquivo é salvo pelo
  `file_picker` (`saveFile`) com o nome sugerido. Ao lado de "Nova equipe" fica "Importar
  modelo…", que abre um arquivo e mostra a prévia.
- **Editor de workflows**: na lista, cada workflow ganha "Exportar como modelo…". O botão
  "Importar workflow…" importa na equipe aberta.
- **Tela da prévia**, que serve aos dois tipos:
  - cabeçalho com o resumo;
  - equipe (id e nome) ou workflow (id);
  - personas, cada uma com a ação num seletor e, em "criar com outro nome", o campo do nome;
  - skills em colisão;
  - posições, no modelo de workflow, cada uma com o seletor da posição de destino;
  - avisos em amarelo e erros em vermelho;
  - "Importar", desligado com erro.

  Cada mudança pede outra prévia. Depois de importar, a tela abre a equipe nova ou o workflow
  novo.
- O que é puro vai para `nucleo/modelos.dart`: os tipos da prévia, as escolhas e a leitura das
  mensagens. O estado vai para `estado/modelos.dart`, e as telas são casca.

## Onde fica no servidor

- `app/src/orquestra/modelos.ts`, com o núcleo puro e o adaptador separados:
  - `exportarEquipe(dados, opcoes)` e `exportarWorkflow(dados, equipe, id)` montam o modelo a
    partir do que já foi lido;
  - `lerModelo(texto)` confere formato, versão, tamanho, tipos e caminhos;
  - `planejar(modelo, atual, escolhas, destino?)` devolve
    `{ resumo, escolhas, avisos, erros, escritas, casa? }`;
  - no adaptador, `lerParaExportar(raiz, ...)` e `aplicar(raiz, plano)`, com o desfazer.
- `server.ts` trata os três tipos e publica as mudanças.
- `lerModelo` recusa `versao` maior que a conhecida, com "modelo de uma versão mais nova do
  control-tower".

## Testes

Seguem a regra do projeto: núcleo puro no `bun test`, sem testar UI.

- **Ida e volta.** Exportar a equipe de uma pasta de exemplo e importar numa pasta vazia recria os
  mesmos arquivos. Ficam de fora o que a exportação tira e as rotinas, que voltam com
  `ativa: false`.
- **O que nunca sai.** Orçamento, `protegida`, `diretorio`, `memory.md`, `.claude-plugin/` e
  conversas.
- **Padrões das escolhas.** Persona que existe vira `usar`, persona nova vira `criar`, id de
  excluída vira `vaga`. Skill igual não aparece. Skill diferente vira `usar` com aviso.
- **Renomear propaga.**
  - Persona criada com outro nome troca o id nas posições.
  - Skill importada com outro id troca nas posições, nas personas e no `name` do `SKILL.md`.
  - A ligação de posições reescreve as três referências do workflow.
- **Caminhos.** `../x`, `/etc/x`, `.git/x` e mais de 4 níveis são recusados.
- **Erro bloqueia.** `aplicar` não grava nada com erro no plano. Uma falha no meio desfaz o que foi
  criado e devolve a Casa.
- **Protocolo.** A seção nova no `protocolo.json` e o teste da web descontando os tipos só do
  desktop.
- **Flutter.** O codec cobre os tipos novos (teste que já existe) e testes do `nucleo/modelos.dart`
  leem a prévia e serializam as escolhas.

A ida e volta na máquina real é do Ueslei, pelo desktop, no uso que fecha a fase.

## Como ficou na implementação

- **Exportar.** O `modelo-exportar` não tem campo de tipo, porque ele bateria com o `tipo` da
  mensagem. Com `workflow` na mensagem sai o modelo de workflow; sem ele, sai o da equipe.
- **Prévia.** Além do que a spec previa, devolve:
  - `personasDoModelo`, uma lista de `{ id, nome, traz }`. `traz` diz se o modelo tem o perfil;
    sem ele, `criar` não é possível.
  - `posicoesDoModelo`, uma lista de `{ id, titulo }`, para a tela mostrar nomes no lugar de ids.
  - `entra`, com as linhas prontas do que será criado.

  Se o arquivo não for um modelo válido, a prévia volta com `resumo: null` e o motivo em `erros`.
- **Personas e skills que o modelo não traz.** Uma persona citada numa posição sem ter vindo no
  modelo (exportado sem personas, ou feito à mão) fica vaga se não existir aqui, e `criar` dá erro.
  Uma skill que a equipe usa e que não veio no modelo é a daqui, sem pergunta. Se ela não existir
  aqui, é erro. Só entram as skills da Casa usadas pelas posições e pelas personas criadas.
- **Versão.** O workflow que vem com a equipe também volta para a versão 1.
- **Desfazer.** `aplicar` devolve uma função que apaga o que foi criado e devolve a Casa. O
  servidor chama essa função se a recarga dos workflows ou das rotinas falhar.
- **Desktop.**
  - O organograma não tem menu por equipe, então "Exportar como modelo…" virou um ícone na barra
    de edição, ao lado da lixeira. "Importar modelo…" fica depois de "Nova equipe".
  - Na lista de workflows, cada cartão ganhou "Exportar como modelo…", e a lista ganhou
    "Importar workflow…".
  - Os arquivos Dart são `importacao.dart` (`nucleo/`, `estado/` e `tela/`), porque
    `nucleo/modelos.dart` já existia com outro conteúdo.
- **Prévias fora de ordem.** O cliente deixa uma prévia em voo por vez. Uma mudança feita enquanto
  ela espera vira um pedido novo assim que a resposta chega. Os campos de texto esperam 400 ms.
- **Escolhas na tela.** O que o usuário escolhe fica nas escolhas locais. A prévia só preenche as
  chaves que faltam, para não apagar o que está sendo digitado.
- **Teste de ponta a ponta.** Rodou num servidor isolado, sobre uma cópia da pasta de dados real:
  - a Casa foi exportada;
  - a prévia sugeriu `casa-2` com as cinco personas daqui;
  - o id `casa` foi recusado;
  - um arquivo inválido foi recusado;
  - a importação criou `casa-copia` num commit só;
  - o workflow `initial` foi exportado;
  - na Serafin, a prévia pediu a ligação da posição;
  - na cópia, o workflow entrou como `initial-2`, ligado pelo id;
  - reimportar no mesmo id foi recusado.
