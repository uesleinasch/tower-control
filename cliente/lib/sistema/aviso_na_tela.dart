import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../estado/sala.dart';
import '../nucleo/avisos.dart';
import 'notificador.dart';

Future<void> responderAoAviso(
  NotificationResponse resposta,
  Sala sala,
  Notificador notificador,
  Future<String?> Function() endereco,
) async {
  final botao = resposta.actionId;
  if (botao != null && botao != abrirConversa) {
    await notificador.executar(resposta, endereco);
    return;
  }
  final aviso = Notificacao.daCarga(resposta.payload);
  if (aviso == null) return;
  switch (destinoDe(aviso)) {
    case AbrirConversa(:final conversaId):
      sala.abrirConversa(conversaId);
    case NovaComAlfredNoTickTask():
      sala.novaConversaNoTickTask();
    case null:
  }
}
