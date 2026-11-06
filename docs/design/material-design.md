# Material Design (M3) para o Control Tower

Referência de elementos e padrões do Google Material Design (Material 3) para o design system do Control Tower. Pesquisa feita em 06/11/2026.

## Propósito e restrições do projeto

O documento reúne o que o design system precisa decidir (cor, tipografia, forma, elevação, movimento, layout, componentes, ícones) com valores conferidos nas fontes e a API Flutter correspondente.

Restrições do projeto:

- Cliente Flutter (desktop Linux e Android), web em JS puro como secundária.
- Fonte Inter.
- Público: usuários de tecnologia com habilidade média (apps de celular e programas de computador avançados) e programadores juniores.
- Biblioteca de ícones leve.
- Responsividade também no desktop (janela redimensionável, mouse e teclado).

Estado atual (`cliente/lib/tela/tema.dart`): `useMaterial3: true`, `ColorScheme.fromSeed(seedColor: 0xFF5B8DEF)` com `surface`, `surfaceContainerHighest`, `onSurface`, `onSurfaceVariant`, `primary` e `error` sobrescritos, tema claro e escuro, `NavigationBar` com `height: 64`, campos com raio 18. Usa `Icons.*` (cerca de 190 usos), `cupertino_icons` no pubspec e Flutter 3.47.5.

### Notas de verificação

- As páginas de m3.material.io são renderizadas por JavaScript e não puderam ser lidas por fetch. Os valores deste documento vêm de fontes primárias legíveis: código do Flutter (`typography.dart`, `motion.dart`, `color_scheme.dart`, `theme_data.dart`), tokens do `material-components-android`, `material-color-utilities` (Dart), documentação do Android (window size classes) e pub.dev (API e página de cada pacote).
- Itens marcados com "(especificação M3, não relido)" vêm do conhecimento da especificação e devem ser conferidos em m3.material.io antes de virarem token do design system.
- Margens por classe de janela e a lista de componentes do Material 3 Expressive não foram confirmadas em fonte oficial legível.

## 1. Fundamentos do M3

### O que mudou do M2 para o M3

| Aspecto | Material 2 | Material 3 |
|---|---|---|
| Cor | Poucas cores (primary, secondary, surface, background) | ColorScheme com 45 papéis, containers, tonal palettes, geração a partir de seed (HCT) |
| Elevação | Sombra + overlay de opacidade por elevação | Superfícies por tom (`surfaceContainer*`), sombra só onde faz sentido |
| Forma | Cantos de 4dp | Escala de formas (0 a full), pílulas e cantos grandes |
| Tipografia | Roboto, escala H1 a overline | Type scale display/headline/title/body/label (15 estilos) |
| Estados | Overlays variados | State layers padronizados (hover 8%, focus 10%, pressed 10%, dragged 16%) |
| Componentes | Botões contained/outlined/text | Filled, tonal, elevated, outlined, text; NavigationBar/Rail/Drawer; SegmentedButton; SearchBar |
| Movimento | Curvas legadas | Easing standard/emphasized e durações em tokens (M3 Expressive: springs) |
| Personalização | Tema fixo | Dynamic color (Android 12+), temas gerados de qualquer cor |

### Dynamic color

Cores derivadas do papel de parede do usuário (Android 12+) ou de uma seed. No Flutter, `ColorScheme.fromSeed` gera o esquema a partir de uma cor, e o pacote `dynamic_color` (2.1.0, 20/08/2026, Apache 2.0) lê a paleta do sistema (`DynamicColorBuilder`). Para um produto com identidade própria como o Control Tower, a seed fixa é mais previsível que o dynamic color do sistema.

### Tokens de design (três camadas)

| Camada | Exemplo | Função |
|---|---|---|
| Reference (`md.ref.*`) | `md.ref.palette.primary40`, `md.ref.typeface.plain` | Valores brutos: paletas, famílias |
| System (`md.sys.*`) | `md.sys.color.primary`, `md.sys.typescale.body-large`, `md.sys.shape.corner.medium`, `md.sys.motion.duration.short2` | Decisões de tema, apontam para reference |
| Component (`md.comp.*`) | `md.comp.filled-button.container.color` | Valores de cada componente, apontam para system |

No Flutter: reference vive nos tonal palettes internos do `material_color_utilities`, system em `ColorScheme`, `TextTheme`, `Durations`, `Easing` e `ThemeData`, component nos temas `FilledButtonThemeData`, `NavigationBarThemeData`, `InputDecorationTheme` etc. e nos `ButtonStyle`.

### Estado do Flutter (importante)

- O Flutter 3.47 trouxe `package:material_ui` (1.10.0 em 03/11/2026) e `package:cupertino_ui` como pacotes oficiais, desacoplados do framework. As bibliotecas dentro do SDK (`package:flutter/material.dart`) estão congeladas e "agendadas para deprecação formal em uma próxima stable". Migração opcional: `dart fix --apply --code=migrate_design_widgets`, com `MaterialUiCompatibilityBridge` para pacotes de terceiros que ainda importam o material antigo.
- O Material 3 Expressive chega pelo `material_ui` de forma incremental: `StyleVariant` (1.2.0) define as variantes M3 e M3 Expressive, `IconButton` ganhou suporte Expressive (1.5.0) e exemplo (1.8.0). Há também o pacote comunitário `material_3_expressive` (1.2.0, 23/10/2026, 44 widgets, springs e shape morphing, fonte padrão Google Sans Flex), que exige Flutter 3.47+ e usa `material_ui`.

## 2. Cor

### Papéis do ColorScheme

O `ColorScheme` tem 45 cores. Pares "on" são o conteúdo sobre a cor correspondente. Tons abaixo vêm de `MaterialDynamicColors` (esquema tonalSpot, contraste padrão).

