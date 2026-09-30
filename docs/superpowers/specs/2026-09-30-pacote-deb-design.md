# Pacote .deb e APK por GitHub Release

Instalar e atualizar o Control Tower numa máquina com um comando, a partir de um GitHub
Release gerado por tag, e publicar o APK assinado no mesmo Release. Uso pessoal, repo
privado `uesleinasch/tower-control`.

Fora de escopo: atualização automática dentro do app, repositório apt, arquiteturas além
de `amd64`, macOS.

## O comando

Instalar e atualizar são o mesmo comando:

```bash
gh release download -R uesleinasch/tower-control -p '*.deb' -D /tmp --clobber && sudo apt install -y /tmp/control-tower_*_amd64.deb
```

`sudo apt remove control-tower` tira código e serviços e nunca toca nos dados.

Pré-requisito que não se empacota: login do Claude Code na conta do usuário
(`~/.claude/`). O Agent SDK traz o próprio binário do Claude Code
(`@anthropic-ai/claude-agent-sdk-linux-x64`) e usa essas credenciais.

## Código e dados separados

Hoje o repositório é código e dados ao mesmo tempo, e o servidor usa a raiz do clone
como `cwd` das personas. Passa a haver duas raízes, resolvidas em `app/src/caminhos.ts`:

| raiz | variável | padrão no clone | no pacote |
|---|---|---|---|
| código (web, modelos) | `CT_INSTALACAO` | raiz do repositório | `/opt/control-tower` |
| dados | `CT_DADOS` | `~/.local/share/control-tower` | `~/.local/share/control-tower` |

A raiz de dados vale nos dois modos: rodar do clone e rodar do pacote leem os mesmos
dados. Ela é o `cwd` das sessões do SDK, então os caminhos relativos das personas
(`decisions/`, `profiles/`) não mudam.

```
/opt/control-tower/
  bin/control-tower-servidor   servidor, bun build --compile
  bin/control-tower-mcp        MCP das decisões, bun build --compile
  bin/ai-memory
  web/                         a página
  modelos/                     profiles/<p>/profile.md, board/charter.md, atalhos.md,
                               decisions/INDEX.md
  memoria-config.toml
  cliente/                     app Flutter de desktop + control-tower.apk
/usr/lib/systemd/user/         ai-memory.service, control-tower.service
/usr/share/applications/       control-tower.desktop

~/.local/share/control-tower/  git próprio
  profiles/ decisions/ board/ atalhos.md   versionados
  conversations/ memoria/                  fora do git dos dados
```

## Primeira subida

Com a pasta de dados sem o marcador `.control-tower`:

1. Copia `modelos/` para a pasta de dados.
2. Se houver origem de importação, copia por cima dela: `profiles/` (inclusive
   `memory.md`), `decisions/`, `board/`, `atalhos.md` e `conversations/`. A origem é
   `CT_IMPORTAR_DE`, ou o arquivo `.importar-de` na pasta de dados (escrito pelo
   `postinst`), ou, rodando do clone, a raiz do próprio clone.
3. Copia as sessões do SDK de `~/.claude/projects/<slug da origem>/` para
   `~/.claude/projects/<slug dos dados>/`, para o `resume` das conversas importadas
   continuar funcionando.
4. `git init`, `.gitignore` com `conversations/` e `memoria/`, commit inicial.
5. Grava o marcador. Importação nunca roda de novo.

Falha na importação aborta a subida sem gravar o marcador, para a próxima subida
tentar de novo; nada da origem é alterado.

A migração da memória (`memory.md` → ai-memory) passa a rodar sozinha: na agenda,
quando o daemon responde e ainda existe `memory.md`, com a mesma verificação item a item
de `migracao.ts`. Falha entra na mesma espera crescente das outras tarefas.

## Git dos dados

Depois de gravar uma ata e depois de cada turno de conselheiro, o servidor faz
`git add -A && git commit` na pasta de dados se houver mudança em `profiles/`,
`decisions/`, `board/` ou `atalhos.md`, com mensagem `dados: <o que mudou>`. Falha de
git só vira aviso no log.

## O repositório de código

- `profiles/<p>/profile.md`, `board/charter.md`, `atalhos.md` e `decisions/INDEX.md`
  vão para `app/modelos/`, que é a fonte dos padrões.
- `decisions/`, `board/minutes/` e os `memory.md` saem do repositório depois que esta
  máquina importar; o histórico do git os mantém.
- `app/mcp/server.ts` lê decisões da raiz de dados.
- `scripts/servico.sh` segue para rodar do clone, com `CT_DADOS` no padrão.

## Serviços

Units em `/usr/lib/systemd/user/` com os nomes de hoje (`control-tower.service`,
`ai-memory.service`), para o app de desktop seguir controlando `control-tower.service`.
O `postinst`:

- `systemctl --global enable` das duas units;
- para `SUDO_USER`: se existir `~/.config/systemd/user/control-tower.service` do modo
  clone, lê o `WorkingDirectory` dela, grava a raiz do clone em
  `~/.local/share/control-tower/.importar-de` (se os dados ainda não existirem), renomeia
  as units antigas para `.bak` (senão sombreariam as do pacote) e reinicia os serviços
  daquele usuário;
- avisa se `~/.claude/` do usuário não tiver credenciais.

## APK

`signingConfig` do release já é o debug. O CI escreve o secret
`ANDROID_DEBUG_KEYSTORE` (base64 da `~/.android/debug.keystore` do Ueslei) em
`~/.android/debug.keystore` antes do build, então todo APK sai com a mesma assinatura
e atualiza por cima. Sem o secret, o workflow falha em vez de publicar APK com chave
aleatória. Configurar uma vez:

```bash
gh secret set ANDROID_DEBUG_KEYSTORE < <(base64 -w0 ~/.android/debug.keystore)
```

O app de desktop procura o APK também ao lado do próprio executável, que no pacote é
`/opt/control-tower/cliente/control-tower.apk`.

## Workflows

`release.yml`, em push de tag `v*`, tudo em `ubuntu-22.04` (glibc da máquina alvo):

| job | faz |
|---|---|
| `ai-memory` | `cargo build --release -p ai-memory-cli`, cache `Swatinem/rust-cache` |
| `servidor` | `bun install`, `bun test`, `bun build --compile` do servidor e do MCP |
| `flutter` | `flutter test`, build linux e apk assinado; Flutter 3.47.5 |
| `pacote` | monta o `.deb` na versão da tag e publica o Release com `.deb` e `.apk` |

`testes.yml`, em push no `main`: `bun test` e `flutter test`, sem Rust.

O `.deb` depende de `libgtk-3-0` e `git`, e recomenda `adb`.
