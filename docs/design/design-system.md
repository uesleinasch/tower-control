# Design system do Control Tower

Este é o padrão visual e de interação do Control Tower, do app Flutter (desktop Linux e Android) e, nos tokens, da web. Ele aplica o Google Material Design 3 aos princípios de UI/UX levantados em duas referências:

- `docs/design/referencias-ui-ux.md`: princípios gerais, com fonte (NN/g, Laws of UX, Refactoring UI, WCAG 2.2);
- `docs/design/material-design.md`: Material 3 e a implementação no Flutter, com fonte.

Este documento decide. As referências explicam o porquê. Quando uma regra daqui contrariar uma referência, vale esta, e o motivo está escrito ao lado. Decisões que não vieram de nenhuma das duas estão marcadas como **(decisão)** e listadas no fim.

## 1. Para quem é

Pessoas de tecnologia com habilidade média, acostumadas a apps de celular e a programas de computador mais avançados, e programadores juniores. Daí saem quatro consequências:

- **Densidade é bem-vinda, ruído não.** O usuário lê uma tela cheia de informação, desde que a hierarquia diga o que importa primeiro (heurística 8 de Nielsen).
- **Padrões conhecidos vencem invenção.** Componentes Material sem customização, nos lugares onde esse usuário já os encontrou em outros apps (lei de Jakob).
- **Aceleradores para quem já sabe.** Atalhos de teclado, menu de contexto e ações em lote no desktop, sem esconder o caminho do novato (heurística 7).
- **Vocabulário do produto com consistência.** Persona, posição, equipe, tarefa, rotina e workflow sempre com o mesmo nome, ícone e cor.

## 2. Princípios

1. **Status sempre visível.** Tudo o que roda sozinho (tarefa, execução, fluxo, rotina, resposta do chat) mostra o estado atual, com cor, ícone e texto.
2. **O que precisa do Ueslei vem primeiro.** Aprovações, decisões e bloqueios têm o maior peso visual da tela em que aparecem.
3. **Nunca só cor.** Todo estado combina cor, ícone e rótulo, inclusive no grafo.
4. **Desfazer em vez de confirmar.** Ação reversível acontece na hora e oferece "Desfazer". Diálogo de confirmação só para o que não volta.
5. **Um token para cada decisão.** Cor, espaço, raio, tipo, duração e ícone saem de tokens nomeados. Valor solto no código é defeito.
6. **Desktop é desktop.** Hover, foco por teclado, tooltips, atalhos e janelas de qualquer largura são requisito, não extra.

## 3. Cor

### 3.1 Esquema

- Seed: `#5B8DEF` (o azul atual), variante `DynamicSchemeVariant.tonalSpot`.
- Claro e escuro saem da mesma seed. O app segue o tema do sistema (`ThemeMode.system`, que já é o comportamento atual), e o tema escuro é o mais testado.
- **Nenhum papel sobrescrito à mão.** Hoje o `tema.dart` sobrescreve `surface`, `onSurface`, `onSurfaceVariant` e `primary`, o que quebra a coerência tonal e tira a garantia de contraste do esquema gerado. As cores de fundo, painel e borda passam a ser papéis do esquema (tabela 3.2).
- Alto contraste como opção futura de Configuração: `contrastLevel: 1.0` na mesma seed.

### 3.2 Onde cada papel entra

| Uso | Papel | Substitui no tema atual |
|---|---|---|
| Fundo da janela | `surface` | `fundo` (`#10131A` / `#F5F7FA`) |
| Painéis, barras de navegação, lista lateral | `surfaceContainer` | `painel` |
| Cartões sobre o fundo | `surfaceContainerLow` | |
| Menus, diálogos, sheets | `surfaceContainerHigh` | |
| Campos preenchidos, balão do Ueslei no chat | `surfaceContainerHighest` | `surfaceContainerHighest` manual |
| Texto principal | `onSurface` | |
| Texto secundário, metadados, ícone inativo | `onSurfaceVariant` | |
| Borda de campo, divisor forte | `outline` | |
| Divisor sutil, borda de cartão | `outlineVariant` | `borda` |
| Ação principal, foco, seleção | `primary` / `onPrimary` | `_acento` |
| Indicador de navegação, botão tonal, chip selecionado | `secondaryContainer` / `onSecondaryContainer` | |
| Destaque de "precisa de você" | `tertiaryContainer` / `onTertiaryContainer` | |
| Erro e ação destrutiva | `error`, `errorContainer` | `perigo` |
| Snackbar e tooltip | `inverseSurface` / `onInverseSurface` | |

