# Control Tower — Design

Data: 2026-08-22
Status: aprovado
Metodologia: SDD (spec-driven development) — esta spec é a fonte de verdade; implementação direta a partir dela, testes apenas onde agregam valor real (núcleo puro crítico), sem TDD.

## Visão

Sala de decisões pessoal do Ueslei: quatro perfis com personalidade própria (Poe, Nati, Lucas, Pami), um conselho (board) que delibera em conjunto, e um registro de decisões pesquisável. Interação por uma interface de chat dedicada na rede local — **não** reutiliza o claude-local-session como interface, apenas suas convenções de stack.

## Decisões de arquitetura (fechadas com o Ueslei)

1. **Interface dedicada**: aplicação web própria, focada só nesse trabalho.
2. **Motor híbrido**: Claude Agent SDK (`@anthropic-ai/claude-agent-sdk`) como engine das conversas + MCP server para expor as decisões a outras sessões Claude Code.
3. **Board com deliberação oculta**: perfis deliberam em paralelo nos bastidores; o usuário recebe apenas a síntese (consenso, divergências nomeadas, recomendação final).
4. **Monorepo**: código e conteúdo juntos no control-tower.
5. **SDD**: sem TDD; commits granulares; repositório git local, remote privado adicionado manualmente pelo Ueslei ao final.

## Arquitetura

```
navegador (LAN) ──HTTP/WS :7878──► tower server (Bun + TypeScript)
                                      │
                                      ├── conversa 1:1 → sessão Agent SDK (system prompt do perfil)
                                      ├── board → fan-out: 1 query por perfil em paralelo + query de síntese
                                      └── lê/escreve: profiles/, board/, decisions/, conversations/

app/mcp (stdio) ──► sessões Claude Code consultam decisões (buscar_decisoes, ler_decisao)
```

- O Agent SDK usa a autenticação existente do Claude Code (assinatura) — sem custo de API.
- Runtime Bun, TypeScript, UI em HTML/CSS/JS puro sem framework nem build (convenção herdada do claude-local-session). Todo código, string de UI e commit em português.

## Estrutura do repositório

```
control-tower/
├── app/
│   ├── src/
│   │   ├── server.ts       # Bun.serve: HTTP estático + WebSocket + rotas
│   │   ├── sessions.ts     # ciclo de vida das conversas (Agent SDK, resume por sessão)
│   │   ├── prompt.ts       # montagem do system prompt (profile.md + memory.md + casa)
│   │   ├── board.ts        # orquestrador do conselho (fan-out + síntese + ata)
│   │   ├── decisions.ts    # registro e indexação de decisões
│   │   └── store.ts        # persistência das conversas (jsonl)
│   ├── web/                # index.html, app.js, style.css
│   └── mcp/
│       └── server.ts       # MCP stdio: buscar_decisoes, ler_decisao
├── profiles/
│   └── {poe,nati,lucas,pami}/
│       ├── profile.md      # núcleo fixo: identidade, voz, valores, expertise, estilo
│       └── memory.md       # memória evolutiva — o próprio perfil atualiza
├── board/
│   ├── charter.md          # regras do conselho: formato do parecer, critérios, papéis
│   └── minutes/            # uma ata por convocação: YYYY-MM-DD-<slug>.md
├── decisions/
│   ├── INDEX.md            # uma linha por decisão
│   └── YYYY-MM-DD-<slug>.md
├── conversations/          # runtime, gitignored (histórico jsonl)
└── docs/superpowers/specs/ # esta spec
```

## Perfis

Quatro perfis, cada um com personalidade rica e distinta:

- **Poe** — o Amigo. Personalidade construída para evoluir com o tempo; conversa franca, humana, sem jargão corporativo.
- **Nati** — Engenheira de Software Sênior. Expertise profunda em Haskell, domain-driven design, data-driven design e fullstack. Opinião técnica firme e fundamentada.
- **Lucas** — o Gestor. Gestão de empresas, visão de negócio, trade-offs econômicos.
- **Pami** — a Projetista. Gestão e criação de projetos, técnicas de mercado (roadmaps, riscos, escopo, priorização).

### Montagem do system prompt

