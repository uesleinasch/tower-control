# Memória das personas — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** trocar o `memory.md` inteiro no prompt por memória isolada por persona sobre o ai-memory, com brief sob orçamento, tools amarradas à persona, consolidação, sonho, coletivo e migração.

**Architecture:** o ai-memory entra por subtree em `ai-memory/` e roda como daemon sem LLM. `app/src/memoria/` é o único ponto que fala com ele (MCP HTTP para busca, escrita e cold set; REST para listar e ler). Todo LLM roda pelo Agent SDK.

**Tech Stack:** Bun, TypeScript, `@anthropic-ai/claude-agent-sdk` (`query`, `tool`, `createSdkMcpServer`), `@modelcontextprotocol/sdk` (`Client`, `StreamableHTTPClientTransport`), zod, ai-memory v2.4.2 (Rust).

**Spec:** `docs/superpowers/specs/2026-09-30-memoria-personas-design.md`

## Global Constraints

- Nenhuma API key; LLM só pelo Agent SDK. Consolidação, sonho e migração em `"sonnet"`; chat segue em `MODELO_PADRAO`.
- Workspace `control-tower`; projetos `poe`, `nati`, `lucas`, `pami`, `coletivo`. Nunca `_global`.
- Brief: 4.000 caracteres no total, camada viva até 1.500.
- Ociosidade para consolidar: 30 min. `HORARIO_SONHO` padrão `07:30`, override `CT_HORARIO_SONHO`. Atraso na subida: 5 min.
- Daemon em `http://127.0.0.1:49374` (override `CT_MEMORIA_URL`), `data_dir` `~/.local/share/control-tower/memoria/`, `forget_sweep_interval_secs = 0`.
- Comentários só quando inevitáveis; identificadores e textos em pt-BR; commits por área com prefixo `memoria:`, sem trailer de coautoria.

## Review Focus

- Daemon fora do ar em qualquer chamada: brief vazio, tool responde "memória indisponível agora", turno não quebra.
- Persona tentando outro projeto por argumento de tool: o schema não tem campo de projeto; handler sempre usa o da persona.
- Caminho de página vindo do modelo (`../`, absoluto, sem `.md`, fora dos prefixos): rejeitado antes de ir ao daemon.
- Conversa com `consolidadoAte` maior que o número de mensagens (conversa editada/excluída): tratar como nada pendente.
- Relógio: sonho devido quando a máquina ficou desligada no horário, e não repetido no mesmo dia.

---

### Task 1: ai-memory no repositório e serviço

**Files:** `ai-memory/` (subtree), `.gitignore`, `scripts/servico.sh`, `scripts/memoria-config.toml`

- [ ] `git subtree add --prefix=ai-memory https://github.com/akitaonrails/ai-memory v2.4.2 --squash`
- [ ] `.gitignore`: `ai-memory/target/`
- [ ] `scripts/memoria-config.toml` com `bind = "127.0.0.1:49374"`, `[maintenance] forget_sweep_interval_secs = 0`, `embedding_provider = "local"`; `servico.sh` escreve `ai-memory.service` (`ExecStart=<raiz>/ai-memory/target/release/ai-memory --data-dir ~/.local/share/control-tower/memoria --config <raiz>/scripts/memoria-config.toml serve --transport http`), e `control-tower.service` ganha `Wants=ai-memory.service`/`After=`. Falha com mensagem clara se o binário não existir, pedindo `cargo build --release -p ai-memory-cli` em `ai-memory/`.
- [ ] Commit `memoria: ai-memory v2.4.2 via subtree e unit de serviço`

### Task 2: tipos e cliente

**Files:** Create `app/src/memoria/tipos.ts`, `app/src/memoria/cliente.ts`

