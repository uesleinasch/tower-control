# Fase 11 do orquestrador: skills por persona

TickTask #504, subtarefa 11 da #496. Parte da spec-mãe (`2026-10-07-orquestrador-personas-design.md`)
e da descrição da #504: pasta com `SKILL.md`, versionada na pasta de dados, anexada por persona e
injetada no runtime sem depender do system prompt, com skills da organização e de cada persona.
Sem rodada de perguntas: o que ficou em aberto foi decidido aqui e está marcado como **(decisão
desta fase)**.

## Para que serve

Hoje, ensinar uma persona a fazer algo do jeito do Ueslei é repetir na conversa, escrever na
instrução da tarefa ou mexer no `profile.md`, que vai inteiro em todo turno. Uma skill é um
procedimento guardado à parte: um nome, uma linha dizendo quando usar e o passo a passo, com
arquivos de apoio se precisar. A persona vê só a lista (nome e descrição) e abre a skill quando o
pedido casa com ela. Escreve-se uma vez, vale para quem tiver a skill, em conversa e em tarefa.

Uso que fecha a fase: no desktop, o Ueslei cria na biblioteca da Casa a skill
`relatorio-semanal` (como escrever o relatório da semana) e a anexa ao Poe. No chat, pede ao Poe
o relatório da semana e o Poe segue a skill sem que o pedido a cite. Depois, a posição `executor`
recebe uma skill com um script de apoio, e uma tarefa do Alfred usa a skill e roda o script pela
aprovação de comando de sempre.

## O que o teste do SDK mostrou

Rodado em 05/11/2026 com o Agent SDK do projeto e Haiku, antes desta spec:

- Uma pasta local passada em `plugins` carrega as skills dela mesmo com `settingSources: []`. O
  manifesto `.claude-plugin/plugin.json` aceita `"skills": "./"`, então as skills ficam direto na
  raiz da pasta. O nome que o modelo vê é `<plugin>:<skill>`.
- `skills: 'all'` traz também as skills embutidas do Claude Code (deep-research, design...). A
  opção precisa da lista explícita.
- `tools` limita as ferramentas nativas, e sem `Skill` na lista o modelo não abre skill nenhuma.
  Com `Skill`, o Haiku abriu a skill certa sem o pedido citá-la e seguiu o corpo.
- Uma skill criada entre dois turnos apareceu na sessão retomada (`resume`) e foi usada. A lista
  não depende do system prompt congelado.
- `Read` de um arquivo fora do `cwd` foi negado. Arquivo de apoio precisa estar dentro do `cwd`
  ou em `additionalDirectories`.

## Objetivos

- Biblioteca de skills da Casa e skills próprias de cada persona, em pastas versionadas no git
  dos dados, editáveis à mão e pelo desktop.
- Anexar skills da biblioteca a personas e a posições.
- Skills disponíveis no chat, nas tarefas (execução, plano e revisão) e nos pareceres do board,
  pelo mecanismo nativo do SDK.
- Editor de skills no desktop; web e celular mostram quais skills cada persona e posição têm.

## Fora desta fase

- Persona que cria ou melhora skill sozinha (no sonho ou ao fim de uma tarefa).
- Importar skill de fora da pasta de dados pela interface (de `~/.claude/skills`, de um zip, de um
  repositório). Copiar a pasta à mão para `skills/` funciona.
- Skill por workflow ou por caixa de workflow. A caixa usa a posição, e a posição tem skills.
- Estatística de uso de cada skill.
- Exportar skills em pacote: é a fase 13 (templates).

## Anti-objetivos

- Skill no system prompt ou no bloco do turno. A lista entra pelo SDK, e o corpo só quando a
  persona abre a skill.
- Vazar as skills do Ueslei no Claude Code (`~/.claude/skills`, plugins dele) ou as embutidas para
  as personas. Só entra o que está na pasta de dados e foi anexado.
- Skill como atalho para comando sem aprovação. Script de skill roda pelo Bash da posição, com o
  mesmo hook de aprovação.
- Skill quebrada derrubando conversa ou tarefa.

## 1. Onde moram

Na pasta de dados, versionadas no git dela:

```
skills/                                  biblioteca da Casa (plugin "ct-casa")
  .claude-plugin/plugin.json             { "name": "ct-casa", "skills": "./" }
  relatorio-semanal/
    SKILL.md
    modelo.md                            arquivo de apoio (opcional)
profiles/<persona>/skills/               skills próprias da persona (plugin "ct-<persona>")
  .claude-plugin/plugin.json             { "name": "ct-<persona>", "skills": "./" }
  revisar-texto/SKILL.md
```

O servidor cria os manifestos quando falta (na subida e ao salvar a primeira skill de um dono). O
prefixo `ct-` não colide com id de persona, que só tem letras **(decisão desta fase)**.

**`SKILL.md`** é o formato do Claude Code: frontmatter com `name` (igual ao nome da pasta) e
`description` (obrigatória, até 1.024 caracteres, dizendo o que faz e quando usar), e o corpo em
Markdown. Outras chaves do frontmatter são mantidas como estão. O id da skill segue
`^[a-z][a-z0-9-]{0,63}$` e não muda depois de criada; renomear é criar outra e excluir a antiga.

**Skill inválida** (sem frontmatter, `name` diferente da pasta, sem descrição) não derruba a
subida, ao contrário de equipe e workflow, porque a pasta é editada à mão com o servidor de pé e
o SDK a lê a cada chamada **(decisão desta fase)**. Ela aparece na lista com o erro, e o servidor
a deixa de fora das sessões.

## 2. Quem tem cada skill

- **Persona:** `persona.json` ganha `skills: string[]`, ids da biblioteca da Casa.
- **Posição:** cada posição de `equipe.json` ganha `skills: string[]`, também ids da biblioteca.
- **Próprias:** as skills em `profiles/<persona>/skills/` valem sempre para aquela persona, em
  qualquer posição.

O conjunto de uma chamada é a união das próprias, das da persona e das da posição em que ela está
naquela chamada: a posição da Casa no chat, a dona da tarefa na execução e no plano, a revisora na
revisão **(decisão desta fase)**. Anexar id que não existe na biblioteca é recusado ao salvar a
persona ou a equipe.

## 3. Onde entram

| Chamada | Skills |
|---|---|
| chat com conselheiro e com o Alfred | sim |
| tarefa: execução, plano e revisão de etapa | sim |
| board: parecer de cada membro (deliberação e revisão de tarefa) | sim, as de cada membro |
| síntese do moderador do board | não |
| memória: consolidação, sonho e geração de perfil | não |

**Como entram.** Um ponto só monta as opções a partir do conjunto: `plugins` com a pasta da Casa e
a da persona (`skipMcpDiscovery: true`), `skills` com a lista explícita de nomes qualificados
(`ct-casa:relatorio-semanal`, `ct-poe:revisar-texto`), `Skill` acrescentada a `tools` e a
`allowedTools` (abrir skill não muda nada fora da sessão). Conjunto vazio: nada disso entra, para
não gastar tokens de lista à toa. Nunca `skills: 'all'`.

**Arquivos de apoio.** O `cwd` das sessões é a pasta de dados, então a persona lê os arquivos da
skill com `Read`. Quando a posição tem `diretorio`, as pastas das skills do conjunto vão para
`additionalDirectories`.

**Scripts.** Só posição com `comandos` tem Bash. O script de uma skill passa pelo mesmo hook de
aprovação de qualquer comando, com a política da posição.

**Sessões em andamento.** A lista vem do SDK a cada turno, então anexar, editar ou excluir uma
skill vale a partir do próximo turno, inclusive em conversa retomada. Nada vai no `profile.md` nem
no bloco `<memória>`.

## 4. Telas

**Desktop (edição).** Equipes ganha a aba "Skills", ao lado do organograma e dos workflows:

- lista em dois grupos, "Casa" e uma seção por persona com skills próprias, com nome, descrição,
  quem usa e o erro, se a skill estiver inválida;
- "Nova skill" (na Casa ou numa persona), "Editar" e "Excluir";
- editor com id (só na criação), descrição com contador até 1.024 e o corpo em Markdown num campo
  grande, mais a lista dos arquivos de apoio, só leitura (arquivo de apoio se edita à mão na
  pasta) **(decisão desta fase)**;
- rascunho com Salvar e Descartar, validado no núcleo e de novo no servidor.