Camadas se separam por tom de superfície e borda `outlineVariant`, não por sombra (seção 7).

### 3.3 Cores semânticas

O M3 só tem `error`. Sucesso, aviso e informação entram como `ThemeExtension<CoresSemanticas>`, cada uma com quatro papéis (cor, sobre-cor, container, sobre-container), geradas de uma paleta tonal com os mesmos tons dos papéis do M3 (claro 40/100/90/10, escuro 80/20/30/90) e harmonizadas com a seed (`Blend.harmonize`).

| Semântica | Cor de origem **(decisão)** | Uso |
|---|---|---|
| `sucesso` | `#2E9E5B` | Concluída, aprovada, execução terminada |
| `aviso` | `#D99A1E` | Bloqueada, orçamento em 80%, atrasada, espera longa |
| `info` | papéis `primary` | Mensagem neutra, dica |
| erro | papéis `error` | Falha, recusa, ação destrutiva |

Toda cor semântica sai acompanhada de ícone e texto.

### 3.4 Estados do domínio

Hoje cada tela tem a sua função de cor (`_corDoEstado` no painel, `corDaFicha` e `corDoFluxo` nos workflows, `_corDoResultado` nas rotinas). Elas passam a usar um mapa único, no núcleo:

| Estado | Papel | Ícone (Material Symbols) |
|---|---|---|
| backlog | `onSurfaceVariant` | `inventory_2` |
| a fazer, na fila | `secondary` | `schedule` |
| em andamento, rodando | `primary` | `progress_activity` (animado) ou `play_circle` |
| em revisão, esperando aprovação | `tertiary` | `rate_review` |
| bloqueada, pausada | `aviso` | `block` / `pause_circle` |
| concluída, aprovada | `sucesso` | `check_circle` |
| cancelada, interrompida | `onSurfaceVariant` | `cancel` |
| falhou, recusada | `error` | `error` |

O texto do estado sempre aparece ao lado do ícone, num chip ou num rótulo `labelMedium`, exceto em espaço mínimo (nó do grafo em zoom baixo). Nesse caso o ícone vai com tooltip.

### 3.5 Cor das personas

A cor da persona (`persona.json` ou `corDaPersona`) é identidade, não estado. Ela só aparece no avatar, no marcador do nome e na borda do nó da persona no organograma. Nunca colore um estado, um botão nem um texto longo. Texto sobre a cor da persona usa preto ou branco, o que der contraste de 4,5:1.

### 3.6 Contraste

Texto 4,5:1 (3:1 a partir de 18 sp, ou de 14 sp em negrito). Ícone informativo, borda de componente e indicador de foco 3:1. Os pares gerados pelo esquema já cumprem isso. As semânticas, as cores de persona e qualquer exceção precisam ser medidas nos dois temas.

## 4. Tipografia

### 4.1 Famílias

- **Inter**, empacotada em `assets/fonts/` (sem `google_fonts`, para não depender de rede nem trocar de fonte na primeira abertura). Pesos 400, 500 e 600. Licença OFL 1.1 registrada no `LicenseRegistry`.
- **JetBrains Mono** **(decisão)**, empacotada, pesos 400 e 500, para código, comandos, logs, ids e JSON. Hoje o app usa `'monospace'`, que muda de fonte entre Linux e Android. A JetBrains Mono tem licença OFL e altura-x parecida com a da Inter.
- As fontes de marca já declaradas no pubspec (Trajan Pro, Schyler) ficam restritas à marca e nunca aparecem na interface de trabalho.

### 4.2 Escala

A escala é a do M3, com os mesmos tamanhos e alturas de linha, e só estes nove estilos são usados:

