# Control Tower

Minha sala de decisões: um chat na rede local para conversar com quatro perfis de
conselheiros, convocar um board que delibera em conjunto, e registrar decisões num
formato leve e pesquisável. O design completo está em
[docs/superpowers/specs/2026-08-22-control-tower-design.md](docs/superpowers/specs/2026-08-22-control-tower-design.md).

## Instalar pelo pacote

Cada tag `v*` gera um GitHub Release com o `.deb` (servidor, memória, app de desktop e
serviços) e o APK. Instalar e atualizar são o mesmo comando:

```bash
gh release download -R uesleinasch/tower-control -p '*.deb' -D /tmp --clobber && sudo apt install -y /tmp/control-tower_*_amd64.deb
```

Pré-requisito: login do Claude Code nesta conta (`claude` e fazer login). O pacote traz o
próprio binário do Claude Code que o Agent SDK usa, mas as credenciais são suas.
`sudo apt remove control-tower` tira código e serviços e não toca nos dados.

Publicar uma versão: `git tag v0.2.0 && git push --tags`. O APK é assinado com a
`~/.android/debug.keystore`, guardada como secret uma única vez:

```bash
gh secret set ANDROID_DEBUG_KEYSTORE < <(base64 -w0 ~/.android/debug.keystore)
```

## Onde ficam os dados

Tudo o que é seu fica em `~/.local/share/control-tower/` (ou `CT_DADOS`), com git próprio:
`profiles/`, `decisions/`, `board/`, `atalhos.md` e, fora do git, `conversations/` e a
memória das personas (`memoria/`). Na primeira subida ela nasce dos modelos em
`app/modelos/` e, se houver um clone antigo, importa perfis, decisões, atas, atalhos e
conversas dele. O servidor faz commit sozinho quando surge decisão, ata ou mudança de perfil.

## Como rodar do clone

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
Editar `atalhos.md` na pasta de dados (formato `- rótulo :: texto`) e recarregar a página muda a
lista.

O clipe no composer anexa imagem, arquivo de texto e PDF (até 10 MB; imagem grande é
reduzida antes de subir). O conselheiro abre o anexo com a ferramenta `Read`, então
consegue descrever um print e ler um log longo por partes. Anexo fica em
`conversations/anexos/` da pasta de dados, fora do git.

Pelo menu do navegador, "Adicionar à tela inicial" instala como app e abre sem a
barra de endereço.

## App de desktop e de celular (Flutter)

Além da página web, há um app nativo em `cliente/` para Linux e Android. No computador ele
fica na bandeja, sobe no login e tem uma tela de **Configuração**: estado do serviço com
iniciar/parar/reiniciar, logs ao vivo, endereços de rede, autostart e a instalação no celular.

```bash
sudo apt install -y libgtk-3-dev libx11-dev libxi-dev   # uma vez
bash scripts/instalar-cliente.sh                          # compila, instala e abre na bandeja
```

Para o celular: plugue no cabo com depuração USB, abra Configuração → Celular e toque em
**Instalar e conectar**. O app abre já com os endereços da rede local e do Tailscale e, a
cada abertura, usa o primeiro que responder. Detalhes em [cliente/README.md](cliente/README.md).

## Instalar do clone como serviço (sobe no boot)

Para desenvolver. Precisa de Bun e de `cargo` (o ai-memory é Rust).

```bash
./install.sh                 # de dentro do clone: deps, ai-memory, serviços systemd de usuário
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

Cada perfil tem um `profile.md` em `profiles/<nome>/` da pasta de dados: o núcleo fixo da
personalidade. A memória de cada um mora no ai-memory (`ai-memory/`, serviço
`ai-memory.service`), separada por persona: a cada turno entra só um resumo do que é
relevante, até 4.000 caracteres. Depois de cada conversa a própria persona repassa o que
ouviu e guarda, e uma vez por dia (07:30) "sonha", fundindo lembranças velhas. A memória
coletiva tem só as decisões e as atas do board. Design em
[docs/superpowers/specs/2026-09-30-memoria-personas-design.md](docs/superpowers/specs/2026-09-30-memoria-personas-design.md).

## Alfred

Os quatro perfis são conselheiros: conversam, guardam memória e registram decisão. O
**Alfred** é de outro tipo — executor. Ele verifica arquivo, edita coisa e roda comando,
a pedido direto, sem opinar. Não emite parecer no board, não tem memória e não
registra ADR.

Comando de terminal não roda direto: aparece na tela com o comando exato e dois botões.
Negar é resposta final — ele diz que foi negado e para. O botão **auto** no header dispensa
a aprovação naquela conversa (a escolha fica gravada no meta); o comando continua aparecendo
no chat, para o modo não ser caixa preta.

O botão **TickTask** abre uma conversa em registro direto: o Alfred fala com o servidor MCP
do app TickTask, lendo porta e token de `~/.config/ticktask/mcp-config.json`. Com o app
fechado as ferramentas não existem e ele avisa em vez de quebrar.

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
claude mcp add --scope user control-tower -- /opt/control-tower/bin/control-tower-mcp   # pelo pacote
claude mcp add --scope user control-tower -- bun run <clone>/app/mcp/server.ts         # do clone
```

## Estrutura

```
app/           servidor Bun + Agent SDK, UI web, MCP server e modelos padrão (app/modelos/)
ai-memory/     ai-memory (Rust) via git subtree: a memória das personas
cliente/       app Flutter (Linux e Android) do mesmo servidor
packaging/     o .deb: units systemd, atalho, postinst
.github/       release por tag (.deb + APK) e testes a cada push
```
