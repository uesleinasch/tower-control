# Fase 14 do orquestrador: testes de interface com cliques reais

TickTask #534, a última subtarefa da #496. O pedido do Ueslei, em 05/11/2026, veio depois de um campo do
editor de rotinas parecer travado e depois funcionar sem nenhuma mudança no código. O `bun test` e o
`flutter test` estavam verdes, e só clicando deu para ver o problema.

As decisões dele estão marcadas como **(Ueslei)**. O que eu decidi sozinho está marcado como
**(decisão minha)**.

## Para que serve

Até aqui, cada fase foi testada no núcleo, ponta a ponta pelo WebSocket e na conferência visual do
Ueslei. Falta um robô que clique na interface de verdade, na web, no app desktop e no celular, e que
acuse sozinho o que ninguém viu quebrar:

- a tela que não responde ao clique;
- o campo que trava;
- o botão que manda a mensagem errada;
- a mudança que não chega no outro cliente.

## Objetivos

- Testes automatizados que clicam na interface real das três plataformas **(Ueslei)**.
- Um comando só, rodado quando o Ueslei pedir **(Ueslei)**. Não roda em build local nem no CI.
- Cada teste precisa fazer sentido **(Ueslei)**. O teste:
  - **começa no clique e termina no efeito real**: o arquivo gravado na pasta de dados, o commit, a
    tarefa no status certo ou a mensagem chegando no outro cliente. Não vale só "o botão apareceu";
  - **segue um uso real**, de ponta a ponta, escrito como cena;
  - **já viu dar errado**. Ao escrever cada cena, quebra-se de propósito a função que ela cobre, e o
    teste precisa ficar vermelho. A quebra feita e o resultado ficam registrados. Teste que nunca
    falhou não entra.
- As personas respondem por um **modelo falso**, sem gastar com o Claude **(Ueslei)**, mas só a
  "cabeça" é falsa (ver "O modelo falso").

## Fora desta fase

- Testar a qualidade das respostas do Claude real.
- Tocar na notificação do sistema Android. A aprovação pelo celular é feita na tela do app
  **(decisão minha)**: o `integration_test` não alcança a gaveta de notificações, e trazer outra
  ferramenta só para isso não compensa agora.
- As ações do desktop sobre systemd, journalctl e adb (`nucleo/acoes.dart`). Elas mexem na máquina
  e ficam com o teste de núcleo que já existe.
- Rodar no GitHub Actions.

## O que não pode acontecer

- **Encostar nos dados do Ueslei:**
  - a pasta de dados real;
  - o `ai-memory` em uso;
  - o TickTask real;
  - as sessões do Claude Code dele;
  - o app instalado no celular dele.
- **Teste verde com a função quebrada**: é o motivo da regra "já viu dar errado".
- **Teste que falha ao acaso**, por esperar tempo fixo em vez de esperar o estado certo.

## O modelo falso

Comprovado num teste descartável em 05/11/2026:

- o servidor do control-tower subiu com `ANTHROPIC_BASE_URL` apontando para um servidor local
  falso e `ANTHROPIC_API_KEY` falsa;
- o Claude Code de verdade conversou com ele;
- o falso respondeu ao Alfred com uma chamada `Bash`;
- o hook de aprovação de verdade mandou a `permissao` pelo WebSocket;
- a aprovação fez o comando rodar.

Então o caminho inteiro roda de verdade: o SDK, os hooks, a política de aprovação, as ferramentas
MCP (`comentar`, `devolver`, `aprovar`, `pedir_mudanca`, `delegar`) e as skills. Só a resposta do
modelo é programada.

- O falso fala a API de mensagens da Anthropic com streaming. Ele devolve texto e chamadas de
  ferramenta, e aceita o `count_tokens`.
- A resposta vem de um **roteiro** que cada cena carrega antes de agir, por uma rota de controle do
  próprio falso. O roteiro é uma lista de regras do tipo "quando a mensagem for desta persona e
  contiver tal texto (ou a última coisa for o resultado de tal ferramenta), responda com isto". O
  formato exato fica com quem implementar.
- O falso registra cada pedido recebido. A cena pode conferir o que a persona recebeu, por exemplo
  que o bloco `<tarefa>` levou o plano aprovado, ou que a lista de skills da chamada tem a skill
  anexada.
- Pedido sem regra que case é erro da cena, com o pedido no relatório. O falso nunca inventa uma
  resposta.

## Isolamento

Cada rodada sobe, numa porta própria:

- o servidor do control-tower, com `CT_DADOS` numa pasta de dados montada do zero pelo próprio teste;
- o modelo falso;
- um TickTask falso, um servidor MCP HTTP com as ferramentas que o espelho usa, apontado por
  `CT_TICKTASK_CONFIG`.

No fim, apaga tudo. O isolamento também cobre:

- `CT_MEMORIA_URL` aponta para uma porta sem nada, e o brief de memória sai vazio, como já acontece
  com o daemon fora do ar. A consolidação e o sonho não podem gravar no `ai-memory` real.