| Token | Estilo M3 | Tamanho / linha (sp) | Peso | Uso |
|---|---|---|---|---|
| `titulo-tela` | `titleLarge` | 22 / 28 | 500 **(decisão)** | Título da tela e da app bar |
| `titulo-secao` | `titleMedium` | 16 / 24 | 600 **(decisão)** | Seção, cartão, diálogo |
| `titulo-item` | `titleSmall` | 14 / 20 | 500 | Item de lista, nó do grafo |
| `corpo-grande` | `bodyLarge` | 16 / 24 | 400 | Mensagens do chat no celular |
| `corpo` | `bodyMedium` | 14 / 20 | 400 | Texto padrão, chat no desktop |
| `corpo-pequeno` | `bodySmall` | 12 / 16 | 400 | Metadados, legendas |
| `rotulo` | `labelLarge` | 14 / 20 | 500 | Botões, abas |
| `rotulo-medio` | `labelMedium` | 12 / 16 | 500 | Chips, estados, badges |
| `numero-destaque` | `headlineSmall` | 24 / 32 | 500 | Números do painel (gasto, contagens) |

Os demais estilos (display, headline grande e médio, `labelSmall`) não são usados. Precisar de um deles é sinal para rever a hierarquia.

### 4.3 Ajustes para a Inter

- **Tracking 0** em todos os estilos **(decisão)**. Os valores de tracking do M3 foram calibrados para a Roboto, e a Inter, mais larga e com altura-x maior, fica espaçada demais com eles. Conferir visualmente no primeiro build.
- `FontFeature.tabularFigures()` (`tnum`) em todo número que muda ou se compara: custos, tokens, contagens, horários, durações, colunas de tabela.
- `FontFeature.slashedZero()` e as variantes `cv05` e `cv08` em ids curtos exibidos com a Inter. Id longo, comando e log usam a mono.
- Texto de leitura (mensagens do chat, planos, entregas, descrições) tem largura máxima de **720 dp** (`larguraDeLeitura`), cerca de 75 caracteres no `corpo`, mesmo em janela larga.

## 5. Espaçamento e densidade

### 5.1 Escala

| Token | dp | Uso típico |
|---|---|---|
| `esp1` | 4 | Ícone e rótulo no mesmo chip, ajuste fino |
| `esp2` | 8 | Entre elementos de um grupo, padding de chip |
| `esp3` | 12 | Padding de item de lista no desktop |
| `esp4` | 16 | Padding de cartão, margem lateral no celular |
| `esp5` | 24 | Entre seções, margem lateral a partir de medium |
| `esp6` | 32 | Entre blocos grandes |
| `esp7` | 48 | Respiro de estado vazio |

Regra: o espaço entre grupos é maior que o espaço dentro do grupo (proximidade). Valor fora da escala é defeito.

### 5.2 Densidade

- Base `VisualDensity.adaptivePlatformDensity`: `standard` no Android e `compact` no Linux.
- A densidade compacta corta o padding vertical. Nunca reduz o tamanho da fonte nem a área de clique abaixo do mínimo.
- Área de clique mínima: **48 dp** no celular e **32 dp** no desktop **(decisão)**, acima do piso de 24 da WCAG 2.5.8, porque a usabilidade cai antes do piso.

## 6. Forma

| Token | Raio (dp) | Onde |
|---|---|---|
| `raio-xs` | 4 | Badges, marcadores, nó de tamanho mínimo |
| `raio-sm` | 8 | Campos de texto, chips, menus, tooltips |
| `raio-md` | 12 | Cartões, nós do grafo, balões do chat |
| `raio-lg` | 16 | Sheets, painéis flutuantes |
| `raio-xl` | 28 | Diálogos |
| `raio-total` | pílula | Botões, campo de busca, compositor do chat |

O raio 18 dos campos no tema atual sai da escala: o campo comum vai para `raio-sm` e o compositor do chat para `raio-total`.

## 7. Elevação

| Camada | Superfície | Sombra |
|---|---|---|
| Fundo | `surface` | não |
| Painel fixo (lateral, rail, barra) | `surfaceContainer` | não |
| Cartão | `surfaceContainerLow` + borda `outlineVariant` | não |
| Menu, tooltip, snackbar | `surfaceContainerHigh` / `inverseSurface` | nível 3 (6 dp) |
| Diálogo, sheet modal | `surfaceContainerHigh` | nível 5 (12 dp) |
| Nó arrastado no editor | a do nó | nível 4 (8 dp) |

`surfaceTintColor: Colors.transparent` em todos os componentes **(decisão)**: o tom por elevação foi substituído pelos containers, e misturar os dois deixa as camadas desiguais.

## 8. Movimento

