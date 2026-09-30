# Memória das personas sobre o ai-memory

TickTask #440, que absorve a #312. Troca o `memory.md` injetado inteiro em todo turno por
uma memória com recuperação sob orçamento, isolada por persona, com uma memória coletiva
de decisões e atas, consolidada e "sonhada" pela própria persona.

Fora de escopo, por decisão: Mimic Human Conversation (#446, esforço à parte baseado em
exemplos), rerank, despejo automático de páginas, patch `claude-cli` no ai-memory, UI
própria de memória e memória do Alfred.

## Requisitos que moldam o desenho

- **Nenhuma API key.** Todo uso de LLM passa pelo Claude Agent SDK com a autenticação do
  Claude Code. O provider `anthropic-oauth` do ai-memory está descartado: a própria
  documentação dele o marca como contrário aos termos da Anthropic.
- **Cada persona tem memória independente.** O que o Ueslei conta ao Poe fica com o Poe,
  como entre pessoas.
- **A memória coletiva é só decisões e atas do board.** Fatos pessoais não são coletivos.
- **Personalidade tem núcleo fixo e camada viva.** `profile.md` continua intocável; a
  persona forma opiniões, jeito de falar com o Ueslei e posições na própria memória.
- **Tudo que usa LLM roda do nosso lado, na voz da persona.** O ai-memory fica com
  armazenamento, índice, busca, decaimento e versionamento.

## Por que o ai-memory

Foram avaliados três candidatos. graphify (Python) e Graft (TypeScript) são grafos de
**código** para agentes de programação: nenhum tem gravação pelo agente durante a
conversa, escopo por persona, episódio ou fato que muda com o tempo. O ai-memory é o
único sistema de memória de agente de fato: páginas markdown versionadas em git,
índice SQLite com FTS5, grafo de entidades, tiers (working, episodic, semantic,
procedural), decaimento com `pinned` isento, supersede em vez de delete e escopos
`workspace` + `project` explícitos que falham fechados.

Ideias dos outros dois que entram aqui: meia-vida e sinais de utilidade (o `reflect.py`
do graphify) e injeção por relevância com orçamento (o hook do Graft).

## O código do ai-memory dentro do repositório

`ai-memory/` na raiz, ao lado de `app/` e `cliente/`, entra por
`git subtree add --prefix=ai-memory <upstream> v2.4.2 --squash`. Nossas mudanças são
commits comuns com prefixo `memoria:`. Atualizar é opcional e se faz com
`git subtree pull --prefix=ai-memory <upstream> <tag> --squash`; o projeto pode divergir
do upstream sem obrigação de acompanhar. `ai-memory/target/` fica fora do git.

O binário roda como unit systemd de usuário `ai-memory.service`, em `127.0.0.1`, sem
provider de LLM, e `scripts/servico.sh` passa a escrever as duas units. O `data_dir`
fica em `~/.local/share/control-tower/memoria/`, fora do repositório, pelo mesmo motivo
das conversas: é conteúdo pessoal. O git interno do ai-memory versiona esse conteúdo.

## Escopos

Workspace `control-tower` com cinco projetos: `poe`, `nati`, `lucas`, `pami` e
`coletivo`. O escopo reservado `_global` **não é usado**: a busca num projeto único o
une automaticamente, e isso vazaria entre personas.

## Arquitetura

```
┌─ control-tower.service (Bun) ──────────────────────────┐
│ sessions.ts ── conversar() ─┐                          │
│ prompt.ts  ◄── brief ───────┤                          │
│ app/src/memoria/            │                          │
│   cliente.ts      MCP HTTP ─┼──► ai-memory.service     │
│   ferramentas.ts  tools amarradas à persona            │
│   recuperacao.ts  monta o brief do turno               │
│   consolidacao.ts consolidação após ociosidade         │
│   sonho.ts        sonho diário                         │
│   agenda.ts       gatilhos a partir de datas em disco  │
│   coletivo.ts     espelha decisions/ e board/minutes   │
│   migracao.ts     memory.md → páginas (roda uma vez)   │
└─────────────────────────────────────────────────────────┘
```