| Papel | Uso | Tom claro / escuro |
|---|---|---|
| `primary` / `onPrimary` | Botão principal, FAB, estados ativos | 40 / 80 (primary) |
| `primaryContainer` / `onPrimaryContainer` | Destaque menos intenso que primary (botão tonal, indicador de nav) | 90 / 30 |
| `secondary` / `secondaryContainer` | Componentes de menor ênfase (chips de filtro, nav rail) | 40 / 80 e 90 / 30 |
| `tertiary` / `tertiaryContainer` | Acento contrastante, equilíbrio | 40 / 80 e 90 / 30 |
| `error` / `errorContainer` | Erros e ações destrutivas | 40 / 80 e 90 / 30 |
| `surface` | Fundo base de telas e componentes | 98 / 6 |
| `surfaceDim` / `surfaceBright` | Fundo escurecido ou clareado, constante entre temas conforme o caso | 87 / 6 (dim) |
| `surfaceContainerLowest` | Camada mais baixa | 100 / 4 |
| `surfaceContainerLow` | Cartões e áreas sutis | 96 / 10 |
| `surfaceContainer` | Painéis, barras de navegação | 94 / 12 |
| `surfaceContainerHigh` | Menus, diálogos | 92 / 17 |
| `surfaceContainerHighest` | Campos preenchidos, cartões elevados | 90 / 22 |
| `onSurface` / `onSurfaceVariant` | Texto principal e secundário | 10 / 90 e 30 / 80 |
| `outline` | Bordas de campo, divisores fortes | 50 / 60 |
| `outlineVariant` | Divisores sutis | 80 / 30 |
| `inverseSurface` / `onInverseSurface` | Snackbar, tooltips | 20 / 90 |
| `inversePrimary` | Ação sobre `inverseSurface` | 80 / 40 |
| `primaryFixed`, `primaryFixedDim` (e secondary, tertiary) | Igual nos dois temas | fixo |
| `scrim`, `shadow` | Película de modais e sombra | preto |
| `surfaceTint` | Legado do tom por elevação (no M3 atual a elevação usa containers) | primary |

Regra de uso: fundo de tela em `surface`, blocos em `surfaceContainer*` (mais alto = mais destacado), conteúdo em `onSurface`, rótulo secundário em `onSurfaceVariant`, bordas em `outline` (campos) ou `outlineVariant` (divisores).

No Flutter: `Theme.of(context).colorScheme.surfaceContainerHigh` etc. Parâmetros `primary:`, `surface:` em `ColorScheme.fromSeed` sobrescrevem um papel isolado. Cuidado: sobrescrever poucos papéis e deixar os demais gerados quebra a coerência tonal (o tema atual faz isso em `surface`, `onSurface` e `onSurfaceVariant`).

### Tonal palettes

Cada papel sai de uma paleta tonal: 13 tons de 0 (preto) a 100 (branco) em HCT (matiz, croma, tom). As paletas de um esquema: primary, secondary, tertiary, neutral, neutral variant e error. No esquema tonalSpot (padrão), o croma do primary é 36, do secondary 16, do neutral 6 e do neutral variant 8, com o tertiary girado 60 graus no matiz.

### Geração por seed e variantes

`ColorScheme.fromSeed({seedColor, brightness, dynamicSchemeVariant = tonalSpot, contrastLevel = 0.0, ...})`. Variantes de `DynamicSchemeVariant`:

| Variante | Efeito (documentação do Flutter) |
|---|---|
| `tonalSpot` | Padrão. Paletas pastel de croma baixo |
| `fidelity` | As paletas batem com a seed, mesmo muito saturada |
| `content` | Quase idêntica a fidelity. `primaryContainer` é a seed ajustada, tertiary análoga |
| `monochrome` | Escala de cinza, sem croma |
| `neutral` | Quase cinza, um toque de croma (primary croma 12) |
| `vibrant` | Pastel de croma alto, primary no croma máximo (200) |
| `expressive` | Pastel de croma médio, matiz do primary diferente da seed |
| `rainbow`, `fruitSalad` | Lúdicas, o matiz da seed não aparece |

Para uma ferramenta de trabalho com seed azul `0xFF5B8DEF`, `tonalSpot` dá interface calma e `fidelity`/`content` preservam a identidade da seed. `neutral` serve se o produto quiser quase só cinza com acento.

### Cores semânticas extras (sucesso, aviso, info)

O M3 base só tem `error`. Para sucesso/aviso/info:

- Criar "custom colors": gerar uma paleta tonal por cor e derivar quatro papéis (cor, sobre-cor, container, sobre-container) com os mesmos tons dos papéis acentuados (claro 40/100/90/10, escuro 80/20/30/90).
- Harmonizar com a seed para não destoar do tema: `Blend.harmonize` em `material_color_utilities` (0.13.1) e `Color.harmonizeWith` em `dynamic_color`.
- No Flutter, guardar em `ThemeExtension<CoresSemanticas>` (com `lerp` e `copyWith`) dentro de `ThemeData.extensions`, acessado por `Theme.of(context).extension<CoresSemanticas>()`.
- Nunca depender só da cor: acompanhar de ícone e texto (acessibilidade).

### Claro, escuro e contraste

- Brilho: `ColorScheme.fromSeed(brightness: Brightness.dark)` e `ThemeData.brightness`; `MaterialApp(theme:, darkTheme:, themeMode:)`.
- Contraste: `contrastLevel` de -1.0 a 1.0 (0.0 padrão, 0.5 médio, 1.0 alto). As `ContrastCurve` do `material_color_utilities` ajustam os tons por nível. Dá para oferecer "alto contraste" como opção do usuário.
- Alvos WCAG: 4,5:1 para texto normal, 3:1 para texto grande e componentes de UI. Os pares do esquema gerado atendem a isso no contraste padrão. Cores sobrescritas à mão (como no tema atual) precisam ser verificadas.

## 3. Tipografia

### Type scale do M3

Valores de `_M3Typography.englishLike` (Flutter, gerado dos tokens do Material), base para o design system:

