# App Flutter — desktop e celular

TickTask #429. Cliente nativo em Flutter para Linux e Android, no modelo do
`claude-local-session`: sobe com a máquina, tem interface amigável de uso e de configuração
no computador e sai do cabo já conectado no celular.

O servidor Bun continua sendo o motor e segue no systemd de usuário com linger. O app é um
cliente dele e, no desktop, também o painel de controle da instalação.

## Decisões de partida

- **UI nativa em Dart, não casca WebView.** `flutter_inappwebview` e `webview_flutter` não
  suportam Linux; embutir a página no desktop exigiria janela webkitgtk à parte. Com UI
  nativa, uma árvore de widgets serve os dois alvos.
- **Paridade completa com a página web** na primeira versão: conversas, chat com streaming,
  aprovação do alfred, board, decisões, anexos, citação e atalhos. A página `app/web/`
  continua existindo.
- **O servidor não ganha rotas de administração.** Ele não tem autenticação; reiniciar
  serviço ou instalar APK por HTTP ficaria aberto para qualquer um na LAN. Toda ação de
  sistema roda no processo local do app desktop.
- **O servidor continua no systemd.** O app não é dono do processo `bun`; se fosse, o
  servidor morreria com o app e não subiria sem login.

Fora de escopo: notificações com o app fechado, iOS, macOS/Windows, `.deb`, aposentar a
página web e replicar `chunk` para outros sockets.

## Estrutura

Projeto em `cliente/`, irmão de `app/`, com toolchain própria. `bun test` não depende do
Flutter. Alvos: `linux` e `android`.

```
cliente/lib/
  nucleo/            puro, coberto por flutter test
    protocolo.dart   mensagens WS de entrada e saída (sealed classes) + codec JSON
    modelos.dart     MetaConversa, Mensagem, Anexo, Decisao, Perfil
    baloes.dart      divisão da resposta em balões pela linha ---
    enderecos.dart   candidatos LAN/Tailscale; disputa em paralelo com sonda injetada
    acoes.dart       allowlist de ações de sistema → (executável, argv)
    autostart.dart   conteúdo do .desktop de autostart
  conexao/           I/O
    canal.dart       WebSocket com reconexão e backoff, stream de eventos
    anexos_http.dart POST /anexo multipart; URL de GET /anexo/<id>
    sonda.dart       GET /enderecos com timeout
  estado/            ChangeNotifier por área: conversas, chat ativo, board, decisões, conexão
  tela/              UI responsiva
  sistema/           só Linux: executor das ações, bandeja, janela, instância única
```

O núcleo recebe o efeito como parâmetro (`disputar(candidatos, sonda)`), para teste sem rede.

## Protocolo

O Dart implementa exatamente os tipos que o servidor já usa.

- Saída: `listar`, `nova`, `mensagem`, `abrir`, `excluir`, `permissao-resposta`, `board`,
  `decisoes`, `decisao`.
- Entrada: `conversas`, `criada`, `conversa`, `chunk`, `fim`, `permissao`, `comando`,
  `aviso`, `erro`, `excluida`, `board-status`, `board-sintese`, `decisoes`, `decisao`,
  `atalhos`.

Os campos de cada tipo são os de `app/src/server.ts` e `app/src/tipos.ts`; o protocolo não
muda. Dois acréscimos no servidor:

1. **`GET /enderecos`** devolve `{ "lan": "...", "tailscale": "...", "porta": 7878 }`, a
   partir de `enderecos()` em `rede.ts`. Campos ausentes quando a interface não existe.
2. **Contrato do protocolo.** `docs/protocolo.json` lista os nomes dos tipos por direção
   (`cliente→servidor`, `servidor→cliente`). `bun test` falha se `server.ts` ou `app.js`
   usarem um `tipo` fora da lista, ou se a lista tiver um tipo que nenhum dos dois usa.
   `flutter test` lê o mesmo arquivo e falha se o codec Dart não cobrir todos. Quem mudar
   o protocolo num lado é barrado nos outros dois.

