# Notificações: avisos no celular e no desktop, com o app fechado

TickTask #462 (lembretes do TickTask) e #443 (avisos com o celular fechado). Avisar no
celular Android e no desktop Linux quando uma resposta termina, quando o Alfred pede
aprovação e quando um lembrete do TickTask vence, mesmo com o app fechado, e deixar agir
direto pela notificação.

Fora de escopo, por decisão: notificações na página web (ela só informa a conversa
visível), Firebase/FCM ou qualquer serviço de terceiro, fila para aplicar ações quando o
TickTask está fechado, interpretação de linguagem natural de datas no código.

## Decisões tomadas

- **Lembretes:** os quatro tipos — na hora agendada, resumo do dia, atrasadas e pedido em
  conversa.
- **Canal:** direto do servidor, sem terceiros. O app mantém um serviço em primeiro plano
  ligado ao próprio Control Tower pela LAN ou pelo Tailscale. O conteúdo (nomes de tarefa,
  comandos do Alfred) não passa por ninguém.
- **Ações no aviso:** aprovar/negar comando, concluir/adiar tarefa e responder em texto.
- **Alcance:** celular e desktop. Resposta terminada e aprovação ficam em silêncio quando a
  conversa está aberta e em primeiro plano em algum cliente; lembretes sempre avisam. Uma
  ação feita num aparelho limpa o aviso nos outros.
- **Abordagem:** stream de avisos próprio (`GET /avisos`) e ações por HTTP
  (`POST /avisos/<id>/acao`), no padrão que o claude-local-session já usa com o ntfy
  (`mobile/lib/notificacao/escuta.dart` e `servico.dart` servem de referência). O WebSocket
  do chat continua como está, salvo pela mensagem `visivel`. Descartadas: tudo pelo
  WebSocket (o isolate de segundo plano teria de reimplementar o codec e cada tipo novo
  exigiria os três clientes) e um servidor compatível com ntfy usando o app oficial (sem
  resposta em texto e sem app de desktop Linux).

## 1. Central de avisos no servidor

Módulo novo `app/src/avisos/`.

**Aviso:**

```ts
interface Aviso {
  id: string            // UUID
  seq: number           // crescente, para reconexão
  tipo: "resposta" | "aprovacao" | "lembrete" | "resumo" | "atrasada"
  titulo: string
  corpo: string
  alvo: { conversaId?: string; permissaoId?: string; tarefaId?: number }
  acoes: ("aprovar" | "negar" | "concluir" | "adiar" | "responder")[]
  criadoEm: string
  expiraEm?: string     // aprovação: criadoEm + 120 s
}
```

Resolver um aviso gera o evento `{ tipo: "resolvido", id, seq, como, em, aparelho? }`, em que
`como` é `aprovado`, `negado`, `concluida`, `adiada`, `respondido`, `lido` ou `expirado`.

- **Persistência:** `conversations/avisos.jsonl` (fora do git), só append de avisos e
  eventos de resolução. Poda de 7 dias na subida, que nunca remove a última linha: o
  maior `seq` sobrevive e o contador não recomeça do zero.
- **`GET /avisos?desde=<seq>`:** NDJSON, uma linha por aviso ou evento. Primeiro o backlog
  depois de `seq`, depois ao vivo. Linha de keep-alive (`{}`) a cada 25 s. Se `desde` for
  maior que o maior `seq` (arquivo apagado à mão, dados restaurados), vai o backlog
  inteiro. A rota desliga o `idleTimeout` do Bun (`server.timeout(req, 0)`): o padrão de
  10 s cortaria o stream antes do keep-alive.
- **`POST /avisos/<id>/acao`** com `{ acao, texto?, adiarPara?: "1h" | "amanha",
  aparelho?: string }`: `200` com o resultado; `409` se o aviso já foi resolvido ou
  expirou, com `como` e `aparelho` de quem resolveu; `404` se não existe; `400` se a ação
  não está entre as do aviso. O `aparelho` é um nome livre ("celular", "desktop") e vai
  para o evento `resolvido`.
- **Silêncio quando visível:** tipo novo no WebSocket, cliente → servidor:
  `visivel` com `{ conversaId: string | null }`. A web manda pelo `visibilityState`, o
  Flutter pelo ciclo de vida do app e pela tela aberta. O servidor guarda a conversa
  visível de cada socket e só gera `resposta` e `aprovacao` quando nenhum socket mostra
  aquela conversa. Entra em `docs/protocolo.json` e nos três clientes.
