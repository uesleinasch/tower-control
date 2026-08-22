# Alfred — perfil executor

TickTask #314. Um perfil que executa tarefas na máquina: verifica arquivo, edita coisa,
roda comando. Pedido direto, sem conversa.

## O que torna isto arquitetural

Alfred não é um quinto conselheiro; é um **segundo tipo de perfil**. O código assumia que
todo perfil é conselheiro, e é aí que está o trabalho:

- `board.ts` fazia `PERFIS.map(...)`, então um nome novo no array seria convocado ao board
  automaticamente e teria parecer na ata
- `instrucoesDaCasa` manda registrar ADR, manter `memory.md` e diz "você NUNCA edita
  qualquer outro arquivo" — contradiz frontalmente a função do alfred
- `sessions.ts` tinha um único conjunto de ferramentas e permissão para todos

## Dois tipos

```ts
export const CONSELHEIROS = ["poe", "nati", "lucas", "pami"] as const
export const EXECUTORES = ["alfred"] as const
export const PERFIS = [...CONSELHEIROS, ...EXECUTORES] as const

export type Conselheiro = (typeof CONSELHEIROS)[number]
export type Perfil = (typeof PERFIS)[number]
```

`board.ts` itera `CONSELHEIROS`. `montarSystemPromptParecer` aceita só `Conselheiro`, então
o tipo impede que alguém convoque um executor ao board depois. `server.ts` segue validando
contra `PERFIS`, então alfred é selecionável no chat.

## Prompt

`instrucoesDaCasa` passa a ser de conselheiro. Nasce `instrucoesDoExecutor`, e
`montarSystemPrompt` ramifica pelo tipo.

Alfred tem `profile.md` e **não tem `memory.md`**: executor não faz diário, e o que ele
precisa saber da máquina é fato fixo, escrito à mão. `POLITICAS_DE_TAMANHO` é
`Record<Perfil, string>`, então o compilador cobra uma política para ele — "uma ou duas
linhas, sem preâmbulo".

## Ferramentas e aprovação de comando

Alfred recebe `Bash` além das ferramentas de arquivo, e `permissionMode: "default"` em vez
de `acceptEdits` — assim o `canUseTool` decide tudo explicitamente, sem depender de como
os dois mecanismos interagem entre si.

- Read, Write, Edit, Grep, Glob: `{ behavior: "allow" }` sem perguntar
- Bash: pergunta na UI e espera a resposta

```
servidor → { tipo: "permissao", id, comando }
cliente  → cartão no chat com o comando + Permitir / Negar
cliente  → { tipo: "permissao-resposta", id, permitido }
servidor → resolve a promessa → PermissionResult
```

O servidor mantém um mapa de pendentes por id. **Timeout de 2 minutos nega**, e desconexão
do cliente nega todas as pendentes daquela conexão — sem isso uma aba fechada deixaria o
alfred travado esperando resposta para sempre.

Sem "permitir sempre": `updatedPermissions` existe no SDK, mas é superfície que ninguém
pediu.

## Alcance

Sem cerca de diretório. Alfred age onde for pedido.

Isso não afrouxa nada: foi **medido** que `cwd` não restringe. Com as opções que o chat já
usa hoje, um perfil leu `/etc/hostname` — fora do repo. Formalizar uma cerca só para o
alfred seria teatro enquanto os outros quatro não têm nenhuma.

## Risco aceito

O serviço continua em `0.0.0.0` sem autenticação, por decisão do usuário depois de o risco
ser apresentado. Alfred não muda isso para melhor nem para pior: leitura e escrita
arbitrárias de arquivo já eram possíveis por qualquer perfil, e escrita arbitrária já é
execução de código — basta escrever em `~/.bashrc`.

A aprovação de comando protege contra o alfred fazer besteira a pedido do próprio usuário,
não contra terceiros na rede. Quem quiser fechar a exposição de verdade tem duas saídas
levantadas e não escolhidas: escutar apenas em localhost e no IP do Tailscale, ou exigir
token no upgrade do WebSocket.

## Testes

- `ehConselheiro` separa os dois tipos
- alfred fora da lista que o board convoca
- `montarSystemPrompt("alfred")` contém instrução de executor e **não** contém a de
  registrar decisão em ADR
- alfred tem política de tamanho própria

O fluxo de aprovação fica para verificação manual: depende de duas pontas conversando.

## Arquivos

| Arquivo | Papel |
|---|---|
| `app/src/tipos.ts` | `CONSELHEIROS`, `EXECUTORES`, `Conselheiro`, `ehConselheiro` |
| `app/src/prompt.ts` | `instrucoesDoExecutor`, ramificação, política do alfred |
| `app/src/board.ts` | itera `CONSELHEIROS` |
| `app/src/sessions.ts` | ferramentas e `canUseTool` por tipo |
| `app/src/server.ts` | mapa de pendentes, roteamento da permissão no WebSocket |
| `profiles/alfred/profile.md` | novo |
| `app/web/index.html`, `app.js`, `style.css` | botão, cor, cartão de permissão |
| `app/src/nucleo.test.ts` | os quatro testes |