Limitação herdada: `chunk` vai só para o socket que fez o pedido. Se a conexão cair no meio
de uma resposta, o app reconecta e faz `abrir`; a resposta completa aparece quando o
servidor a grava no `.jsonl`.

## Interface de uso

Uma árvore de widgets; o layout sai da largura.

- **≥ 840 px (desktop):** coluna lateral com estado da conexão, Nova, Conversas, Board,
  Decisões e Configuração; coluna principal com a tela ativa.
- **< 840 px (celular):** uma tela por vez, com barra inferior Conversas · Board · Decisões.
  A tela inativa não é montada — mesma regra da página web. Configuração não aparece no
  Android.

Telas:

- **Conversas:** lista com avatar colorido por perfil e título. Excluir por toque longo
  (celular) ou menu de contexto (desktop), sempre com confirmação.
- **Nova conversa:** folha com seleção de perfil (quatro conselheiros e alfred), modelo
  (padrão `haiku`), modo auto e foco `ticktask` (visível só para alfred). O primeiro envio
  manda `nova`.
- **Chat:** streaming por `chunk`, balões separados por `---`, Markdown renderizado
  (`flutter_markdown`). Selecionar trecho de um balão permite citar (`citacao`). Chips de
  atalho acima do composer. Anexos pelo seletor de arquivos (desktop) ou câmera e galeria
  (celular), enviados por `POST /anexo` antes da mensagem; os ids vão em `anexos`. Anexos
  de mensagens antigas abrem por `GET /anexo/<id>`.
- **Aprovação do alfred:** card fixo acima do composer com o comando literal, Negar e
  Permitir, e contagem regressiva de 120 s. Em modo auto, `comando` aparece só como
  registro no chat.
- **Board:** campos de pauta e contexto, linha de status ao vivo (`board-status`), síntese
  em Markdown (`board-sintese`).
- **Decisões:** lista com filtro local por tag e projeto; detalhe em Markdown.
- **Conexão:** ponto verde (conectado), amarelo (reconectando), vermelho (sem servidor).
  Sem conexão o envio fica desabilitado; nada é enfileirado às cegas.
- **Tema:** claro e escuro conforme o sistema. Ícone derivado de `app/web/icone.svg`.

## Desktop (Linux)

**Conexão:** sempre `ws://127.0.0.1:<porta>/ws`, porta 7878 configurável.

**Distribuição:** `scripts/instalar-cliente.sh` roda `flutter build linux --release` e
`flutter build apk --release`, copia o bundle e o `control-tower.apk` para
`~/.local/share/control-tower-cliente/` e escreve a entrada de menu em
`~/.local/share/applications/control-tower.desktop` com o ícone. O `install.sh` da raiz o
chama quando `flutter` está no PATH e segue sem ele quando não está.

**Sobe com a máquina:**

- Servidor: systemd de usuário com linger, como hoje.
- App: `~/.config/autostart/control-tower.desktop` com `--bandeja`, escrito e apagado pelo
  interruptor da tela de Configuração. Nunca em `/etc/xdg/autostart/`. No login aparece só o
  ícone na bandeja, sem janela.
- Bandeja (`tray_manager`): ícone com a cor do estado do serviço; menu Abrir, Nova conversa,
  Reiniciar servidor, Sair. Fechar a janela esconde (`window_manager`); Sair encerra.
- Instância única: socket Unix em `$XDG_RUNTIME_DIR/control-tower-cliente.sock`. Abrir de
  novo traz a janela existente para frente e encerra a segunda instância.

**Tela de Configuração:**

