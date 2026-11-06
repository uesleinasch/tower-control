# Referências de UI/UX para o Control Tower

Este documento reúne princípios gerais de UI/UX, com fonte, para servir de base teórica ao design system do Control Tower. O design system usará o Material Design (pesquisado à parte). Aqui ficam as regras que valem para qualquer sistema visual: usabilidade, hierarquia, espaçamento, tipografia, cor, acessibilidade, estados, formulários, navegação, responsividade, texto de interface, ícones e interfaces de chat e de agentes.

**Perfil de usuários.** Pessoas de tecnologia com habilidade média, acostumadas a apps de celular e a programas de computador mais avançados, e programadores juniores. Tipografia: Inter. Clientes: app Flutter (Material 3) para desktop Linux e Android, mais uma web em JS puro. Janelas de desktop de tamanhos variados.

**Como ler.** Cada seção traz regras curtas, o porquê quando não é óbvio e a fonte. Números só aparecem quando a fonte os dá. Onde só encontrei fonte secundária, o texto avisa. A seção final traduz tudo em diretrizes para o produto.

---

## 1. Heurísticas de usabilidade e leis de UX

### 1.1 As 10 heurísticas de Nielsen (resumo aplicável)

Fonte: [NN/g, 10 Usability Heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/).

1. **Visibilidade do status do sistema.** Dizer sempre o que está acontecendo, com feedback em tempo razoável. Em um orquestrador, toda tarefa, execução e fluxo precisa mostrar estado atual (na fila, rodando, em revisão, bloqueada).
2. **Correspondência com o mundo real.** Usar a linguagem do usuário, não a do sistema. Os termos do produto (persona, posição, equipe) valem se forem usados de forma consistente e explicados na primeira vez.
3. **Controle e liberdade do usuário.** Saída de emergência clara: cancelar, desfazer, voltar. Toda execução longa precisa de "parar".
4. **Consistência e padrões.** Mesma coisa com mesmo nome e mesma aparência; seguir convenções da plataforma.
5. **Prevenção de erros.** Eliminar condições propensas a erro ou pedir confirmação antes da ação. Preferir impedir (desabilitar com motivo) a deixar errar.
6. **Reconhecimento em vez de memorização.** Opções e informações visíveis ou fáceis de recuperar; ajuda contextual em vez de tutorial longo. Exemplo: buscar a persona numa lista, não exigir digitar o id.
7. **Flexibilidade e eficiência de uso.** Atalhos escondidos do novato e disponíveis ao especialista: aceleradores como teclado e gestos, personalização.
8. **Design estético e minimalista.** Cada informação extra compete com a relevante. Isso não proíbe densidade, proíbe ruído.
9. **Ajudar a reconhecer, diagnosticar e corrigir erros.** Mensagem em linguagem simples, que aponta o problema e sugere a solução.
10. **Ajuda e documentação.** Se precisar, que seja fácil de achar, focada na tarefa e curta.

### 1.2 Leis de UX relevantes