- **`visivel` também resolve e revela:** ao mostrar uma conversa, os `resposta` abertos
  dela viram `lido`. Quando a conversa deixa de estar visível em todos os sockets, cada
  aprovação pendente dela que ainda não tem aviso ganha o aviso na hora: senão o comando
  pedido com a tela aberta expiraria sem ninguém ver.
- **Fontes:** fim do turno em `responderNaConversa` gera `resposta` (título com o perfil,
  corpo com o começo da resposta); `tratarComando` gera `aprovacao` com o mesmo id da
  permissão e o comando no corpo. Aprovar ou negar pelo aviso chama `resolverPermissao`;
  quando a permissão resolve por outro caminho (tela do chat, prazo de 120 s), o aviso é
  resolvido junto. O board não gera aviso: ele é síncrono na tela.
- **Conversa sem socket:** `responderNaConversa` e `tratarComando` passam a aceitar `ws`
  ausente (resposta pelo aviso). Sem socket não há `chunk`, `fim` nem `comando`; outro
  cliente com a conversa aberta só vê a resposta ao reabrir.
- **Socket fechado com aprovação pendente:** hoje o `close` nega na hora. Passa a negar só
  se ninguém escuta o stream de avisos; havendo alguém, a permissão espera o prazo de 120 s.
- **Segurança:** mesmo modelo do resto do app (rede local, sem autenticação). As ações só
  funcionam com o UUID do aviso. Nenhuma ação mexe em systemd, adb ou arquivos do sistema.

## 2. Lembretes do TickTask

Módulo `app/src/avisos/lembretes.ts`. O servidor fala direto com o MCP HTTP do TickTask
(porta e token em `~/.config/ticktask/mcp-config.json`, como em `ticktask.ts`), que só
existe enquanto o app do TickTask está aberto.

- **Retrato, a cada 5 min:** tarefas não finalizadas com horário ou prazo nas próximas 48 h
  e as atrasadas, gravadas em `conversations/lembretes.json` com `atualizadoEm`. Com o
  TickTask fechado, vale o último retrato. O cliente MCP HTTP é o do
  `@modelcontextprotocol/sdk`. Como `search_tasks` não filtra "não finalizada" nem
  agendamento, o retrato junta `agenda` (agendadas) com `search_tasks` por prazo e filtra
  o status no código.
- **Disparo, a cada minuto:** função pura `disparos(retrato, agora, config, jaDisparados)`
  que devolve os avisos a gerar. Os disparados ficam registrados por
  `tarefaId + momento + tipo` no mesmo arquivo, então restart não repete; o registro é
  podado depois que o momento passa.
- **Configuração** em `avisos.json` na pasta de dados, com padrões embutidos:
  `{ "antecedenciaMin": 10, "resumoDiario": "08:00" }`.

Regras:

- **Na hora agendada:** `antecedenciaMin` antes de `scheduled_time` e de `due_time`. Tarefa
  só com data não gera aviso de horário; entra no resumo. Com o servidor fora do ar no
  momento do disparo, o lembrete ainda sai na subida se estiver até 30 min depois do
  horário da tarefa; depois disso é pulado.
- **Resumo do dia:** no horário configurado, um aviso `resumo` com o que está agendado para
  hoje, o que vence hoje e quantas estão atrasadas. Se o retrato tiver mais de 24 h, o
  resumo diz que a agenda pode estar desatualizada e desde quando. Perdido o horário, sai
  na subida se ainda não saiu hoje e for antes das 12:00.
- **Atrasada:** um aviso `atrasada` quando o prazo com hora passa sem a tarefa ser
  finalizada, uma vez só, e só se o prazo venceu nas últimas 24 h (senão a primeira subida
  avisaria cada atraso antigo); depois ela só aparece no resumo. Prazo só com data nunca
  gera `atrasada`: entra como atrasada no resumo do dia seguinte.
- **Pedido em conversa:** ferramenta `agendar_lembrete({ titulo, data: "AAAA-MM-DD",
  hora: "HH:MM" })` para todos os perfis, num MCP in-process como o da memória. O modelo
  resolve "amanhã às 9h" para data e hora; o código só valida o formato. Cria a tarefa no
  TickTask com `scheduled_date`, `scheduled_time` e a etiqueta `lembrete`. Com o TickTask
  fechado, a ferramenta devolve o erro e a persona avisa que não agendou.
- **Ações:** `concluir` muda o status para `finalizada`; `adiar` regrava o horário para
  agora + 1 h ou amanhã às 09:00 (o que remarca o lembrete), no campo que gerou o aviso:
  `scheduled_*` para agendamento, `due_*` para prazo. Adiar uma `atrasada` move o prazo. Com o TickTask fechado, a ação
  devolve erro claro e o aviso continua aberto.