| Mudança | Duração | Curva |
|---|---|---|
| Estado de componente (hover, seleção, ícone) | `Durations.short2` (100 ms) | `Easing.standard` |
| Expandir, recolher, trocar conteúdo | `Durations.medium1` (250 ms) | `Easing.standard` |
| Painel ou diálogo entrando | `Durations.medium2` (300 ms) | `Easing.emphasizedDecelerate` |
| Painel ou diálogo saindo | `Durations.short4` (200 ms) | `Easing.emphasizedAccelerate` |

Animação só para mostrar mudança de estado. Com `MediaQuery.disableAnimationsOf(context)` ligado, tudo vira corte seco. O M3 Expressive (springs) fica de fora por enquanto.

## 9. Estados de interação

| Estado | Tratamento |
|---|---|
| Repouso | estilo base |
| Hover (desktop) | camada de 8% da cor "sobre" e cursor de mão em tudo que é clicável |
| Foco por teclado | camada de 10% e contorno de 2 dp em `primary` (3:1 contra o fundo) |
| Pressionado | camada de 10% e ripple |
| Arrastando | camada de 16% e elevação 4 |
| Selecionado | `secondaryContainer`, e ícone com `fill: 1` |
| Desabilitado | conteúdo com 38% de opacidade e, quando couber, tooltip com o motivo |
| Carregando | indicador no lugar do conteúdo, mantendo o tamanho do componente |
| Erro | `error` no contorno e mensagem abaixo do campo |

Tempo de resposta (NN/g): até 0,1 s nada, até 1 s cursor ou estado de pressionado, de 1 a 10 s spinner no próprio componente (ou skeleton na carga inicial da tela), acima de 10 s barra de progresso com descrição e "Cancelar".

## 10. Layout responsivo

### 10.1 Classes de janela

A classe vem da largura da janela (`MediaQuery.sizeOf`) ou do espaço do widget (`LayoutBuilder`), nunca do tipo de aparelho. Fica num enum `ClasseDeJanela` no núcleo.

| Classe | Largura (dp) | Margem lateral | Navegação | Painéis |
|---|---|---|---|---|
| compact | < 600 | 16 | `NavigationBar` (80 dp) | 1 |
| medium | 600 a 839 | 24 | `NavigationRail` sem rótulos | 1, ou 2 em lista e detalhe |
| expanded | 840 a 1199 | 24 | `NavigationRail` com rótulos | 2 |
| large | 1200 a 1599 | 24 | `NavigationRail(extended: true)` | 2 ou 3 |
| extra-large | ≥ 1600 | 24 | `NavigationRail(extended: true)` | 3, com conteúdo limitado em largura |

A `larguraDupla = 840` de `raiz.dart` passa a ser o corte `expanded`. A janela do desktop pode cair em qualquer classe, e cada tela precisa funcionar em todas.

**Destinos em compact** (decisão do Ueslei, 06/11/2026: as ações mais importantes na barra e as demais num menu hambúrguer):

| Onde | Destinos |
|---|---|
| `NavigationBar` | Conversas, Painel, Tarefas **(decisão: a divisão)** |
| Menu hambúrguer (`NavigationDrawer` modal, aberto pelo ícone `menu` no início da app bar) | Equipes, Board, Decisões, e Configuração quando existir no celular |

O menu marca o destino atual e mostra badges de pendência como a barra. Ao escolher um destino, ele fecha e a barra fica sem item selecionado. Em medium e acima não há menu hambúrguer: o rail mostra os seis destinos.

### 10.2 Layout por tela

| Tela | Padrão canônico | Comportamento ao estreitar |
|---|---|---|
| Conversas e chat | lista e detalhe | Abaixo de expanded mostra uma tela por vez, como hoje no celular |
| Tarefas | lista e detalhe | Idem, e a seleção sobrevive à mudança de largura |
| Painel | feed de cartões | De 1 coluna (compact) a 3 (large ou maior), com "Precisa de você" sempre na primeira posição |
| Equipes, organograma e workflows | painel principal com painel de apoio (propriedades) | Abaixo de expanded o painel de apoio vira sheet. Em compact, o grafo é só leitura e a edição fica no desktop |
| Configuração, formulários | coluna única | Largura máxima de 720 dp, centralizada |

O `ScaffoldAdaptativo` é próprio, sobre `LayoutBuilder`. O `flutter_adaptive_scaffold` foi descontinuado.

## 11. Componentes

### 11.1 Ações