**Anexar.** O painel da persona (fase 4) e o painel da posição no organograma ganham "Skills": a
lista das anexadas, com "+" que escolhe da biblioteca e "x" para tirar. A persona mostra também,
sem edição, as próprias. Na persona, o anexo vai pelo `persona-salvar`; na posição, pelo
`equipe-salvar` do rascunho do organograma, como os outros campos.

**Web e celular.** Só leitura: o detalhe da persona e o da posição listam as skills, com a
descrição.

## 5. Protocolo

- cliente→servidor: `skills` (pede a lista); só no desktop, `skill-salvar`
  (`{ dono, skill: { id, descricao, corpo }, nova }`, com `dono` = `"casa"` ou o id da persona) e
  `skill-excluir` (`{ dono, id }`);
- servidor→cliente: `skills` (`{ lista }`, cada item com `dono`, `id`, `descricao`, `corpo`,
  `arquivos`, `erro?` e `usadaPor: { personas, posicoes }`), mandado a todos a cada mudança;
- `persona-salvar` aceita `skills`; a posição em `equipe-salvar` aceita `skills`; `personas` e
  `equipes` devolvem os campos.

**Regras do servidor:**

- `skill-salvar` com `nova` recusa id que já existe no mesmo dono; sem `nova`, recusa skill que
  não existe.
- Ao salvar, reescreve o `SKILL.md` com o frontmatter conhecido mais as chaves que já estavam lá.
- Excluir uma skill da Casa anexada a alguém é recusado, com a lista de quem usa, como o workflow
  disparado por rotina. Excluir uma skill própria é livre.
- Excluir uma persona deixa as skills próprias dela na pasta, porque a persona excluída tem o id
  reservado.
- Toda mudança vira commit no git dos dados ("skill relatorio-semanal criada na Casa").

## 6. Testes

`bun test`:

- leitura e validação do `SKILL.md`: frontmatter, `name` igual à pasta, descrição obrigatória e
  limite, chaves extras mantidas ao regravar;
- conjunto de uma chamada: próprias, da persona e da posição, sem repetir, sem as inválidas;
- opções do SDK geradas pelo conjunto: `plugins`, nomes qualificados, `Skill` em `tools` e
  `allowedTools` só com conjunto não vazio, `additionalDirectories` com `diretorio`;
- anexar id inexistente recusado em `validarPersona` e `validarEquipe`; excluir skill em uso
  recusado; manifesto criado quando falta;
- o teste de protocolo cobra os tipos novos.

`flutter test`: o codec dos tipos novos, a validação do rascunho de skill (id, descrição e
limite) e os anexos de persona e posição.

Ponta a ponta num servidor isolado, com modelo de verdade: a skill de relatório no chat do Poe e
a skill com script numa tarefa do Alfred, com a aprovação do comando.

## O que fica com quem implementa

Nomes internos, o desenho da aba e do editor, o texto dos erros e a ordem dos commits. A ordem
sugerida é: leitura, validação e gravação de skills; conjunto e opções do SDK nas chamadas; anexos
em persona e posição; protocolo; telas.

## Como ficou na implementação

- **Instrução no prompt.** No teste de ponta a ponta, a Nati via a lista e não abria a skill
  própria: o `systemPrompt` do control-tower substitui o do Claude Code, e junto ia a orientação de
  usar skills. As instruções da casa, do executor e do parecer ganharam um bloco "Skills" que
  manda abrir a skill que casa com o pedido. Com ele a Nati abriu nas duas tentativas. Conversas
  que já existiam ficam com o prompt antigo, que congela no começo da sessão.
- **Git.** `skills/` entrou na lista de pastas versionadas do git dos dados; sem isso os commits
  das skills não aconteciam.
- **Anexos.** A existência das skills anexadas é conferida ao salvar, com `validarPersona` e
  `validarEquipe` recebendo o conjunto da Casa mais o que já estava anexado, para uma skill
  apagada à mão não travar outras mudanças.
- **Telas.** O dono da skill se escolhe no botão "Nova skill" e não muda no editor. O "+" só
  oferece skills válidas da Casa. Erro ao anexar na persona cai no aviso genérico, como o do
  orçamento. O celular não tem a aba Skills, só a lista nos detalhes de persona e posição.