`prompt.ts` concatena, nesta ordem:
1. `profiles/<perfil>/profile.md` — núcleo fixo, nunca alterado pelo perfil.
2. `profiles/<perfil>/memory.md` — memória evolutiva.
3. Instruções da casa (constante no código): responder em pt-BR; o perfil pode atualizar **apenas** seu próprio `memory.md` quando aprender algo durável sobre o Ueslei ou seus projetos; quando uma decisão for tomada na conversa, registrá-la via formato de decisão (abaixo); nunca editar `profile.md`.

### Evolução

A sessão do Agent SDK roda com `cwd` na raiz do repo, ferramentas Read/Write/Edit/Grep/Glob e `permissionMode: "acceptEdits"`. A instrução da casa restringe a escrita ao próprio `memory.md` e a `decisions/`. Separar núcleo fixo de memória garante que a evolução não corrompe a personalidade.

## Conversas 1:1

- Uma conversa = uma sessão do Agent SDK. O servidor guarda o `sessionId` retornado e usa `resume` nas mensagens seguintes.
- Persistência: `conversations/<id>.jsonl` (uma linha por mensagem: `{role, text, ts, profile}`). Suficiente para reabrir o histórico na UI; o contexto do modelo vem do resume do SDK.
- Streaming: o servidor repassa os chunks do SDK pela WebSocket para a UI renderizar progressivamente.

## Board

1. Usuário envia pauta (+ contexto opcional) pela UI.
2. `board.ts` dispara em paralelo uma query single-shot por perfil: recebe a pauta + charter e devolve parecer estruturado — posição, argumentos, riscos, recomendação.
3. Query de síntese (sem personalidade — moderador neutro) consolida: consenso, divergências nomeadas por perfil, recomendação final.
4. Ata gravada em `board/minutes/YYYY-MM-DD-<slug>.md` com os quatro pareceres íntegros + síntese.
5. UI recebe apenas a síntese, com link para a ata completa.
6. Se a síntese propõe uma decisão, o usuário confirma na UI e ela é registrada em `decisions/`.

## Decisões

Um arquivo por decisão — ADR enxuto, grep-friendly:

```markdown
---
id: 2026-08-22-motor-agent-sdk
date: 2026-08-22
title: Usar Agent SDK como motor do chat
status: aceita          # proposta | aceita | revogada
tags: [arquitetura, control-tower]
projeto: control-tower
participantes: [nati, lucas]
---

## Contexto
## Decisão
## Alternativas descartadas
## Consequências
```

`INDEX.md`: uma linha por decisão (`- 2026-08-22 · aceita · [título](arquivo.md) · tags`). `decisions.ts` mantém o índice ao registrar; regenerável a partir dos frontmatters.

### MCP server (`app/mcp/server.ts`)

Stdio, para registrar em outras sessões Claude Code do Ueslei:
- `buscar_decisoes({texto?, tags?, status?})` → linhas do índice + trechos que casam (busca por frontmatter + grep no corpo).
- `ler_decisao({id})` → conteúdo integral do arquivo.

## Interface web

Uma página, três áreas:
- **Barra lateral**: perfis (avatar/cor por perfil), botão "Convocar board", lista de conversas recentes, atalho para decisões.
- **Chat**: mensagens com streaming, indicador de qual perfil responde.
- **Decisões**: listagem do índice com filtro por tag/status e leitura de uma decisão.

LAN only: bind `0.0.0.0:7878`, sem autenticação (mesma postura do local-session — rede local confiável).

## Tratamento de erros

- Queda da sessão SDK → mensagem de erro no chat + a conversa permite reenviar (nova sessão com resume ou recomeço).
- Parecer de perfil que falha no board → síntese prossegue com os que responderam, nomeando a ausência.
- Escrita de decisão/ata: write em arquivo temporário + rename (atômico).

## Testes (mínimos, SDD)

Apenas núcleo puro onde erro seria silencioso: montagem do system prompt, parse/serialização do frontmatter de decisão, atualização do INDEX.md. Nada de testes de UI ou de integração com o SDK — validação manual pelo Ueslei.

## Fases de entrega

1. **Fundação (conteúdo)**: personalidades dos 4 perfis, charter do board, formato/INDEX de decisões, estrutura de diretórios, git.
2. **Chat 1:1**: servidor + Agent SDK + UI mínima com seletor de perfil.
3. **Board**: fan-out, síntese, atas, fluxo de confirmação de decisão.
4. **MCP das decisões**: server stdio + instruções de registro.
5. **Refinamentos**: streaming polido, filtros de decisão, melhorias de memória.