- **Hierarquia de botões:** uma `FilledButton` por contexto, para a ação principal. A secundária importante é `FilledButton.tonal`, a média é `OutlinedButton`, a de baixa ênfase é `TextButton`. Ação compacta usa `IconButton`, sempre com tooltip.
- **Rótulo com verbo e objeto:** "Aprovar comando", "Criar tarefa", "Salvar workflow". "OK" e "Sim" não são usados.
- **Destrutivo:** cor `error`, verbo explícito ("Excluir persona"). Nunca é o botão focado por padrão. Exclusões graves mantêm a digitação do nome.
- **FAB:** não é usado no desktop. No celular, só onde a tela tiver uma ação principal de criar.

### 11.2 Entrada

- **Campos de formulário:** `TextField` outlined, `raio-sm`, rótulo flutuante sempre visível (`labelText`), texto de ajuda e erro abaixo do campo. A referência de UI/UX pede rótulo fora do campo. O rótulo flutuante do M3 cumpre o mesmo objetivo, porque continua visível com o campo preenchido.
- **Validação:** ao sair do campo, e na hora em campos estruturados (cron, JSON, id), com prévia quando existir ("próximas execuções" da rotina). A entrada com erro nunca é apagada.
- **Compositor do chat:** campo preenchido (`surfaceContainerHighest`), `raio-total`, botão de enviar `IconButton.filled`. Durante a resposta, o botão vira "Parar".
- **Alternâncias:** `Switch` com efeito imediato, nunca misturado com um "Salvar". Escolha de 2 a 5 opções usa `SegmentedButton`.
- **Seleção múltipla e filtros:** `FilterChip`. Atalhos do chat (`atalhos.md`) são chips de sugestão.

### 11.3 Conteúdo

- **Cartões:** `Card.outlined` (borda `outlineVariant`, fundo `surfaceContainerLow`, `raio-md`, padding `esp4`). `Card` elevado não é usado.
- **Listas:** `ListTile` com densidade da plataforma, hover no desktop, ação secundária no menu do item (`MenuAnchor`) e também no clique direito.
- **Tabelas e números:** números alinhados à direita e com `tnum`, cabeçalho fixo em listas longas.
- **Estado vazio:** ícone, uma frase do que é a tela e a próxima ação como botão. Nunca uma tela em branco.
- **Carregamento:** skeleton na primeira carga de uma tela, spinner num cartão isolado, barra de progresso acima de 10 s.

### 11.4 Feedback e sobreposição

- **Snackbar:** feedback breve, no máximo uma ação ("Desfazer"), `persist: false` quando tiver ação. Erro que exige decisão não vai para snackbar.
- **Diálogo:** só para decisão que interrompe (confirmar exclusão, digitar nome). Fluxo longo vai para uma tela ou um painel.
- **Sheet:** ações e conteúdo secundário no celular, painel de apoio em medium.
- **Menu:** `MenuAnchor`, com o atalho de teclado à direita do item (`MenuItemButton.shortcut`).
- **Tooltip:** obrigatório em todo botão só com ícone, `waitDuration` de 500 ms.
- **Badge:** contagem de pendências na navegação (aprovações, decisões).

### 11.5 Padrões do Control Tower

- **Balão do chat:** `raio-md`, largura máxima de `larguraDeLeitura`. Ueslei em `surfaceContainerHighest`, persona em `surfaceContainerLow` com o avatar e o nome na cor da persona. O streaming não pode mover o layout, e a rolagem automática só acontece quando a conversa já está no fim. "Pensando" e "usando ferramenta" aparecem depois de 1 s.
- **Pedido de aprovação** (comando do Alfred, plano, etapa do Ueslei): cartão com `tertiaryContainer` na faixa superior, mostrando quem pede, em qual tarefa, o efeito exato (comando completo na mono, diff ou plano) e duas ações com verbo ("Aprovar comando" como `FilledButton`, "Negar" como `OutlinedButton`). Depois de resolvido, o cartão perde os botões e mostra o resultado.
- **"Precisa de você":** a primeira seção do painel, com `tertiaryContainer` e contagem, ordenada pela prioridade do servidor.
- **Nó do grafo** (organograma e workflow): `raio-md`, `surfaceContainerLow`, borda `outlineVariant` (`primary` com 2 dp quando focado ou selecionado), ícone do tipo de caixa, título `titulo-item` e estado pelo mapa 3.4. Erros de validação ficam presos ao nó, com texto. Ligar e mover nós também precisa funcionar sem arrastar, por menu e por teclado (WCAG 2.5.7).
- **Chip de modo** ("auto", foco TickTask): `FilterChip` selecionado, `rotulo-medio`. Não pode passar da largura do cabeçalho em compact.

