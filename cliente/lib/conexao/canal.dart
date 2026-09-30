import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../nucleo/protocolo.dart';

enum EstadoConexao { conectado, reconectando, semServidor }

class Canal extends ChangeNotifier {
  Canal(this._resolverEndereco);

  final Future<String?> Function() _resolverEndereco;
  final _eventos = StreamController<Entrada>.broadcast();
  final _conexoes = StreamController<void>.broadcast();

  WebSocket? _ws;
  Timer? _religar;
  var _tentativas = 0;
  var _ativo = false;

  EstadoConexao estado = EstadoConexao.reconectando;
  String? endereco;

  Stream<Entrada> get eventos => _eventos.stream;
  Stream<void> get conexoes => _conexoes.stream;
  bool get conectado => estado == EstadoConexao.conectado;

  void iniciar() {
    if (_ativo) return;
    _ativo = true;
    _conectar();
  }

  void pausar() {
    _ativo = false;
    _religar?.cancel();
    _ws?.close();
    _ws = null;
  }

  void reconectarJa() {
    _religar?.cancel();
    _tentativas = 0;
    if (_ativo && _ws == null) _conectar();
  }

  bool enviar(Saida saida) {
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) return false;
    ws.add(saida.codificar());
    return true;
  }

  Future<void> _conectar() async {
    _definir(estado == EstadoConexao.semServidor ? EstadoConexao.semServidor : EstadoConexao.reconectando);
    final alvo = await _resolverEndereco();
    if (!_ativo) return;
    if (alvo == null) {
      _definir(EstadoConexao.semServidor);
      _agendar();
      return;
    }
    try {
      final ws = await WebSocket.connect('ws://$alvo/ws').timeout(const Duration(seconds: 5));
      if (!_ativo) {
        await ws.close();
        return;
      }
      ws.pingInterval = const Duration(seconds: 20);
      _ws = ws;
      endereco = alvo;
      _tentativas = 0;
      _definir(EstadoConexao.conectado);
      _conexoes.add(null);
      ws.listen(
        (dado) => _eventos.add(Entrada.decodificar('$dado')),
        onDone: _caiu,
        onError: (_) => _caiu(),
        cancelOnError: true,
      );
    } catch (_) {
      _definir(_tentativas >= 2 ? EstadoConexao.semServidor : EstadoConexao.reconectando);
      _agendar();
    }
  }

  void _caiu() {
    _ws = null;
    if (!_ativo) return;
    _definir(EstadoConexao.reconectando);
    _agendar();
  }

  void _agendar() {
    _religar?.cancel();
    final atraso = min(10000, 500 * pow(2, _tentativas).toInt());
    _tentativas = min(_tentativas + 1, 5);
    _religar = Timer(Duration(milliseconds: atraso), () {
      if (_ativo && _ws == null) _conectar();
    });
  }

  void _definir(EstadoConexao novo) {
    if (estado == novo) return;
    estado = novo;
    notifyListeners();
  }

  @override
  void dispose() {
    pausar();
    _eventos.close();
    _conexoes.close();
    super.dispose();
  }
}
