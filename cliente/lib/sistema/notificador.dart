import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../conexao/avisos.dart';
import '../nucleo/avisos.dart';

class Notificador {
  Notificador({required this.aparelho}) : campoDeTexto = Platform.isAndroid;

  final String aparelho;
  final bool campoDeTexto;
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> iniciar({
    DidReceiveNotificationResponseCallback? aoResponder,
    DidReceiveBackgroundNotificationResponseCallback? emSegundoPlano,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
      ),
      onDidReceiveNotificationResponse: aoResponder,
      onDidReceiveBackgroundNotificationResponse: emSegundoPlano,
    );
  }

  Future<NotificationResponse?> respostaQueAbriuOApp() async {
    final detalhes = await _plugin.getNotificationAppLaunchDetails();
    return detalhes?.didNotificationLaunchApp == true ? detalhes!.notificationResponse : null;
  }

  Future<void> mostrar(Notificacao n, Alerta alerta, {String? problema}) async {
    final agora = DateTime.now();
    final corpo = [?problema, corpoDe(n, agora)].join('\n\n');
    await _plugin.show(
      id: idDaNotificacao(n.id),
      title: n.titulo,
      body: corpo,
      payload: n.paraCarga(),
      notificationDetails: _detalhes(n, botoesDe(n, campoDeTexto: campoDeTexto, agora: agora), corpo,
          silencioso: alerta != Alerta.tocar),
    );
  }

  Future<void> resultado(Notificacao n, String texto) => _plugin.show(
        id: idDaNotificacao(n.id),
        title: n.titulo,
        body: texto,
        payload: n.paraCarga(),
        notificationDetails: _detalhes(n, const [], texto, silencioso: true, some: true),
      );

  Future<void> apagar(String id) => _plugin.cancel(id: idDaNotificacao(id));

  Future<void> executar(NotificationResponse resposta, Future<String?> Function() endereco) async {
    final n = Notificacao.daCarga(resposta.payload);
    final botao = resposta.actionId;
    if (n == null || botao == null) return;
    final pedido = pedidoDoBotao(botao, texto: resposta.input, aparelho: aparelho);
    if (pedido == null) return;
    final alvo = await endereco();
    final (status, corpo) =
        alvo == null ? (0, <String, dynamic>{'erro': 'Sem conexão com o Control Tower'}) : await postarAcao(alvo, n.id, pedido);
    final texto = textoDoResultado(status, corpo);
    if (status == 200 || status == 404 || status == 409) {
      await resultado(n, texto);
    } else {
      await mostrar(n, Alerta.silencioso, problema: texto);
    }
  }

  NotificationDetails _detalhes(Notificacao n, List<Botao> botoes, String corpo,
      {required bool silencioso, bool some = false}) {
    final canal = canalDe(n.tipo);
    final prazo = n.expiraEm?.difference(DateTime.now());
    return NotificationDetails(
      android: AndroidNotificationDetails(
        canal.id,
        canal.nome,
        importance: canal.alta
            ? Importance.high
            : canal.baixa
                ? Importance.low
                : Importance.defaultImportance,
        priority: canal.alta ? Priority.high : Priority.defaultPriority,
        silent: silencioso,
        onlyAlertOnce: true,
        styleInformation: BigTextStyleInformation(corpo),
        timeoutAfter: some
            ? 10000
            : prazo != null && !prazo.isNegative
                ? prazo.inMilliseconds
                : null,
        actions: [
          for (final b in botoes)
            AndroidNotificationAction(
              b.id,
              b.rotulo,
              inputs: b.comTexto ? const [AndroidNotificationActionInput(label: 'Sua resposta')] : const [],
            ),
        ],
      ),
      linux: LinuxNotificationDetails(
        urgency: canal.alta ? LinuxNotificationUrgency.critical : LinuxNotificationUrgency.normal,
        suppressSound: silencioso,
        timeout: some ? const LinuxNotificationTimeout(10000) : const LinuxNotificationTimeout.systemDefault(),
        actions: [for (final b in botoes) LinuxNotificationAction(key: b.id, label: b.rotulo)],
      ),
    );
  }
}
