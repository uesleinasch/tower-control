# Testes de interface

Bateria de cenas com cliques reais na web (Playwright), no app desktop (`integration_test` sob o Xvfb) e no app do celular (`integration_test` no aparelho, pacote `dev.ueslei.controltower.teste`). O servidor de teste roda com dados próprios, o modelo falso e o TickTask falso de `app/interface/falsos/`. Nada encosta em `~/.local/share/control-tower`, no ai-memory, em `~/.config/ticktask`, em `~/.claude` nem no app `dev.ueslei.controltower`.

Spec: `docs/superpowers/specs/2026-11-05-testes-de-interface-design.md`.

## O comando

```bash
bash scripts/testes-de-interface.sh [web|desktop|celular|conjuntas] [cena]
```

- Sem argumento, roda as quatro etapas em ordem: `web`, `desktop`, `celular` e `conjuntas`.
- O segundo argumento filtra pelo nome do teste: `-g` no Playwright e `--plain-name` no Flutter. Nas `conjuntas`, o filtro vira `conjunta: <cena>`, por exemplo `bash scripts/testes-de-interface.sh conjuntas "cena 8"`.
- Só roda quando o Ueslei pede. Não há build local nem CI dessa bateria.

Variáveis opcionais:

| Variável | Para quê |
|---|---|
| `CT_SERIAL` | escolhe o aparelho quando há mais de um no `adb devices` |
| `FLUTTER` | caminho do `flutter` (padrão `~/flutter/bin/flutter`) |
| `AAPT` | caminho do `aapt` (padrão: o mais novo em `~/Android/Sdk/build-tools/`) |
| `CT_MANTER_PASTA` | mantém a pasta da rodada mesmo quando tudo passa |

### O que precisa estar instalado

- Bun, `jq` e `curl`.
- Node com `npx`, e o pacote das cenas da web: `cd app/interface/web && npm ci && npx playwright install chromium`.
- Flutter em `~/flutter/bin` (ou `FLUTTER`).
- No desktop: `xvfb-run`, `xdotool`, `xmodmap` e `dbus-run-session`. O script confere e diz o que falta.
- No celular: `adb`, o `aapt` do Android SDK e o aparelho conectado, **desbloqueado e com a tela acesa**. Sem aparelho, ou com a tela bloqueada ou apagada, a etapa sai `pulou` com o motivo, e não `falhou`.

### Como cada etapa roda

- **web.** O próprio Playwright sobe um ambiente por arquivo de cena (`subirCena` em `app/interface/web/apoio.ts`) dentro da pasta da rodada. Ao descer, guarda o `servidor.log` e o `GET /_controle/sem-regra` ao lado.
- **desktop.** Ambiente novo por rodada (o id de persona excluída fica reservado), `XDG_*` em `/tmp/ct-xdg-*` (o socket da instância única não cabe no caminho da pasta do ambiente) e `xvfb-run -a env XDG_*=… dbus-run-session -- flutter test integration_test/desktop_test.dart -d linux`. O app de teste recusa `XDG_*` fora de pasta de teste (`exigirXdgDeTeste`).
- **celular.** O script:
  1. confere o aparelho e a tela (`dumpsys window` com `mDreamingLockscreen=false` e sem `isKeyguardShowing=true`, e `dumpsys power` com `mWakefulness=Awake`);
  2. faz o build com `CT_APP_TESTE=1` e confere pelo `aapt` que o pacote é `dev.ueslei.controltower.teste` antes de instalar com `adb install -r`;
  3. dá o `pm grant` do `POST_NOTIFICATIONS` só ao pacote de teste;
  4. acrescenta o `adb reverse` das duas portas da rodada (servidor e modelo falso);
  5. roda `flutter test integration_test/celular_test.dart -d <serial> --no-uninstall` com `CT_APP_TESTE=1` no ambiente e o `ambiente.json` em base64 no `--dart-define=CT_AMBIENTE_JSON`;
  6. confere os arquivos que a cena 2 deixa na pasta do ambiente (`cena2.txt`, `cena2-aviso.txt`, `cena2-auto.txt`, e nenhum `cena2-negado.txt`).

  Nunca use `flutter install`, `flutter run` ou `flutter test -d` sem `CT_APP_TESTE=1`: o `flutter install` desinstala a versão antiga do pacote do APK e apagaria o app de verdade.