## 12. Ícones

- **Biblioteca:** `material_symbols_icons`, estilo **Outlined**, peso 400, grade 0 no claro e -25 no escuro, `fill: 1` só no estado selecionado. É o par oficial do M3, é mantido e faz tree-shaking com `Symbols.nome`. `Symbols.get()` e mapas de nomes são proibidos, porque desligam o tree-shaking.
- **Critério para manter a escolha:** depois da migração, `flutter build linux --analyze-size` e `flutter build apk --analyze-size` não podem mostrar a fonte de ícones acima de 300 KB **(decisão)**. Se passar, o padrão volta a ser `Icons.*` nativo (Material Icons, também com tree-shaking e sem dependência), e este documento é atualizado.
- **Uma família só.** Nada de Lucide, Cupertino ou outra misturada. O `cupertino_icons` sai do pubspec se nenhum código usar.
- **Tamanhos:** 20 dp em listas densas, barras de ferramentas e dentro de botões. 24 dp no padrão. 16 dp só dentro de chips e badges.
- **Rótulo:** ícone sozinho só em ações universais (fechar, voltar, buscar, mais opções, enviar), sempre com tooltip e `semanticLabel`. Ações menos comuns e recursos de IA levam texto.
- **Mesmo conceito, mesmo ícone, no app inteiro.** A tabela 3.4 vale para estados. Conceitos do produto, mantendo os que a navegação já usa: conversas `forum`, board `gavel`, decisão `fact_check`, painel `dashboard`, tarefa `task_alt`, equipe e organograma `account_tree`. Os que faltam **(decisão)**: persona `person`, rotina `event_repeat`, workflow `schema`, aprovação `verified_user`, skill `extension`.

## 13. Texto de interface

- Português brasileiro com acentuação correta. Sem travessão.
- Botões com verbo e objeto, menus com verbo, títulos com substantivo.
- Mensagem de erro em três partes: o que aconteceu, por quê (se souber) e o que fazer.
- Glossário fixo: persona (nunca "agente"), posição, equipe, tarefa, execução, rotina, workflow, caixa, decisão, aprovação.
- Datas relativas até 7 dias ("há 5 min", "ontem às 14:20") e absolutas depois.

## 14. Acessibilidade

Critério de pronto para toda tela nova ou alterada:

- [ ] contraste 4,5:1 no texto e 3:1 em ícones, bordas e foco, nos dois temas;
- [ ] nenhum significado só por cor;
- [ ] área de clique de 48 dp no celular e 32 dp no desktop;
- [ ] navegação completa por teclado no desktop, em ordem lógica, com foco visível;
- [ ] toda ação de arrastar com alternativa sem arrastar;
- [ ] `Semantics` e `tooltip` em controles só com ícone;
- [ ] funciona com o texto do sistema em 200% sem cortar (`MediaQuery.textScalerOf`), sem altura fixa em componente com texto;
- [ ] movimento reduzido respeitado;
- [ ] avisos de status (execução concluída, novo pedido) anunciados ao leitor de tela sem interromper, salvo urgência.

## 15. Desktop

- Cursor de mão e hover em tudo que é clicável.
- Clique direito abre o mesmo menu do botão "mais opções" do item.
- Atalhos com `Shortcuts` + `Actions` e indicados nos menus. Atalho de tecla única só fora de campos de texto e desligável. Os primeiros **(decisão)**: `Ctrl+N` nova conversa, `Ctrl+K` busca, `Ctrl+Enter` enviar ou salvar, `Esc` fecha painel, sheet ou diálogo, `Ctrl+1` a `Ctrl+6` destinos da navegação.
- `Scrollbar` visível em áreas roláveis longas e `SelectionArea` em textos que o usuário copia (mensagens, entregas, logs).
- Painéis redimensionáveis por divisor arrastável, com largura lembrada por tela.

## 16. Mapeamento para o Flutter

Este é o esqueleto do `tema.dart` previsto (a implementação é outra tarefa):

