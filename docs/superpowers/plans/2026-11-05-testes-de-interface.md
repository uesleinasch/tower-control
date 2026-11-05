# Testes de interface com cliques reais: plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para implementar este plano tarefa a tarefa. Os passos usam caixas (`- [ ]`) para acompanhar o andamento.

**Objetivo:** um comando, rodado quando o Ueslei pedir, que sobe um ambiente isolado e clica na web, no app desktop e no celular dele, cobrindo as 12 cenas da spec.

**Arquitetura:** o ambiente tem três partes, todas em portas livres e numa pasta temporária:
- o servidor do control-tower de verdade;
- um modelo falso, que fala a API de mensagens da Anthropic com respostas de roteiro;
- um TickTask falso, que é um servidor MCP HTTP.

Quem clica muda por plataforma: o Playwright na web, o `integration_test` do Flutter no desktop (sob `xvfb-run`) e o mesmo `integration_test` no aparelho, num pacote separado. As cenas que envolvem dois clientes se sincronizam por pontos de encontro na rota de controle do modelo falso.

**Tecnologia:**
- Bun e TypeScript nos falsos e no ambiente;
- `@modelcontextprotocol/sdk` (já é dependência) no TickTask falso;
- `@playwright/test` pelo Node, num pacote próprio;
- `integration_test` do SDK do Flutter;
- `xvfb-run` e `adb`.

**Spec:** `docs/superpowers/specs/2026-11-05-testes-de-interface-design.md`

## Restrições globais

- **Português brasileiro** em identificadores, mensagens, nomes de cena e docs.
- **Comentários:** só quando forem extremamente necessários. Nada de comentário narrativo.
- **Commits:** granulares, com prefixo da área (`interface:`, `servidor:`, `celular:`, `docs:`) e **sem** trailer de coautoria de IA.
- **Isolamento.** Nada pode encostar em:
  - `~/.local/share/control-tower`;
  - o `ai-memory` em `127.0.0.1:49374`;
  - `~/.config/ticktask`;
  - `~/.claude`;
  - o app `dev.ueslei.controltower` no aparelho;
  - o `adb reverse` que já existe.
- **Variáveis do servidor de teste:** ele recebe `CT_DADOS`, `TOWER_PORTA`, `CT_TICKTASK_CONFIG`, `CT_MEMORIA_URL` (uma porta morta), `CLAUDE_CONFIG_DIR`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY=sk-falsa` e `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.
- **Celular:** o pacote de teste é `dev.ueslei.controltower.teste`, com o rótulo "Control Tower teste". Ele é desinstalado ao terminar. Sem aparelho conectado e desbloqueado, os passos do celular aparecem como **pulados**, e não como falha.
- **Tempo:** nenhuma espera de tempo fixo decide um teste. As esperas são por condição e têm prazo.
- **"Já viu dar errado":** toda cena tem uma sabotagem registrada em `docs/testes-de-interface.md`, com a função quebrada, a data e a saída vermelha. Teste que nunca falhou não entra.
- **Modelo falso:** um pedido sem regra que case é erro da cena, e o falso nunca inventa resposta.
- **O comando** é `bash scripts/testes-de-interface.sh [web|desktop|celular|conjuntas] [cena]`, e só roda quando o Ueslei pede: nada de build local nem CI.

## Pontos de revisão

1. **App desktop sob o xvfb tropeçando na bandeja.** O `tray_manager` e o `window_manager` podem falhar sem bandeja do sistema. O app de teste precisa subir sem bandeja, e a falha dela não pode derrubar a cena. Fica coberto pelo teste de fumaça do desktop na Tarefa 5.
2. **Chamada do modelo em segundo plano sem regra.** A geração de perfil, a consolidação e o sonho chegam fora da hora e fazem a cena seguinte falhar com um "pedido sem regra" que não é dela. A Tarefa 3 trata isso com o registro por cena e a regra de fundo, com teste.
3. **Prévia ou estado velho na tela depois do clique.** A cena confere o efeito no disco ou no servidor antes de declarar sucesso, e nunca só o widget. Isso vale para todas as cenas e é conferido na revisão de cada tarefa de cena.
4. **Aparelho bloqueado ou com permissão de notificação pendente.** O diálogo do sistema trava o `integration_test`. A Tarefa 7 concede a permissão por `adb shell pm grant` antes de rodar e confere a tela desbloqueada, com teste no script.
5. **Porta ocupada ou ambiente que não desce.** Uma rodada interrompida não pode deixar servidor vivo nem `adb reverse` órfão. A Tarefa 8 instala um `trap` que encerra pelo pid guardado (nunca `pkill -f`) e remove só a porta acrescentada, com teste.

