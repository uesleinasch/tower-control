import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../estado/servidor.dart';
import 'escuta_avisos.dart';
import 'notificador.dart';

const aparelhoCelular = 'celular';
const chaveAvisosLigados = 'avisos_ligados';

Future<SharedPreferences> _prefsFrescas() async {
  final prefs = await SharedPreferences.getInstance();
  // Cada isolate tem o próprio cache: sem reload, o serviço não vê o pareamento novo.
  await prefs.reload();
  return prefs;
}

Future<String?> _endereco() async => ServidorRemoto(await _prefsFrescas()).resolver();

@pragma('vm:entry-point')
Future<void> agirEmSegundoPlano(NotificationResponse resposta) async {
  DartPluginRegistrant.ensureInitialized();
  final notificador = Notificador(aparelho: aparelhoCelular);
  await notificador.iniciar();
  await notificador.executar(resposta, _endereco);
}

class ServicoDeAvisos {
  const ServicoDeAvisos();

  void preparar() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'avisos-servico',
        channelName: 'Conexão com o Control Tower',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> ligado() => FlutterForegroundTask.isRunningService;

  Future<bool> notificacoesPermitidas() async =>
      await FlutterForegroundTask.checkNotificationPermission() == NotificationPermission.granted;

  Future<void> ligar({bool pedirPermissoes = true}) async {
    if (pedirPermissoes) {
      if (!await notificacoesPermitidas()) await FlutterForegroundTask.requestNotificationPermission();
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }
    if (await ligado()) return;
    await FlutterForegroundTask.startService(
      serviceId: 7878,
      serviceTypes: const [ForegroundServiceTypes.remoteMessaging],
      notificationTitle: 'Control Tower',
      notificationText: 'Escutando avisos',
      callback: iniciarEscuta,
    );
  }

  Future<void> desligar() => FlutterForegroundTask.stopService();
}

@pragma('vm:entry-point')
void iniciarEscuta() => FlutterForegroundTask.setTaskHandler(_Escuta());

class _Escuta extends TaskHandler {
  EscutaDeAvisos? _escuta;

  @override
  Future<void> onStart(DateTime hora, TaskStarter iniciador) async {
    final notificador = Notificador(aparelho: aparelhoCelular);
    await notificador.iniciar(emSegundoPlano: agirEmSegundoPlano);
    _escuta = EscutaDeAvisos(
      endereco: _endereco,
      prefs: _prefsFrescas,
      notificador: notificador,
      aoMudar: (situacao) => FlutterForegroundTask.updateService(notificationText: situacao),
    )..iniciar();
  }

  @override
  void onRepeatEvent(DateTime hora) {}

  @override
  Future<void> onDestroy(DateTime hora, bool porTimeout) async => _escuta?.parar();
}