## 3. App Flutter

**Android** (`flutter_foreground_task` e `flutter_local_notifications`):

- Serviço em primeiro plano com notificação fixa discreta ("Control Tower: escutando
  avisos"), ligado por um interruptor na Configuração, ativo por padrão após o pareamento,
  com reinício no boot. Pede a permissão de notificações (Android 13+) e a exceção de
  otimização de bateria. `foregroundServiceType=dataSync` (Android 14).
- No isolate do serviço: `GET /avisos?desde=<último seq salvo>`, disputando os endereços
  (LAN e Tailscale) como o app já faz; reconexão com espera crescente de 2 s a 60 s.
- Canais: *Aprovações* e *Lembretes* (alta, heads-up), *Respostas* (normal), *Resumo*
  (baixa).
- Ações no aviso: Aprovar/Negar (com o comando à vista); Concluir, +1 h, Amanhã 09:00;
  Responder com o campo de texto do Android. Rodam em segundo plano, chamam
  `POST /avisos/<id>/acao` e trocam o aviso pelo resultado ou pelo erro.
- Toque abre o app na conversa certa; lembrete abre a tela de conversa nova com o Alfred,
  foco TickTask ligado e caixa de texto vazia, sem enviar nada.
- Evento `resolvido` apaga ou atualiza o aviso no aparelho.

**Desktop Linux:** o app da bandeja assina o mesmo stream no processo principal e mostra
os avisos pelo `flutter_local_notifications` (libnotify), com os mesmos botões. Sem campo
de texto no Linux, "Responder" abre a conversa.

**Presença:** o app manda `visivel` quando uma conversa está na tela com o app em primeiro
plano, e `null` ao ir para segundo plano.

**Código:** `lib/nucleo/avisos.dart` puro e testado (linha NDJSON → aviso; tipo → canal,
texto e ações) e a casca em `lib/sistema/` (serviço, notificador, chamada das ações).

## 4. Falhas e casos de borda

- **Celular sem rede:** na volta o backlog chega pelo `desde`; resolvidos não aparecem;
  aprovação vencida chega como expirada, sem botões; avisos do backlog aparecem sem som.
- **Servidor reiniciado com aprovação pendente:** na subida, todo aviso `aprovacao` aberto
  vira `expirado`.
- **Ação em dois aparelhos:** a primeira vale; a segunda recebe `409` e o aviso mostra que
  já foi resolvido no outro aparelho.
- **Responder pelo aviso:** entra em `naFilaDaConversa` como mensagem normal, sem socket de
  chat; a resposta gera um novo aviso `resposta`, e um comando do Alfred gera `aprovacao`.
- **Canal de aprovação do Alfred:** passa a contar também quem escuta o stream de avisos.
  Sem socket de chat e sem ninguém no stream, o comando continua negado. Prazo de 120 s e
  denylist do modo auto inalterados.
- **Android matando o serviço:** exceção de bateria, reinício no boot e reconexão; ao abrir
  o app, o serviço religa e recebe o backlog.
- **Horários:** sempre no fuso local (`dataLocal`, `dataHoraLocal` de `app/src/texto.ts`).

## 5. Testes e entrega

Testes no núcleo puro:

- Servidor (`bun test`): formato do aviso e do NDJSON; regra de silêncio; backlog pelo
  `desde` (e `desde` além do maior `seq`); poda que preserva o `seq`; `409` na segunda
  ação; aprovações expiradas na subida; `lido` ao mostrar a conversa; `disparos()` com
  antecedência, tarefa só com data, atrasada uma vez e só nas últimas 24 h, resumo no
  horário, tolerância de disparo perdido, sem repetir após restart; novos horários de "+1 h" e "amanhã 09:00"; validação de data e hora do
  `agendar_lembrete`. O `bun test` roda em TZ=UTC: os testes de horário fixam
  `process.env.TZ`.
- Flutter (`flutter test`): linha NDJSON → aviso; tipo → canal, texto e ações; contrato do
  protocolo com `visivel`.
- Validação real: script de smoke que assina `/avisos` e provoca uma aprovação de verdade.
  A confirmação visual no celular e no desktop é do Ueslei.

Entrega em 4 fases, cada uma com subtarefa no TickTask, commits e build local:

1. Central de avisos no servidor: stream, ações de aprovação e resposta, `visivel` nos três
   clientes, canal de aprovação estendido.
2. Lembretes do TickTask: retrato, motor, resumo, atrasadas, concluir/adiar e
   `agendar_lembrete`.
3. Android: serviço, notificações e ações.
4. Desktop Linux: notificações na bandeja.