---

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/interface/falsos/roteiro.ts` | Núcleo puro: tipos do roteiro, casamento das regras com um pedido e montagem do stream SSE |
| `app/interface/falsos/modelo.ts` | O servidor HTTP do modelo falso (API e `/_controle`) |
| `app/interface/falsos/ticktask.ts` | O servidor MCP HTTP do TickTask falso, com rotas de controle |
| `app/interface/ambiente.ts` | Sobe e derruba o ambiente inteiro e grava `ambiente.json` |
| `app/interface/subir.ts` | CLI: `bun run interface/subir.ts <pasta>` sobe, imprime o JSON e fica vivo até o SIGTERM |
| `app/interface/fumaca.ts` | Fumaça do ambiente: a aprovação do Alfred pelo WebSocket (o teste de viabilidade, agora permanente) |
| `app/src/sessao-sdk.ts` | Passa a respeitar o `CLAUDE_CONFIG_DIR` |
| `app/src/nucleo.test.ts` | Testes do roteiro, do stream, do TickTask falso e do `CLAUDE_CONFIG_DIR` |
| `app/interface/web/` | Pacote Node do Playwright: `package.json`, `playwright.config.ts`, `apoio.ts` e `cenas/*.spec.ts` |
| `cliente/integration_test/apoio/` | O ambiente lido do `--dart-define`, a subida do app, o seletor de arquivos falso, o encontro e as esperas |
| `cliente/integration_test/desktop_test.dart` | As cenas do desktop |
| `cliente/integration_test/celular_test.dart` | Os passos do celular |
| `cliente/lib/sistema/arquivos.dart` | O ponto onde o teste troca o `FilePicker` (abrir e salvar) |
| `cliente/android/app/build.gradle.kts` | O sufixo `.teste` e o rótulo quando `CT_APP_TESTE=1` |
| `scripts/testes-de-interface.sh` | O comando: as etapas, o `trap`, o celular e o relatório |
| `docs/testes-de-interface.md` | As cenas, o que cada uma prova e o registro das sabotagens |

---

### Tarefa 1: Modelo falso

**Arquivos:**
- Criar `app/interface/falsos/roteiro.ts`.
- Criar `app/interface/falsos/modelo.ts`.
- Testes em `app/src/nucleo.test.ts`, num `describe("modelo falso")` novo.

**Interfaces:**

Produz, em `roteiro.ts`:

```ts
export type Bloco = { texto: string } | { ferramenta: string; entrada: Record<string, unknown> }
export interface Regra {
  nome: string
  quando: { sistema?: string; mensagem?: string; resultadoDe?: string; temFerramenta?: string }
  responde: Bloco[]
  vezes?: number
  fundo?: boolean
}
export interface PedidoRecebido {
  em: string
  modelo: string
  sistema: string
  ultimaMensagem: string
  resultadoDe: string | null
  ferramentas: string[]
  corpo: unknown
}
export function lerPedido(corpo: unknown): PedidoRecebido
export function casar(regras: Regra[], usadas: Map<string, number>, pedido: PedidoRecebido): Regra | null
export function sseDaResposta(blocos: Bloco[], modelo: string): string
export function respostaJson(blocos: Bloco[], modelo: string): Record<string, unknown>
```

Produz, em `modelo.ts`:

```ts
export function servirModeloFalso(porta?: number): { porta: number; fechar(): void }
```

Rotas do `modelo.ts`:
- `POST /v1/messages` e `POST /v1/messages/count_tokens`;
- `POST /_controle/roteiro`, com corpo `{ cena: string; regras: Regra[] }`, que substitui as regras da cena e zera o uso;
- `GET /_controle/pedidos?cena=` e `GET /_controle/sem-regra`;
- `POST /_controle/encontro`, com corpo `{ nome: string; lado: string; lados: string[] }`. Responde quando todos os `lados` chegaram, com prazo de 90 s e 408 ao estourar.

Regras de casamento:
- **Campos de `quando`.** Cada campo é um texto contido: `sistema` no system prompt, `mensagem` no último texto do usuário, `resultadoDe` no nome da ferramenta do último `tool_result` e `temFerramenta` na lista de ferramentas. Todos os presentes precisam casar.
- **Ordem.** Vence a primeira regra, na ordem do roteiro, que case e ainda tenha uso. `vezes` vale 1 por padrão, e `fundo: true` não tem limite.
- **Sem regra.** O pedido vai para `sem-regra` e recebe 500 com `{"error":{"type":"api_error","message":"sem regra no roteiro"}}`.

- [ ] **Passo 1: escrever os testes que falham**

  `describe("modelo falso")`:
  - `"casa pela persona e pela mensagem e consome a regra"`: duas regras, uma com `sistema: "Você é Nati"` e outra com `mensagem: "relatório"`. O pedido da Nati casa com a primeira. Um segundo pedido igual não casa mais (`vezes` 1) e devolve `null`.
  - `"resultadoDe casa o tool_result da ferramenta"`: o corpo tem a última mensagem com `tool_result` de `toolu_1`, e o `assistant` anterior tem `tool_use` `Bash` com o id `toolu_1`. `lerPedido(corpo).resultadoDe` é `"Bash"`, e a regra com `resultadoDe: "Bash"` casa.
  - `"regra de fundo não se esgota"`: a mesma regra com `fundo: true` casa três vezes.
  - `"sse de ferramenta tem tool_use com input_json_delta e stop_reason tool_use"`: o texto de `sseDaResposta([{ ferramenta: "Bash", entrada: { command: "echo a" } }], "m")` contém `"type":"tool_use"`, `"name":"Bash"`, `"partial_json":"{\"command\":\"echo a\"}"` e `"stop_reason":"tool_use"`.
  - `"sse de texto termina em end_turn"`: contém `"text_delta"` com o texto e `"stop_reason":"end_turn"`.
  - `"servidor responde 500 e registra pedido sem regra"`: sobe com `servirModeloFalso(0)` e faz `fetch` de um `/v1/messages` sem roteiro. O status é 500, e `GET /_controle/sem-regra` traz um pedido.
  - `"encontro libera quando os dois lados chegam"`: dois `fetch` concorrentes a `/_controle/encontro`, com os lados `web` e `desktop`, resolvem os dois com 200.

- [ ] **Passo 2:** rodar `cd app && bun test -t "modelo falso"`. Esperado: FALHA, porque o módulo não existe.
- [ ] **Passo 3: implementar `roteiro.ts` e `modelo.ts`.** O `sseDaResposta` segue a sequência do teste de viabilidade:
  - `message_start`;
  - para cada bloco, `content_block_start`, `delta` e `stop`;
  - `message_delta`, com `stop_reason` `tool_use` se houver ferramenta e `end_turn` se não houver;
  - `message_stop`.

  Os ids das ferramentas saem de um contador por processo (`toolu_falso_N`).
- [ ] **Passo 4:** rodar `cd app && bun test -t "modelo falso"`. Esperado: PASSA.
- [ ] **Passo 5:** `git commit -m "interface: modelo falso que fala a API de mensagens com respostas de roteiro, registro de pedidos e pontos de encontro"`.

### Tarefa 2: TickTask falso

**Arquivos:**
- Criar `app/interface/falsos/ticktask.ts`.
- Testes em `app/src/nucleo.test.ts`, no `describe("ticktask falso")`.

**Interfaces:**

Produz:

```ts
export function servirTickTaskFalso(porta?: number, token?: string): { porta: number; token: string; fechar(): void }
```

O servidor:
- **MCP Streamable HTTP em `/mcp`.** Exige o `Bearer` do token e expõe `create_task`, `update_task`, `write_notes`, `get_task` e `server_info`. As respostas seguem o formato que `espelho.ts` lê: `create_task` devolve `{ created: { id } }`, e `get_task` devolve `{ task: { id, name, status, parent_task_id } }`.
- **Controle.** `GET /_controle/tarefas` e `POST /_controle/finalizar/<id>`, que faz o papel do Ueslei finalizando lá.

- [ ] **Passo 1: escrever o teste que falha.** O teste se chama `"o espelho cria, lê e finaliza no ticktask falso"`. Ele usa `conectarTickTask({ url: "http://127.0.0.1:<porta>/mcp", token })` de `orquestra/espelho.ts`, chama `create_task` com `{ name: "x", status: "proximas" }` e depois `get_task` com o id devolvido. O status lido é `"proximas"`. Depois de `POST /_controle/finalizar/<id>`, o `get_task` devolve `"finalizada"`. Com o token errado, a conexão falha.
- [ ] **Passo 2:** rodar `bun test -t "ticktask falso"`. Esperado: FALHA.
- [ ] **Passo 3: implementar** com `McpServer` e `StreamableHTTPServerTransport` do `@modelcontextprotocol/sdk`, sobre `node:http`, com as tarefas num `Map` em memória.
- [ ] **Passo 4:** rodar `bun test -t "ticktask falso"`. Esperado: PASSA.
- [ ] **Passo 5:** `git commit -m "interface: TickTask falso por MCP HTTP com as ferramentas que o espelho usa e rotas para finalizar como o Ueslei"`.

### Tarefa 3: Ambiente isolado e fumaça

**Arquivos:**
- Criar `app/interface/ambiente.ts`, `app/interface/subir.ts` e `app/interface/fumaca.ts`.
- Mudar `app/src/sessao-sdk.ts`.
- Testes em `app/src/nucleo.test.ts`.

**Interfaces:**

Consome as Tarefas 1 e 2. Produz:

```ts
export interface Ambiente {
  pasta: string
  dados: string
  servidor: string
  porta: number
  modelo: string
  ticktask: string
  log: { servidor: string }
  encerrar(): Promise<void>
}
export async function subirAmbiente(pasta: string): Promise<Ambiente>
```

`subir.ts` grava `<pasta>/ambiente.json`, com `{ dados, servidor, porta, modelo, ticktask, logServidor, pid }`, e mantém o processo vivo até o SIGTERM. Esse arquivo é o que o Playwright, o Flutter e o script leem.

`sessao-sdk.ts`: a pasta base passa a ser `process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), ".claude")`.

- [ ] **Passo 1: escrever os testes que falham.**
  - `"pasta da sessão do SDK respeita CLAUDE_CONFIG_DIR"`: com `process.env.CLAUDE_CONFIG_DIR = "/tmp/x"`, a função de caminho de `sessao-sdk.ts` devolve um caminho que começa com `/tmp/x/projects/`. Sem a variável, ele começa com `~/.claude/projects/`.
  - `"modelo falso: chamada de fundo casa a regra de fundo da cena"`: um roteiro com `fundo: true` e `sistema: "consolid"` responde a três pedidos de consolidação seguidos.
- [ ] **Passo 2:** rodar `bun test -t "CLAUDE_CONFIG_DIR|fundo"`. Esperado: FALHA.
- [ ] **Passo 3: implementar `sessao-sdk.ts` e `ambiente.ts`.**
  - O `subirAmbiente` cria `dados/`, `claude/` e `ticktask.json` (`{ enabled: true, port, token }`) dentro da pasta.
  - Depois sobe os dois falsos e faz o `Bun.spawn` de `bun run src/server.ts` com as variáveis das restrições globais.
  - A porta de `CT_MEMORIA_URL` é obtida abrindo e fechando um socket.
  - Ele espera o `GET /enderecos` responder (prazo de 30 s).
  - O `encerrar` mata pelo pid e apaga a pasta.
- [ ] **Passo 4: implementar `fumaca.ts`.** Ele sobe o ambiente e carrega um roteiro com duas regras:
  - `sistema: "Alfred"` e `temFerramenta: "Bash"` respondem com `Bash` `echo fumaca > <pasta>/fumaca.txt`;
  - `resultadoDe: "Bash"` responde com o texto `"feito"`.

  Depois manda `nova` para `alfred` pelo WebSocket e aprova a `permissao`. Ele confere que `fumaca.txt` contém `fumaca` e que `GET /_controle/sem-regra` está vazio, e então encerra. A saída do processo é 0 se passou e 1 se falhou.
- [ ] **Passo 5:** rodar `bun test` (tudo verde) e `bun run interface/fumaca.ts`. Esperado: `fumaça ok` e saída 0. Conferir que `~/.claude/projects` não ganhou nenhuma pasta nova (`ls -t ~/.claude/projects | head -3` antes e depois).
- [ ] **Passo 6: sabotagem.** Em `hookDeComando` (`sessions.ts`), trocar a resposta para allow sem perguntar e rodar `fumaca.ts`. Esperado: FALHA, porque nenhuma `permissao` chega. Reverter o código e anotar o resultado para a Tarefa 8.
- [ ] **Passo 7:** `git commit -m "interface: ambiente isolado com servidor, modelo e TickTask falsos, fumaça da aprovação do Alfred e sessão do SDK respeitando CLAUDE_CONFIG_DIR"`.

### Tarefa 4: Web (Playwright): cenas 1, 4, 5 e 6

**Arquivos:**
- Criar `app/interface/web/package.json`, com `@playwright/test` fixado e o script `"cenas": "playwright test"`.
- Criar `app/interface/web/playwright.config.ts`, com Chromium sem janela, `screenshot: "only-on-failure"`, `retries: 0`, `workers: 1` e o reporter `list`.
- Criar `app/interface/web/apoio.ts` e `app/interface/web/cenas/{chat,tarefas,governanca,revisao}.spec.ts`.
- Mudar o `.gitignore` da raiz: `app/interface/web/node_modules/` e `test-results/`.

**Interfaces:**

Consome o `ambiente.json`, pelo caminho em `CT_AMBIENTE`, e as rotas `/_controle/*` da Tarefa 1. Produz, em `apoio.ts`:

```ts
export function ambiente(): { servidor: string; modelo: string; dados: string; porta: number }
export async function roteiro(cena: string, regras: Regra[]): Promise<void>
export async function pedidos(cena: string): Promise<PedidoRecebido[]>
export async function semRegra(): Promise<PedidoRecebido[]>
export async function encontro(nome: string, lado: string, lados: string[]): Promise<void>
export async function esperarArquivo(caminho: string, contendo?: string, prazoMs?: number): Promise<string>
export async function ws(): Promise<{ mandar(m: object): void; esperar(tipo: string, filtro?: (m: any) => boolean): Promise<any>; fechar(): void }>
```

Os tipos `Regra` e `PedidoRecebido` vêm de `../falsos/roteiro.ts`, como `import type`. Todo `test.afterEach` confere que `semRegra()` está vazio.

- [ ] **Passo 1: escrever as cenas.** Cada teste nomeia a cena da spec:
  - `chat.spec.ts`, **"cena 1: mensagem para a Nati vira balões e fica gravada"**: o roteiro responde com o texto `"um\n\n---\n\ndois"`. Clica na Nati, digita e envia. Espera os dois balões, com os textos `um` e `dois`, e confere que `dados/conversations/*-nati-*.jsonl` contém `dois`.
  - `chat.spec.ts`, **"cena 1: anexo chega ao modelo"**: anexa `nota.txt` pelo `setInputFiles` e envia. O último pedido da cena tem, no `ultimaMensagem`, o caminho do anexo em `conversations/anexos/`.
  - `tarefas.spec.ts`, **"cena 4: tarefa criada na web volta em revisão com a entrega, e o comentário devolve"**:
    1. O roteiro responde o Alfred com o texto `"entrega 1"`, `"entrega 2"` em seguida e uma regra de fundo para a consolidação.
    2. A cena cria a tarefa para a posição `executor` pela tela.
    3. Ela espera o status "em revisão" na tela e a entrega `entrega 1`.
    4. Ela comenta "refaça", espera de novo "em revisão" com `entrega 2` e confere, no pedido que o falso recebeu, que o bloco `<tarefa>` traz `refaça`.
  - `governanca.spec.ts`, **"cena 5: orçamento estourado segura a fila e o painel diz por quê"**:
    - Antes de subir, `persona.json` do Alfred recebe `orcamentoMensalUSD: 0.000001` e `uso.jsonl` ganha um registro de tarefa de US$ 0,01.
    - A tarefa criada fica na fila, e o painel mostra o motivo de orçamento.
    - Nenhum pedido do Alfred chega ao falso.
  - `governanca.spec.ts`, **"cena 5: pausar e retomar pelo painel"**: pausa a persona e confere a tarefa parada sem pedido novo. Depois retoma e espera o pedido chegar.
  - `governanca.spec.ts`, **"cena 5: plano aprovado chega na execução seguinte"**:
    - A posição tem `aprovarPlano: true` (escrito no `equipe.json` pela semeadura).
    - O roteiro dá o plano `"plano X"` e depois a entrega.
    - Na tela, o plano aparece e a cena clica em "Aprovar plano".
    - O pedido seguinte do Alfred contém `plano X` no `<tarefa>`.
  - `revisao.spec.ts`, **"cena 6: mudança volta à executora e a nova entrega volta à mesma revisora"**:
    1. A política do executor é revisão pela posição `conselho-nati`.
    2. O roteiro faz a Nati chamar `mcp__orquestra__pedir_mudanca` na primeira vez e `mcp__orquestra__aprovar` na segunda.
    3. A tela mostra a volta.
    4. Os pedidos da Nati são exatamente dois.
  - `revisao.spec.ts`, **"cena 6: board como revisão decide pela síntese"**: os quatro conselheiros recebem pareceres por regra, e a síntese termina com `DECISÃO: aprovar`. A tarefa segue.

  A semeadura de arquivos de cada cena (`equipe.json`, `persona.json`, `uso.jsonl`) é feita por `test.beforeAll`, com o ambiente subido por cena. Uma função `subirCena(semear)` em `apoio.ts` sobe, através de `subir.ts`, um ambiente por arquivo de cena.
- [ ] **Passo 2: instalar e rodar.** `cd app/interface/web && npm install && npx playwright install chromium && npx playwright test`. Esperado: tudo PASSA.
- [ ] **Passo 3: sabotagens, uma por teste.** Para cada uma: quebrar, rodar o teste, ver FALHA, reverter e anotar.

  | Teste | Sabotagem |
  |---|---|
  | chat | o `normalizadorDeStream` deixa de separar no `---` |
  | anexo | `resolverAnexos` devolve `[]` |
  | tarefa | `aoEntregar` não muda o status |
  | orçamento | `motivoDeBloqueio` devolve `null` |
  | pausa | `pausar` não grava |
  | plano | o bloco `<tarefa>` não inclui o plano aprovado |
  | revisão | o `retorno` volta para a primeira etapa |
  | board | `DECISÃO` é ignorada |
- [ ] **Passo 4:** `git commit -m "interface: cenas da web com Playwright (chat, tarefas, governança e revisão)"`.

### Tarefa 5: Desktop: apoio, fumaça e cenas 3, 7 e 10

**Arquivos:**
- Mudar `cliente/pubspec.yaml`: `integration_test: sdk: flutter` em `dev_dependencies`.
- Criar `cliente/lib/sistema/arquivos.dart`.
- Mudar `cliente/lib/tela/anexar.dart` e `cliente/lib/tela/importacao.dart` para chamar `arquivos`.
- Criar `cliente/integration_test/apoio/{ambiente,app,falsos,esperas}.dart`.
- Criar `cliente/integration_test/desktop_test.dart`.

**Interfaces:**

Produz, em `arquivos.dart`:

```dart
typedef EscolherArquivos = Future<List<({String nome, String caminho})>?> Function({List<String>? extensoes});
typedef SalvarArquivo = Future<String?> Function({required String nome, required List<int> bytes});
EscolherArquivos escolherArquivos = _escolherPeloFilePicker;
SalvarArquivo salvarArquivo = _salvarPeloFilePicker;
```

As duas são variáveis de topo, para o teste sobrescrever.

Produz, em `integration_test/apoio/`:
- `AmbienteDeTeste.lido()`, que lê o ambiente de um de dois lugares, via `String.fromEnvironment`: `CT_AMBIENTE_JSON` (o JSON em base64, para o celular) ou, na falta dele, `CT_AMBIENTE` (o caminho do `ambiente.json`, para o desktop). Os campos são `servidor`, `porta`, `modelo` e `dados`.
- `Future<void> subirDesktop(WidgetTester t, AmbienteDeTeste a)`, que grava `porta` nas `SharedPreferences` e chama `app.main(['--sem-bandeja'])`.
- `Future<void> roteiro(String cena, List<Map<String, Object?>> regras)`, `Future<List<Map>> pedidos(String cena)` e `Future<void> encontro(String nome, String lado, List<String> lados)`.
- `Future<void> esperarAte(WidgetTester t, bool Function() condicao, {Duration prazo = const Duration(seconds: 30)})`, que faz `pump` a cada 100 ms e falha com uma mensagem ao estourar o prazo.
- `Future<String> esperarArquivo(String caminho, {String? contendo})`.

`main.dart` passa a reconhecer `--sem-bandeja`: não inicia a bandeja e mostra a janela direto. É o mesmo caminho de `pedeBandeja` ao contrário.

- [ ] **Passo 1: escrever a fumaça do desktop.** O teste é `"desktop: sobe sem bandeja, conecta no servidor de teste e lista as personas"`. Ele espera a Nati na lista.
- [ ] **Passo 2:** rodar sob o xvfb, com as `XDG_*` temporárias:

  ```bash
  xvfb-run -a env XDG_DATA_HOME=<pasta>/xdg/data XDG_CONFIG_HOME=<pasta>/xdg/config XDG_CACHE_HOME=<pasta>/xdg/cache XDG_RUNTIME_DIR=<pasta>/xdg/run ~/flutter/bin/flutter test integration_test/desktop_test.dart -d linux --dart-define=CT_AMBIENTE=<pasta>/ambiente.json --plain-name "desktop: sobe"
  ```

  O `HOME` fica, porque a ferramenta do Flutter depende dele. A spec pedia `HOME` e `XDG_*` temporários, mas o app só usa as `XDG_*` e o `HOME` como reserva do autostart (`nucleo/autostart.dart`), e com `XDG_CONFIG_HOME` definido o `HOME` não é consultado. Esperado: PASSA. Conferir também que o `ls ~/.config/autostart` não mudou.
- [ ] **Passo 3: escrever as cenas.**
  - **"cena 3: persona e equipe criadas pelo organograma ficam no disco"**:
    1. O roteiro tem uma regra de fundo para a geração de perfil.
    2. A cena cria a persona "Vera" e a equipe "Teste".
    3. Ela arrasta as caixas e liga a da Vera à do Alfred pelo "+", depois salva.
    4. O `equipes/teste/equipe.json` tem a posição da Vera com `respondeA` na do Alfred, e o `git log -1` da pasta de dados cita a equipe.
    5. Excluir a Vera com o nome errado é recusado, e com o nome certo o `profiles/vera` some.
    6. Uma conversa com a Vera, aberta antes da exclusão pelo roteiro da geração, aparece só para leitura, sem o campo de envio.
  - **"cena 7: editor de rotinas guarda exatamente o que foi digitado, com o servidor quieto"**: preenche nome, título, descrição, porquê e cron (`0 9 * * 1`) e marca o webhook. Depois salva. O `equipes/casa/rotinas/<id>.json` tem os mesmos valores, caractere por caractere, inclusive acentos.
  - **"cena 7: e com o servidor publicando enquanto se digita"**: o mesmo preenchimento, só que entre um campo e outro um `ws()` do apoio manda `tarefa-criar` e `rotina-disparar` e derruba o socket do app (`sala.canal.pausar()` e depois `iniciar()`). O arquivo final é idêntico ao do teste anterior.
  - **"cena 7: disparo manual e pelo webhook criam a tarefa"**:
    - o botão "Disparar" cria a tarefa;
    - o `POST /rotinas/casa/<id>` com o `X-Token` copiado da tela cria outra;
    - o histórico mostra duas linhas, `manual` e `webhook`.
  - **"cena 10: skill criada e anexada chega à persona e abre"**:
    1. A cena cria a skill `checklist` (descrição e corpo) e a anexa à Nati.
    2. Abre uma conversa com a Nati. O pedido que o falso recebe lista `ct-casa:checklist`, e o roteiro responde chamando a ferramenta `Skill`.
    3. O pedido seguinte traz no `tool_result` o corpo da skill.
- [ ] **Passo 4:** rodar o `desktop_test.dart` inteiro sob o xvfb. Esperado: PASSA.
- [ ] **Passo 5: sabotagens.**

  | Cena | Sabotagem |
  |---|---|
  | 3 | `completarLayout` descarta o `respondeA` |
  | 7, servidor quieto | o campo de título do editor de rotinas recria o controller a cada build |
  | 7, servidor publicando | o mesmo, só no rebuild por publicação |
  | 7, disparo | `AGENDADOR.webhook` devolve 403 sempre |
  | 10 | `skillsDaChamada` devolve `null` |

  Para cada uma: ver FALHA, reverter e anotar.
- [ ] **Passo 6:** rodar `~/flutter/bin/flutter test` e `~/flutter/bin/flutter analyze` (verdes) e fazer `git commit -m "interface: cenas do desktop com integration_test sob xvfb (organograma, rotinas e skills) e seletor de arquivos substituível"`.

### Tarefa 6: Desktop: cenas 9 (workflows), 11 (espelho) e 12 (modelos)

**Arquivos:**
- Mudar `cliente/integration_test/desktop_test.dart`.
- Se crescer, criar `cliente/integration_test/cenas/workflows.dart` e importar no `desktop_test.dart`.

**Interfaces:**

Consome o apoio da Tarefa 5 e o `servirTickTaskFalso`, pelo `ticktask` do `ambiente.json`, com `GET /_controle/tarefas` e `POST /_controle/finalizar/<id>`.

- [ ] **Passo 1: escrever as cenas de workflow, que são prioridade.**
  - **"cena 9: workflow montado no editor salva, inicia e segue pelo ramo devolvido"**:
    1. A cena cria pelo editor o workflow `triagem`:
       - entrada `dados: texto`;
       - `executar` (executor), com a saída `prioridade: {escolha: [alta, baixa]}`;
       - `condicao` (`prioridade igual alta` vai para `paralelo`, senão vai para `fim-baixa`);
       - `paralelo`, que abre `executar` A (conselho-nati) e `executar` B (conselho-poe);
       - `juncao`;
       - `decisao_humana` ("seguir?", com as opções seguir e parar);
       - `fim`.
    2. Uma ligação de `juncao` para ela mesma mostra o erro preso à caixa e deixa o salvar desligado. A cena desfaz a ligação.
    3. Ao salvar, o `equipes/casa/workflows/triagem.json` existe com `versao: 1`.
    4. A cena inicia o workflow. O roteiro faz o executor chamar `mcp__orquestra__devolver` com `{prioridade: "alta"}`, e as tarefas A e B aparecem.
    5. A cena aprova as entregas de A e B pelo painel do desktop. O fluxo para na decisão humana.
    6. A decisão é tomada pelo WebSocket do apoio, porque aqui ela representa o celular. O fluxo termina `concluido`.
  - **"cena 9: a outra rodada segue pelo outro ramo"**: o `devolver` dá `baixa`, e o fluxo termina em `fim-baixa` sem abrir A nem B.
  - **"cena 9: laço para no limite"**: workflow semeado com `laco` (`maxVoltas: 2`), que volta enquanto `ok igual false`. O executor devolve sempre `{ok: false}`. O fluxo sai pelo limite, com exatamente 2 execuções no falso.
  - **"cena 9: cancelar uma tarefa do fluxo cancela o fluxo"**.
  - **"cena 9: terminar sem devolver é falha"**: o executor responde só texto, e a execução vai para falha com `SEM_DEVOLUCAO` visível na tela.
- [ ] **Passo 2: escrever as outras cenas.**
  - **"cena 11: espelho sobe o item, finalizar lá age aqui e resolver aqui finaliza lá"**:
    1. A cena liga o espelho na Configuração, com projeto e tags, e salva.
    2. Cria pelo apoio uma tarefa que cai em aprovação do Ueslei.
    3. Espera essa tarefa no `GET /_controle/tarefas` do TickTask falso, com `[CT]` no nome.
    4. Faz `POST /_controle/finalizar/<id>`. A tarefa fica `concluida` aqui, e a auditoria tem "via TickTask".
    5. Um segundo item é resolvido pela tela e aparece `finalizada` no falso.
  - **"cena 12: exportar e importar como nova, resolvendo a colisão"**:
    1. Exporta a equipe `casa` com `salvarArquivo` substituído, e o JSON salvo é capturado.
    2. Importa com `escolherArquivos` devolvendo esse arquivo.
    3. Na prévia, troca a Nati para "Criar com outro nome: Natália" e importa.
    4. A `equipes/casa-2/equipe.json` existe com a posição dela apontando para `natalia`, e o organograma mostra a equipe nova.
- [ ] **Passo 3:** rodar o `desktop_test.dart` inteiro sob o xvfb. Esperado: PASSA.
- [ ] **Passo 4: sabotagens.**

  | Teste | Sabotagem |
  |---|---|
  | ramo da condição | a condição no `motor.ts` sempre pega o `senao` |
  | erro preso à caixa | `validarRascunho` ignora a ligação a si mesma |
  | junção | a junção libera com uma ficha só |
  | laço | `MAX_VOLTAS_DO_LACO` é ignorado |
  | cancelar | cancelar a tarefa não cancela o fluxo |
  | `SEM_DEVOLUCAO` | o runtime aceita entrega sem `devolver` |
  | espelho | `acaoDo` devolve `null` |
  | modelos | `planejar` ignora `criar` com nome |

  Para cada uma: ver FALHA, reverter e anotar.
- [ ] **Passo 5:** `git commit -m "interface: cenas do desktop para workflows (ramos, paralelo, junção, decisão, laço, cancelamento), espelho e modelos"`.

### Tarefa 7: Celular: pacote de teste e passos do aparelho

**Arquivos:**
- Mudar `cliente/android/app/build.gradle.kts`.
- Mudar `cliente/android/app/src/main/AndroidManifest.xml`: o rótulo vem de `@string/app_name`.
- Criar `cliente/integration_test/celular_test.dart`.

**Interfaces:**

Consome o apoio da Tarefa 5. Produz `Future<void> subirCelular(WidgetTester t, AmbienteDeTeste a)`, que grava `enderecos: ['127.0.0.1:<porta>']` nas `SharedPreferences` e chama `app.main([])`.

O `build.gradle.kts` faz o seguinte quando `System.getenv("CT_APP_TESTE") == "1"`:
- `applicationIdSuffix = ".teste"`;
- `resValue("string", "app_name", "Control Tower teste")`.

Sem a variável, ele usa `resValue("string", "app_name", "Control Tower")` (ou o rótulo atual).

- [ ] **Passo 1: conferir o pacote separado.**

  ```bash
  CT_APP_TESTE=1 ~/flutter/bin/flutter build apk --debug
  aapt dump badging build/app/outputs/flutter-apk/app-debug.apk | head -1
  ```

  Esperado: `package: name='dev.ueslei.controltower.teste'`. Sem a variável, o nome continua `dev.ueslei.controltower`. Rodar também `flutter build apk --release` normal e conferir o id de sempre: o release do CI não pode mudar.
- [ ] **Passo 2: escrever os passos do celular.** Cada um nomeia a cena e o lado:
  - **"cena 1 (celular): mensagem para a Nati vira balões"**: a mesma cena da web, só que na tela do celular, que mostra uma tela por vez.
  - **"cena 2 (celular): Alfred pede, celular aprova, comando roda"**:
    1. O roteiro do Alfred usa `Bash` `echo cena2 > <dados>/../cena2.txt`.
    2. O celular abre a conversa, envia e aprova na tela.
    3. O apoio do celular confere pelo servidor (`ws` e `permissao-resolvida` com `aprovado`). O script confere o arquivo no fim, porque o celular não lê o disco da máquina.
  - **"cena 2 (celular): negado não roda"**: o mesmo, negando. O `permissao-resolvida` vem com `negado`, e o `tool_result` que o falso recebe é de erro.
  - **"cena 2 (celular): pelo aviso, com o chat fechado"**:
    1. A conversa fica fechada, e o serviço de avisos do app de teste escuta o `/avisos`.
    2. O comando pede aprovação. O teste pega o aviso recebido pelo `Notificador` do app e chama `responderAoAviso` com o `actionId` de aprovar, como o toque faria.
    3. O comando roda.
  - **"cena 2 (celular): no auto, comum passa e sensível pede"**: a conversa do Alfred está em auto. O `echo` passa sem `permissao`, e um `rm -rf <pasta>/x` (sensível por `exigeAprovacaoSempre`) pede.
  - **"cena 6 (celular): aprovação final do Ueslei pelo celular"**: o apoio semeia uma tarefa já na etapa do Ueslei. O celular abre o painel, aprova, e a tarefa fica `concluida`.
  - **"cena 9 (celular): decisão humana tomada no celular termina o fluxo"**: o apoio semeia um fluxo parado na `decisao_humana`. O celular escolhe "seguir", e o fluxo fica `concluido`.
- [ ] **Passo 3: rodar.**

  ```bash
  adb -s <serial> shell pm grant dev.ueslei.controltower.teste android.permission.POST_NOTIFICATIONS
  adb -s <serial> reverse tcp:<porta> tcp:<porta>
  CT_APP_TESTE=1 ~/flutter/bin/flutter test integration_test/celular_test.dart -d <serial> --dart-define=CT_AMBIENTE_JSON=<conteúdo do ambiente.json em base64>
  ```

  O celular não lê o arquivo da máquina, então o ambiente vai inteiro no `--dart-define`. O `pm grant` só funciona depois da primeira instalação, então a ordem é: instalar com `flutter install` sob `CT_APP_TESTE=1`, conceder e depois rodar o teste.

  Esperado: PASSA, e o `adb shell pm list packages | grep controltower` mostra os dois pacotes durante o teste.
- [ ] **Passo 4: sabotagens.**

  | Passo | Sabotagem |
  |---|---|
  | aprovar | `resolverPermissao` ignora `permitido` |
  | aviso | `Notificador.executar` não faz o POST |
  | auto | `exigeAprovacaoSempre` devolve `false` |
  | aprovação final | `tarefa-decidir` não conclui |
  | decisão | `MOTOR.decidir` ignora a opção |

  Para cada uma: ver FALHA, reverter e anotar.
- [ ] **Passo 5:** `git commit -m "celular: pacote de teste dev.ueslei.controltower.teste e passos de interface no aparelho (chat, aprovação do Alfred, aprovação final e decisão)"`.

### Tarefa 8: Comando, cenas conjuntas, relatório e registro

**Arquivos:**
- Criar `scripts/testes-de-interface.sh`.
- Criar `docs/testes-de-interface.md`.
- Mudar `app/interface/web/cenas/painel.spec.ts` (criar), `cliente/integration_test/desktop_test.dart` e `celular_test.dart`, com os lados das cenas conjuntas.
- Mudar o `CLAUDE.md` local, com o bloco da fase 14 (fica só local, porque está no `.gitignore`).

**Interfaces:**

Consome tudo o que veio antes. O script tem quatro etapas: `web`, `desktop`, `celular` e `conjuntas`, todas por padrão. Cada etapa sobe o seu ambiente com `subir.ts`, roda e encerra.

Nas `conjuntas`, um único ambiente serve às três plataformas ao mesmo tempo, e cada lado se identifica no `encontro`:
- **cena 2, comando de tarefa a todos.** A web cria a tarefa do Alfred. O comando pedido aparece no desktop e no celular, com o `tarefaId`. O desktop aprova.
- **cena 8, painel.** A web resolve um item do "Precisa de você". O desktop e o celular conferem que o item sumiu da tela deles.

- [ ] **Passo 1: escrever o script.**
  - **Sem `set -e` engolindo o relatório.** Cada etapa grava `passou`, `falhou` ou `pulou`, com a duração, em `<pasta>/resultado.tsv`.
  - **`trap`.** Ele encerra cada `subir.ts` pelo pid guardado, nunca com `pkill -f`. Também faz `adb reverse --remove tcp:<porta>` só da porta de teste e `adb uninstall dev.ueslei.controltower.teste`.
  - **Celular.** O aparelho vem do `adb devices`, a tela desbloqueada é conferida pelo `dumpsys window` (`mDreamingLockscreen=false` ou o equivalente), e a etapa fica `pulou` com motivo se não houver aparelho ou se ele estiver bloqueado.
  - **Na falha**, o script imprime a cena, o caminho da captura (`test-results/` do Playwright ou `<pasta>/capturas/` do Flutter, quando houver), o log do servidor e o `GET /_controle/sem-regra`.
  - **A pasta da rodada** fica em `/tmp/ct-interface-<data>` e só é apagada se tudo passar.
- [ ] **Passo 2: escrever o teste do `trap`.**

  ```bash
  bash scripts/testes-de-interface.sh web & sleep 20; kill -INT %1; wait
  ```

  Depois: `ss -ltnp` não mostra as portas da rodada, e `adb reverse --list` mostra só as entradas que já existiam antes. Esperado: nada órfão.
- [ ] **Passo 3: escrever os lados das cenas conjuntas** (`painel.spec.ts` e os testes `"conjunta: ..."` no desktop e no celular) e rodar `bash scripts/testes-de-interface.sh conjuntas`. Esperado: PASSA, ou `celular: pulou` sem aparelho, com a web e o desktop passando.
- [ ] **Passo 4: sabotagem das conjuntas.** Primeiro, `mandarATodos` vira um envio só para o socket de origem nas publicações de tarefa: a cena 2 conjunta FALHA. Depois, o `agendarPainel` deixa de ser chamado na resolução: a cena 8 FALHA. Reverter as duas.
- [ ] **Passo 5: escrever `docs/testes-de-interface.md`.**
  - O comando e os argumentos.
  - O que precisa estar instalado: Node, `xvfb-run`, `adb` e, no celular, aparelho desbloqueado.
  - Uma tabela com uma linha por teste: cena, plataforma, o que prova, sabotagem feita, data e saída vermelha, que é a primeira linha da falha. As linhas vêm das anotações das Tarefas 3 a 8.
- [ ] **Passo 6:** rodar `bash scripts/testes-de-interface.sh` completo, com o aparelho conectado. Esperado: todas as cenas `passou`.
- [ ] **Passo 7:** `git commit -m "interface: comando dos testes de interface com etapas, cenas conjuntas, relatório por cena e registro das sabotagens"`.