| Estilo | Tamanho (sp) | Line-height (sp) | Peso | Tracking |
|---|---|---|---|---|
| displayLarge | 57 | 64 (1,12) | 400 | -0,25 |
| displayMedium | 45 | 52 (1,16) | 400 | 0 |
| displaySmall | 36 | 44 (1,22) | 400 | 0 |
| headlineLarge | 32 | 40 (1,25) | 400 | 0 |
| headlineMedium | 28 | 36 (1,29) | 400 | 0 |
| headlineSmall | 24 | 32 (1,33) | 400 | 0 |
| titleLarge | 22 | 28 (1,27) | 400 | 0 |
| titleMedium | 16 | 24 (1,50) | 500 | 0,15 |
| titleSmall | 14 | 20 (1,43) | 500 | 0,1 |
| bodyLarge | 16 | 24 (1,50) | 400 | 0,5 |
| bodyMedium | 14 | 20 (1,43) | 400 | 0,25 |
| bodySmall | 12 | 16 (1,33) | 400 | 0,4 |
| labelLarge | 14 | 20 (1,43) | 500 | 0,1 |
| labelMedium | 12 | 16 (1,33) | 500 | 0,5 |
| labelSmall | 11 | 16 (1,45) | 500 | 0,5 |

Uso: display e headline para títulos de tela e números grandes de painel, title para títulos de cartão, diálogo e app bar, body para texto corrido, label para botões, chips e abas. O M3 Expressive acrescenta variantes enfáticas (peso maior) dos mesmos estilos, ainda não parte do `TextTheme` estável.

No Flutter: `Theme.of(context).textTheme.bodyMedium`; `ThemeData(fontFamily: 'Inter')` troca a família em todos os estilos; `textTheme.apply(fontFamily: 'Inter')` ou `copyWith` por estilo ajusta pesos e tracking; `Typography.material2021(platform: ...)` é a base; `TextStyle.fontFeatures: [FontFeature.tabularFigures()]` para números alinhados em tabelas e painéis (a Inter tem a feature `tnum`).

### Trocar a família para Inter

Fatos: Inter é SIL Open Font License 1.1 (arquivo LICENSE.txt do repositório `rsms/inter`). Última release v4.1 (16/11/2024), pacote de 33,7 MB com variantes estáticas e variável. O Google Fonts distribui `Inter[opsz,wght].ttf` (variável, eixos de tamanho óptico e peso) com licença OFL.

| Critério | `google_fonts` (9.0.0, 28/09/2026, flutter.dev, 6,4 mil likes) | Fonte empacotada em assets |
|---|---|---|
| Uso | `GoogleFonts.interTextTheme()` | `fonts:` no pubspec + `fontFamily: 'Inter'` |
| Offline | Busca por HTTP no primeiro uso e cacheia. Primeira abertura sem rede cai na fonte padrão (flash de troca). Se o arquivo estiver nos assets (`google_fonts/Inter-Regular.ttf`), ele tem prioridade sobre a rede | Sempre disponível, sem flash |
| Tamanho do app | Menor (fontes baixadas em runtime) ou igual ao empacotado se usar assets | Cresce pelos arquivos incluídos (escolha 400/500/600/700 ou a variável) |
| Privacidade e infra | Requisição aos servidores do Google na primeira vez | Nenhuma |
| Licença | Registrar a OFL no `LicenseRegistry` (o README do pacote mostra como) | Idem |
| Manutenção | Dependência a mais | Atualização manual da fonte |

Para o Control Tower (LAN, desktop e celular, uso offline plausível), o empacotamento em assets é mais robusto: sem rede, sem flash, sem dependência extra. Pesos mínimos: 400 (corpo), 500 (title/label), 600 (ênfase) e 700 se necessário. A variável permite `FontVariation('wght', 500)` e o eixo `opsz`, com um arquivo só, porém maior que quatro estáticos subsetados. Registrar a OFL com `LicenseRegistry.addLicense`.

Ajuste fino: a escala do M3 foi calibrada para Roboto. Inter tem x-height maior e é mais larga. Conferir o tracking de `bodyLarge` (0,5) e `labelSmall` e, se pesar, reduzir. O app ainda não declara nenhuma fonte no pubspec e usa a padrão da plataforma.

## 4. Forma, elevação, movimento, estados e densidade

### Escala de formas (shape scale)

Valores dos tokens do `material-components-android`:

| Token | Raio |
|---|---|
| none | 0dp |
| extra-small | 4dp |
| small | 8dp |
| medium | 12dp |
| large | 16dp |
| large-increased | 20dp |
| extra-large | 28dp |
| extra-large-increased | 32dp |
| extra-extra-large | 48dp |
| full | 50% (pílula/círculo) |

Aplicação típica: chips e campos em small/extra-small, cartões em medium, diálogos em extra-large, botões e barras de pesquisa em full. Os níveis "increased" e extra-extra-large vêm do M3 Expressive.

No Flutter: `RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))`, `StadiumBorder()` (full), `shape:` em cartões, botões, chips; formas por tema em `CardThemeData`, `FilledButtonThemeData` etc. Criar constantes (`Raios.md = 12`) no design system, já que o Flutter não expõe a escala como API única.

### Elevação

| Nível | dp | Uso típico |
|---|---|---|
| 0 | 0 | Superfícies base, botões filled |
| 1 | 1 | Cartões elevados, botões elevated |
| 2 | 3 | Barras de navegação, app bar rolada |
| 3 | 6 | FAB, menus, snackbar |
| 4 | 8 | Hover/pressed de itens elevados |
| 5 | 12 | Diálogos, sheets modais |

Tonal elevation vs sombra: no M3 a separação principal vem do tom da superfície (`surfaceContainer*`), não da sombra. A sombra (`shadow`) é complementar e só em elementos flutuantes. O `surfaceTint` (tom por elevação) foi substituído pelos containers; manter `surfaceTintColor: Colors.transparent` (o tema atual faz isso na `AppBar`) evita o tom automático.