| Bloco | Conteúdo |
|---|---|
| Servidor | `systemctl --user is-active`/`is-enabled control-tower`; Iniciar, Parar, Reiniciar; linger ligado/desligado (`loginctl show-user`) com a instrução para ligar; porta |
| Logs | `journalctl --user -u control-tower -n 200 -f` ao vivo, filtro de texto, copiar |
| Inicialização | interruptor "Abrir na bandeja ao entrar na sessão" |
| Rede | endereços LAN e Tailscale vindos de `/enderecos`, com copiar |
| Celular | aparelhos do `adb devices`; por aparelho, **Instalar e conectar** |

**Instalar e conectar:** `adb -s <serial> install -r <apk>` e, em seguida,
`adb -s <serial> shell am start -n dev.ueslei.controltower/.MainActivity --es servidores '<json>'`,
com `<json>` = lista de `ws://host:porta` montada a partir de `/enderecos`. Progresso na tela
e erro literal do adb. Sem `adb` no PATH ou sem APK em
`~/.local/share/control-tower-cliente/`, o botão fica desabilitado com a explicação.

**Fronteira de segurança:** `nucleo/acoes.dart` é uma allowlist. Cada ação mapeia para um
executável fixo e argv em lista, executado com `Process.start` sem shell. O serial passa
por `^[A-Za-z0-9.:_-]+$`; o JSON dos servidores é gerado pelo app, nunca digitado. Nenhuma
dessas ações existe como rota do servidor.

## Celular (Android)

- Pacote `dev.ueslei.controltower`. A `MainActivity` lê o extra `servidores` do intent e o
  entrega ao Dart pelo `MethodChannel` `control_tower/pareamento`. Os endereços vão para
  `shared_preferences`; não há token a proteger.
- `network_security_config` libera tráfego em claro. Sem isso o Android 9+ bloqueia `ws://`
  e a conexão falha sem mensagem útil.
- A cada abertura, `disputar` sonda em paralelo todos os endereços guardados com
  `GET /enderecos` e fica com o primeiro que responde; a resposta regrava a lista, então IP
  trocado pelo DHCP se corrige enquanto alguma rota funcionar.
- Sem nenhum endereço respondendo: tela "Servidor não encontrado" com Tentar de novo e campo
  manual `host:porta` como último recurso.
- Em segundo plano o WebSocket fecha; na volta, reconecta e faz `abrir` na conversa ativa.
  Aprovação pendente enquanto o app estava fechado expira pelo prazo do servidor.

## Erros

| Situação | Comportamento |
|---|---|
| `erro` do servidor | banner no chat com o texto |
| `aviso` do servidor | aviso discreto que some sozinho |
| aprovação sem resposta em 120 s | card vira "expirou — comando negado" |
| upload falhou | anexo fica no composer com Tentar de novo |
| conexão caiu | backoff exponencial até 10 s, ponto amarelo |
| ação de sistema falhou | `stderr` literal no bloco da Configuração |

## Testes

- `flutter test` (núcleo): codec com uma fixture por tipo do protocolo e cobertura contra
  `docs/protocolo.json`; divisão de balões; `disputar` com sonda falsa (vencedor, todos
  falham, lista renovada); allowlist de ações (argv esperado, serial inválido recusado);
  conteúdo do `.desktop` de autostart.
- `bun test`: contrato do protocolo sobre `server.ts` e `app.js`; forma da resposta de
  `/enderecos`.
- UI sem teste automatizado. Confirmação visual e de comportamento é do Ueslei, no desktop
  e no celular.

## Fases

1. Servidor: `/enderecos`, `docs/protocolo.json` e teste de contrato
2. Projeto `cliente/` e núcleo (protocolo, modelos, balões, endereços)
3. Conexão WS, HTTP de anexos e camada de estado
4. Uso I: conversas, chat com streaming e aprovação do alfred
5. Uso II: board, decisões, anexos, citação e atalhos
6. Desktop: janela, bandeja, instância única e autostart
7. Desktop: tela de Configuração (servidor, logs, rede)
8. Celular: pareamento por intent e "Instalar e conectar" via adb
9. Instalação: `instalar-cliente.sh`, `install.sh` e documentação (README, CLAUDE.md)