- **conjuntas.** Um ambiente só, com as três plataformas ao mesmo tempo (`painel.spec.ts` com `CT_AMBIENTE_DE_PE`, e os testes `conjunta:` do desktop e do celular com `CT_LADOS`). Os lados se sincronizam pelo `POST /_controle/encontro` do modelo falso, com nova tentativa no 408 até 10 minutos, porque os builds do Flutter levam mais que os 90 s do encontro. Sem aparelho, a lista de lados fica `web,desktop` e a metade do celular sai `pulou`.

### O relatório

- A pasta da rodada é `/tmp/ct-interface-<data>`. Ela só é apagada se nada falhar.
- `resultado.tsv` tem uma linha por etapa e plataforma: `passou`, `falhou` ou `pulou`, com os segundos e o motivo. Uma rodada interrompida ganha a linha `rodada - interrompida`.
- Na falha, o script imprime as cenas vermelhas (`✘` do Playwright, `[E]` do Flutter), o log da plataforma, as capturas (`web-resultados/` do Playwright; `<pasta>/capturas/` do Flutter quando houver), o `servidor.log` e o `sem-regra` do modelo falso.

### O `trap`

Ao sair por qualquer motivo, o script:
- encerra cada plataforma e cada `subir.ts` pelo grupo de processos do pid guardado (`TERM`, depois `KILL` se o grupo não sumir), nunca por `pkill -f`;
- tira só as portas de `adb reverse` que ele acrescentou;
- desinstala o `dev.ueslei.controltower.teste`, se instalou;
- apaga as `/tmp/ct-xdg-*` da rodada.

Num terminal, o Ctrl-C chega ao script. Num shell não interativo, o bash ignora o `SIGINT` dos comandos em segundo plano, então `bash scripts/testes-de-interface.sh web & sleep 20; kill -INT %1` não interrompe nada: use `set -m` antes (como no terminal) ou `kill -TERM`. Os dois caminhos foram testados em 05/11/2026: depois do sinal, o `ss -ltnp` ficou igual ao de antes, o `adb reverse --list` continuou vazio e não sobrou `subir.ts`, servidor, Chromium nem pasta de ambiente.

## Registro das sabotagens

Toda cena entrou na bateria depois de ficar vermelha com uma quebra de propósito. Cada quebra foi revertida com `git checkout -- <arquivo>` (ou pela cópia guardada), com o `git diff` limpo depois, e nenhuma foi comitada. A "primeira linha vermelha" é a primeira linha da falha. Todas as datas são de 05/11/2026.

### Servidor de teste (fumaça)

| Cena | Plataforma | O que prova | Sabotagem | Primeira linha vermelha |
|---|---|---|---|---|
| fumaça do ambiente | servidor (`bun run interface/fumaca.ts`) | o servidor de teste sobe isolado e o comando do Alfred pede permissão antes de rodar | `hookDeComando` (`sessions.ts`) com `const liberado = true` | `fumaça falhou: o comando rodou sem pedir permissão` |

### Web (Playwright)

