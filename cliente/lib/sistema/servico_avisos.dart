import 'dart:async';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../conexao/avisos.dart';
import '../estado/servidor.dart';
import '../nucleo/avisos.dart';
import 'notificador.dart';

const aparelhoCelular = 'celular';
const chaveAvisosLigados = 'avisos_ligados';
const _chaveSeq = 'avisos_seq';

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
  final _notificador = Notificador(aparelho: aparelhoCelular);
  StreamSubscription<LinhaDeAviso>? _inscricao;
  Timer? _religar;
  Future<void> _fila = Future.value();
  var _tentativa = 0;
  var _ativo = true;

  @override
  Future<void> onStart(DateTime hora, TaskStarter iniciador) async {
    await _notificador.iniciar(emSegundoPlano: agirEmSegundoPlano);
    await _conectar();
  }

  Future<void> _conectar() async {
    if (!_ativo) return;
    final prefs = await _prefsFrescas();
    final endereco = await ServidorRemoto(prefs).resolver();
    if (endereco == null) {
      _situacao('Procurando o Control Tower…');
      _agendarReconexao();
      return;
    }
    await _inscricao?.cancel();
    _inscricao = escutarAvisos(endereco, prefs.getInt(_chaveSeq) ?? 0).listen(
      (linha) => _fila = _fila.then((_) => _tratar(prefs, linha)).catchError((_) {}),
      onError: (_) => _agendarReconexao(),
      onDone: _agendarReconexao,
      cancelOnError: true,
    );
    _situacao('Escutando avisos');
  }

  Future<void> _tratar(SharedPreferences prefs, LinhaDeAviso linha) async {
    _tentativa = 0;
    switch (linha) {
      case Notificacao():
        final alerta = alertaDe(linha, DateTime.now());
        if (alerta != Alerta.ignorar) await _notificador.mostrar(linha, alerta);
      case Resolucao(:final id, :final aparelho):
        // Neste aparelho a ação já trocou o aviso pelo resultado; apagar esconderia a resposta.
        if (aparelho != aparelhoCelular) await _notificador.apagar(id);
    }
    await prefs.setInt(_chaveSeq, linha.seq);
  }

  // Rede de celular derruba conexão longa o tempo todo; sem religar, o serviço ficaria de pé
  // sem escutar nada.
  void _agendarReconexao() {
    if (!_ativo) return;
    _situacao('Reconectando…');
    _religar?.cancel();
    final segundos = [2, 5, 15, 30, 60][_tentativa.clamp(0, 4)];
    _tentativa++;
    _religar = Timer(Duration(seconds: segundos), _conectar);
  }

  void _situacao(String texto) => FlutterForegroundTask.updateService(notificationText: texto);

  @override
  void onRepeatEvent(DateTime hora) {}

  @override
  Future<void> onDestroy(DateTime hora, bool porTimeout) async {
    _ativo = false;
    _religar?.cancel();
    await _inscricao?.cancel();
  }
}