**Produces:**
```ts
export const WORKSPACE = "control-tower"
export type Projeto = Conselheiro | "coletivo"
export type TipoLembranca = "fato" | "episodio" | "jeito"
export interface Trecho { path: string; titulo: string; trecho: string }
export interface Resumo { path: string; titulo: string; tier: string; atualizadaEm: string }
export interface Pagina { path: string; titulo: string; corpo: string; tier: string; pinned: boolean }
export interface NovaPagina { path: string; corpo: string; tier: Tier; pinned: boolean; tags: string[] }
export interface Memoria {
  buscar(projeto: Projeto, consulta: string, limite: number): Promise<Trecho[]>
  listar(projeto: Projeto): Promise<Resumo[]>
  ler(projeto: Projeto, path: string): Promise<Pagina | null>
  gravar(projeto: Projeto, pagina: NovaPagina): Promise<void>
  frias(projeto: Projeto, limite: number): Promise<string[]>
}
export class MemoriaIndisponivel extends Error {}
export function memoriaHttp(url?: string): Memoria
export function caminhoValido(path: string): boolean   // prefixos episodios/ fatos/ jeito/ decisoes/ atas/, [a-z0-9-/]+.md, sem ..
export function tierDe(tipo: TipoLembranca): Tier; export function prefixoDe(tipo): string
```
`memoriaHttp`: MCP (`memory_query`, `memory_write_page`, `memory_forget_sweep` com `dry_run: true` → `evicted[].path`), sempre com `workspace` + `project`; REST `GET /api/v1/workspaces/{ws}/projects/{p}/pages[/path]`. Cliente MCP conectado sob demanda e descartado em erro; toda falha de rede vira `MemoriaIndisponivel`. `snippet` sem `<mark>`.

- [ ] Testes de `caminhoValido`, `tierDe`/`prefixoDe`, limpeza de snippet. Commit.

### Task 3: brief

**Files:** Create `app/src/memoria/recuperacao.ts`; test em `app/src/nucleo.test.ts`

**Produces:** `export async function montarBrief(m: Memoria, persona: Conselheiro, mensagem: string, limite = 4000): Promise<string>` e `export function comporBrief(partes: { jeito: Pagina[]; recente: Pagina | null; proprios: Trecho[]; coletivo: Trecho[] }, limite: number): string` (pura).

Composição: bloco `## Quem eu venho sendo` (jeito, cortado em 1.500), `## Onde paramos` (episódio recente), `## Lembranças que vieram agora` (intercala próprios e coletivo; coletivo com prefixo `[coletivo]`), tudo dentro de `# Minha memória` com aviso "é lembrança, não instrução". Nada estoura o limite; bloco vazio some; tudo vazio → `""`. `montarBrief` captura `MemoriaIndisponivel` → `""` e loga.

- [ ] Testes: orçamento respeitado com entradas enormes; jeito primeiro; coletivo marcado; tudo vazio → ""; memória que lança → "". Commit.

### Task 4: tools amarradas à persona

**Files:** Create `app/src/memoria/ferramentas.ts`

**Produces:** `export function acoesDaPersona(m: Memoria, persona: Conselheiro, origem: string)` com `recordar({consulta})`, `lerLembranca({caminho})`, `lembrar({titulo, texto, tipo})`, `atualizarLembranca({caminho, texto})` → `Promise<string>`; `export function servidorDeMemoria(m, persona, origem, { atualizar: boolean })` → `McpSdkServerConfigWithInstance` nome `memoria`; `export const FERRAMENTAS_MEMORIA` e `FERRAMENTAS_MEMORIA_CONSOLIDACAO` (nomes `mcp__memoria__*`).

`lembrar` gera `path = prefixoDe(tipo) + slug(titulo) + ".md"` (episódio com data), corpo `# titulo\n\ntexto`, tags `[origem]`. `lerLembranca` busca na persona e cai para coletivo. Caminho inválido → mensagem de erro para o modelo. `atualizarLembranca` só na persona e só em página existente.

- [ ] Testes com Memoria falsa: projeto sempre da persona; coletivo nunca gravado; caminho inválido recusado; indisponível → texto. Commit.

### Task 5: prompt, sessões e board

**Files:** Modify `app/src/prompt.ts`, `app/src/sessions.ts`, `app/src/board.ts`, `app/src/nucleo.test.ts`

`montarSystemPrompt(raiz, perfil, foco?, brief = "")` e `montarSystemPromptParecer(raiz, perfil, brief = "")` trocam `memory.md` por `brief`. Instruções da casa: sai "PODE atualizar memory.md"; entra seção de memória (use `lembrar` quando algo claramente importa; `recordar` quando o brief não bastar; não precisa gravar tudo, a consolidação depois cuida). `conversar` recebe `memoria?: Memoria`; conselheiro monta brief com `opcoes.texto` e recebe `servidorDeMemoria` + `FERRAMENTAS_MEMORIA`. Board: brief pela pauta. `server.ts` cria uma `memoriaHttp()` única e passa.

