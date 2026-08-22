# Anexos no chat — imagem, texto e PDF

TickTask #309. Anexar imagem, arquivo de texto e PDF a uma mensagem do chat, com o
conteúdo chegando ao conselheiro e o anexo visível ao reabrir a conversa.

Fora de escopo, por decisão: vincular anexo a uma decisão registrada em `decisions/`.
Anexo de conversa é descartável e vive fora do git; anexo de decisão é permanente e
versionado. São ciclos de vida diferentes e viram card próprio.

## Como o anexo chega ao modelo

O arquivo é gravado em disco e o agente o abre com a ferramenta `Read`, que já está em
`allowedTools` e trata os três tipos nativamente — `FileReadOutput` tem variantes
`text`, `image` e `pdf`, e `FileReadInput` aceita `pages` para paginar PDF.

A alternativa era montar blocos `image`/`document` em base64 e passar um
`AsyncIterable<SDKUserMessage>` para o `query()`. Foi descartada: reescreveria o núcleo
de `sessions.ts`, carregaria o arquivo inteiro em contexto, estouraria em PDF grande e
transformaria log longo numa parede de tokens. Pelo disco, o agente lê só a parte de que
precisa.

O caminho absoluto entra no texto **enviado ao modelo**, não no texto **gravado e
exibido**. Isso já é o padrão de `responderNaConversa`, que hoje faz a mesma divergência
para citação: `textoParaModelo` recebe o preâmbulo e o `texto` do `.jsonl` fica limpo.

Bloco injetado antes da mensagem do usuário:

```
[Anexos desta mensagem. Leia cada um com a ferramenta Read antes de responder:]
- /abs/.../conversations/anexos/mt4a-1b2c3d4e.png — imagem "erro-tela.png"
- /abs/.../conversations/anexos/mt4a-9f8e7d6c.pdf — pdf "contrato.pdf" (2,1 MB)
```

**Risco conhecido:** os perfis são personas, não agentes de tarefa; uma persona pode não
chamar o `Read`. A frase acima é explícita para reduzir isso, e o primeiro teste real
revela. Se falhar, o plano B é passar imagem inline e manter texto e PDF pelo disco —
troca contida em `sessions.ts`, sem tocar em armazenamento nem UI.

## Armazenamento

Diretório plano: `conversations/anexos/<id>.<ext>`, com um sidecar
`conversations/anexos/<id>.json` contendo o `Anexo` completo.

Plano, e não por conversa, porque o upload acontece **antes** de a conversa existir: numa
conversa nova o id só é criado na primeira mensagem. Um diretório por conversa exigiria
área de staging e um move; o id global dispensa os dois.

`conversations/*` já está no `.gitignore`, então anexo nunca é commitado por acidente.

O sidecar existe para que o servidor nunca confie em caminho vindo do cliente. A mensagem
do WebSocket carrega **apenas ids**; o servidor lê o sidecar para obter nome, mime, tipo,
tamanho e extensão.

**Folga aceita:** anexo enviado cujo balão nunca foi despachado fica órfão no diretório.
Custa um arquivo pequeno num diretório ignorado pelo git, e limpar isso exigiria varredura
ou expiração. Não vale a complexidade num app pessoal; fica registrado como escolha, não
como esquecimento.

## Tipos

```ts
export type TipoAnexo = "imagem" | "texto" | "pdf"

export interface Anexo {
  id: string
  nome: string      // nome original, só para exibir
  tipo: TipoAnexo
  mime: string
  bytes: number
  arquivo: string   // relativo à raiz: conversations/anexos/<id>.<ext>
}

export interface Mensagem {
  // ...campos atuais
  anexos?: Anexo[]
}
```

`anexos` é opcional para que as linhas de `.jsonl` já gravadas continuem sendo lidas sem
migração.

## Aceitação e limites

- **Imagem:** `image/png`, `image/jpeg`, `image/webp`, `image/gif`
- **PDF:** `application/pdf`
- **Texto:** qualquer `text/*`, mais uma lista de extensões que o navegador costuma
  reportar como `application/octet-stream` (`log`, `md`, `txt`, `csv`, `json`, `ts`, `js`,
  `py`, `sql`, `yml`, `yaml`, `sh`)