`app/src/memoria/` é o único ponto do Control Tower que fala com o ai-memory. Nenhuma
persona recebe as tools cruas dele: recebe um MCP in-process do SDK
(`createSdkMcpServer`) cujas tools **sempre** injetam `workspace=control-tower` e
`project=<persona>`, sem argumento que permita trocar. A persona lê `coletivo`, mas só o
nosso código escreve nele. O isolamento é garantido pelo adaptador, não pelo prompt.

## Fluxo de um turno

1. `recuperacao.ts` monta o **brief** da persona com orçamento de **4.000 caracteres**,
   nesta ordem de prioridade:
   - **Camada viva**: páginas `pinned` da persona, sempre, com teto de 1.500 caracteres.
   - **Contexto recente**: o episódio mais recente da persona, para saber "onde paramos".
   - **Lembranças relevantes**: `memory_query` com o texto da mensagem, uma busca na
     persona e outra em `coletivo` (os hits de uma busca com `scopes` não dizem de que
     projeto vieram), intercaladas até completar o orçamento. Trecho vindo de `coletivo`
     chega marcado como decisão ou ata.

   A camada viva e o episódio recente saem da listagem REST
   (`GET /api/v1/workspaces/{ws}/projects/{p}/pages`) filtrada pelo prefixo do caminho,
   porque o ai-memory não lista por `pinned`.
2. `montarSystemPrompt` passa a ser `[profile.md, brief, instruções da casa]`. O brief é
   cercado como material de memória, não como instrução.
3. Durante a resposta, a persona tem as tools:
   - `recordar(consulta)`: busca mais fundo em `[persona, coletivo]`;
   - `ler_lembranca(caminho)`: lê a página inteira;
   - `lembrar(titulo, texto, tipo)`: grava na hora algo que claramente importa, com
     `tipo` em `fato`, `episodio` ou `jeito` (camada viva).
4. Depois do turno nada roda; o turno custa o mesmo que hoje.

**Daemon fora do ar:** o brief sai vazio com aviso no log e a persona responde com o
`profile.md` e o `resume` do SDK. As tools respondem "memória indisponível agora". A
conversa nunca quebra por causa da memória.

**Custo:** o Poe paga hoje ~6,8 KB por turno (profile + memory), e cresce. Com o
orçamento, a parte de memória tem teto de 4 KB e não cresce. Escalar o orçamento é
decisão futura, com medição.

## Tipos de página

| tipo | tier | pinned | caminho |
|---|---|---|---|
| episódio | episodic | não | `episodios/AAAA-MM-DD-<slug>.md` |
| fato | semantic | não | `fatos/<slug>.md` |
| jeito (camada viva) | procedural | sim | `jeito/<slug>.md` |
| decisão (coletivo) | semantic | não | `decisoes/<arquivo>.md` |
| ata (coletivo) | episodic | não | `atas/<arquivo>.md` |

Toda escrita da persona leva a tag de origem: `origem:conversa:<id>`,
`origem:sonho:<data>` ou `origem:migracao`.

## Consolidação (depois de cada conversa)

- **Gatilho:** a conversa está há **30 minutos** sem mensagem e tem trecho novo desde a
  última consolidação. `MetaConversa` ganha `consolidadoAte`, o número de mensagens já
  processadas. A ociosidade é calculada pela data da última mensagem do `.jsonl`, nunca
  por temporizador em memória.
- **Sessão:** SDK com **Sonnet**, system prompt com o `profile.md` da persona e as
  instruções de consolidação; prompt com o trecho novo e as lembranças que ela já tem
  sobre os temas do trecho. Tools: as do turno mais `atualizar_lembranca(caminho,
  texto)`, que gera nova versão da página (supersede) em vez de duplicar.
- **Produz:** um episódio da conversa; fatos novos ou atualizados (fato que contradiz um
  antigo atualiza a página antiga); e, quando algo mudou nela, página de camada viva.
- **Falha:** `consolidadoAte` só avança ao fim, então a próxima verificação refaz. A
  sessão conta como falha se o daemon cair no meio ou se a persona não gravar nada. Cada
  item que falha espera o dobro da vez anterior antes de ser tentado de novo (5 min, 10,
  20… até 6 h), para uma falha persistente não gastar Sonnet a cada ciclo. Uma
  consolidação por persona por vez. Refazer não duplica, porque a persona atualiza em
  vez de criar.