| Cena | Plataforma | O que prova | Sabotagem | Primeira linha vermelha |
|---|---|---|---|---|
| cena 1: mensagem para a Nati vira balões e fica gravada | web | a resposta se divide em balões na tela e no `.jsonl` | `normalizar` (`ritmo.ts`) com `saida += "\n"` no lugar de `"\n---\n"` | `Error: expect(locator).toHaveText(expected) failed` (um balão `"um\ndois"`) |
| cena 1: anexo chega ao modelo | web | o anexo vai para `conversations/anexos/` e o caminho chega ao modelo | `resolverAnexos` (`server.ts`) com `return []` | `Error: expect(received).toContain(expected) // indexOf` |
| cena 4: tarefa criada na web volta em revisão com a entrega, e o comentário devolve | web | a entrega leva a tarefa a `em_revisao` e o comentário a devolve | `rodar` (`runtime.ts`): o `this.repo.devolver(...)` da entrega trocado por `return` | `Error: expect(locator).toContainText(expected) failed` (`Status: em andamento`) |
| cena 5: orçamento estourado segura a fila e o painel diz por quê | web | o despachante segura a execução e o painel mostra o motivo | `motivoDeBloqueio` (`governanca.ts`) devolve `null` | `Error: expect(locator).toContainText(expected) failed`, esperando `na fila: Alfred sem orçamento` |
| cena 5: pausar e retomar pelo painel | web | a pausa grava e chega a todos | `pausar` (`repositorio.ts`) sem o `INSERT` | `Error: prazo de 60000 ms estourado esperando a mensagem "orquestra"` |
| cena 5: plano aprovado chega na execução seguinte | web | o plano aprovado vai no `<tarefa>` | `blocoDaTarefa` (`execucao.ts`) sem a linha do `plano_aprovado` | `Error: expect(locator).toContainText(expected) failed`, esperando `executei o plano` |
| cena 6: mudança volta à executora e a nova entrega volta à mesma revisora | web | o `retorno` leva a nova entrega à etapa que pediu a mudança | `aposEntrega` (`politica.ts`) devolve sempre `etapa: 0` | `Error: expect(locator).toHaveCount(expected) failed` (2 esperados, 3 recebidos) |
| cena 6: board como revisão decide pela síntese | web | a síntese do board aprova ou pede mudança | `decisaoDaSintese` (`politica.ts`) devolve `null` | `Error: expect(locator).toContainText(expected) failed`, esperando `DECISÃO: aprovar` |

### Desktop (`integration_test` sob o Xvfb)

