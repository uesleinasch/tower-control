# Control Tower

Minha sala de decisões: um chat na rede local para conversar com quatro perfis de
conselheiros, convocar um board que delibera em conjunto, e registrar decisões num
formato leve e pesquisável. O design completo está em
[docs/superpowers/specs/2026-08-22-control-tower-design.md](docs/superpowers/specs/2026-08-22-control-tower-design.md).

## Como rodar

```bash
cd app
bun install
bun run dev        # sobe em http://0.0.0.0:7878 (rede local e Tailscale)
```

Se o serviço systemd estiver rodando, ele já está com a porta 7878 e o `bun run dev`
morre com `EADDRINUSE` — pare o serviço antes (`systemctl --user stop control-tower`).

O motor das conversas é o Claude Agent SDK, que usa a autenticação do Claude Code já
instalado na máquina — não precisa de API key. No startup o servidor imprime os três
endereços: localhost, IP da rede local e IP do Tailscale (quando houver).

## No celular

Abra um dos endereços impressos no startup. O IP da rede local só funciona se o
celular estiver na mesma Wi-Fi; o IP do Tailscale funciona de qualquer lugar, desde
que o celular esteja no tailnet. Para saber qual usar:

```bash
tailscale ping <nome-do-celular>   # "direct" = mesma rede; "via DERP" = use o IP do Tailscale
```

A interface é responsiva: no celular a lista de conselheiros e conversas é a
primeira tela e a conversa é a segunda, com
"←" e o botão voltar do sistema voltando para a lista. Toque longo num balão abre
o menu de responder e copiar.

Com o campo vazio aparecem chips de atalho acima dele — tocar envia a frase na hora.
Editar `atalhos.md` na raiz (formato `- rótulo :: texto`) e recarregar a página muda a
lista.

O clipe no composer anexa imagem, arquivo de texto e PDF (até 10 MB; imagem grande é
reduzida antes de subir). O conselheiro abre o anexo com a ferramenta `Read`, então
consegue descrever um print e ler um log longo por partes. Anexo fica em
`conversations/anexos/`, fora do git.

Pelo menu do navegador, "Adicionar à tela inicial" instala como app e abre sem a
barra de endereço.

## Instalar como serviço (sobe no boot)

```bash
./install.sh                 # de dentro do clone: deps + serviço systemd de usuário
```

Em uma máquina nova, um comando só (clona, instala deps e registra o serviço):

```bash
git clone <url-do-repo> && cd control-tower && ./install.sh
# ou direto: ./install.sh <url-do-repo>   (clona em ~/control-tower)
```

O serviço (`control-tower.service`) reinicia sozinho em caso de falha e, com linger
ativo (o instalador tenta ativar), sobe no boot mesmo sem login. Comandos úteis:

```bash
systemctl --user status control-tower.service
journalctl --user -u control-tower.service -f
bash scripts/servico.sh      # reinstala/atualiza a unit
```

## Perfis

- **Poe** — o Amigo. Personalidade que evolui com o tempo; franqueza acima de conforto.
- **Nati** — Engenheira de Software Sênior: Haskell, DDD, data-driven design, fullstack.
- **Lucas** — o Gestor: gestão de empresas, visão de negócio, valor × custo × risco.
- **Pami** — a Projetista: criação e gestão de projetos, técnicas de mercado.

Cada perfil vive em `profiles/<nome>/`: `profile.md` é o núcleo fixo da personalidade;
`memory.md` é a memória evolutiva que o próprio perfil atualiza quando aprende algo
durável.

## Alfred

Os quatro perfis são conselheiros: conversam, guardam memória e registram decisão. O
**Alfred** é de outro tipo — executor. Ele verifica arquivo, edita coisa e roda comando,
a pedido direto, sem opinar. Não emite parecer no board, não tem `memory.md` e não
registra ADR.

Comando de terminal não roda direto: aparece na tela com o comando exato e dois botões.
Negar é resposta final — ele diz que foi negado e para.

## Board

Pela interface, o botão "Convocar board" envia uma pauta aos quatro perfis em paralelo.
Cada um emite um parecer independente (regras em `board/charter.md`), um moderador
neutro sintetiza consenso, divergências e recomendação, e a ata completa fica em
`board/minutes/`. Você recebe só a síntese.

## Decisões

Uma decisão = um arquivo Markdown em `decisions/` com frontmatter YAML (id, date,
title, status, tags, projeto, participantes) e corpo ADR enxuto. O `decisions/INDEX.md`
tem uma linha por decisão para lookup barato.

### Consultar de outras sessões Claude Code

O MCP server em `app/mcp/server.ts` expõe `buscar_decisoes` e `ler_decisao`:

```bash
claude mcp add --scope user control-tower -- bun run <caminho>/control-tower/app/mcp/server.ts
```

## Estrutura

```
app/           servidor Bun + Agent SDK, UI web e MCP server
profiles/      personalidade fixa + memória evolutiva de cada perfil
board/         charter do conselho e atas das deliberações
decisions/     decisões registradas + índice
conversations/ histórico das conversas (runtime, fora do git)
```