- `CLAUDE_CONFIG_DIR` aponta para uma pasta temporária, para as sessões do SDK não caírem no
  `~/.claude` do Ueslei. O `sessao-sdk.ts`, que apaga o `.jsonl` da sessão ao excluir uma conversa,
  monta hoje o caminho a partir de `~/.claude`. Ele passa a respeitar `CLAUDE_CONFIG_DIR`, senão
  apagaria no lugar errado.
- `ANTHROPIC_BASE_URL` e `ANTHROPIC_API_KEY` vão só para o servidor de teste.

## As três plataformas

**Web.** O Playwright, num navegador sem janela, abre o servidor de teste e clica como o Ueslei
clicaria. Ele fica num pacote próprio, fora das dependências do app, e roda pelo Node
**(decisão minha)**. Tira uma captura na falha.

**Desktop.** É onde está a maior parte, porque toda a edição vive no desktop. O `integration_test`
do Flutter roda o app de verdade sob o `xvfb-run`, sem tomar a tela do Ueslei.

- O app precisa apontar para a porta do servidor de teste. Hoje ele conecta em `127.0.0.1` na porta
  configurada. Se for preciso, ganha um jeito de receber a porta só no teste, sem mudar o uso normal
  **(decisão minha)**.
- O teste espera o estado certo com `pumpAndSettle` ou condições, e nunca com `sleep` fixo.

**Celular**, no aparelho do Ueslei conectado pelo cabo **(Ueslei)**:

- O teste instala uma versão separada do app, com outro id de pacote (`dev.ueslei.controltower.teste`,
  nome "Control Tower teste"). Isso é obrigatório: o `integration_test` instala um APK, e com o
  mesmo id e a mesma chave ele passaria por cima do app do dia a dia, com a configuração dele.
- O aparelho alcança o servidor de teste pelo `adb reverse`, sem depender da rede.
- Se não houver aparelho conectado e desbloqueado, a parte do celular é pulada com um aviso claro,
  e isso não conta como falha.
- Ao terminar, a versão de teste é desinstalada **(decisão minha)**.

## As cenas

As cenas de prioridade são as duas que o Ueslei apontou **(Ueslei)**: a aprovação do Alfred e os
workflows. Elas cobrem também as variações, e as outras cobrem o caminho principal.

**1. Chat.** Na web e no celular: abrir a conversa com a Nati, mandar uma mensagem e ver os balões
chegando em streaming, separados pelo `---`. A conversa fica gravada. Também se anexa um arquivo,
e o anexo aparece no pedido que o falso recebeu.

**2. Aprovação do Alfred (prioridade).**
- O Alfred pede um comando, o celular mostra o pedido e o Ueslei aprova na tela. O comando roda, o
  que se confere por um arquivo criado pelo comando.
- O mesmo pedido negado: o comando não roda.
- Com o chat fechado e ninguém olhando a conversa, o pedido vira aviso, e a aprovação pelo aviso
  vale.
- No modo auto, um comando comum passa sem pedir, e um comando sensível (`exigeAprovacaoSempre`)
  pede mesmo assim.
- O comando pedido dentro de uma tarefa chega a todos os clientes com o `tarefaId`.

**3. Personas e organograma (desktop).** Criar uma persona e criar uma equipe. Ligar as caixas pelo
"responde a" e salvar: o `equipe.json` fica certo e há o commit. Excluir a persona exige digitar o
nome, e as conversas dela viram só leitura.

**4. Tarefas e runtime.** Criar uma tarefa na web para uma posição. A persona falsa executa, e a
tarefa chega em revisão com a entrega. Um comentário do Ueslei devolve a tarefa, e a nova entrega
volta.

**5. Governança.** Com o orçamento da persona estourado, a tarefa fica na fila, e o painel diz por
quê. Pausar e retomar pelo painel. Na aprovação do plano, o plano aparece, o Ueslei aprova, e a
execução seguinte recebe o plano no `<tarefa>`.

**6. Revisão e aprovação.** A revisora pede mudança pela ferramenta `pedir_mudanca`, a tarefa volta
para a executora, e a nova entrega volta para a mesma revisora. A aprovação final é do Ueslei, pelo
celular. Numa variação, o board é a etapa de revisão, e a síntese decide.

**7. Rotinas (desktop).** O travamento foi no desktop, e o Ueslei não lembra qual campo era nem o que
acontecia em volta **(Ueslei)**. Por isso a cena digita em todos os campos do editor duas vezes:

- uma com o servidor quieto;
- outra com coisas chegando enquanto se digita **(decisão minha)**, que são as causas prováveis de um
  campo travar sem mudança de código:
  - publicações do painel e de tarefas (rebuild);
  - uma rotina disparando;
  - a reconexão do socket.

Ao salvar, o `rotina.json` precisa ter exatamente o que foi digitado. Depois a rotina é disparada à
mão e pelo webhook com o token, e cada disparo cria a tarefa e aparece no histórico.