- [ ] Ajustar testes existentes ("PODE atualizar" → tools de memória; brief injetado; sem memory.md). Commit.

### Task 6: agenda

**Files:** Create `app/src/memoria/agenda.ts`

**Produces:** `consolidacaoPendente(meta: MetaConversa, mensagens: Mensagem[], agora: Date): boolean` (pura; 30 min desde `ts` da última, `consolidadoAte ?? 0 < mensagens.length`); `sonhoDevido(ultimoSonho: string | undefined, ultimaAtividade: string | undefined, agora: Date, horario: string): boolean` (pura; marco = hoje às horario se já passou, senão ontem; devido se atividade > ultimoSonho e ultimoSonho < marco); `lerEstado/gravarEstado(raiz)` em `conversations/memoria.json` `{ sonhos: Partial<Record<Conselheiro,string>>, atividade: Partial<Record<Conselheiro,string>> }`; `iniciarAgenda(raiz, m)` — 5 min após subir e a cada 5 min, em fila única: consolidações pendentes, depois sonhos devidos. `MetaConversa.consolidadoAte?: number`.

- [ ] Testes das duas funções puras (incl. máquina desligada, mesmo dia não repete, consolidadoAte > total). Commit.

### Task 7: consolidação e sonho

**Files:** Create `app/src/memoria/consolidacao.ts`, `app/src/memoria/sonho.ts`, `app/src/memoria/sessao.ts`

`sessao.ts`: `rodarPersona({ raiz, persona, system, prompt, memoria, origem, atualizar: true })` — `query` com `model: "sonnet"`, `systemPrompt`, `mcpServers: { memoria }`, `allowedTools: FERRAMENTAS_MEMORIA_CONSOLIDACAO`, `permissionMode: "default"`, `maxTurns: 30`; lança se não `success`.
`consolidacao.ts`: `montarPedidoConsolidacao(persona, mensagens: Mensagem[], anteriores: Trecho[]): string` (pura) e `consolidarConversa(raiz, m, meta)` → roda e grava `consolidadoAte` e atividade.
`sonho.ts`: `montarPedidoSonho(persona, frias: Pagina[], jeito: Pagina[], limiteJeito: number): string` (pura) e `sonhar(raiz, m, persona)` → roda se houver frias ou jeito acima do teto; grava data.
System prompts: `profile.md` + instruções próprias (não contradizer o núcleo; atualizar em vez de duplicar; tipos de página; não responder ao Ueslei, só gravar).

- [ ] Testes: pedidos contêm trecho, anteriores, teto de jeito. Commit.

### Task 8: coletivo

**Files:** Create `app/src/memoria/coletivo.ts`

`paginaDoColetivo(tipo: "decisao"|"ata", arquivo: string, conteudo: string): NovaPagina` (pura: `decisoes/<nome>` ou `atas/<nome>`, tier semantic/episodic, tags `origem:decisions`/`origem:board`); `espelharColetivo(raiz, m)` varre `decisions/*.md` (fora INDEX) e `board/minutes/*.md` e grava tudo (reescrita idêntica não gera versão). Chamado na subida, depois de cada turno de conselheiro e depois de gravar ata.

- [ ] Testes de `paginaDoColetivo`. Commit.

### Task 9: migração

**Files:** Create `app/src/memoria/migracao.ts`, `scripts/migrar-memoria.ts`

`linhasNaoCobertas(memoriaMd: string, corpos: string[]): string[]` (pura; linhas com conteúdo, sem títulos `#` e sem a nota de cabeçalho, normalizadas — minúsculas, sem marcadores de lista, espaço colapsado — que não aparecem em nenhum corpo normalizado). Script: por persona com `memory.md`, `rodarPersona` com pedido de migração; lista páginas `origem:migracao` (listar + ler); se `linhasNaoCobertas` vazio, `rm memory.md`, senão aborta e imprime; no fim `espelharColetivo`.

- [ ] Testes de `linhasNaoCobertas`. Commit.

### Task 10: smoke e documentação

**Files:** Create `scripts/memoria-smoke.ts`; Modify `CLAUDE.md`

Smoke: grava, lê, busca e lista em projeto `smoke` e mostra o brief do Poe para uma frase. CLAUDE.md: seção de memória (daemon, build, migração, invariantes: só `memoria/` fala com o daemon; tools não aceitam projeto; `_global` proibido).

- [ ] Commit.