## Sonho (uma vez por dia)

- **Gatilho:** `HORARIO_SONHO`, padrão **07:30**, com override por `CT_HORARIO_SONHO`.
  Cada persona grava a data do último sonho; se o horário passou e ela não sonhou desde
  então, e teve atividade desde o último sonho, o sonho está devido.
- **Faz:** pega até 40 páginas frias da persona, que o ai-memory entrega em
  `memory_forget_sweep` com `dry_run=true`. Só episódios ficam frios: fatos, camada viva e
  pinned são isentos do decaimento. A persona agrupa por tema e reescreve cada grupo como uma
  lembrança única na voz dela; as originais ficam substituídas, não apagadas.
- **Poda da camada viva:** se `jeito/` passar de 1.500 caracteres, a persona funde e
  resume, e decide o que ainda a define. A camada viva só acrescenta ao núcleo: não
  pode contradizer valores nem limites do `profile.md`.
- **Modelo:** Sonnet.
- **Decaimento nativo:** no ai-memory ele não entra no ranking da busca; só define o
  conjunto frio. **O despejo fica desligado** com
  `[maintenance] forget_sweep_interval_secs = 0`. Nada some sem passar pelo sonho.

## Máquina desligada

Os gatilhos vêm de datas gravadas em disco. Na subida do servidor, depois de 5 minutos,
roda em segundo plano, uma persona por vez: primeiro as consolidações pendentes, depois
os sonhos devidos. O chat funciona durante isso. Execução interrompida é refeita inteira,
porque os marcadores só avançam no fim.

## Coletivo

`decisions/` e `board/minutes/` continuam como fonte da verdade no repositório, e o
`buscar_decisoes` do MCP continua funcionando. `coletivo.ts` espelha cada decisão e cada
ata como página em `coletivo`: ao gravar uma ata no board e, na subida do servidor, com
uma varredura que espelha o que faltar ou tiver mudado (comparação por conteúdo).
Decisões são registradas pela persona com a ferramenta `Write`, então a varredura na
subida e uma varredura depois de cada turno de conselheiro cobrem esse caminho.

## Migração

`migracao.ts` roda uma vez por persona. Uma sessão Sonnet da própria persona recebe o
`memory.md` e o grava como páginas, classificando fato, episódio e camada viva, com tag
`origem:migracao`. Antes de remover o `memory.md`, o script confere que toda linha com
conteúdo aparece em alguma página (texto normalizado) e aborta listando o que faltou. O
`memory.md` continua no histórico do git. Depois roda a varredura do coletivo.

Enquanto o `memory.md` de uma persona existir, ele continua entrando no prompt, ao lado
do brief. Assim, reiniciar o serviço antes de migrar não apaga a memória de ninguém, e a
migração é o único ponto que tira o arquivo antigo de cena.

## O que muda no código existente

- `prompt.ts`: brief no lugar do `memory.md`, nas conversas e no parecer do board; sai a
  instrução "você pode atualizar memory.md"; entra a orientação de uso das tools de
  memória. O formato de decisão fica como está.
- `sessions.ts`: conselheiros recebem o MCP de memória e as tools dele entram em
  `allowedTools`.
- `tipos.ts`: `consolidadoAte` em `MetaConversa`.
- `server.ts`: inicia a agenda de consolidação e sonho e espelha o coletivo.
- `board.ts`: parecer usa o brief; a ata é espelhada no coletivo.

## Testes

Núcleo puro, como o repositório já faz:

- brief dentro do orçamento, prioridade da camada viva, marcação do coletivo e brief
  vazio com daemon fora;
- gatilhos de consolidação pendente e sonho devido, incluindo máquina desligada;
- tools sempre com o `project` da persona, sem argumento que o sobrescreva;
- cobertura linha a linha da migração;
- `montarSystemPrompt` com brief e sem `memory.md`.

E um smoke test manual contra o daemon real em `scripts/`, fora do `bun test`, porque
depende do binário.