**8. Painel.** Um item do "Precisa de você" é resolvido pela ação dele, e a web e o celular se
atualizam juntos.

**9. Workflows (prioridade).**
- Montar no editor do desktop um workflow com executar, condição, paralelo, junção, decisão humana e
  fim, ligando as caixas.
- Uma ligação inválida mostra o erro preso à caixa, e o salvar fica recusado até corrigir.
- Salvar (o JSON e o commit) e iniciar.
- A caixa executar devolve as saídas pela ferramenta `devolver`, e a condição segue pelo ramo certo.
  Uma segunda rodada devolve o outro valor e pega o outro ramo.
- O paralelo abre duas tarefas e a junção espera as duas.
- A decisão humana é tomada no celular, e o fluxo termina.
- Variações:
  - o laço para no limite de voltas;
  - cancelar uma tarefa do fluxo cancela o fluxo;
  - terminar sem `devolver` conta como falha.

**10. Skills (desktop).** Criar uma skill e anexar a uma persona. Na conversa seguinte, o pedido que o
falso recebe traz a skill. Quando o falso chama a ferramenta `Skill`, o conteúdo da skill volta no
resultado.

**11. Espelho.** Ligar o espelho na Configuração. Um item do "Precisa de você" aparece no TickTask
falso. Finalizar lá faz a ação aqui, e resolver aqui finaliza lá.

**12. Modelos (desktop).** Exportar uma equipe para arquivo e importar como nova, resolvendo uma
colisão de persona. A equipe nova aparece no organograma com o workflow.

A cena 3 (desktop) e a cena 4 (web) usam a mesma rodada de servidor quando faz sentido. Quem
implementar decide como agrupar as cenas por rodada.

### Regras que valem para todas as cenas (decisões minhas, depois da leitura do revisor)

- **"O outro cliente" é a interface de verdade, não uma sonda.**
  - Nas cenas 2 (comando de tarefa chegando a todos) e 8 (a web e o celular juntos), uma plataforma
    age e a outra confere a tela.
  - A web e o desktop rodam juntos na máquina. Eles se encontram por uma rota de controle do modelo
    falso: um ponto de encontro simples, com nome por cena.
  - Sem celular conectado, só a metade do celular é pulada.
- **Aprovação pelo aviso (cena 2).**
  - O app de teste escuta o `/avisos` com o próprio serviço de avisos, o que também garante que o
    comando espere em vez de ser negado.
  - O teste chama o mesmo tratador que o toque na notificação chamaria (`Notificador`/resposta ao
    aviso em `cliente/lib/sistema/`), e ele faz o `POST /avisos/<id>/acao`.
  - Só a gaveta do sistema fica de fora.
- **Plataforma de cada cena.**
  - O celular roda só os passos marcados como dele: as cenas 1, 2 e 8, a aprovação final da cena 6
    e a decisão humana da cena 9.
  - O resto da 6 e as cenas 4 e 5 rodam na web. A 11 roda no desktop.
  - Sem aparelho, os passos do celular não são repetidos no desktop: são pulados com aviso.
- **Seletor de arquivos.**
  - No Flutter, `FilePicker.pickFiles` e `FilePicker.saveFile` são trocados por um falso dentro do
    teste. O anexo da cena 1 e o exportar e importar da cena 12 seguem pelo resto do caminho
    verdadeiro.
  - Na web, o Playwright preenche o `input` de arquivo.
- **Isolamento do app desktop de teste.**
  - Ele roda sob o xvfb com `HOME` e `XDG_*` temporários. Assim não encosta no socket de instância
    única, nas preferências nem no autostart da instalação do dia a dia.
  - O `adb reverse` que o app do Ueslei já usa não é removido. O teste acrescenta a porta dele e
    tira só essa no fim.
- **Chamadas em segundo plano.** As chamadas ao modelo que não vêm de um clique também entram no
  roteiro da cena que as provoca, como a geração do perfil ao criar uma persona e a consolidação ao
  abrir uma conversa nova.

## O comando e o relatório

- `bash scripts/testes-de-interface.sh` roda tudo. Com um argumento, roda só uma plataforma ou uma
  cena.
- O resultado sai por cena e plataforma: passou, falhou ou pulou (o celular sem aparelho), com o
  tempo de cada uma. Na falha, mostra o que era esperado, o que aconteceu, a captura quando a
  plataforma permite e o caminho do log do servidor e do falso.
- `docs/testes-de-interface.md` lista as cenas e o que cada uma prova. Para cada cena, registra a
  quebra feita de propósito, a data e o resultado vermelho.

## Testes desta fase

A própria bateria é o entregável. Além dela:

- `bun test` cobre o núcleo do modelo falso: o casamento das regras do roteiro e o formato do stream.
- O teste do protocolo continua valendo. Se o falso ou o teste precisarem de algum tipo novo no
  WebSocket, ele entra pelo caminho normal: a lista e os três clientes.