No Flutter: `Material(elevation: n)`, `Card(elevation:)`, `ElevatedButton`, `surfaceTintColor`, `shadowColor`. O Flutter usa pares dp em `elevation:` (1, 3, 6, 8, 12).

### Movimento

Durações (`Durations` no Flutter e tokens Android, ms):

| Token | ms | Token | ms |
|---|---|---|---|
| short1 | 50 | long1 | 450 |
| short2 | 100 | long2 | 500 |
| short3 | 150 | long3 | 550 |
| short4 | 200 | long4 | 600 |
| medium1 | 250 | extralong1 | 700 |
| medium2 | 300 | extralong2 | 800 |
| medium3 | 350 | extralong3 | 900 |
| medium4 | 400 | extralong4 | 1000 |

Curvas (`Easing` no Flutter, cubic-bezier):

| Token | Valores |
|---|---|
| standard | 0.2, 0, 0, 1 |
| standardAccelerate | 0.3, 0, 1, 1 |
| standardDecelerate | 0, 0, 0, 1 |
| emphasizedAccelerate | 0.3, 0, 0.8, 0.15 |
| emphasizedDecelerate | 0.05, 0.7, 0.1, 1 |
| emphasized | caminho composto (no Flutter, usa-se `Easing.emphasizedDecelerate`/`Accelerate` por direção) |
| linear | 0, 0, 1, 1 |

Regras: entrada na tela usa decelerate, saída usa accelerate, transições pequenas (ícone, estado) em short1 a short4, transições de painel e diálogo em medium2 a medium4. O M3 Expressive substitui easing por springs (spatial e effects), disponíveis no pacote `material_3_expressive`.

No Flutter: `AnimatedContainer(duration: Durations.medium2, curve: Easing.standard)`, `Durations`, `Easing` (de `material.dart`), `PageTransitionsTheme`.

### State layers

Sobreposição da cor "sobre" do componente com opacidade fixa:

| Estado | Opacidade da camada |
|---|---|
| Hover | 8% (0,08) |
| Focus | 10% (0,10) |
| Pressed | 10% (0,10) |
| Dragged | 16% (0,16) |
| Disabled (container) | 12% e conteúdo 38% (0,38 é o token `disabled_state_layer_opacity`) |

No Flutter: `WidgetStateProperty` (`WidgetState.hovered`, `focused`, `pressed`, `dragged`, `selected`, `disabled`) em `ButtonStyle.overlayColor`, `InkWell.overlayColor`, `hoverColor`, `focusColor`. Os widgets do Material já aplicam os valores. Em widgets customizados, usar `InkWell` e `MouseRegion` com essas opacidades.

### Densidade

`VisualDensity` encolhe ou expande o espaçamento de componentes em passos de 4px por unidade, de -4,0 a 4,0:

| Valor | horizontal/vertical |
|---|---|
| `VisualDensity.standard` | 0 |
| `VisualDensity.comfortable` | -1 |
| `VisualDensity.compact` | -2 |

`VisualDensity.adaptivePlatformDensity` devolve `standard` em Android/iOS/Fuchsia e `compact` em Linux/macOS/Windows. Em desktop, usar compacta em listas, tabelas, barras de ferramentas e campos reduz a rolagem (programas de computador avançados são densos). Manter os alvos de toque de 48dp no celular (mouse permite alvos menores no desktop). Use `ThemeData(visualDensity: VisualDensity.adaptivePlatformDensity)` e ajuste fino por componente (`materialTapTargetSize: MaterialTapTargetSize.shrinkWrap`, `visualDensity` no `ButtonStyle`).

## 5. Layout e responsividade

### Window size classes (confirmadas na documentação do Android)

| Classe | Largura | Dispositivo típico |
|---|---|---|
| Compact | < 600dp | Celular em retrato |
| Medium | 600 a < 840dp | Tablet em retrato, dobráveis abertos em retrato |
| Expanded | 840 a < 1200dp | Tablet em paisagem, janelas de desktop médias |
| Large | 1200 a < 1600dp | Tablets grandes, desktop |
| Extra-large | ≥ 1600dp | Desktop |

Alturas: compact < 480dp, medium 480 a < 900dp, expanded ≥ 900dp (a altura compacta em paisagem de celular torna dois painéis impraticáveis). As classes dependem da janela disponível, não do dispositivo: nunca usar lógica `isTablet`.

### Margens, colunas e painéis

- Margem lateral: 16dp em compact e 24dp a partir de medium é a orientação usual do M3 (especificação M3, não relido; não confirmada em fonte oficial legível, e para large/extra-large a faixa "24dp ou mais" também não foi confirmada).
- Grade de colunas: 4 (compact), 8 (medium), 12 (expanded) com gutters de 8, 16 e 24dp, segundo fonte secundária (Android skill de terceiros, não oficial).
- Painéis: 1 painel em compact, 1 ou 2 em medium, 2 em expanded, 2 ou 3 em large e extra-large (fonte secundária, SAP Fiori). Sempre ao menos um painel flexível.

### Layouts canônicos

| Padrão | Descrição | Bom para |
|---|---|---|
| List-detail | Lista e detalhe lado a lado. Em janela estreita mostra só um por vez, com navegação para o detalhe | Conversas, tarefas, personas |
| Supporting pane | Painel principal e painel de apoio (inspetor, contexto) | Editor de workflow com painel de propriedades |
| Feed | Grade de cartões equivalentes que vai de 1 coluna a várias | Painel de controle, atividade |

### No Flutter

