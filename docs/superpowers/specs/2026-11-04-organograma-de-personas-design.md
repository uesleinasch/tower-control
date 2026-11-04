# Fase 4 do orquestrador: organograma de personas

TickTask #498, subtarefa 4 da #496, que absorve a #455 (criar persona pela interface) e a #456
(excluir persona). Parte das seções 1, 7 e 10 da spec-mãe
(`2026-10-07-orquestrador-personas-design.md`) e não reabre nada dela. Sem rodada de
perguntas: o que a spec-mãe deixou em aberto foi decidido aqui e está marcado como
**(decisão desta fase)**.

## Para que serve

Até a fase 3 só existe a Casa, e as personas ainda estão fixas na interface: a web lista as
cinco no `index.html`, e o app tem `Perfil.todos` com nomes e cores no código. Ao fim desta
fase, o Ueslei cria e exclui personas pela interface, monta equipes além da Casa no app
desktop, arrastando e ligando posições num organograma, e vê esse organograma na web e no
celular. Uma posição com subordinadas pode delegar trabalho a elas.

Uso que fecha a fase: no desktop, o Ueslei cria a persona "Vera" a partir de uma descrição
curta e monta a equipe "Código", com a Nati como `tech-lead` e o Alfred como `executor`,
respondendo a ela. Ele cria uma tarefa para a `tech-lead`, a Nati delega uma subtarefa ao
`executor`, o Ueslei a libera e o Alfred executa. O organograma da Código aparece na web e no
celular.

## Objetivos

- Personas vindas do servidor em todos os clientes, sem lista fixa.
- Criar persona a partir de uma descrição base, com o `profile.md` gerado em segundo plano.
- Excluir persona com confirmação, sem perder histórico.
- Várias equipes, gravadas pelo servidor com validação e commit no git dos dados.
- Editor do organograma no desktop; visualização na web e no celular.
- Tarefas e execuções em qualquer equipe, não só na Casa.
- Delegação de uma posição para as que respondem a ela.

## Fora desta fase

- Orçamento, pausa e aprovação de plano (fase 5). O campo `orcamentoMensalUSD` continua sem
  efeito.
- Revisão por outra persona (fase 6). A entrega continua indo para o Ueslei revisar.
- Editor de workflows (fase 10). O componente de grafo daqui é a base dele, mas só desenha
  posições e "responde a".
- Editor na web e no celular. Na web, só criar e excluir persona, que é formulário e não
  grafo **(decisão desta fase)**.
- Editar o `profile.md` pela interface. Ele continua editável à mão na pasta de dados.
- Chat com persona fora da Casa. O chat direto continua usando a posição na Casa (spec-mãe).

## Anti-objetivos

- Persona trabalhar sozinha por delegação. A subtarefa delegada nasce em `backlog` e só roda
  depois que o Ueslei a passa para `a_fazer`, como a spec-mãe pede até a fase 5.
- Perder dado ao excluir: conversas, atas e memória ficam.
- Gravar definição inválida: o servidor é o juiz e recusa com os erros.

## 1. Personas como dado em todos os clientes

`persona.json` ganha o campo opcional `cor` (`#rrggbb`). Sem ele, a cor sai de uma paleta
fixa pelo hash do id, igual em todos os clientes porque quem calcula é o servidor.

Mensagem nova servidor→cliente `personas`, enviada na abertura do socket e a cada mudança:

```ts
{ tipo: "personas", lista: Array<{
  id, nome, inicial, cor,
  titulo: string | null,   // título da posição na Casa
  conversa: boolean,       // tem posição na Casa: aparece no chat
  executor: boolean,       // a posição na Casa tem "comandos"
  excluivel: boolean,
  modelo: string | null,
  gerandoPerfil: boolean,
}> }
```

A web monta a barra de personas e as iniciais a partir dela, e o `index.html` perde a lista
fixa. O app troca `Perfil.todos` por um registro preenchido por essa mensagem; `porChave`
continua existindo, com o mesmo fallback para id desconhecido. Persona sem posição na Casa
não aparece no chat **(decisão desta fase)**: ela só trabalha nas equipes em que está.

## 2. Criar persona

Cliente→servidor `persona-criar`: `{ nome, base, modelo?, cor? }`. A `base` é a descrição
livre do Ueslei (quem é, papel, jeito), com até 4.000 caracteres.

1. O id sai do nome: minúsculas, sem acento e só letras, entre 2 e 24 (`^[a-z]{2,24}$`).
   Se o id já existe, ou se é de uma persona excluída (seção 3), o servidor recusa e pede
   outro nome.
