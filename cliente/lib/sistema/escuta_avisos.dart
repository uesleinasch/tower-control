import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../conexao/avisos.dart';
import '../nucleo/avisos.dart';
import 'notificador.dart';

const _chaveSeq = 'avisos_seq';

class EscutaDeAvisos {
  EscutaDeAvisos({
    required this.endereco,
    required this.prefs,
    required this.notificador,
    this.aoMudar,
  });

  final Future<String?> Function() endereco;
  final Future<SharedPreferences> Function() prefs;
  final Notificador notificador;
  final void Function(String situacao)? aoMudar;

  StreamSubscription<LinhaDeAviso>? _inscricao;
  Timer? _religar;
  Future<void> _fila = Future.value();
  var _tentativa = 0;
  var _ativa = false;

  void iniciar() {
    if (_ativa) return;
    _ativa = true;
    unawaited(_conectar());
  }

  Future<void> parar() async {
    _ativa = false;
    _religar?.cancel();
    await _inscricao?.cancel();
  }

  Future<void> _conectar() async {
    if (!_ativa) return;
    final alvo = await endereco();
    if (alvo == null) {
      aoMudar?.call('Procurando o Control Tower…');
      _agendarReconexao();
      return;
    }
    final preferencias = await prefs();
    await _inscricao?.cancel();
    _inscricao = escutarAvisos(alvo, preferencias.getInt(_chaveSeq) ?? 0).listen(
      (linha) => _fila = _fila.then((_) => _tratar(preferencias, linha)).catchError((_) {}),
      onError: (_) => _agendarReconexao(),
      onDone: _agendarReconexao,
      cancelOnError: true,
    );
    aoMudar?.call('Escutando avisos');
  }

  Future<void> _tratar(SharedPreferences preferencias, LinhaDeAviso linha) async {
    _tentativa = 0;
    switch (linha) {
      case Notificacao():
        final alerta = alertaDe(linha, DateTime.now());
        if (alerta != Alerta.ignorar) await notificador.mostrar(linha, alerta);
      case Resolucao(:final id, :final aparelho):
        // Neste aparelho a ação já trocou o aviso pelo resultado; apagar esconderia a resposta.
        if (aparelho != notificador.aparelho) await notificador.apagar(id);
    }
    await preferencias.setInt(_chaveSeq, linha.seq);
  }

  // Conexão longa cai sem avisar (rede de celular, suspensão do notebook); sem religar, a
  // escuta ficaria de pé sem ouvir nada.
  void _agendarReconexao() {
    if (!_ativa) return;
    aoMudar?.call('Reconectando…');
    _religar?.cancel();
    final segundos = [2, 5, 15, 30, 60][_tentativa.clamp(0, 4)];
    _tentativa++;
    _religar = Timer(Duration(seconds: segundos), _conectar);
  }
}