- Medir: `MediaQuery.sizeOf(context)` (janela inteira) ou `LayoutBuilder` (espaço do widget). A documentação do Flutter recomenda abstrair o widget, medir e então ramificar, e cita 600 como limite entre `NavigationBar` e `NavigationRail`.
- Criar uma enum `ClasseDeJanela` (compact, medium, expanded, large, extraLarge) a partir da largura, no próprio app.
- Navegação por classe: `NavigationBar` (compact), `NavigationRail` (medium), `NavigationRail(extended: true)` ou `NavigationDrawer` (expanded ou maior).
- `flutter_adaptive_scaffold` (0.3.3+1, 06/05/2025) está **descontinuado** (`isDiscontinued: true` na API do pub.dev, sem pacote substituto indicado; a issue de descontinuação é flutter/flutter#162965 segundo o README de um sucessor). Alternativas de terceiros recentes, mas pequenas: `adaptive_scaffold_router` 0.3.1 (19/06/2026, BSD-3, com `go_router`) e `prism_adaptive_scaffold` 0.1.0 (19/10/2026, 0 likes). Nenhuma é oficial nem estabelecida. Recomendação: escrever um `ScaffoldAdaptativo` próprio (50 a 150 linhas) sobre `LayoutBuilder` + `NavigationBar`/`NavigationRail`, que o app já tem em parte. `adaptive_breakpoints` também está descontinuado.
- Painéis: `Row` com `Expanded`/`SizedBox(width:)`, `Flexible`, e para redimensionar painéis no desktop um divisor arrastável próprio (o Flutter não tem `SplitPane` embutido).

## 6. Componentes M3 e quando usar

Dimensões marcadas (V) foram conferidas no código do Flutter. As demais são da especificação (não relidas).

### Botões

| Componente | Quando usar | Flutter |
|---|---|---|
| Filled | Ação principal da tela (uma por contexto) | `FilledButton` |
| Filled tonal | Ação importante secundária | `FilledButton.tonal` |
| Elevated | Separar de fundo estampado; usar pouco | `ElevatedButton` |
| Outlined | Ação média, secundária | `OutlinedButton` |
| Text | Ação de baixa ênfase, diálogos, cartões | `TextButton` |
| Icon button | Ação compacta (standard, filled, tonal, outlined) | `IconButton`, `IconButton.filled`, `.filledTonal`, `.outlined` |
| FAB | Ação primária flutuante (56dp (V: elevação 6); small, large, extended) | `FloatingActionButton`, `.small`, `.large`, `.extended` |

Altura padrão de botão: 40dp (especificação M3). Rótulos em `labelLarge`. Em desktop, hover mostra o state layer e o cursor muda (`SystemMouseCursors.click`).

### Chips

| Tipo | Uso | Flutter |
|---|---|---|
| Assist | Ação inteligente ou atalho (abrir mapa, criar tarefa) | `ActionChip` |
| Filter | Filtro com seleção (alterna) | `FilterChip` |
| Input | Entidade digitada (destinatário, etiqueta) com remoção | `InputChip` |
| Suggestion | Resposta ou consulta sugerida (chips de atalho do chat) | `ActionChip` ou `ChoiceChip` |

Altura 32dp (especificação M3). Os "chips de atalho" do chat do Control Tower são Suggestion chips.

### Cartões, listas, campos de texto

- Cartões: `Card` (elevated), `Card.filled`, `Card.outlined`. Filled e outlined funcionam bem em tema com bordas e superfícies como o do Control Tower. Raio medium (12dp) por padrão.
- Listas: `ListTile` (um, dois ou três linhas), `ListView.builder`, `ExpansionTile`. Em desktop, densidade compacta e `hoverColor`.
- Campos de texto: `TextField` com `InputDecoration`. Filled (padrão, `filled: true`, indicador inferior) ou outlined (`OutlineInputBorder`). Altura 56dp (especificação M3). Outlined costuma ser mais legível em formulários densos de desktop. Use `helperText`/`errorText` e `labelText` flutuante.

### Menus, diálogos, sheets, snackbars

| Componente | Quando | Flutter | Notas |
|---|---|---|---|
| Menu | Lista de ações a partir de um gatilho | `MenuAnchor`, `PopupMenuButton`, `DropdownMenu`, `MenuBar` (desktop) | Menu de contexto de clique direito: `MenuAnchor` + `GestureDetector(onSecondaryTapDown)` |
| Diálogo | Decisão que interrompe (confirmar exclusão) | `AlertDialog`, `Dialog`, `showDialog`, `Dialog.fullscreen` | (V) largura 280 a 560dp, evitar para fluxos longos |
| Bottom sheet | Ações ou conteúdo secundário no celular | `showModalBottomSheet`, `BottomSheet` | Em desktop vira side sheet ou diálogo |
| Side sheet | Painel lateral de apoio em telas largas | `Drawer`/`endDrawer`, ou painel próprio | Sem widget oficial dedicado ao side sheet do M3 |
| Snackbar | Feedback breve e não bloqueante, 1 ação opcional | `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` | (V) elevação 6. Para erro crítico, usar diálogo ou aviso persistente |

### Navegação

| Componente | Classe de janela | Flutter | Notas |
|---|---|---|---|
| Navigation bar | Compact | `NavigationBar` | 3 a 5 destinos, altura 80dp (V). O tema atual usa 64 |
| Navigation rail | Medium em diante | `NavigationRail` | Largura 80dp (V); `extended: true` com rótulos a partir de `minExtendedWidth` 256 (V) |
| Navigation drawer | Expanded e maior (padrão), modal no compact | `NavigationDrawer` (tile 56dp, V), `Drawer` (largura 304, V) | Muitos destinos ou agrupados |
| Top app bar | Todas | `AppBar`, `SliverAppBar` (small, medium, large via `.medium()`/`.large()`) | Altura 56dp (V) |
| Tabs | Alternar visões irmãs | `TabBar` + `TabBarView` | Primary e secondary tabs |
| Segmented button | 2 a 5 opções exclusivas ou múltiplas | `SegmentedButton<T>` | Alternativa a chips de filtro |

### Seleção, progresso, badges, tooltips, busca

- Switch/checkbox/radio: `Switch` (liga/desliga com efeito imediato), `Checkbox` (marcar itens, inclui tri-state), `Radio`/`RadioGroup` (uma opção entre várias).
- Progresso: `LinearProgressIndicator`, `CircularProgressIndicator` (determinado ou indeterminado; o M3 Expressive traz versão ondulada).
- Badge: `Badge` (ponto ou contagem sobre ícone).
- Tooltip: `Tooltip(message:)` com `waitDuration` para hover no desktop. Todo botão só com ícone precisa de tooltip.
- Busca: `SearchBar` + `SearchAnchor` (sugestões em visão expandida) ou `SearchAnchor.bar`.
- Seletores: `showDatePicker`, `showTimePicker`, `Slider`, `DropdownMenu`.

### Especificidades de desktop

- Hover: state layer de 8% e cursor de mão (`MouseRegion`, `InkWell.mouseCursor`). Foco visível por teclado em todo controle.
- Tooltips: `waitDuration` em torno de 500 ms (padrão do `Tooltip`; (especificação M3, não relido)), em botões com ícone.
- Menus de contexto: botão direito com `MenuAnchor` ou `ContextMenuController`; menus de aplicativo com `MenuBar`.
- Atalhos: `Shortcuts` + `Actions`, ou `CallbackShortcuts` para atalhos simples; exibir o atalho no item de menu (`MenuItemButton.shortcut`).
- Ordem de foco: `FocusTraversalGroup`, `FocusNode`, `Focus`. Scrollbar visível: `Scrollbar(thumbVisibility: true)`. Seleção de texto: `SelectionArea`.
- Densidade compacta e alvos menores que 48dp só com entrada de mouse e teclado; no celular manter 48dp.

## 7. Acessibilidade no M3

- Alvo mínimo de toque de 48dp (`kMinInteractiveDimension = 48.0`, V). Botões do Material já garantem isso por padrão (`MaterialTapTargetSize.padded`). Ao encolher visualmente, preservar a área de toque (`SizedBox`/`InkResponse` com padding), especialmente no celular.
- Contraste: 4,5:1 (texto normal) e 3:1 (texto grande e componentes de UI). Os pares on/surface do esquema gerado cumprem; revisar cores sobrescritas e cores semânticas próprias. `contrastLevel` oferece opção de alto contraste.
- Não depender só de cor para significado: sucesso, erro e aviso levam ícone e texto.
- Foco: indicador visível em toda ação por teclado (state layer de focus 10% mais borda quando necessário); ordem de foco lógica, `Semantics(label:)`, `ExcludeSemantics` só onde preciso.
- Texto: respeitar o fator de escala do sistema (`MediaQuery.textScalerOf`), nada com altura fixa que corte texto ampliado. Botões só com ícone precisam de `tooltip`/`semanticLabel`.
- Movimento: respeitar `MediaQuery.disableAnimationsOf` (reduzir movimento).

## 8. Ícones

### Material Symbols

Sucessor dos Material Icons. Fontes variáveis em três estilos (Outlined, Rounded, Sharp) e eixos:

| Eixo | Faixa | Padrão |
|---|---|---|
| Fill (preenchimento) | 0 a 1 | 0 |
| Weight (peso) | 100 a 700 | 400 |
| Grade | -50 a 200 | 0 |
| Optical size | 20 a 48 | 24 (48 no pacote Flutter) |

Padrão M3: ícone contorno quando inativo e preenchido (fill 1) quando selecionado (por exemplo no `NavigationBar`). Optical size ajusta a espessura ao tamanho, grade compensa fundo escuro (reduzir em tema escuro para texto/ícone não "estourar").

No Flutter: `Icons.*` nativo (constantes `IconData`, com variantes `_outlined`, `_rounded`, `_sharp`; o `icons.dart` do Flutter master tem 8.825 constantes). Pacote `material_symbols_icons`: `Symbols.home`, `Symbols.home_rounded`, parâmetros `fill`, `weight`, `grade`, `opticalSize` no `Icon`.

### Comparativo de bibliotecas

Dados do pub.dev e dos repositórios em 06/11/2026.

| Biblioteca | Ícones | Licença | Tree-shaking da fonte | Manutenção | Estilo e encaixe com M3 |
|---|---|---|---|---|---|
| `Icons` nativos (Material Icons) | cerca de 2,2 mil glifos em 4 estilos (8.825 constantes) | Apache 2.0 | Sim, por padrão em build release (`--no-tree-shake-icons` desliga) | Parte do Flutter (congelada com o material; vai para `material_ui`) | Material clássico, sem eixos variáveis. Encaixe total, zero dependência |
| `material_symbols_icons` 4.2960.0 | 4.264 em 3 estilos (outlined, rounded, sharp), mais variações de eixo | Apache 2.0 | Sim com `Symbols.nome`. `Symbols.get()` e `symbols_map.dart` exigem `--no-tree-shake-icons` ou desligam o shaking | 23/07/2026, 303 likes, 356 mil downloads/30 dias | Oficial do Google, eixos fill/weight/grade/opsz. Fontes do repositório: Outlined 10,6 MB, Rounded 15,1 MB, Sharp 8,8 MB (antes do shaking) |
| `lucide_icons_flutter` 4.0.2 | cerca de 2 mil (2.029 SVGs no Lucide upstream, Lucide 1.70.0 de 06/11/2026; o pacote usa a 1.67.0) | MIT no pacote (Lucide é ISC) | Sim (declarado no README) | 04/11/2026, 212 likes, 385 mil downloads | Traço fino de 6 espessuras (100 a 600), consistente, visual de ferramenta de desenvolvedor. Estilo diferente do M3, mas combina com tema escuro. O pacote antigo `lucide_icons` (0.257.0, 2023) está abandonado |
| `phosphor_flutter` 2.1.0 | README fala em 772 (upstream tem 1.512 regulares) | MIT | Sim (constantes de fonte) | 10/05/2024, 168 likes, 85 mil downloads | 6 pesos (thin a bold, fill, duotone). Estilo arredondado e amigável. Pacote estagnado |
| `hugeicons` 4.4.0 | mais de 6 mil gratuitos (stroke rounded) | MIT | Sim, declarado (ícones como dados vetoriais, widget `HugeIcon`) | 30/10/2026, 456 likes, 89 mil downloads | Traço arredondado único, visual próprio. Usa widget próprio, não `Icon` |
| `remixicon` 4.9.3 | mais de 3 mil | MIT | Fonte | 04/04/2026, 87 likes | Neutro, linha e preenchido (line/fill) |
| `tabler_icons` 2.5.0+1 | milhares no upstream | MIT | Fonte | 26/02/2023, parado | Não recomendado (sem manutenção) |

Observações:

- "Leve" depende do shaking: o Flutter só inclui os glifos referenciados como constantes. Usar `flutter build ... --analyze-size` para medir o efeito real em cada alvo. Não foi possível confirmar nesta pesquisa se o shaking preserva os eixos variáveis do `material_symbols_icons`; testar antes de fixar a decisão.
- Misturar duas famílias de ícones no mesmo app costuma desalinhar o traço. Escolher uma como padrão.
- `cupertino_icons` não é necessário num app só Material (Linux e Android); remover do pubspec se nenhum código usa `CupertinoIcons`.

### Recomendação de ícones

Adotar `material_symbols_icons` em estilo Outlined (com `fill: 1` nos estados selecionados), migrando por etapas a partir dos `Icons.*` atuais (muitos nomes coincidem), por ser o par oficial do M3, mantido e com tree-shaking, e deixar os `Icons` nativos como fallback de custo zero se a medição de tamanho do build não for satisfatória. Lucide é a alternativa se a equipe preferir um traço mais fino e técnico, mas foge do M3.

## 9. Material na web (secundário)

- `@material/web` (Material Web Components, `md-filled-button`, `md-outlined-text-field` etc.) está **em modo de manutenção, aguardando novos mantenedores** (aviso no README do repositório `material-components/material-web`). Para Angular, o README recomenda o Angular Material.
- Para a web em JS puro do Control Tower, a opção mais prudente é usar só os tokens do M3 em CSS: variáveis `--md-sys-color-*`, escala tipográfica, raios e durações calculados a partir dos mesmos valores deste documento, mantendo uma fonte única de tokens (por exemplo, um JSON gerado a partir do tema Flutter) em vez de depender de componentes em manutenção mínima.
- O `@material/web` ainda serve como referência de implementação dos componentes e traz `md-typescale-styles` e o gerador de tema.

## Recomendações para o Control Tower

1. **Seed e esquema:** manter `ColorScheme.fromSeed(seedColor: 0xFF5B8DEF)` e escolher `dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot` (padrão) ou `fidelity` explicitamente, em vez de sobrescrever papéis isolados (`surface`, `onSurface`, `onSurfaceVariant`). Se uma superfície precisar de tom específico, ajustar via papéis `surfaceContainer*` e documentar a exceção.
2. **Escuro e claro:** tema escuro como padrão (`ThemeMode.dark` ou sistema), com `darkTheme` e `theme` gerados da mesma seed. Oferecer opção "alto contraste" via `contrastLevel: 1.0`.
3. **Cores semânticas:** criar `ThemeExtension<CoresSemanticas>` com sucesso, aviso e info (cor, sobre-cor, container, sobre-container), harmonizadas à seed, com ícone e texto sempre junto da cor.
4. **Inter empacotada:** incluir Inter nos assets (400, 500, 600 e 700, ou a variável) e usar `ThemeData(fontFamily: 'Inter')`, sem `google_fonts` em runtime. Registrar a OFL no `LicenseRegistry`. Ativar `FontFeature.tabularFigures()` em números de painel.
5. **Type scale:** adotar a escala M3 de 15 estilos sem alterar os tamanhos; ajustar apenas tracking quando a Inter ficar larga. Usar `bodyMedium` (14) como corpo no desktop e `bodyLarge` (16) no celular.
6. **Forma:** tokens `Raios` (4, 8, 12, 16, 28, full) e remover o raio 18 solto do tema de campos (usar 8 outlined ou 12). Cartões em 12, diálogos em 28, botões e busca em full.
7. **Elevação:** separar camadas por `surfaceContainer*` e bordas (`outlineVariant`), sombra só em menus, diálogos e FAB; manter `surfaceTintColor: Colors.transparent` onde o tom automático atrapalhar.
8. **Densidade:** `VisualDensity.adaptivePlatformDensity` como base e compacta (-2) em tabelas, listas e barras de ferramentas no desktop. Mínimo de 48dp no celular.
9. **Classes de janela:** criar `ClasseDeJanela` no app com cortes 600, 840, 1200 e 1600 (compact a extra-large), medida por `MediaQuery.sizeOf` na raiz e `LayoutBuilder` em painéis.
10. **Navegação por classe:** `NavigationBar` (compact), `NavigationRail` (medium), `NavigationRail(extended: true)` com rótulos (expanded e maior); ajustar a altura do `NavigationBar` de 64 para os 80dp do M3 se não houver motivo para o desvio.
11. **Sem `flutter_adaptive_scaffold`:** construir um `ScaffoldAdaptativo` próprio, pequeno e testável; evitar os sucessores de terceiros ainda sem tração.
12. **Layouts canônicos:** chat e tarefas em list-detail, editor de workflow com painel de propriedades como supporting pane, painel de controle como feed de cartões que muda de 1 para N colunas.
13. **Ícones:** `material_symbols_icons` Outlined como padrão (fill nos selecionados), migrar gradualmente de `Icons.*`, medir com `--analyze-size` e remover `cupertino_icons` se não usado. Fallback: `Icons` nativos.
14. **Desktop de verdade:** hover com state layer, `Tooltip` em todo botão de ícone, atalhos com `Shortcuts`/`Actions` exibidos nos menus, `MenuBar` e menu de contexto com `MenuAnchor`, `Scrollbar` visível e foco por teclado.
15. **Componentes preferidos:** `FilledButton` para a ação principal e `FilledButton.tonal` para a secundária, chips Suggestion para atalhos do chat, `SegmentedButton` para alternâncias de 2 a 5 opções, `SnackBar` para feedback leve e `AlertDialog` só para confirmações (aprovação de comandos usa diálogo ou aviso persistente).
16. **Movimento:** usar `Durations` e `Easing` do Flutter (short2 para estados, medium2 para painéis, `Easing.emphasizedDecelerate` na entrada e `emphasizedAccelerate` na saída) e respeitar `disableAnimations`.
17. **Material 3 Expressive:** não adotar agora. Acompanhar o `material_ui` (`StyleVariant`); reavaliar quando mais componentes tiverem suporte oficial.
18. **`material_ui`:** planejar a migração de `package:flutter/material.dart` para `package:material_ui/material_ui.dart` (`dart fix --apply --code=migrate_design_widgets`), pois o material embutido está congelado e será deprecado. Fazer em um commit isolado, com os testes do Flutter rodando antes e depois.
19. **Acessibilidade como critério de pronto:** alvos de 48dp no celular, contraste 4,5:1 e 3:1, foco visível, `Semantics` e escala de texto do sistema testadas em cada tela nova.
20. **Web:** manter só tokens CSS derivados dos mesmos valores (sem `@material/web`, em manutenção mínima) e gerar a lista de tokens de uma fonte única.

## Fontes

Material Design e tokens:
- Material Design 3 (site oficial, renderizado por JS, não legível por fetch): https://m3.material.io
- material-components-android, tokens de elevação, estado e movimento: https://github.com/material-components/material-components-android
- Shape (escala de cantos): https://github.com/material-components/material-components-android/blob/master/docs/theming/Shape.md
- Elevação (tokens): https://github.com/material-components/material-components-android/blob/master/lib/java/com/google/android/material/elevation/res/values/tokens.xml
- State layers (tokens): https://github.com/material-components/material-components-android/blob/master/lib/java/com/google/android/material/resources/res/values/tokens.xml
- Movimento (tokens): https://github.com/material-components/material-components-android/blob/master/lib/java/com/google/android/material/motion/res/values/tokens.xml
- material-color-utilities (papéis e tons): https://github.com/material-foundation/material-color-utilities/blob/main/dart/lib/dynamiccolor/material_dynamic_colors.dart
- material-color-utilities (variantes de esquema): https://github.com/material-foundation/material-color-utilities/tree/main/dart/lib/scheme
- Window size classes (Android): https://developer.android.com/develop/ui/compose/layouts/adaptive/window-size-classes
- Canonical layouts (Android): https://developer.android.com/develop/ui/compose/layouts/adaptive/canonical-layouts
- Codelab de layout adaptativo (margens, painéis): https://developer.android.com/codelabs/adaptive-material-guidance
- Material Web (README e modo de manutenção): https://github.com/material-components/material-web

Flutter:
- Tipografia M3 (`typography.dart`): https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/material/typography.dart
- Movimento (`motion.dart`): https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/material/motion.dart
- ColorScheme e DynamicSchemeVariant (`color_scheme.dart`): https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/material/color_scheme.dart
- ThemeData e VisualDensity (`theme_data.dart`): https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/material/theme_data.dart
- Constantes do Material (`constants.dart`): https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/material/constants.dart
- Abordagem geral de apps adaptativos: https://docs.flutter.dev/ui/adaptive-responsive/general
- Telas grandes: https://docs.flutter.dev/ui/adaptive-responsive/large-screens
- Migração para material_ui e cupertino_ui: https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui
- Material and Cupertino decoupling are here: https://flutter.dev/blog/decoupling-material-cupertino
- What's new in Flutter 3.47: https://flutter.dev/blog/whats-new-in-flutter-3-47
- ThemeData.useMaterial3 true por padrão: https://docs.flutter.dev/release/breaking-changes/material-3-default.html

Pacotes (pub.dev):
- material_ui: https://pub.dev/packages/material_ui
- material_3_expressive: https://pub.dev/packages/material_3_expressive
- flutter_adaptive_scaffold (descontinuado): https://pub.dev/packages/flutter_adaptive_scaffold
- adaptive_scaffold_router: https://pub.dev/packages/adaptive_scaffold_router
- prism_adaptive_scaffold: https://pub.dev/packages/prism_adaptive_scaffold
- dynamic_color: https://pub.dev/packages/dynamic_color
- material_color_utilities: https://pub.dev/packages/material_color_utilities
- google_fonts: https://pub.dev/packages/google_fonts
- material_symbols_icons: https://pub.dev/packages/material_symbols_icons
- lucide_icons_flutter: https://pub.dev/packages/lucide_icons_flutter
- phosphor_flutter: https://pub.dev/packages/phosphor_flutter
- hugeicons: https://pub.dev/packages/hugeicons
- remixicon: https://pub.dev/packages/remixicon
- tabler_icons: https://pub.dev/packages/tabler_icons
- API do pub.dev (versão, data, likes, descontinuação): https://pub.dev/api/packages/<pacote>

Fontes e ícones (repositórios):
- Inter (licença OFL 1.1 e releases): https://github.com/rsms/inter
- Inter no Google Fonts (METADATA): https://github.com/google/fonts/tree/main/ofl/inter
- Material Symbols Icons para Flutter (fontes e README): https://github.com/timmaffett/material_symbols_icons
- Lucide (ícones e releases): https://github.com/lucide-icons/lucide
- Phosphor core: https://github.com/phosphor-icons/core
- google_fonts (README, bundling e licença): https://github.com/flutter/packages/tree/main/packages/google_fonts

Material 3 Expressive (fontes secundárias):
- Android Authority, Material 3 Expressive: https://www.androidauthority.com/google-material-3-expressive-features-changes-availability-supported-devices-3556392/
- Dezeen, Google Material Design update: https://www.dezeen.com/2025/05/28/google-ushers-in-age-of-expressive-interfaces-with-material-design-update/amp/
- SAP Fiori, canonical layouts (contagem de painéis): https://www.sap.com/design-system/fiori-design-android/v26-4/foundations/adaptive-layout/canonical-layouts