| Cena | Plataforma | O que prova | Sabotagem | Primeira linha vermelha |
|---|---|---|---|---|
| desktop: sobe sem bandeja, conecta no servidor de teste e lista as personas | desktop | o app de teste sobe sem bandeja, só com `XDG_*` de teste, e conecta na porta da rodada | fumaça sob o xvfb com `env -u XDG_DATA_HOME -u XDG_CONFIG_HOME` (prova a guarda `exigirXdgDeTeste`) | `Bad state: XDG_DATA_HOME="" não é uma pasta de teste: o app gravaria nas preferências do app instalado` |
| cena 3: persona e equipe criadas pelo organograma ficam no disco | desktop | o organograma grava `equipe.json` e `persona.json` | `completarLayout` (`equipe.ts`) devolve as posições com `respondeA: null` | `Expected: 'execucao'  Actual: <null>` |
| cena 3 (commit da equipe) | desktop | a equipe salva vira commit no git dos dados | `salvarEquipe` (`server.ts`) sem o `registrarNoGit` | `prazo de 30000 ms estourado esperando o commit da equipe Teste no git dos dados (último erro: Bad state: o último commit é "dados: perfil de Vera gerado")` |
| cena 3 (defeito real: aviso com Desfazer preso) | desktop | o aviso do organograma some e a recusa do nome errado aparece | tira o `persist: false` do aviso do organograma | `prazo de 30000 ms estourado esperando a recusa do nome errado` |
| cena 7: editor de rotinas guarda exatamente o que foi digitado, com o servidor quieto | desktop | o campo não trava nem embaralha com o teclado real (`xdotool`) | o `TextField` do título usa `TextEditingController(text: rotina.titulo)` a cada build | `prazo de 15000 ms estourado esperando as teclas chegarem ao campo ( e decisões ({datConferir pendências)` |
| cena 7: e com o servidor publicando enquanto se digita | desktop | publicações, disparos e reconexão no meio do campo não mudam o que foi digitado | o controller do título recriado só quando `estado.lista` muda | `Which: at location ['tarefa']['titulo'] is 'e decisões ({data})Conferir pendências' instead of 'Conferir pendências e decisões ({data})'` |
| cena 7, publicando (defeito real: reconexão tirava o usuário da tela) | desktop | a reconexão reabre a conversa sem levar a tela para o chat | volta o `ir(Tela.chat)` no `ConversaAberta` (`sala.dart`) | `prazo de 5000 ms estourado esperando A finder ... with text "Nome". continuar na tela depois do ruído` |
| cena 7: disparo manual e pelo webhook criam a tarefa | desktop | o disparo à mão e o webhook com token criam a tarefa | `AGENDADOR.webhook` devolve 403 | `Expected: <202>  Actual: <403>` |
| cena 10: skill criada e anexada chega à persona e abre | desktop | a skill anexada vai no pedido e o conteúdo volta pela ferramenta `Skill` | `skillsDaChamada` com `return null` | `Expected: contains 'Skill'  Actual: ['Edit', ...]` |
| cena 9: workflow montado no editor salva, inicia e segue pelo ramo devolvido (ramo) | desktop | a condição segue pelo ramo do `devolver` | `motor.ts`: a condição conclui sempre com `QUANDO_SENAO` | `prazo de 90000 ms estourado esperando as tarefas de executar-2 e executar-3 criadas` |
| cena 9, editor (erro preso à caixa) | desktop | a ligação inválida mostra o erro na caixa e desliga o Salvar | `validarRascunho` (`editor_de_workflow.dart`) sem a regra "a junção precisa de 2 ou mais ligações entrando" | `prazo de 30000 ms estourado esperando o erro "a junção precisa de 2 ou mais ligações entrando" preso à caixa juncao (último erro: Bad state: erros do rascunho: {})` |
| cena 9, editor (junção) | desktop | a junção espera as duas entradas | `motor.ts`: `ficha.chegadas.length >= 1` no lugar de `>= precisa` | `Expected: 'esperando'  Actual: 'concluida'` |
| cena 9: a outra rodada segue pelo outro ramo | desktop | a segunda rodada pega o outro ramo | `motor.ts`: `const regra = no.regras[0]`, sem avaliar | `prazo de 90000 ms estourado esperando o fluxo concluído (último erro: Bad state: o fluxo #1 está rodando: [executar concluida, condicao concluida, paralelo concluida, executar-2 esperando, executar-3 esperando])` |
| cena 9: laço para no limite | desktop | o laço para em `maxVoltas` | `motor.ts:215`: `const repetir = avaliar(no.enquanto, contexto)`, sem `voltas <= no.maxVoltas` (ver nota abaixo) | `prazo de 90000 ms estourado esperando o fluxo concluído (último erro: Bad state: o fluxo #1 está rodando: [voltas concluida, tentar concluida, voltas concluida, tentar concluida, voltas concluida, tentar esperando])` |
| cena 9: cancelar uma tarefa do fluxo cancela o fluxo | desktop | cancelar a tarefa cancela o fluxo inteiro | `motor.ts`: `aoCancelar` sem o `this.cancelar` | `prazo de 90000 ms estourado esperando o fluxo cancelado (último erro: Bad state: o fluxo #1 está rodando: [esperar esperando])` |
| cena 9: terminar sem devolver é falha | desktop | a caixa com `saidas` que termina sem `devolver` falha | `runtime.ts` sem `if (saidas && !devolvido && !pedidoDeAjuda) throw new Error(SEM_DEVOLUCAO)` | `prazo de 90000 ms estourado esperando a falha SEM_DEVOLUCAO na tela da tarefa` |
| cena 11: espelho sobe o item, finalizar lá age aqui e resolver aqui finaliza lá | desktop | o item do "Precisa de você" sobe para o TickTask falso | `acaoDo` (`espelho.ts`) começa com `return null as never` | `prazo de 90000 ms estourado esperando "[CT] #1 espera sua aprovação" no TickTask falso` (só a subida tem vermelho próprio; puxar e fechar não) |
| cena 11 (defeito real: Configuração sem respingo) | desktop | os interruptores da Configuração pintam sobre o próprio `Material` | volta o `Container` com `BoxDecoration(color:)` no bloco (`configuracao.dart`) | `ListTile background color or ink splashes may be invisible.` |
| cena 12: exportar e importar como nova, resolvendo a colisão | desktop | o modelo importado cria a equipe nova com a persona renomeada | `planejar` (`modelos.ts`) com `if (false)` no lugar de `if (acao.nome?.trim())` | `prazo de 30000 ms estourado esperando a prévia com a Natália e sem erros (último erro: Bad state: erros da prévia: [persona Nati: já existe uma persona com o id nati; use a daqui ou escolha outro nome])` |
| guarda do Xvfb no teclado real | desktop | o `xdotool` só roda se o `DISPLAY` for de um Xvfb | **sem vermelho registrado** | provar a guarda exigiria rodar o `xdotool` no display real, com risco de digitar no app instalado. A guarda é a primeira linha das duas funções que chamam o `xdotool` |