- **Teto:** 10 MB por anexo, verificado no cliente e de novo no servidor
- **Redução no cliente:** imagem acima de 1600px no maior lado é redimensionada por canvas
  antes de subir. Corta upload no 5G e corta token na leitura da imagem.

A extensão gravada em disco vem do nome do cliente, mas só depois de passar por
`/^[a-z0-9]{1,8}$/` no valor minúsculo — sem ponto, sem barra. O que não passar cai para
`.txt`. Preserva `.log` e `.ts`, que dão contexto de sintaxe ao agente, sem abrir travessia
de caminho.

O id é gerado no servidor (`<base36 do tempo>-<8 hex>`) e validado por
`/^[a-z0-9-]{8,64}$/` na entrada e na saída. Nome de arquivo do cliente nunca compõe
caminho.

## Superfície

**`POST /anexo`** — `multipart/form-data` com um campo `arquivo`. Valida tipo e tamanho,
grava arquivo e sidecar, responde com o `Anexo`. Erro devolve `400` com motivo em
português.

**`GET /anexo/<id>`** — lê o sidecar, entrega o arquivo com o `Content-Type` registrado.
Sem extensão na URL. Id fora do padrão ou sidecar ausente devolve `404`.

**WebSocket:** `nova` e `mensagem` ganham `anexos?: string[]` — só ids.

## UI

Clipe à esquerda do campo no composer, abrindo menu de três itens:

- **Câmera** — `<input capture="environment" accept="image/*">`, para foto na hora
- **Galeria** — `<input accept="image/*">`
- **Arquivo** — `accept` amplo, para texto e PDF

Três entradas porque no Android um `accept` amplo abre o seletor de documentos e esconde a
câmera; separar é o que faz a foto na hora funcionar em um toque.

Anexos pendentes aparecem como chips acima do composer, cada um removível, no mesmo lugar
onde hoje aparece a barra de citação.

No balão: imagem vira miniatura que abre em tamanho cheio ao toque; texto e PDF viram
cartão com ícone, nome e tamanho, com toque abrindo o arquivo em nova aba. O histórico
renderiza pelo mesmo caminho, lendo `Mensagem.anexos`.

## Erros

- Tipo recusado ou acima do teto: avisa no cliente antes de subir, e o servidor recusa de
  novo — o cliente é conveniência, o servidor é a regra
- Upload falho: mostra o erro e **preserva o texto digitado**, para não perder a mensagem
- Sidecar ou arquivo ausente na hora de montar o prompt: o anexo é omitido e um aviso
  entra no chat, em vez de derrubar a resposta inteira

## Testes

`nucleo.test.ts` cobre núcleo puro; os pedaços puros novos entram lá:

- `classificarAnexo(mime, nome)` → `TipoAnexo | null`, incluindo o caminho da lista de
  extensões
- `extensaoSegura(nome)` → sanitização, com caso de travessia (`../../etc/passwd`)
- `montarBlocoDeAnexos(anexos, raiz)` → o texto injetado no prompt

Upload, entrega e UI ficam para verificação manual no aparelho, como o resto da interface.

## Arquivos

| Arquivo | Papel |
|---|---|
| `app/src/anexos.ts` | novo — classificação, sanitização, gravação e leitura do par arquivo+sidecar |
| `app/src/tipos.ts` | `Anexo`, `TipoAnexo`, `Mensagem.anexos` |
| `app/src/server.ts` | `POST /anexo`, `GET /anexo/<id>`, ids nas mensagens do WS, bloco no prompt |
| `app/web/index.html` | clipe, menu, inputs de arquivo, faixa de pendentes |
| `app/web/app.js` | seleção, redução de imagem, upload, chips, render no balão |
| `app/web/style.css` | clipe, chips, miniatura, cartão de arquivo |
| `app/src/nucleo.test.ts` | os três testes puros |