```dart
ThemeData tema(Brightness brilho) {
  final cores = ColorScheme.fromSeed(
    seedColor: const Color(0xFF5B8DEF),
    brightness: brilho,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  return ThemeData(
    colorScheme: cores,
    fontFamily: 'Inter',
    textTheme: textoDoControlTower(cores),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    scaffoldBackgroundColor: cores.surface,
    dividerTheme: DividerThemeData(color: cores.outlineVariant, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(backgroundColor: cores.surfaceContainer, surfaceTintColor: Colors.transparent),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: cores.surfaceContainer, height: 80),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: cores.surfaceContainer),
    cardTheme: CardThemeData(
      color: cores.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Raios.md),
        side: BorderSide(color: cores.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Raios.sm)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cores.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Raios.xl)),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    extensions: [CoresSemanticas.de(cores)],
  );
}
```

Constantes no núcleo, testáveis e sem dependência de widget:

| Classe | Conteúdo |
|---|---|
| `Espacos` | `esp1` a `esp7` (4 a 48) |
| `Raios` | `xs`, `sm`, `md`, `lg`, `xl` (4 a 28) |
| `ClasseDeJanela` | enum com `de(double largura)` e cortes 600, 840, 1200, 1600 |
| `EstadoVisual` | mapa da tabela 3.4 (estado do domínio para papel, ícone e rótulo) |
| `larguraDeLeitura` | 720 |

A família `JetBrains Mono` entra por um estilo `mono` no `ThemeExtension`, sem `fontFamily: 'monospace'` espalhado pelas telas.

O `package:flutter/material.dart` está congelado e o Flutter 3.47 trouxe o `material_ui` (regra `migrate_design_widgets` no `fix_material.yaml` do SDK). A migração é um commit isolado, com os testes rodando antes e depois, e fica fora da implementação do tema.

## 17. Web

A web (`app/web/`) não usa componentes Material (o `@material/web` está em manutenção mínima). Ela recebe os mesmos tokens como variáveis CSS (`--ct-cor-*`, `--ct-esp-*`, `--ct-raio-*`, `--ct-tipo-*`), gerados dos mesmos valores. A web é secundária: tokens iguais, componentes simples.

## 18. Diferenças do app atual

O que muda quando este padrão for aplicado (para a tarefa de implementação):

1. `tema.dart`: tirar os papéis sobrescritos, `fundo`, `painel` e `borda`, e passar a usar os papéis da tabela 3.2.
2. Raio 18 dos campos para `raio-sm` e `raio-total` no compositor.
3. `NavigationBar` de 64 para 80 dp, com 3 destinos e os outros 3 no menu hambúrguer (seção 10.1). A navegação passa a mudar por classe de janela (hoje há só o corte 840).
4. Os 13 usos de `'monospace'` viram o estilo `mono`.
5. As quatro funções de cor de estado espalhadas viram o `EstadoVisual`.
6. Cerca de 190 `Icons.*` migram para `Symbols.*` com o critério de tamanho da seção 12. O `cupertino_icons` sai se nada o usar.
7. Inter e JetBrains Mono entram nos assets.
8. Valores soltos de espaço e raio passam para `Espacos` e `Raios`.

## 19. Decisões deste documento

Estas são as decisões que não vieram prontas de nenhuma das duas referências. Revisar antes da implementação:

| Decisão | Motivo |
|---|---|
| Seed `#5B8DEF` em `tonalSpot` | Mantém a identidade atual, com paleta calma para ferramenta de trabalho |
| Sucesso `#2E9E5B`, aviso `#D99A1E` | Verde e âmbar reconhecíveis, harmonizados com a seed na geração |
| JetBrains Mono como mono | Mesma fonte em Linux e Android, OFL, combina com a Inter |
| Tracking 0 na Inter | A escala do M3 foi calibrada para a Roboto |
| Pesos 500 em `titulo-tela` e 600 em `titulo-secao` | A Inter em 400 fica leve demais para títulos |
| Nove estilos de texto | A referência pede escala curta; o painel precisa de número em destaque |
| Área de clique de 32 dp no desktop | Acima do piso de 24 da WCAG, para uso confortável com mouse |
| `surfaceTintColor` transparente em tudo | Uma forma só de separar camadas: o tom do container |
| Limite de 300 KB para a fonte de ícones | Torna mensurável o "biblioteca leve" pedido |
| Ícones dos conceitos do produto | Um ícone fixo para cada termo do glossário |
| Atalhos iniciais de teclado | Convenções de apps de desktop conhecidos |
