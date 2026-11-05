import 'dart:async';
import 'dart:convert';

import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/main.dart' as app;
import 'package:control_tower/nucleo/avisos.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/sistema/servico_avisos.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ambiente.dart';
import 'app.dart' show salaDe;
import 'esperas.dart';
import 'falsos.dart' show ws;
import 'pacote.dart';

app.ControlTower? _montado;

Future<void> subirCelular(WidgetTester t, AmbienteDeTeste a) async {
  final montado = _montado;
  if (montado != null) {
    await t.pumpWidget(montado);
  } else {
    exigirPacoteDeTeste(pacoteEmExecucao());
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setStringList('enderecos', ['127.0.0.1:${a.porta}']);
    // Sem a chave, o main trata como primeira vez e abre os diálogos de permissão e de bateria do sistema.
    await prefs.setBool(chaveAvisosLigados, true);
    Object? falhou;
    var subiu = false;
    app
        .main([])
        .then<void>(
          (_) => subiu = true,
          onError: (Object erro) {
            falhou = erro;
          },
        );
    await esperarAte(t, () {
      if (falhou != null) throw StateError('o main() do app falhou: $falhou');
      return subiu && find.byType(app.ControlTower).evaluate().isNotEmpty;
    }, descricao: 'o app subir');
    _montado = t.widget<app.ControlTower>(find.byType(app.ControlTower));
  }
  final sala = salaDe(t);
  await esperarAte(t, () => sala.canal.conectado, descricao: 'o app conectar no servidor de teste');
  sala.ir(Tela.conversas);
  await t.pump();
}

class EscutaDoApp {
  EscutaDoApp(this._sala) {
    _inscricao = _sala.canal.eventos.listen(recebidas.add);
  }

  final Sala _sala;

  late final StreamSubscription<Entrada> _inscricao;
  final recebidas = <Entrada>[];

  bool get conectado => _sala.canal.conectado;

  List<PedidoDePermissao> get pedidos => recebidas.whereType<PedidoDePermissao>().toList();

  PermissaoResolvida? resolvida(String id) =>
      recebidas.whereType<PermissaoResolvida>().where((r) => r.id == id).lastOrNull;

  Future<void> parar() => _inscricao.cancel();
}

Future<Notificacao?> _avisoDoServidor(bool Function(Notificacao n) qual) async {
  final cliente = http.Client();
  try {
    final resposta = await cliente
        .send(http.Request('GET', Uri.parse('${ambiente.servidor}/avisos?desde=0')))
        .timeout(const Duration(seconds: 5));
    final linhas = resposta.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final linha in linhas.timeout(const Duration(seconds: 2), onTimeout: (fim) => fim.close())) {
      final aviso = lerLinha(linha);
      if (aviso is Notificacao && qual(aviso)) return aviso;
    }
    return null;
  } finally {
    cliente.close();
  }
}

Future<Notificacao> avisoNaBandeja(
  WidgetTester t,
  bool Function(Notificacao n) qual, {
  required String descricao,
  Duration prazo = prazoPadrao,
}) async {
  late Notificacao achado;
  await esperarAteAssincrono(t, () async {
    final aviso = await _avisoDoServidor(qual);
    if (aviso == null) throw StateError('o servidor ainda não publicou o aviso');
    // No Android, o getActiveNotifications não devolve a payload: o aviso vem do servidor e a bandeja confere id e título.
    final ativas = await FlutterLocalNotificationsPlugin().getActiveNotifications();
    if (ativas.any((a) => a.id == idDaNotificacao(aviso.id) && a.title == aviso.titulo)) {
      achado = aviso;
      return true;
    }
    throw StateError('aviso ${aviso.id} fora da bandeja: ${[for (final a in ativas) '${a.id} ${a.title}']}');
  }, descricao: descricao, prazo: prazo);
  return achado;
}

Future<void> tocarNoBotaoDoAviso(WidgetTester t, Notificacao aviso, String botao) async {
  await agirEmSegundoPlano(
    NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotificationAction,
      id: idDaNotificacao(aviso.id),
      actionId: botao,
      payload: aviso.paraCarga(),
    ),
  );
  await t.pump();
}

Future<void> negarPendentes(EscutaDoApp escuta) async {
  final pendentes = [
    for (final p in escuta.pedidos)
      if (escuta.resolvida(p.id) == null) p.id,
  ];
  if (pendentes.isEmpty) return;
  final fins = escuta.recebidas.whereType<Fim>().length;
  final c = await ws();
  try {
    for (final id in pendentes) {
      c.mandar({'tipo': 'permissao-resposta', 'id': id, 'permitido': false});
    }
    final limite = DateTime.now().add(const Duration(seconds: 60));
    bool pendurado() =>
        pendentes.any((id) => escuta.resolvida(id) == null) || escuta.recebidas.whereType<Fim>().length == fins;
    while (escuta.conectado && pendurado()) {
      if (DateTime.now().isAfter(limite)) {
        throw StateError('o turno do Alfred continuou pendurado depois de negar $pendentes no teardown');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } finally {
    await c.fechar();
  }
}