Fonte: [Laws of UX](https://lawsofux.com/) e páginas de cada lei, salvo indicação.

- **Lei de Fitts.** O tempo para atingir um alvo depende da distância e do tamanho dele. Alvos grandes o bastante, com espaço entre eles, em lugares fáceis de alcançar ([Fitts](https://lawsofux.com/fittss-law/)). No desktop, bordas e cantos da janela são alvos "infinitos"; no celular, a zona do polegar.
- **Lei de Hick.** O tempo de decisão cresce com o número e a complexidade das opções. Reduzir escolhas quando o tempo importa, quebrar tarefas complexas em passos, destacar a opção recomendada, usar onboarding progressivo, sem simplificar a ponto de abstrair ([Hick](https://lawsofux.com/hicks-law/)).
- **Lei de Jakob.** Usuários passam a maior parte do tempo em outros produtos e preferem que o seu funcione do mesmo jeito ([Jakob](https://lawsofux.com/jakobs-law/)). Para este público, vale copiar as convenções de editores de código, gerenciadores de tarefas e apps de chat.
- **Lei de Miller e carga cognitiva.** A memória de trabalho segura cerca de 7 (±2) itens ([Miller](https://lawsofux.com/millers-law/)). O número não é regra de layout; a lição é agrupar em blocos (chunking) e não obrigar o usuário a lembrar. Carga cognitiva é o esforço mental total para entender e usar a interface ([Cognitive Load](https://lawsofux.com/cognitive-load/)).
- **Limiar de Doherty.** A produtividade sobe quando computador e usuário interagem em menos de 400 ms, sem que um espere o outro ([Doherty](https://lawsofux.com/doherty-threshold/)).
- **Proximidade e semelhança (Gestalt).** Elementos próximos são percebidos como relacionados e organizados mais rápido ([Proximidade](https://lawsofux.com/law-of-proximity/)); elementos parecidos são percebidos como do mesmo grupo ou função ([Semelhança](https://lawsofux.com/law-of-similarity/)). Visão geral dos princípios: [IxDF, Gestalt](https://www.interaction-design.org/literature/topics/gestalt-principles).
- **Lei de Tesler.** Todo sistema tem uma complexidade que não some; alguém a absorve ([Tesler](https://lawsofux.com/teslers-law/)). Em um orquestrador de workflows, a complexidade é real: a decisão de design é o que o sistema resolve com padrões razoáveis e o que o usuário configura.

Regras práticas:

- Agrupe por proximidade antes de usar linha, caixa ou cor. Espaço entre grupos maior que o espaço dentro do grupo.
- Use o mesmo estilo para itens da mesma função (todo botão primário igual) e estilos distintos para funções distintas.
- Nunca faça o usuário memorizar um dado de uma tela para usar em outra: mostre o dado no ponto de uso.

---

## 2. Hierarquia visual

Fontes: [NN/g, Visual Hierarchy](https://www.nngroup.com/articles/visual-hierarchy-ux-definition/); índice do livro [Refactoring UI](https://www.refactoringui.com/) (os títulos dos capítulos são a fonte das regras abaixo; não li o texto completo do livro).

- **Três alavancas do NN/g:** cor e contraste, escala, agrupamento (proximidade e regiões comuns). O que é maior, mais contrastante ou mais isolado atrai o olhar primeiro.
- **Teste do olho semicerrado (squint test).** Borre ou semicerre os olhos: o que ainda se destaca é a hierarquia real. NN/g mostra que o conteúdo (uma foto de cor forte, por exemplo) pode criar uma hierarquia não planejada.
- **Nem todos os elementos são iguais** (Refactoring UI, cap. "Hierarchy is Everything"). Defina um elemento principal por tela e deixe o resto recuar.
- **Desenfatize para enfatizar.** Em vez de aumentar o que importa, reduza o que não importa (cinza mais claro, tamanho menor, peso menor).
- **Tamanho não é tudo.** Combine peso e contraste: texto pequeno e em negrito pode pesar mais que texto grande e leve.
- **Rótulos são último recurso.** Quando o dado se explica sozinho ("12 tarefas", "R$ 3,40"), dispense o rótulo "Total de tarefas:" ou funda-o com o valor.
- **Separe a hierarquia visual da hierarquia do documento.** Um `h3` pode parecer pequeno; o que decide é o papel na tela.
- **Não use texto cinza sobre fundo colorido.** Use uma cor do mesmo matiz com luminosidade ajustada para manter o contraste.
- **Menos pesos.** Dois ou três pesos (regular, médio, semibold) bastam para uma ferramenta densa.

---

## 3. Espaçamento, grid e densidade

Fontes: [Spec, 8-Point Grid](https://spec.fm/specifics/8-pt-grid); índice de [Refactoring UI](https://www.refactoringui.com/) (capítulo "Layout and Spacing"); [NN/g, Data Tables](https://www.nngroup.com/articles/data-tables/); [WCAG 2.2, Target Size](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html).

- **Escala de espaçamento fixa.** Use múltiplos de 8 para dimensões, padding e margens, combinados com uma linha de base de 4 para texto e casos menores (Spec). Uma escala curta (4, 8, 12, 16, 24, 32, 48, 64) elimina decisões arbitrárias. Refactoring UI chama isso de "estabeleça um sistema de espaçamento e tamanhos" e "limite suas escolhas".
- **Comece com espaço demais e tire.** É mais fácil enxugar que perceber o aperto (Refactoring UI, "Start with too much white space").
- **Evite espaçamento ambíguo.** O espaço entre grupos deve ser claramente maior que dentro do grupo, senão a proximidade engana (Refactoring UI, "Avoid ambiguous spacing"; Gestalt).
- **Não preencha a tela inteira.** Conteúdo de leitura e formulários não precisam esticar com a janela (Refactoring UI, "You don't have to fill the whole screen").
- **Enquadre ícones em caixas de tamanho fixo.** Ícones de tamanhos diferentes cabem num quadro de 16, 20 ou 24, mantendo o grid (Spec).
- **Densidade para especialistas.** Tabelas e listas são mais eficientes que cartões para comparar registros e achar padrões (NN/g). Para uma ferramenta densa:
  - reduza padding vertical de linhas, não o tamanho de fonte nem o alvo de clique;
  - mantenha o alvo de clique em pelo menos 24 × 24 px no desktop (WCAG 2.5.8) mesmo com linhas compactas (padding invisível amplia a área);
  - ofereça duas densidades (confortável e compacta) em vez de uma só, deixando o usuário escolher;
  - mantenha cabeçalho de tabela sempre visível para o usuário saber a que cada célula se refere (NN/g, "Users will always know what they're looking at").
- **Tabelas:** apoie quatro tarefas: achar, comparar, ver/editar uma linha e agir sobre registros (NN/g). Para editar uma linha, evite modal que cubra os registros vizinhos: usuários consultam outras linhas enquanto editam (NN/g). Prefira painel lateral ou edição na linha.

---

## 4. Tipografia

Fontes: [Inter](https://rsms.me/inter/), [Inter Lab](https://rsms.me/inter/lab/), [Baymard, Line Length](https://baymard.com/blog/line-length-readability), índice de [Refactoring UI](https://www.refactoringui.com/), [WCAG 2.2 Reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html).

### 4.1 Regras gerais

- **Escala tipográfica definida.** Poucos tamanhos, com passos claros entre eles (Refactoring UI, "Establish a type scale"). Para UI densa, 5 a 7 estilos bastam (por exemplo: legenda, corpo pequeno, corpo, subtítulo, título de seção, título de tela).
- **Comprimento de linha de 50 a 75 caracteres** para texto corrido. Emil Ruder indica 50 a 60 como ótimo; até 75 é aceitável (Baymard). Linha longa demais dificulta achar o início da próxima; linha curta demais quebra o ritmo. O artigo da Baymard cita o WCAG 1.4.8 (máximo de 80 caracteres), critério de nível AAA. A regra vale para prosa; não se aplica a código nem a tabelas.
- **Altura de linha proporcional ao tamanho:** texto pequeno pede mais entrelinha relativa; títulos grandes pedem menos (Refactoring UI, "Line-height is proportional"). Não encontrei número em fonte primária; ver as sugestões de ponto de partida na seção de implicações, marcadas como convenção.
- **Alinhe pensando em leitura:** texto à esquerda; números em tabelas alinhados à direita, de preferência com números tabulares.
- **Reflow.** O conteúdo deve se reorganizar a 320 px de largura CSS (equivalente a 1280 px com zoom de 400%) sem rolagem em duas dimensões, exceto para tabelas de dados, diagramas e conteúdo que exija layout 2D ([WCAG 1.4.10](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)). O editor de grafo é exceção legítima.

### 4.2 Inter

Fonte: [rsms.me/inter](https://rsms.me/inter/) e [Inter Lab](https://rsms.me/inter/lab/).

- **Eixos variáveis.** `opsz` de 14 a 32, `wght` de 100 a 900. O design de texto (opsz baixo) tem x-height alta e detalhes que aumentam o contraste em tamanhos pequenos; o design display (opsz alto) tem linhas limpas e curvas suaves para texto grande. Altura-x: 1118 UPM em opsz 14 e 1056 UPM em opsz 32; altura de caixa alta: 1490 UPM (Inter FAQ).
- **Aplicação prática:** use a variante de texto no corpo e em rótulos de UI; use Inter Display (ou `opsz` alto) apenas em títulos grandes. Quando o app usa a fonte variável, o `opsz` pode seguir o tamanho; se usar a estática, escolha entre Inter e Inter Display por tamanho. O limite exato em que trocar não vem da fonte: o intervalo documentado de `opsz` é 14 a 32, e títulos acima de uns 24 px são os candidatos (convenção, não regra documentada).
- **Recursos OpenType úteis (Inter Lab e página da família):**
  - `tnum`: números tabulares, para colunas comparáveis (custos, tokens, contagens, horários). Obrigatório em tabelas e no painel.
  - `zero`: zero com barra, para diferenciar `0` de `O` (ids, caminhos, comandos).
  - `case`: formas para caixa alta, ajusta parênteses e símbolos ao redor de maiúsculas e números (rótulos em caixa alta).
  - `calt`: alternativas contextuais, ligado por padrão; ajusta pontuação conforme o vizinho e forma setas como `->`. Desligue em texto de código, onde ligaduras confundem.
  - `frac`: converte `1/3` em fração, onde fizer sentido.
  - `ss01` (dígitos abertos), `ss02` (desambiguação com zero), `ss03` (aspas e vírgulas redondas), `ss04` (desambiguação sem zero).
  - `cv11` (a de um andar), `cv05` (l minúsculo com cauda), `cv08` (I maiúsculo com serifa), `cv01` (um alternativo), `cv09` (três de topo reto). `cv05` e `cv08` ajudam a distinguir `l`, `I` e `1` em ids e logs.
- **Inter não é monoespaçada.** Código, logs, ids e comandos pedem uma fonte mono à parte. Números em tabela usam `tnum` da própria Inter.
- **Pesos.** A fonte tem designs dedicados por glifo para os pesos 100, 400 e 900 (Inter); na prática de UI, 400, 500 e 600 cobrem texto, ênfase e títulos.

---

## 5. Cor e contraste

Fontes: [WCAG 1.4.3](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html), [1.4.11](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html), [1.4.1](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html), [Refactoring UI, Building Your Color Palette](https://www.refactoringui.com/previews/building-your-color-palette), [NN/g, Dark Mode](https://www.nngroup.com/articles/dark-mode/).

### 5.1 Números de contraste (WCAG 2.2, nível AA)

- **Texto:** pelo menos 4,5:1. **Texto grande:** pelo menos 3:1 (1.4.3). Texto de componente inativo, decoração pura e logotipos ficam fora.
- **Componentes de UI e indicadores de estado:** pelo menos 3:1 contra as cores adjacentes (1.4.11). Vale para borda de campo, ícone sem rótulo, marca de checkbox, indicador de foco e de seleção.
- **Exemplos reprovados citados pelo W3C:** borda de checkbox `#9D9D9D` sobre branco, com 2,7:1; indicador de foco cinza `#AAA` sobre branco, com 2,3:1; link identificado só por sublinhado vermelho de baixo contraste.
- **Hover** não precisa de 3:1 contra o estado normal, mas não pode tirar o contraste do componente com o entorno (1.4.11).

### 5.2 Papéis de cor

- **Neutros** (cinzas) para texto, fundos e bordas; é a maior parte da interface.
- **Primária** para ações principais e elementos de marca, em poucos tons.
- **Acento e semânticas:** vermelho para destrutivo e erro, amarelo para aviso, verde para sucesso e tendência positiva (Refactoring UI). Informação costuma ser azul (convenção).
- **Várias tonalidades por cor.** Refactoring UI diz que não é raro precisar de até 10 cores com 5 a 10 tons cada em uma UI complexa. Defina a escala de tons de antemão (tokens), não improvise tons caso a caso.
- **Cores para categorias** (tags, linhas de gráfico, tipos de nó no grafo) exigem mais tons de acento; defina um conjunto fechado e teste a distinção sem depender só de cor.

### 5.3 Não depender só de cor

- **WCAG 1.4.1 (nível A):** a cor não pode ser o único meio de transmitir informação. Acrescente texto, forma, ícone ou padrão.
- Estado de execução = cor + ícone + rótulo. Erro de formulário = cor + ícone + texto. Arestas de grafo com semântica (aprovado e recusado) = cor + estilo de linha ou rótulo.

### 5.4 Modo escuro

- **Evidência.** NN/g, ao revisar a literatura: para usuários de visão normal, o modo claro leva a melhor desempenho na maior parte dos casos; ainda assim recomenda oferecer o modo escuro como opção, porque alguns usuários com deficiência visual vão melhor com ele, há possíveis efeitos de longo prazo do modo claro e muita gente simplesmente prefere o escuro.
- **Regras práticas** (convenções amplamente usadas, não extraídas de fonte única): não use branco puro sobre preto puro; use texto levemente atenuado sobre cinza muito escuro; dessature as cores de acento; marque elevação por tom de superfície mais claro em vez de sombra; reverifique todos os contrastes (4,5:1 e 3:1) no tema escuro, que é onde as regressões aparecem.
- **Siga o sistema por padrão** e permita escolher manualmente.

---

## 6. Acessibilidade

Fontes: [WCAG 2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html), [2.5.5](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html), [2.4.7](https://www.w3.org/WAI/WCAG22/Understanding/focus-visible.html), [2.4.13](https://www.w3.org/WAI/WCAG22/Understanding/focus-appearance.html), [2.4.11](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html), [2.5.7](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html), [2.1.4](https://www.w3.org/WAI/WCAG22/Understanding/character-key-shortcuts.html), [2.3.3](https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html), [4.1.3](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html), [NN/g, Touch Targets](https://www.nngroup.com/articles/touch-target-size/).

### 6.1 Alvos de toque e de clique

- **Mínimo AA (2.5.8): 24 × 24 px CSS.** Exceção: um alvo menor passa se um círculo de 24 px centrado nele não tocar outro alvo (espaçamento). Outras exceções: controle equivalente disponível, alvo em linha dentro de texto, controle do navegador sem alteração, apresentação essencial.
- **Recomendado AAA (2.5.5): 44 × 44 px CSS.**
- **NN/g (toque):** pelo menos 1 cm × 1 cm de tamanho físico renderizado, com espaço de segurança entre alvos; alvos pequenos e colados aumentam erros ("slips").
- **Apple HIG:** só achei a cifra de 44 × 44 pt em fontes secundárias, sem confirmar na página da Apple. Trate como consistente com o 44 px do WCAG AAA, não como citação verificada.
- **Prática:** no celular, 44 a 48 px como alvo mínimo; no desktop, 24 px como piso absoluto e 32 px como alvo confortável de ponteiro (convenção). A área clicável pode ser maior que o desenho do ícone (padding invisível).

### 6.2 Foco e teclado

- **Foco visível (2.4.7, AA):** todo elemento que recebe foco de teclado tem indicador visível.
- **Aparência do foco (2.4.13, AAA):** área do indicador pelo menos igual a um perímetro de 2 px do componente e contraste de 3:1 entre os estados com e sem foco. A forma mais simples de atender é um contorno sólido de 2 px.
- **Foco não obscurecido (2.4.11, AA):** o item focado fica pelo menos parcialmente visível; cabeçalhos fixos, rodapés fixos e diálogos não modais são os culpados típicos. Em listas e no grafo, role o item focado para dentro da área visível.
- **Teclado primeiro no desktop.** Todo fluxo possível com mouse deve ser possível com teclado: ordem de tabulação lógica, Enter e Espaço ativam, Esc fecha, setas navegam em listas e menus.
- **Atalhos de uma tecla (2.1.4, A):** devem poder ser desligados, remapeados com modificador, ou valer só com foco no componente. Importante para um chat, onde teclas soltas colidem com digitação.
- **Arrastar (2.5.7, AA):** toda ação por arrastar precisa de alternativa com um único ponteiro e sem arrastar (por exemplo, conectar nós por menu ou botão). Vale para o editor de grafo e para reordenar listas.

### 6.3 Leitores de tela, movimento e mensagens

- **Mensagens de status (4.1.3, AA):** mudanças que não recebem foco (toast, "salvo", progresso, nova resposta) precisam ser anunciadas a tecnologias assistivas por função ou propriedade apropriadas. O W3C lista como falha usar `role="alert"` ou `aria-live="assertive"` em conteúdo que não seja importante e urgente.
- **Nome acessível em todo controle sem texto** (botão só com ícone precisa de rótulo e dica).
- **Movimento (2.3.3, AAA):** respeite a preferência do sistema por movimento reduzido e elimine movimento desnecessário. Animação deve ser a serviço do significado (transição de estado), não decoração.
- **Zoom e texto grande:** layouts que não quebram com fonte maior e com 320 px (ver 4.1).

---

## 7. Estados e feedback

Fontes: [NN/g, Response Times](https://www.nngroup.com/articles/response-times-3-important-limits/), [NN/g, Skeleton Screens](https://www.nngroup.com/articles/skeleton-screens/), [NN/g, Confirmation Dialogs](https://www.nngroup.com/articles/confirmation-dialog/), [NN/g, Empty States](https://www.nngroup.com/articles/empty-state-interface-design/), [NN/g, Toggle Switch](https://www.nngroup.com/articles/toggle-switch-guidelines/), [WCAG 1.4.11](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).

### 7.1 Estados de um componente

Todo componente interativo define: **repouso, hover, foco, pressionado, desabilitado**, e quando couber **carregando, selecionado, erro, sucesso**.

- Foco e seleção precisam de 3:1 contra o entorno (WCAG 1.4.11). Hover pode ser sutil, mas não pode apagar o contraste.
- Hover não existe no toque: nunca esconda ação essencial atrás de hover; no celular, mostre-a sempre ou por gesto com alternativa visível.
- Desabilitado sem explicação frustra: se possível, explique o motivo (dica ou texto de apoio).
- Toggles têm efeito imediato, sem botão Salvar; se a ação precisa de confirmação, use checkbox ou radio com botão (NN/g, Toggle Switch). Não misture toggles imediatos com campos que exigem Salvar no mesmo formulário.

### 7.2 Tempo de resposta

NN/g, Response Times (Nielsen):

- **0,1 s:** limite para o usuário sentir que o sistema reage instantaneamente; só mostrar o resultado. Também é o limite para sentir que manipula diretamente os objetos (selecionar, destacar).
- **1 s:** limite para o fluxo de pensamento não se interromper; o usuário percebe o atraso, mas não precisa de feedback especial. Também é o limite para sentir que navega livremente.
- **10 s:** limite para manter a atenção. Acima disso, o usuário tende a mudar de tarefa; mostre progresso e permita interromper.
- Complemento do Laws of UX: o limiar de Doherty fala em 400 ms como ponto em que o ritmo de interação deixa de travar o usuário.

### 7.3 Skeleton, spinner e barra de progresso

NN/g, Skeleton Screens:

- **Spinner:** melhor para esperas de 2 a 10 s e para um módulo isolado (um cartão no painel).
- **Skeleton:** para carga de tela inteira, com espera abaixo de 10 s; dá noção da estrutura e reduz carga cognitiva.
- **Barra de progresso:** fortemente recomendada acima de 10 s e para processos (upload, download, conversão); acima de 10 s é preciso estimativa explícita de duração.
- Não use skeleton para processos que não sejam carga de tela.

### 7.4 Estado vazio

NN/g, Empty States (3 diretrizes): comunicar o status do sistema (por que está vazio: carregando, sem resultados, sem permissão, nunca usado), dar pistas de aprendizado (o que esta área faz) e oferecer caminho direto para a tarefa principal (botão ou link para o próximo passo, não só "Sem registros").

### 7.5 Ações destrutivas: confirmar ou desfazer

- **Confirmação** só quando a ação é grave ou irreversível, e sempre específica: restate o pedido e diga o que vai acontecer, com nome do item e efeito (NN/g). Diálogo genérico ("Tem certeza?") vira clique automático; diálogos em excesso perdem o efeito.
- **Desfazer** é melhor que confirmar quando a ação é reversível (ação, depois aviso com "Desfazer") porque não interrompe o fluxo (heurísticas 3 e 5). A confirmação com digitação do nome do item cabe em ações de grande impacto (excluir equipe ou persona).
- Rotule o botão destrutivo com o verbo e o objeto ("Excluir persona"), não "OK" ou "Sim".

---

## 8. Formulários e entrada

Fontes: [NN/g, Placeholders](https://www.nngroup.com/articles/form-design-placeholders/), [NN/g, Errors in Forms](https://www.nngroup.com/articles/errors-forms-design-guidelines/), [NN/g, Error-Message Guidelines](https://www.nngroup.com/articles/error-message-guidelines/), [Baymard, Inline Validation](https://baymard.com/blog/inline-form-validation), [web.dev, Sign-in Form Best Practices](https://web.dev/articles/sign-in-form-best-practices).

- **Rótulo sempre visível, fora do campo.** Placeholder no lugar do rótulo é prejudicial (NN/g lista 7 razões; o rótulo some ao digitar, o que sobrecarrega a memória). Placeholder serve só como dica complementar. Texto essencial vai fora do campo, sempre visível.
- **Validação inline com critério (Baymard):** não valide antes de o usuário interagir (a validação prematura "grita" com quem nem começou a digitar); valide ao sair do campo ou ao terminar de digitar; mostre também validação positiva (marca de campo correto) em campos complexos. A Baymard encontrou que 31% dos sites testados não tinham validação inline e 4% a implementavam errado.
- **Sucesso só onde ajuda.** Indicadores de sucesso são úteis em campos complexos (senha, nome de usuário disponível); campo só obrigatório não precisa de "ok" (NN/g).
- **Preserve a entrada.** Nunca apague o que o usuário digitou quando houver erro; deixe editar (NN/g, Error-Message Guidelines).
- **Erro perto do campo, com texto,** não só cor ou ícone; leve o foco ao primeiro erro ao enviar.
- **Defaults sensatos** e preenchimento automático: reduzem digitação e erros. Use os atributos nativos da plataforma (tipo de teclado, autocompletar) onde existirem (web.dev).
- **Campos obrigatórios e opcionais** marcados de forma consistente; peça só o necessário (heurística 8).
- **Entrada estruturada** (ids, cron, JSON) exige formato visível, exemplo, prévia do resultado ("próximas execuções: ...") e erro que aponta a posição do problema. Para usuários juniores, ofereça construtor visual além do campo cru.
- **Ações do formulário:** rótulo com verbo ("Salvar equipe", "Criar rotina"), botão primário um só, cancelar como ação secundária.

---

## 9. Navegação e arquitetura de informação

Fontes: [NN/g, Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/), [NN/g, Accelerators](https://www.nngroup.com/articles/ui-accelerators/), [NN/g, Recognition and Recall](https://www.nngroup.com/articles/recognition-and-recall/), [Jakob's Law](https://lawsofux.com/jakobs-law/), [NN/g, Heurísticas](https://www.nngroup.com/articles/ten-usability-heuristics/).

- **Padrões conhecidos primeiro** (Jakob): navegação lateral para áreas, lista e detalhe, abas dentro de uma área, paleta de comandos. Estranhar o padrão tem custo de aprendizado.
- **Poucas áreas de topo, nomes que o usuário reconhece,** e o mesmo nome em todos os lugares e em todas as plataformas.
- **Divulgação progressiva (Nielsen):** mostre primeiro os recursos centrais, deixe os secundários sob demanda. Difere da divulgação em etapas (wizard), que mostra primeiro o que vem primeiro na sequência de uma tarefa. Aplique em configurações avançadas de persona, política de execução e opções do nó.
- **Reconhecimento em vez de recall:** listas e seletores em vez de campos de texto livres para ids; mostre o contexto (nome da tarefa, da persona) ao lado da ação.
- **Aceleradores (heurística 7, NN/g):**
  - ofereça atalhos de teclado e gestos para as ações frequentes;
  - mostre o atalho na própria interface, alinhado à direita do item de menu ou entre parênteses, com estilo diferente do rótulo, para o especialista ver e o novato ignorar;
  - mantenha uma folha de atalhos (cheat sheet) como último recurso de descoberta;
  - permita personalização.
- **Atalhos de uma tecla só se não conflitarem com digitação** e se puderem ser desligados (WCAG 2.1.4).
- **Sempre diga onde o usuário está** (título da tela, item de navegação ativo) e como voltar.
- **Paleta de comandos** (busca de ações) como acelerador universal para um produto com muitas áreas. É convenção de ferramentas de dev; a fonte consultada trata de aceleradores em geral, não da paleta especificamente.
- **Arrastar e soltar** precisa de sinalizador de "agarrável" (alça ou cursor), feedback durante o gesto e alternativa sem arrastar (NN/g, Drag-and-Drop; WCAG 2.5.7). No toque, deixe pelo menos 1 cm × 1 cm livre ao redor do objeto arrastado para o dedo não cobrir o feedback.

---

## 10. Responsividade e layout adaptativo

Fontes: [NN/g, Responsive Web Design](https://www.nngroup.com/articles/responsive-web-design-definition/), [WCAG 1.4.10 Reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html), [NN/g, Touch Targets](https://www.nngroup.com/articles/touch-target-size/), [NN/g, Data Tables](https://www.nngroup.com/articles/data-tables/).

- **Breakpoints reorganizam elementos** conforme a largura: uma interface de três colunas vira duas e depois uma (NN/g). Use breakpoints pela largura disponível da janela, não pelo tipo de dispositivo, porque no desktop a janela varia.
- **Faixas de largura (convenção, valores ajustáveis):** compacta (menos de 600 px, celular e janela estreita: uma coluna, navegação inferior ou recolhida), média (600 a 1023 px: duas colunas, lista e detalhe lado a lado quando couber) e larga (1024 px ou mais: navegação fixa, lista, detalhe e, se preciso, painel auxiliar). Os números exatos virão do Material.
- **Padrão lista-detalhe:** em tela larga, lado a lado; em tela estreita, uma de cada vez com voltar. O estado da seleção sobrevive à mudança de largura.
- **Prioridade de conteúdo:** decida o que some, o que recolhe e o que vira menu ao estreitar; nunca esconda ação essencial.
- **Tabelas e grafos** são exceção legítima de layout 2D (WCAG 1.4.10): em largura estreita, ofereça visão de lista ou cartão para tabelas e uma visão somente leitura do grafo, com edição completa no desktop (decisão de produto já adotada).
- **Celular com uma mão:** ações frequentes na metade inferior da tela, alvos de pelo menos 1 cm, espaço entre alvos (NN/g, Touch Targets).
- **Janela larga:** não estique texto corrido; limite a largura de leitura (50 a 75 caracteres) e use a largura extra para painéis, não para linhas longas.
- **Teste os extremos:** a menor janela suportada, a maior, texto aumentado e zoom.

---

## 11. Escrita de interface (UX writing)

Fontes: [NN/g, UX Writing Study Guide](https://www.nngroup.com/articles/ux-writing-study-guide/), [NN/g, Error-Message Guidelines](https://www.nngroup.com/articles/error-message-guidelines/), [NN/g, Confirmation Dialogs](https://www.nngroup.com/articles/confirmation-dialog/), [NN/g, Toggle Switch](https://www.nngroup.com/articles/toggle-switch-guidelines/).

- **Botões com verbo e objeto** ("Criar tarefa", "Aprovar plano", "Excluir persona"), não "OK", "Enviar" ou "Sim". O texto deve dizer o resultado.
- **Rótulos curtos, no vocabulário do usuário,** com a palavra-chave no começo (o NN/g recomenda microconteúdo que começa pelas palavras mais informativas).
- **Mensagens de erro (NN/g):**
  - linguagem simples, sem jargão nem códigos obscuros (mostre o código só como diagnóstico técnico);
  - descreva o problema com precisão, sem "Ocorreu um erro";
  - ofereça um remédio (o que fazer agora);
  - tom educado, sem culpar o usuário;
  - proteja o esforço: preserve a entrada e ofereça aceleradores de correção;
  - o pior erro é o que não existe: avise antes de erros prováveis.
- **Confirmações específicas:** nomeie o item e o efeito, não "estes 2 itens" (NN/g).
- **Toggles com rótulos concisos e não neutros** (diga o que fica ligado, não "Ativar/Desativar").
- **Estado vazio:** diga por que está vazio e qual o próximo passo (NN/g).
- **Consistência de termos:** um conceito, uma palavra. Mantenha um glossário curto no repositório.
- **Português brasileiro** com acentuação correta, frases diretas, sem travessões, sem jargão desnecessário; números e datas no formato local.

---

## 12. Ícones

Fontes: [NN/g, Icon Usability](https://www.nngroup.com/articles/icon-usability/), [NN/g, Prompt Controls](https://www.nngroup.com/articles/prompt-controls-genai/), [Spec, 8-Point Grid](https://spec.fm/specifics/8-pt-grid), [WCAG 1.4.11](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).

- **Ícones universais são raros.** Sempre inclua um rótulo de texto visível (NN/g; Tognazzini: "uma palavra vale mil imagens"). Exceção prática: ícones padrão com dica de contexto ao passar o mouse, como copiar, fechar e buscar, e só onde o espaço exigir.
- **Em ferramentas de IA, o rótulo importa ainda mais,** porque os usuários têm pouco modelo mental do que o recurso faz; ícones novos (uma varinha mágica, por exemplo) não foram entendidos por nenhum participante do estudo do NN/g (Prompt Controls). Ícones padrão de copiar, curtir e compartilhar foram entendidos por todos.
- **Pesquise os ícones usados na plataforma e em concorrentes** antes de inventar.
- **Para ícones novos:** simples e esquemáticos; regra dos 5 segundos (se levar mais que isso para pensar num ícone, ele provavelmente não comunica); teste reconhecimento e memorização.
- **Consistência:** mesmo conjunto, mesmo traço, mesmo tamanho base (16, 20 ou 24 px), mesmo estilo (contorno ou preenchido; use preenchido só para indicar seleção ou estado ativo). Enquadre os ícones em caixas de tamanho fixo (Spec).
- **Contraste:** ícone que carrega informação precisa de 3:1 (WCAG 1.4.11).
- **Ícone sozinho** só em ações muito comuns, em barras de ferramentas densas do desktop, com dica de contexto e nome acessível. No celular, prefira ícone com rótulo.
- **Tamanho relativo ajuda a notar** (NN/g): não deixe o ícone de uma ação importante menor que o de uma ação trivial.

---

## 13. Interfaces de chat, IA e ferramentas de fluxo

Fontes: [NN/g, AI: First New UI Paradigm](https://www.nngroup.com/articles/ai-paradigm/), [NN/g, Prompt Controls in GenAI Chatbots](https://www.nngroup.com/articles/prompt-controls-genai/), [Microsoft HAX Toolkit, Guidelines for Human-AI Interaction](https://www.microsoft.com/en-us/haxtoolkit/ai-guidelines/), [NN/g, Skeleton Screens](https://www.nngroup.com/articles/skeleton-screens/), [WCAG 4.1.3](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html). Fontes secundárias, sem peso de norma, estão marcadas.

- **Paradigma.** Nielsen descreve a IA generativa como uma interface de "especificação de resultado por intenção": o usuário diz o que quer, não como. O risco é a perda de controle e de visibilidade: se o usuário não sabe como algo foi feito, fica mais difícil achar e corrigir o erro, e a IA atual erra. Vale manter acesso a visões gráficas e verificáveis do que o agente fez, não só texto.
- **Controles de prompt (NN/g, 4 usos):** descobrir recursos, ensinar e inspirar, definir restrições da conversa e facilitar continuações. Boas práticas: ícones padrão com rótulos ou dicas.
- **Diretrizes de interação humano-IA (Microsoft HAX).** A página do toolkit apresenta 18 diretrizes organizadas por momento: no início, durante a interação, quando o sistema erra e ao longo do tempo. Não consegui abrir a lista detalhada; trate o recorte por momento como estrutura útil para auditar o produto (deixar claro o que o sistema faz e o quanto acerta, permitir corrigir e descartar, explicar).
- **Status do agente (heurística 1).** Uma execução longa precisa mostrar: estado atual (fila, rodando, aguardando aprovação, concluída, falhou), o que está fazendo agora (passo ou ferramenta em uso), tempo decorrido e como parar. Acima de 10 s, indique progresso e permita interromper (NN/g, Response Times).
- **Streaming.** Mostre o texto à medida que chega: reduz a espera percebida (feedback antes de 1 s). Evite saltos de layout durante o stream; role automaticamente só se o usuário está no fim da conversa e ofereça "ir para o fim" se ele rolou para cima. Anuncie o fim da resposta de forma polida a leitores de tela (WCAG 4.1.3: sem `assertive` para conteúdo não urgente).
- **Aprovação humana (fontes secundárias, não verificadas em fonte primária):** aprovar tudo gera fadiga de aprovação (o modal após cada ação só transfere o trabalho de fazer para o de clicar); peça aprovação para o que é difícil de desfazer ou visível a terceiros; mostre o efeito real, não só a intenção (um comando mostra o comando exato, um e-mail mostra o texto); registre o que foi proposto, quem decidiu e o resultado. Combine com as regras gerais de confirmação específica (NN/g, Confirmation Dialogs).
- **Revisão de plano e de entrega:** mostre o que mudou (diff), o motivo e as opções (aprovar, pedir mudança), com texto de ação específico.
- **Ferramentas de fluxo (grafos):** além das regras de arrastar, teclado e foco acima, mantenha a estrutura legível (alinhamento a uma grade, agrupamento por proximidade), dê aos nós rótulos legíveis e estados visíveis (cor, ícone e texto), mostre erros de validação presos ao nó e permita navegar e editar por teclado e por menu.

---

## Implicações para o Control Tower

Diretrizes aplicadas ao produto. Os números marcados como convenção não vêm de fonte única; ajustar conforme o Material e a prática.

1. **Contraste como regra de token.** Todo par texto/fundo dos dois temas deve ter 4,5:1 (3:1 para texto grande), e todo componente de UI, borda e ícone informativo 3:1 (WCAG 1.4.3 e 1.4.11). Verifique no tema escuro também. Cores semânticas (sucesso, aviso, erro, info) ganham tons próprios para texto, fundo e borda.
2. **Nunca só cor.** Estados de tarefa, execução, ficha e aprovação sempre combinam cor, ícone e rótulo (WCAG 1.4.1). Isso vale para o grafo: tipo de nó e estado visíveis sem cor.
3. **Escala de espaço única:** 4, 8, 12, 16, 24, 32, 48 (grid de 8 com meio passo de 4). Aplique em padding, margem e gap; proibir valores soltos. O espaço entre grupos é maior que dentro do grupo.
4. **Duas densidades.** Confortável (padrão no celular) e compacta (painel, tabelas, listas de tarefas no desktop). A compacta reduz o padding vertical, não a fonte nem a área de clique mínima de 24 px (WCAG 2.5.8).
5. **Inter com recursos ligados por contexto:** `tnum` em custos, tokens, contagens, horários e tabelas; `zero` e `cv05`/`cv08` em ids e logs curtos; variante de texto no corpo e Display só em títulos grandes (intervalo `opsz` 14 a 32). Fonte mono para código, comandos e logs.
6. **Escala tipográfica curta,** de 5 a 7 estilos, com 3 pesos (400, 500, 600). Texto de leitura (mensagens do chat, planos, descrições) limitado a 50 a 75 caracteres de largura, mesmo em janela larga.
7. **Chat.** Streaming sem salto de layout; autoscroll só quando o usuário está no fim; indicação clara de quem fala (persona, com nome e cor); estado "pensando/usando ferramenta" visível acima de 1 s; botão de parar durante a resposta; copiar e outras ações com ícone padrão e dica. Balões respeitam a largura de leitura.
8. **Aprovações como momento crítico.** O pedido mostra o efeito exato (o comando completo, o diff, o plano), quem pede, em qual tarefa e as opções com verbos específicos ("Aprovar comando", "Negar"). Reserve a aprovação para o que é difícil de desfazer, para evitar fadiga; ações reversíveis usam aviso com "Desfazer". Pedidos pendentes aparecem no painel com contagem e prioridade.
9. **Confirmação proporcional.** Ação reversível: faz e oferece desfazer. Ação grave (excluir persona ou equipe): diálogo específico com nome e consequência, e digitação do nome nas mais graves, como já ocorre. Botão destrutivo com verbo e objeto, em cor de erro, nunca como padrão focado.
10. **Painel denso com hierarquia.** "Precisa de você" no topo e com maior peso visual; o resto desenfatizado. Cartões e linhas com números tabulares, alinhados à direita; cabeçalhos fixos em tabelas longas; estado vazio com explicação e próxima ação; skeleton na carga inicial da tela e spinner por cartão isolado; barra de progresso para operações acima de 10 s.
11. **Editor de grafo acessível.** Alternativa sem arrastar para conectar e mover nós (menu, botão ou teclado; WCAG 2.5.7), foco visível de 2 px com 3:1, navegação por setas e Tab entre nós, erros de validação presos ao nó com texto, rolagem automática ao nó focado (WCAG 2.4.11). O grafo é exceção de reflow; em largura estreita, mostre lista somente leitura e deixe a edição no desktop.
12. **Teclado e aceleradores no desktop.** Tab e Shift+Tab em ordem lógica, Enter e Esc consistentes, atalhos nas ações frequentes mostrados à direita nos menus, folha de atalhos acessível e, se couber, paleta de comandos. Atalhos de tecla única só se não colidirem com a caixa de texto e podendo ser desligados (WCAG 2.1.4).
13. **Alvos de toque no celular:** pelo menos 44 a 48 px (NN/g pede 1 cm; WCAG AAA, 44 px), com espaço entre alvos; ações principais na metade inferior da tela. No desktop, piso de 24 px e alvo confortável de 32 px (convenção).
14. **Layout adaptativo por largura da janela, não por dispositivo.** Três faixas: compacta (uma coluna), média (lista e detalhe quando couber) e larga (navegação fixa, lista, detalhe e painel auxiliar). Lista-detalhe preserva a seleção ao redimensionar. Valores exatos de breakpoint vêm do Material.
15. **Formulários.** Rótulo fora do campo e sempre visível; validação ao sair do campo e positiva em campos complexos (cron, JSON, id); erro perto do campo, com texto e remédio; nunca apagar a entrada com erro. Campos estruturados mostram exemplo e prévia ("próximas execuções").
16. **Estados completos em todo componente:** repouso, hover, foco, pressionado, desabilitado (com motivo quando possível), carregando, erro. Toggles têm efeito imediato e não convivem com campos que exigem Salvar. Hover nunca é o único caminho para uma ação.
17. **Texto de interface.** Botões com verbo e objeto; erros em linguagem simples, com o que houve e o que fazer; vocabulário único (persona, posição, equipe, tarefa) com glossário; pt-BR com acentuação correta, sem travessão.
18. **Ícones sempre com rótulo** nas ações menos comuns e em qualquer recurso novo ou de IA; ícone sozinho só em ações universais de barra de ferramentas, com dica de contexto e nome acessível. Um conjunto único, traço único, grade de 16, 20 e 24 px.
19. **Modo escuro como opção bem testada,** seguindo o sistema por padrão: sem branco puro sobre preto puro, acentos dessaturados, elevação por tom de superfície, e contrastes reverificados (NN/g recomenda oferecer, não impor).
20. **Movimento com propósito.** Animação só para comunicar mudança de estado; respeitar a preferência de movimento reduzido; mensagens de status (novo aviso, execução concluída) anunciadas a leitores de tela sem `assertive`, salvo urgência real (WCAG 4.1.3).

---

## Fontes

Nielsen Norman Group
- [10 Usability Heuristics for User Interface Design](https://www.nngroup.com/articles/ten-usability-heuristics/)
- [Response Times: The 3 Important Limits](https://www.nngroup.com/articles/response-times-3-important-limits/)
- [Skeleton Screens 101](https://www.nngroup.com/articles/skeleton-screens/)
- [Visual Hierarchy in UX: Definition](https://www.nngroup.com/articles/visual-hierarchy-ux-definition/)
- [Error-Message Guidelines](https://www.nngroup.com/articles/error-message-guidelines/)
- [10 Design Guidelines for Reporting Errors in Forms](https://www.nngroup.com/articles/errors-forms-design-guidelines/)
- [Placeholders in Form Fields Are Harmful](https://www.nngroup.com/articles/form-design-placeholders/)
- [Confirmation Dialogs Can Prevent User Errors, If Not Overused](https://www.nngroup.com/articles/confirmation-dialog/)
- [Designing Empty States in Complex Applications: 3 Guidelines](https://www.nngroup.com/articles/empty-state-interface-design/)
- [Toggle-Switch Guidelines](https://www.nngroup.com/articles/toggle-switch-guidelines/)
- [Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/)
- [Accelerators Maximize Efficiency in User Interfaces](https://www.nngroup.com/articles/ui-accelerators/)
- [Memory Recognition and Recall in User Interfaces](https://www.nngroup.com/articles/recognition-and-recall/)
- [Icon Usability](https://www.nngroup.com/articles/icon-usability/)
- [Touch Targets on Touchscreens](https://www.nngroup.com/articles/touch-target-size/)
- [Dark Mode vs. Light Mode: Which Is Better?](https://www.nngroup.com/articles/dark-mode/)
- [Data Tables: Four Major User Tasks](https://www.nngroup.com/articles/data-tables/)
- [Drag-and-Drop: How to Design for Ease of Use](https://www.nngroup.com/articles/drag-drop/)
- [Responsive Web Design (RWD) and User Experience](https://www.nngroup.com/articles/responsive-web-design-definition/)
- [UX Writing: Study Guide](https://www.nngroup.com/articles/ux-writing-study-guide/)
- [Beyond Blue Links: Making Clickable Elements Recognizable](https://www.nngroup.com/articles/clickable-elements/)
- [AI: First New UI Paradigm in 60 Years](https://www.nngroup.com/articles/ai-paradigm/)
- [Prompt Controls in GenAI Chatbots: 4 Main Uses and Best Practices](https://www.nngroup.com/articles/prompt-controls-genai/)

Laws of UX
- [Laws of UX (índice)](https://lawsofux.com/)
- [Fitts's Law](https://lawsofux.com/fittss-law/)
- [Hick's Law](https://lawsofux.com/hicks-law/)
- [Jakob's Law](https://lawsofux.com/jakobs-law/)
- [Miller's Law](https://lawsofux.com/millers-law/)
- [Cognitive Load](https://lawsofux.com/cognitive-load/)
- [Doherty Threshold](https://lawsofux.com/doherty-threshold/)
- [Tesler's Law](https://lawsofux.com/teslers-law/)
- [Law of Proximity](https://lawsofux.com/law-of-proximity/)
- [Law of Similarity](https://lawsofux.com/law-of-similarity/)

W3C WAI, WCAG 2.2 (Understanding)
- [1.4.1 Use of Color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html)
- [1.4.3 Contrast (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- [1.4.10 Reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)
- [1.4.11 Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)
- [2.1.4 Character Key Shortcuts](https://www.w3.org/WAI/WCAG22/Understanding/character-key-shortcuts.html)
- [2.3.3 Animation from Interactions](https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html)
- [2.4.7 Focus Visible](https://www.w3.org/WAI/WCAG22/Understanding/focus-visible.html)
- [2.4.11 Focus Not Obscured (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html)
- [2.4.13 Focus Appearance](https://www.w3.org/WAI/WCAG22/Understanding/focus-appearance.html)
- [2.5.5 Target Size (Enhanced)](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html)
- [2.5.7 Dragging Movements](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html)
- [2.5.8 Target Size (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)
- [4.1.3 Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html)

Tipografia, cor e layout
- [Inter, família tipográfica](https://rsms.me/inter/)
- [Inter Lab](https://rsms.me/inter/lab/)
- [Refactoring UI (índice do livro)](https://www.refactoringui.com/)
- [Refactoring UI, Building Your Color Palette](https://www.refactoringui.com/previews/building-your-color-palette)
- [Spec, The 8-Point Grid](https://spec.fm/specifics/8-pt-grid)
- [Interaction Design Foundation, Gestalt Principles](https://www.interaction-design.org/literature/topics/gestalt-principles)
- [Baymard, Readability: The Optimal Line Length](https://baymard.com/blog/line-length-readability)

Formulários
- [Baymard, Usability Testing of Inline Form Validation](https://baymard.com/blog/inline-form-validation)
- [web.dev, Sign-in Form Best Practices](https://web.dev/articles/sign-in-form-best-practices)

IA e agentes
- [Microsoft HAX Toolkit, Guidelines for Human-AI Interaction](https://www.microsoft.com/en-us/haxtoolkit/ai-guidelines/)
- Busca web sobre aprovação humana e UX de agentes (resultados secundários, sem peso de norma): [Agent UX Design Patterns](https://www.agenticwire.news/article/agent-ux-design-patterns), [Approval fatigue em human-in-the-loop](https://www.theskinsfactory.com/uiux-design-questions-answers/how-do-you-design-human-in-the-loop-ai-without-creating-approval-fatigue), [Framework de princípios para interação humano-agente](https://arxiv.org/pdf/2607.19941)

Consultadas sem uso direto de conteúdo
- Apple HIG, Layout (a página não retornou texto; a cifra de 44 pt veio só de fontes secundárias, por isso não é citada como verificada).
