# Orquestrador de personas: arquitetura (spec-mãe)

TickTask #496 (orquestrador de personas e workflows) e #497 (esta spec). Levar o Control
Tower de sala de decisões com chat a um lugar onde as personas trabalham: pegam tarefas,
executam, revisam e aprovam umas às outras, em equipes que o Ueslei monta e enxerga
visualmente, com workflows em grafo. Referência: Paperclip (github.com/paperclipai/paperclip);
o levantamento dele e a comparação estão nas notas da #496.

Esta é a spec-mãe: fixa vocabulário, entidades, armazenamento, fronteiras entre módulos e o
recorte das fases. Cada fase (subtarefas 2 a 13 da #496) ganha spec e plano próprios e não
reabre nenhuma decisão daqui. Diagrama da visão macro e das explosões:
`docs/desenhos/orquestrador-personas.excalidraw` (gerado por `gen_orquestrador_personas.py`).

Fora de escopo, por decisão: multiusuário, login, SSO e RBAC; sandboxes na nuvem; adapters
além do Claude Agent SDK (Codex, Cursor, Gemini, HTTP); editor visual na web; o TickTask como
sistema de tarefas do orquestrador.

## Decisões tomadas

- **Vocabulário:** personas, nunca agentes, no código, na UI, nas docs e nas tarefas.
- **Persona, posição e capacidade são coisas separadas.** A persona é identidade (nome, jeito,
  memória, modelo). O papel vem da posição que ela ocupa numa equipe. As capacidades (rodar
  comandos, editar arquivos, TickTask, política de aprovação) são da posição. A divisão fixa
  conselheiro/executor de `tipos.ts` deixa de existir.
- **Várias equipes.** A mesma persona pode ocupar posições em mais de uma equipe, com papel
  diferente em cada; memória e jeito continuam sendo um só.
- **Workflow pertence a uma equipe**, e cada nó aponta para uma posição dela, nunca para a
  persona. Trocar a persona de uma posição não quebra o workflow. Reaproveitar em outra
  equipe é por cópia (templates, fase 13).
- **Equipe padrão "Casa".** A migração cria a Casa espelhando o uso de hoje. O chat direto
  usa a posição da persona na Casa, o board é o conselho da Casa e persona nova entra na Casa
  numa posição de conversa.
- **Tarefas internas.** Sistema próprio; o TickTask vira espelho opcional de mão única
  (fase 12) e o orquestrador funciona sem ele.
- **Armazenamento:** definições em arquivos JSON versionados no git da pasta de dados;
  runtime (tarefas, fila, travas, execuções) em `bun:sqlite`.
- **Formato:** JSON, um arquivo por equipe e um por workflow, com o layout dos nós numa chave
  separada. Prompt longo de etapa fica num `.md` ao lado, referenciado pelo nó.
- **Telas:** o editor visual (organograma e workflows) existe só no app desktop Flutter.
  Web e celular visualizam e agem (aprovar, pedir mudança, pausar, retomar). O servidor valida
  tudo ao salvar.
- **Sem login, confiando na rede**, como hoje. Risco conhecido (seção 9); login no backlog.
- **Onde roda:** dentro do servidor atual, como módulo `app/src/orquestra/`, com o núcleo
  puro separado dos adaptadores. A fronteira permite virar processo separado se um dia doer;
  hoje não vira.
- **Motor:** só o Claude Agent SDK, com a autenticação do Claude Code da máquina.

## 1. Entidades

Os tipos abaixo fixam nomes e relações. Campos de detalhe podem crescer na spec de cada fase,
desde que não mudem o que está aqui.

```ts
type PersonaId = string            // slug: "poe", "alfred", "revisora-de-codigo"

interface Persona {                // profiles/<id>/persona.json
  id: PersonaId
  nome: string
  modelo?: string                  // padrão: MODELO_PADRAO
  protegida?: boolean              // não pode ser excluída (o Alfred nasce protegido)
  orcamentoMensalUSD?: number      // vale em todas as equipes; fase 5
}

type Capacidade = "arquivos" | "comandos" | "ticktask" | "memoria" | "board"
type PoliticaDeAprovacao = "sempre" | "sensiveis" | "auto"

interface Posicao {
  id: string                       // único dentro da equipe: "executor", "revisora"
  titulo: string
  persona: PersonaId | null        // posição vaga é permitida; tarefa para ela espera
  respondeA: string | null         // id de outra posição da mesma equipe; null = Ueslei
  capacidades: Capacidade[]
  aprovacao: PoliticaDeAprovacao   // só pesa com "comandos"
  diretorio?: string               // cwd dos comandos; padrão: pasta de dados
}

interface Equipe {                 // equipes/<id>/equipe.json
  id: string
  nome: string
  posicoes: Posicao[]
  layout: Record<string, { x: number; y: number }>   // por id de posição
}
```

A identidade continua onde já está: `profiles/<id>/profile.md` (jeito), `ritmo.json` e o
projeto da persona no ai-memory. `persona.json` só acrescenta nome, modelo, proteção e orçamento.

**Tarefa** (SQLite): `id`, `equipe`, `posicao` (o dono é a posição, a persona é resolvida
no checkout), `titulo`, `descricao`, `porque` (o objetivo que a persona recebe junto),
`pai` (tarefa-pai), `status`, `dependeDe[]`, `criadaPor` (`ueslei` ou uma execução),
`workflowExecucao?` e `etapa?` quando nasce de um workflow, comentários e entregáveis.
Status: `backlog`, `a_fazer`, `em_andamento`, `em_revisao`, `bloqueada`, `concluida`,
`cancelada`.

**Execução** (SQLite): uma rodada de uma persona sobre uma tarefa: `id`, `tarefa`,
`persona`, `posicao`, `gatilho`, `status` (`na_fila`, `rodando`, `concluida`, `falhou`,
`interrompida`, `pausada_orcamento`), `sessionId` do SDK, início, fim, resultado, log e
referência ao registro de uso.

**Workflow** (arquivo): nós, arestas e layout. **Execução de workflow** (SQLite): instância
viva com a etapa atual, as saídas de cada nó e o caminho percorrido. **Rotina** (arquivo na
equipe, fase 7): gatilho mais o que dispara. **Aprovação** (SQLite): pedido pendente com
alvo, quem pediu e quem resolveu.

## 2. Armazenamento

Na pasta de dados (`CT_DADOS`):

```
profiles/<persona>/persona.json        novo; profile.md e ritmo.json continuam
equipes/<equipe>/equipe.json           posições, capacidades, layout
equipes/<equipe>/workflows/<nome>.json grafo + layout
equipes/<equipe>/workflows/<nome>/*.md prompts longos das etapas
orquestra/orquestra.db                 bun:sqlite, fora do git
```

- O git dos dados versiona as definições e dá auditoria e rollback de configuração. Toda
  gravação de definição pelo servidor vira um commit com mensagem que diz o que mudou.
- `orquestra.db` roda em modo WAL. Transições de estado (checkout, mudança de status,
  enfileirar, concluir execução) são transações: ou acontecem inteiras ou não acontecem.
  É isso que garante dono único e retomada após queda.
- O SQLite só guarda runtime. Perder `orquestra.db` perde histórico de execução, nunca
  definição de equipe ou de workflow.
- `conversations/`, `uso.jsonl`, `decisions/`, `board/` e o ai-memory continuam iguais.

## 3. Módulo `app/src/orquestra/`

Duas camadas, na mesma linha de `app/src/memoria/`:

- **Núcleo puro:** tipos, validação de equipe e de workflow, máquina de estados da tarefa,
  da execução e do workflow, regras da execution policy e resolução de capacidades para as
  opções do SDK. Sem disco, sem SQLite, sem SDK. É o que os testes cobrem.
- **Adaptadores:** repositório SQLite, leitura e gravação das definições (com o commit no git
  dos dados), chamada ao SDK, ponte com avisos e WebSocket.

O resto do servidor fala com o orquestrador por uma interface pequena (criar tarefa, agir
sobre aprovação, pausar ou retomar, ler estado, assinar eventos). O orquestrador usa o que já
existe: `sessions.ts` para chamar o SDK, `uso.ts` para registrar custo, `memoria/` para o
brief e as ferramentas da persona, `avisos/` para notificar.

## 4. Runtime

**Fila de acordar.** Atribuição de tarefa, mensagem na tarefa, aprovação resolvida, fim de
dependência e timer de rotina enfileiram um "acordar" para a posição. Pedidos para a mesma
tarefa ainda não atendidos se juntam num só.

**Antes de rodar:** checa o orçamento da persona (e, na fase 5, do workflow); resolve a
persona da posição (vaga = espera); faz o checkout atômico da tarefa (`a_fazer` para
`em_andamento` com a execução como dona; se outra execução já é dona, não roda).

**Rodar:** monta as opções do SDK a partir das capacidades da posição e chama
`sessions.ts`. Uma sessão do SDK por par (tarefa, persona), retomada com `resume` nos
acordares seguintes. A mensagem leva a tarefa, o "porquê", a cadeia de tarefas-pai e as
ferramentas do orquestrador (comentar, entregar, pedir revisão, criar subtarefa). O uso vai
para `uso.jsonl` com um tipo novo (`tarefa`) e o id da execução.

**Concorrência:** no máximo uma execução por persona ao mesmo tempo, e um limite global
configurável (padrão 2), para não disputar a máquina nem a conta.

**Queda e restart:** na subida, execução `rodando` vira `interrompida` e a tarefa volta para
a fila com o contador de tentativas. Duas interrupções seguidas param a tarefa em
`bloqueada` e geram aviso pedindo ação do Ueslei.

**Invariantes de `sessions.ts` que continuam valendo:** `settingSources: []`,
`env: ambienteDoClaude()`, `tools` limitando as nativas, `allowedTools` como lista de
auto-aprovadas (nunca com `Bash`), hook `PreToolUse` com precedência sobre `canUseTool` e
prompt em streaming quando há comandos. Nada que muda por execução vai no system prompt, que
o Claude Code congela no resume: vai na mensagem, como o brief de memória hoje.

## 5. Capacidades e aprovação

Cada capacidade da posição vira opções do SDK no núcleo puro:

- `arquivos`: Read, Write, Edit, Grep e Glob nativas, auto-aprovadas.
- `comandos`: Bash nas nativas e o hook de aprovação. A política decide: `sempre` pede
  aprovação a cada comando; `sensiveis` pede só o que `exigeAprovacaoSempre` (`comandos.ts`)
  marca; `auto` libera, mas comando sensível ainda pede, como no modo auto de hoje. Sem
  ninguém para aprovar, o comando é negado, como hoje.
- `ticktask`: o MCP do TickTask. No chat direto, o foco continua sendo ligado e desligado
  por conversa; a capacidade só diz se a posição pode ligá-lo.
- `memoria`: o MCP `memoria` da persona e o brief no começo da mensagem. A memória é da
  persona, não da posição: o que ela aprende numa equipe vale nas outras.
- `board`: a posição participa do board da equipe.

A aprovação de comando do Alfred no chat passa a ser um caso desse mecanismo: a posição dele
na Casa tem `comandos` com a política escolhida. O modo auto por conversa e a troca para
`MODELO_DO_AUTO` continuam como hoje no chat direto.

## 6. Workflows e execution policy

**Arquivo** (`equipes/<equipe>/workflows/<nome>.json`):

```json
{
  "id": "codigo-com-revisao",
  "nome": "Código com revisão",
  "versao": 1,
  "nos": [
    { "id": "n1", "tipo": "executar", "posicao": "executor", "prompt": "n1.md",
      "saidas": { "entrega": "texto" } },
    { "id": "n2", "tipo": "revisar", "posicao": "revisora", "de": "n1" },
    { "id": "n3", "tipo": "aprovar", "posicao": null }
  ],
  "arestas": [
    { "de": "n1", "para": "n2" },
    { "de": "n2", "para": "n3", "quando": "aprovado" },
    { "de": "n2", "para": "n1", "quando": "mudanca" }
  ],
  "layout": { "n1": { "x": 0, "y": 0 }, "n2": { "x": 320, "y": 0 }, "n3": { "x": 640, "y": 0 } }
}
```

`posicao: null` num nó de aprovação é o Ueslei. A versão sobe a cada gravação; uma execução
de workflow em andamento continua na versão em que começou.

**Execution policy (fase 6, linear):** o runtime intercepta o "concluí" da executora e manda
a tarefa para `em_revisao` com a revisora, depois para o aprovador. Pedido de mudança volta
à executora original e, refeito, retorna à mesma revisora, não ao início. A executora nunca
revisa o próprio trabalho: o servidor recusa um workflow em que executar e revisar o mesmo
trabalho caem na mesma persona. Cada decisão vira registro na tarefa. O board da equipe é um
tipo de revisão (pareceres e síntese).

**Grafo (fase 9):** acrescenta os nós `decisao_humana`, `condicao`, `paralelo`, `juncao`,
`laco` (com limite de voltas obrigatório), `espera` (evento ou prazo) e `board`. Saídas
tipadas de um nó alimentam as entradas dos seguintes.

**Validação** (núcleo puro, igual no servidor e no editor desktop): toda aresta liga nós
existentes, tipos de saída e entrada batem, todo nó é alcançável a partir do início, ciclo só
existe dentro de `laco`, toda posição citada existe na equipe e tem as capacidades que o
tipo de nó exige. O servidor recusa gravar um workflow inválido e devolve os erros por nó.

## 7. Telas e protocolo

- **App desktop (Flutter):** editor do organograma (fase 4) e dos workflows (fase 10). Um
  único componente de grafo, com o modelo e as regras em `cliente/lib/nucleo/`, testado com
  `flutter test`, e a tela só desenhando. O desktop grava pelo WebSocket; o servidor valida e
  commita.
- **Web e celular:** visualizam organograma, tarefas, execuções e workflows (com a etapa
  atual) e agem: aprovar, pedir mudança, pausar, retomar. Na web, o desenho é SVG próprio,
  sem biblioteca, só leitura.
- **Protocolo:** cada fase acrescenta seus tipos em `docs/protocolo.json` e nos três clientes,
  como hoje (o `bun test` e o `flutter test` cobram). Os tipos de aviso novos (aprovação de
  tarefa, tarefa bloqueada, orçamento estourado) ficam em `app/src/avisos/`, fora do
  `server.ts`.

## 8. Migração

Na primeira subida com o orquestrador (fase 2), uma vez só, marcada no `.control-tower`:

- Para cada perfil de hoje, cria `profiles/<id>/persona.json` (o Alfred com
  `protegida: true`). `profile.md`, `ritmo.json`, conversas e projetos no ai-memory não mudam
  de lugar nem de id.
- Cria `equipes/casa/equipe.json`: posição `conselho-<id>` para Poe, Nati, Lucas e Pami, com
  `arquivos`, `memoria` e `board`; posição `executor` para o Alfred, com `arquivos` e
  `comandos` na política `sempre`, mais `ticktask`.
- O tipo `Perfil` deixa de ser união fixa e vira `PersonaId` validado contra
  `profiles/*/persona.json`. `ehConselheiro` dá lugar à pergunta "a posição tem a capacidade
  X?". `idValido`/`exigirId` continuam valendo para o id de persona, que vira caminho.
- O chat direto, o board, a consolidação, o sonho e o foco TickTask seguem funcionando como
  hoje, agora lendo as capacidades da posição na Casa.

## 9. Segurança

O servidor não tem autenticação. Hoje qualquer aparelho na rede local ou na Tailscale que
abre a página pode, por exemplo, ligar o modo auto do Alfred. Com o orquestrador, o mesmo
aparelho pode editar uma equipe e dar `comandos` com política `auto` a uma posição. É um
risco aceito por decisão, com o login registrado no backlog. O que continua valendo:
comando sensível sempre pede aprovação, sem ninguém para aprovar o comando é negado, e
toda alteração de definição vira commit no git dos dados, que mostra o que mudou e permite
desfazer.

## 10. Recorte das fases

Cada fase passa por spec, plano e implementação e termina em algo que o Ueslei usa.

1. **Spec de arquitetura** (esta).
2. **Fundação: personas como dados, equipe Casa e tarefas internas.** Migração da seção 8,
   `orquestra.db` e tarefas com dono único. Inclui a base de equipes que hoje estava na
   fase 4, porque tarefa pertence a uma posição. Uso: criar tarefa para uma posição e
   acompanhar status e comentários.
3. **Runtime.** Fila de acordar, execuções rastreadas, retomada após queda. Uso: tarefa
   atribuída ao Alfred na Casa é executada sozinha, com log e custo à vista.
4. **Organograma de personas.** Várias equipes, criar e excluir persona (#455, #456),
   "responde a", delegação, e o componente de grafo do desktop estreando como editor do
   organograma. Uso: montar a equipe "Código" e ver o organograma na web e no celular.
5. **Governança.** Orçamento com aviso e parada, pausar e retomar, aprovação de plano,
   trilha de auditoria. Uso: limite mensal por persona funcionando.
6. **Execution policy linear.** Executar, revisar, aprovar, com o board como revisão. Uso: o
   fluxo Alfred executa, Nati revisa, Ueslei aprova.
7. **Rotinas e gatilhos.** Cron, webhook, API, com concorrência e catch-up; a agenda de
   memória vira uma rotina. Uso: uma rotina diária real.
8. **Painel.** Execuções ao vivo, aprovações pendentes, gasto do mês, atenção necessária.
9. **Workflows em grafo.** Motor com os nós da seção 6 e retomada exata.
10. **Editor visual de workflows** no desktop, reusando o componente da fase 4.
11. **Skills por persona.**
12. **Adaptador do TickTask** (espelho de mão única).
13. **Templates** de equipe e workflow.

## 11. Testes

Seguem a regra do projeto: núcleo puro, não UI. No servidor (`bun test`): validação de
equipe e de workflow, máquinas de estado, execution policy (mudança volta à mesma revisora,
executora não revisa o próprio trabalho), resolução de capacidades para as opções do SDK
(nenhuma combinação põe `Bash` em `allowedTools`) e a migração sobre uma pasta de dados de
exemplo. No Flutter (`flutter test`): o modelo do grafo e as mesmas regras de validação do
servidor, contra os mesmos casos. O protocolo continua coberto pelos testes que já existem.

## Riscos

- **Escopo.** O Paperclip é mantido por um time. Mitigação: cada fase termina em uso real, e
  nenhuma fase começa antes da anterior estar em uso.
- **Remover o tipo fixo `Perfil`** toca servidor, prompt, memória, board e os três clientes.
  Mitigação: a fase 2 faz isso sozinha, antes de qualquer comportamento novo, com o chat
  funcionando igual ao fim.
- **Custo de execução autônoma.** Persona acordando sozinha gasta sem ninguém olhando. O
  limite de concorrência entra na fase 3, o orçamento por persona na fase 5 e, até lá, toda
  tarefa é criada à mão pelo Ueslei.
- **Duas validações de workflow** (Dart e TypeScript). Mitigação: o servidor é o juiz, e os
  dois lados rodam o mesmo conjunto de casos.