**Por que a sabotagem do laço foi em `motor.ts` e não em `MAX_VOLTAS_DO_LACO`.** A constante `MAX_VOLTAS_DO_LACO` (`workflow.ts`) só limita o valor de `maxVoltas` que a validação aceita (de 1 a 20). Ela não entra na execução: quem para o laço é a comparação `voltas <= no.maxVoltas` em `motor.ts:215`. Mudar a constante deixaria a cena verde, porque o workflow da cena usa `maxVoltas: 2`, que continua válido. Tirar a comparação faz o laço repetir sem parar, e é isso que a cena precisa pegar.

### Celular (`integration_test` no aparelho)

Rodados no aparelho `0088238899`, cada sabotagem num ambiente novo e só com o teste dela (`--plain-name`).

| Cena | Plataforma | O que prova | Sabotagem | Primeira linha vermelha |
|---|---|---|---|---|
| cena 1 (celular): mensagem para a Nati vira balões | celular | o app divide a resposta em balões e mostra uma tela por vez | `dividirBaloes` (`baloes.dart`) devolve `[texto.trim()]` | `prazo de 60000 ms estourado esperando o balão "dois" no fim do turno` |
| cena 2 (celular): Alfred pede, celular aprova, comando roda | celular | o Permitir do cartão libera o comando | `resolverPermissao` (`server.ts`) com `soltarPermissao(id, false, como)` | `Expected: false  Actual: <true>` |
| cena 2 (celular): negado não roda | celular | o Negar do cartão barra o comando | `resolverPermissao` com `soltarPermissao(id, true, como)` | `Expected: true  Actual: <false>` (o falso recebeu `cena2-negado`) |
| cena 2 (celular): pelo aviso, com o chat fechado | celular | o aviso aparece na bandeja e o botão do aviso aprova pelo `POST /avisos/<id>/acao` | `Notificador.executar` (`notificador.dart`) com `return;` antes do `postarAcao` | `prazo de 15000 ms estourado esperando o permissao-resolvida do servidor depois do toque no aviso` |
| cena 2 (celular): no auto, comum passa e sensível pede | celular | no auto, o `echo` roda sem pedir e o `rm -rf` pede | `exigeAprovacaoSempre` (`comandos.ts`) devolve `false` | `prazo de 60000 ms estourado esperando o pedido de aprovação do comando sensível` |
| cena 2 (celular), no auto (defeito real: cabeçalho estourando a largura) | celular | o cabeçalho do chat cabe no celular com o auto ligado | o chip do auto com `auto · claude-opus-5-5` também no chat compacto (antes da correção `630078a4`) | `A RenderFlex overflowed by 12 pixels on the right.` |
| cena 6 (celular): aprovação final do Ueslei pelo celular | celular | o Aprovar do painel conclui a tarefa | `case "tarefa-decidir"` (`server.ts`) sem o `ORQUESTRA.decidir` | `prazo de 30000 ms estourado esperando #1 concluída no servidor` |
| cena 9 (celular): decisão humana tomada no celular termina o fluxo | celular | a opção tocada no celular é a que o fluxo segue | `MOTOR.decidir` (`motor.ts`) usa `no.opcoes[0]` no lugar de `opcao` | `Expected: contains pair 'opcao' => 'seguir'` (saiu `parar`) |

