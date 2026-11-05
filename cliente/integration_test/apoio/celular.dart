import 'dart:async';

import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/main.dart' as app;
import 'package:control_tower/nucleo/avisos.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/sistema/servico_avisos.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ambiente.dart';
import 'app.dart' show salaDe;
import 'esperas.dart';
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
  EscutaDoApp(Sala sala) {
    _inscricao = sala.canal.eventos.listen(recebidas.add);
  }

  late final StreamSubscription<Entrada> _inscricao;
  final recebidas = <Entrada>[];

  List<PedidoDePermissao> get pedidos => recebidas.whereType<PedidoDePermissao>().toList();

  PermissaoResolvida? resolvida(String id) =>
      recebidas.whereType<PermissaoResolvida>().where((r) => r.id == id).lastOrNull;

  Future<void> parar() => _inscricao.cancel();
}

Future<(ActiveNotification, Notificacao)> avisoNaBandeja(
  WidgetTester t,
  bool Function(Notificacao n) qual, {
  required String descricao,
  Duration prazo = prazoPadrao,
}) async {
  late (ActiveNotification, Notificacao) achado;
  await esperarAteAssincrono(t, () async {
    final ativas = await FlutterLocalNotificationsPlugin().getActiveNotifications();
    for (final ativa in ativas) {
      final n = Notificacao.daCarga(ativa.payload);
      if (n != null && qual(n)) {
        achado = (ativa, n);
        return true;
      }
    }
    throw StateError('na bandeja: ${[for (final a in ativas) '${a.title} (${a.payload == null ? 'sem carga' : 'com carga'})']}');
  }, descricao: descricao, prazo: prazo);
  return achado;
}

Future<void> tocarNoBotaoDoAviso(WidgetTester t, ActiveNotification ativa, String botao) async {
  await agirEmSegundoPlano(
    NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotificationAction,
      id: ativa.id,
      actionId: botao,
      payload: ativa.payload,
    ),
  );
  await t.pump();
}
