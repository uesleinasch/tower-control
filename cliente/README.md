# Control Tower — app Flutter

Cliente nativo do servidor em `app/`, para Linux e Android. Fala o mesmo protocolo WebSocket
da página web (`docs/protocolo.json`) e não substitui a página: os dois convivem.

- **Desktop (Linux):** conecta em `127.0.0.1:7878`, fica na bandeja, sobe no login com
  `--bandeja` e tem a tela de Configuração (servidor, logs, rede, autostart, celular).
- **Celular (Android):** recebe os endereços do servidor pelo desktop no cabo e, a cada
  abertura, fica com o primeiro que responder em `/enderecos` (LAN ou Tailscale).

## Instalar

Da raiz do repositório:

```bash
sudo apt install -y libgtk-3-dev libx11-dev libxi-dev   # uma vez, para compilar no Linux
bash scripts/instalar-cliente.sh
```

O script compila o desktop e o APK, copia para `~/.local/share/control-tower-cliente/`, cria a
entrada no menu, liga o autostart na bandeja (`SEM_AUTOSTART=1` para não ligar) e abre o app.

Para o celular: plugue no cabo com depuração USB, abra **Configuração → Celular** e toque em
**Instalar e conectar**. O app é instalado e aberto já com os endereços deste computador.

## Estrutura

| Núcleo puro (coberto por `flutter test`) | Casca (I/O e UI) |
| --- | --- |
| `nucleo/protocolo.dart`, `modelos.dart`, `baloes.dart`, `enderecos.dart`, `formato.dart`, `acoes.dart`, `autostart.dart`; `estado/` | `conexao/`, `sistema/`, `tela/`, `main.dart` |

`sistema/` só roda no Linux. Toda ação de sistema sai de `nucleo/acoes.dart`: executável fixo
e argv em lista, sem shell, com serial do adb e usuário validados. Nenhuma delas existe como
rota do servidor, que não tem autenticação.

## Comandos

```bash
flutter test                  # núcleo, estado e contrato do protocolo
flutter analyze
flutter run -d linux
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

`CONTROL_TOWER_APK=/caminho.apk` força o APK usado por "Instalar e conectar".

## Armadilhas

- Sem `network_security_config` o Android 9+ recusa `ws://` em claro, sem mensagem útil.
- `adb shell` junta o argv numa string para o shell do aparelho: o JSON dos endereços vai
  entre aspas simples (`aspasShell`), senão chega sem as aspas duplas.
- No Android, abrir câmera ou seletor pausa o app; o WebSocket só fecha após 30 s em segundo
  plano, e reabrir a mesma conversa preserva citação e anexos do compositor.
- A bandeja é StatusNotifierItem: no GNOME exige a extensão AppIndicator (o Ubuntu já traz).