### Conjuntas (web, desktop e celular num ambiente só)

| Cena | Plataforma | O que prova | Sabotagem | Primeira linha vermelha |
|---|---|---|---|---|
| conjunta: cena 2, comando de tarefa chega a todos e o desktop aprova | web | a web cria a tarefa pela tela; o pedido chega com o `tarefaId`, o desktop aprova, a tarefa vai a `em_revisao` e o comando gravou o arquivo | `tratarComandoDeTarefa` (`server.ts`) manda o `permissao` só ao socket que criou a tarefa, no lugar do `mandarATodos` | `Error: prazo de 120000 ms estourado esperando a mensagem "permissao"` |
| conjunta: cena 2 | desktop | o pedido aparece na tarefa aberta no desktop, e o Permitir dele libera o comando | a mesma | `prazo de 180000 ms estourado esperando o pedido do comando da tarefa chegar ao desktop` |
| conjunta: cena 2 | celular | o pedido aparece na tarefa aberta no celular e sai da tela quando o desktop aprova | a mesma | `prazo de 180000 ms estourado esperando o pedido do comando da tarefa chegar ao celular` |
| conjunta: cena 8, item resolvido na web some do painel | web | o Aprovar do painel da web conclui a tarefa, e o item sai do painel da web | `publicarTarefa` (`server.ts`) sem o `agendarPainel()` | `Error: expect(locator).toHaveCount(expected) failed` |
| conjunta: cena 8 | desktop | o item resolvido na web sai do painel do desktop em até 5 s | a mesma | `prazo de 5000 ms estourado esperando o item de #1 sumir do painel do desktop depois da resolução na web` |
| conjunta: cena 8 | celular | o item resolvido na web sai do painel do celular em até 5 s | a mesma | `prazo de 5000 ms estourado esperando o item de #1 sumir do painel do celular depois da resolução na web` |

Notas das conjuntas:
- **Cena 8, primeira tentativa verde.** Tirar o `agendarPainel` só do `case "tarefa-decidir"` (trocando `publicarTarefa(id)` por um `mandarATodos` da tarefa) deixou a cena verde. A resolução passa pelo `aplicarDecisao` do runtime, que chama `publicarTarefa`, e é ali que mora o `agendarPainel`. Por isso a sabotagem registrada é no `publicarTarefa`.
- **Prazo de 5 s na cena 8.** O servidor também remonta o painel a cada 30 s (`setInterval(agendarPainel, 30_000)`). Com a sabotagem, esse relógio pode cair dentro dos 5 s e deixar a cena verde por acaso, com chance perto de 1 em 6.

### Testes de unidade que nasceram da fase

| Teste | Onde | Sabotagem | Primeira linha vermelha |
|---|---|---|---|
| pasta da sessão do SDK respeita `CLAUDE_CONFIG_DIR` | `bun test` | antes da mudança em `sessao-sdk.ts` | `Expected: true Received: false` |
| `resultadoDe` acha o `tool_result` antes da mensagem de sistema que o Opus põe no fim | `bun test` | antes da correção do falso | `Expected: "Bash"  Received: null` |
| reconexão não troca a tela (`Sala.tratar`) | `flutter test` | volta o `ir(Tela.chat)` no `ConversaAberta` | `Expected: Tela:<Tela.equipes>  Actual: Tela:<Tela.chat>` |
| pacote do teste no celular | `flutter test` | guarda com `if (false)` | `Expected: throws <Instance of 'StateError'>  Actual: <Closure: () => void>` |
| bloco da Configuração pinta sobre o próprio `Material` | `flutter test` | volta o `Container` com `BoxDecoration(color:)` | `ListTile background color or ink splashes may be invisible.` |