2. Grava `profiles/<id>/persona.json` e um `profile.md` provisório (`# <Nome>` e a base),
   e acrescenta à Casa a posição `conselho-<id>` com `arquivos` e `memoria`, sem `board`
   **(decisão desta fase)**: cada pauta do board chama todos os conselheiros, e entrar no
   board fica a cargo do Ueslei, pelo editor. Commit no git dos dados ("persona Vera
   criada"), recarga do elenco e `personas` para todos.
3. Em segundo plano, uma chamada ao SDK em Sonnet (`perguntarUmaVez`, com o tipo de uso
   novo `persona`) transforma a base num `profile.md` completo. Ela recebe a base e o
   `profile.md` de uma persona da Casa como exemplo de formato. O resultado substitui o
   provisório e vira um segundo commit ("perfil de Vera gerado"). Enquanto isso,
   `gerandoPerfil` fica `true`. Se falhar, o provisório fica e sai um aviso.

O projeto da persona no ai-memory nasce na primeira gravação, como hoje. A evolução da
personalidade com o tempo, que a #455 pede, já existe: a camada viva `jeito/` e o sonho
diário. Nada muda ali.

## 3. Excluir persona

Cliente→servidor `persona-excluir`: `{ id, confirmacao }`, em que `confirmacao` precisa ser
igual ao nome da persona. O cliente pede que o Ueslei digite o nome. O servidor chama
`exigirPerfilExcluivel`, e o Alfred continua protegido.

- Toda posição que ela ocupa, em qualquer equipe, fica vaga (`persona: null`). As tarefas
  dessas posições esperam, como a fase 3 já faz com posição vaga.
- Execução dela que está rodando é interrompida sem contar como falha.
- `profiles/<id>/` é apagado. O commit no git dos dados guarda tudo e permite desfazer.
- O id entra em `profiles/excluidas.json` e não pode ser reusado: o projeto dela no
  ai-memory continua intacto, e uma persona nova com o mesmo id herdaria a memória
  **(decisão desta fase)**.
- As conversas ficam e passam a ser só leitura: o servidor recusa mensagem nova em conversa
  de persona que não existe, e os clientes mostram o id no lugar do nome. Atas e decisões não
  mudam.

## 4. Várias equipes

O `Elenco` passa a carregar todas as `equipes/*/equipe.json`, e a Casa continua obrigatória.
`equipePorId` no servidor e a busca de posição do runtime passam a valer para qualquer
equipe.

A mensagem `equipes` (servidor→cliente) passa a levar todas as equipes, com os campos
completos de cada posição (`aprovacao`, `diretorio`) e o `layout`, que o editor precisa.

Cliente→servidor `equipe-salvar`: `{ equipe }`, a equipe inteira. O servidor:

1. valida com `validarEquipe` e com as regras desta fase:
   - posição removida, ou com persona trocada, não pode ter tarefa em `em_andamento`;
   - posição removida não pode ter tarefa aberta (fora de `concluida` e `cancelada`);
   - a Casa não pode ser renomeada nem ter o id trocado;
2. completa o `layout` das posições sem coordenada (seção 5);
3. grava, commita com uma mensagem que diz o que mudou ("equipe Código: +executor,
   executor responde a tech-lead"), recarrega o elenco e manda `equipes` e `personas` para
   todos.

Erros voltam como `erro`, com a lista do validador. Equipe nova é só `equipe-salvar` com um
id que ainda não existe.

Cliente→servidor `equipe-excluir`: `{ id }`. A Casa não pode ser excluída, e equipe com
tarefa aberta também não. O diretório da equipe é apagado e o commit guarda.

## 5. Layout

O desenho sempre vem do `layout` gravado. Posição sem coordenada recebe uma, calculada no
núcleo puro do servidor (`completarLayout`, em `orquestra/equipe.ts`). O algoritmo é uma
árvore por "responde a": as raízes (que respondem ao Ueslei) ficam numa linha no topo,
cada nível desce 160 px e os irmãos ficam lado a lado com 280 px entre eles, sem mexer nas
posições que já têm coordenada. Os clientes não calculam layout **(decisão desta fase)**:
uma implementação só.

## 6. Editor do organograma (app desktop)

Tela nova "Equipes", no desktop e no celular, com o mesmo componente de grafo e o modo de
edição ligado só no desktop.

**Núcleo puro** (`cliente/lib/nucleo/organograma.dart`, testado): modelo da equipe em
edição e as operações `mover`, `ligar` (define "responde a"; recusa ciclo e posição
inexistente), `soltar` (responde ao Ueslei), `adicionarPosicao` (id único), `removerPosicao`
(quem respondia a ela passa a responder ao chefe dela), `editarPosicao` e `validar`, com as
mesmas regras estruturais de `validarEquipe` contra os mesmos casos. É esse núcleo que a
fase 10 reaproveita.

**Tela:**

- Topo: seletor de equipe, "Nova equipe", "Salvar" e "Descartar". Mudança não salva fica
  marcada, e trocar de equipe com mudança pendente pede confirmação.
- Canvas com pan e zoom próprios, como no Excalidraw: arrastar o fundo move a vista, Ctrl + roda
  ou pinça dá zoom em volta do cursor, e há botões de zoom e "ajustar à tela". Cada posição é
  um cartão com título, avatar e nome da persona (ou "vaga") e as capacidades. Posição sem
  chefe é uma caixa solta, sem linha (responde ao Ueslei implicitamente); as linhas ligam cada
  cartão ao chefe.
- Arrastar o cartão o move. Arrastar o "+" de baixo de um cartão até outro faz o segundo
  responder ao primeiro, e ele desce para baixo do chefe se estiver na mesma altura ou acima.
  "Organizar" redesenha a árvore por níveis.
- Clicar num cartão abre o painel lateral: título, persona (lista das personas, mais
  "vaga"), "Responde a" (posições que não formam ciclo, ou "ninguém"), "Adicionar
  subordinada", capacidades (caixas de marcar), política de aprovação (só com `comandos`),
  diretório (só com `comandos`) e "Remover posição".
- Painel "Personas", na mesma tela: lista com cor e nome, "Nova persona" (nome, descrição
  base, modelo, cor) e "Excluir" com o campo de confirmação do nome. Persona com
  `gerandoPerfil` mostra um indicador.

Sem biblioteca de grafo **(decisão desta fase)**: são cartões numa árvore, e o
`CustomPaint` resolve com o que o Flutter já tem.

## 7. Web e celular

- **Web:** tela "Equipes" na barra lateral. Seletor de equipe e organograma em SVG próprio,
  só leitura, desenhado do `layout`, com rolagem na largura do celular. Clicar num nó mostra
  a posição (persona, capacidades e tarefas abertas, com link para elas). Na mesma tela,
  criar e excluir persona, com os mesmos campos e confirmação do desktop.
- **Celular:** a tela "Equipes" do app, sem edição. Tocar num cartão mostra os detalhes.
- **Tarefas:** as telas de tarefas da web e do app ganham o seletor de equipe, e o
  formulário de tarefa nova lista as posições da equipe escolhida.

## 8. Rodar tarefa fora da Casa

`trabalhar()` passa a montar o system prompt pela posição da tarefa, e não pela posição da
persona na Casa: `montarSystemPrompt` recebe se a posição roda comandos, em vez de perguntar
ao elenco. Assim a Nati numa posição sem `memoria` trabalha sem memória naquela equipe, e o
Alfred numa posição com `comandos` recebe as instruções de executor. Uma execução por
persona continua valendo entre equipes.

## 9. Delegação

Posição com subordinadas diretas (alguma posição da mesma equipe responde a ela) ganha a
ferramenta `delegar` no MCP `orquestra`:

```
delegar(posicao, titulo, descricao?, porque?)
```

- `posicao` precisa responder diretamente à posição da tarefa atual. Senão, a ferramenta
  devolve as subordinadas válidas.
- Cria uma subtarefa (`pai` = tarefa atual, mesma equipe, `criadaPor` = `execucao:<id>`)
  em `backlog`, com registro na tarefa-mãe ("delegou #14 a executor").
- Sai um aviso "Nati delegou #14", que abre a subtarefa. O Ueslei a passa para `a_fazer`
  quando quiser que rode.

O bloco `<tarefa>` da fase 3 ganha a lista das subordinadas da posição (id, título e
persona), quando existem, e a regra "para dividir o trabalho, use `delegar`; a subtarefa só
roda quando o Ueslei liberar".

## 10. Protocolo

Tipos novos em `docs/protocolo.json`, no `server.ts`, no `app.js` e no codec Dart:

- cliente→servidor: `personas`, `persona-criar`, `persona-excluir`, `equipe-salvar`,
  `equipe-excluir`;
- servidor→cliente: `personas`.

`equipes` já existe nas duas direções e só ganha campos.

## 11. Testes

`bun test`:

- id a partir do nome (acentos, espaços, nome curto demais, colisão, id excluído);
- criar persona grava `persona.json`, o `profile.md` provisório e a posição na Casa;
- excluir deixa as posições vagas em todas as equipes, reserva o id e recusa o Alfred;
- `completarLayout` não mexe no que tem coordenada e põe os subordinados abaixo do chefe;
- `equipe-salvar` recusa posição removida com tarefa aberta e a Casa renomeada;
- `delegar` só aceita subordinada direta e cria em `backlog`;
- o system prompt de `trabalhar()` segue a posição da tarefa;
- o teste de protocolo cobra os tipos novos.

`flutter test`: operações e validação do `organograma.dart` (ligar recusa ciclo; remover
religa os subordinados ao chefe), o registro de personas e o codec dos tipos novos.

## O que fica com quem implementa

Nomes internos, a paleta de cores, o texto do pedido de geração do `profile.md`, o desenho
exato dos cartões e das linhas, o formato da mensagem de commit e a ordem dos commits. A
ordem sugerida é: personas dinâmicas nos três clientes; criar e excluir; várias equipes e
`equipe-salvar` no servidor; tarefas por equipe e `trabalhar()` pela posição; delegação;
núcleo do organograma e editor desktop; visualização na web e no celular.
