import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'ambiente.dart';

const _prazoDaMensagem = Duration(seconds: 30);

Future<Object?> _controle(String caminho, [Object? corpo]) async {
  final uri = Uri.parse('${ambiente.modelo}$caminho');
  final resposta = corpo == null ? await http.get(uri) : await http.post(uri, body: jsonEncode(corpo));
  if (resposta.statusCode != 200) {
    throw StateError('$caminho respondeu ${resposta.statusCode}: ${resposta.body}');
  }
  return jsonDecode(utf8.decode(resposta.bodyBytes));
}

Future<void> roteiro(String cena, List<Map<String, Object?>> regras) async {
  await _controle('/_controle/roteiro', {'cena': cena, 'regras': regras});
}

Future<List<Map>> pedidos(String cena) async =>
    ((await _controle('/_controle/pedidos?cena=${Uri.encodeQueryComponent(cena)}')) as List).cast<Map>();

Future<List<Map>> semRegra() async => ((await _controle('/_controle/sem-regra')) as List).cast<Map>();

Future<void> conferirSemRegra() async {
  final soltos = await semRegra();
  if (soltos.isEmpty) return;
  final resumo = soltos.map((p) {
    final sistema = '${p['sistema']}';
    final mensagem = '${p['ultimaMensagem']}';
    return '- sistema: ${sistema.substring(0, sistema.length.clamp(0, 160))}'
        ' | mensagem: ${mensagem.substring((mensagem.length - 300).clamp(0, mensagem.length))}';
  });
  fail('${soltos.length} pedido(s) sem regra no modelo falso:\n${resumo.join('\n')}');
}

Future<void> encontro(String nome, String lado, List<String> lados) async {
  await _controle('/_controle/encontro', {'nome': nome, 'lado': lado, 'lados': lados});
}

bool deQuem(Map pedido, String cabecalho) => '${pedido['sistema']}'.contains(cabecalho);

class Conexao {
  Conexao._(this._socket) {
    _socket.listen((dado) {
      final mensagem = jsonDecode('$dado') as Map<String, dynamic>;
      for (final ouvir in [..._ouvintes]) {
        ouvir(mensagem);
      }
    });
  }

  final WebSocket _socket;
  final _ouvintes = <void Function(Map<String, dynamic>)>{};

  void mandar(Map<String, Object?> mensagem) => _socket.add(jsonEncode(mensagem));

  Future<Map<String, dynamic>> esperar(
    String tipo, {
    bool Function(Map<String, dynamic> m)? filtro,
    Duration prazo = _prazoDaMensagem,
  }) {
    final pronto = Completer<Map<String, dynamic>>();
    late void Function(Map<String, dynamic>) ouvir;
    final relogio = Timer(prazo, () {
      _ouvintes.remove(ouvir);
      pronto.completeError(StateError('prazo de ${prazo.inMilliseconds} ms estourado esperando a mensagem "$tipo"'));
    });
    ouvir = (m) {
      if (m['tipo'] == 'erro') {
        relogio.cancel();
        _ouvintes.remove(ouvir);
        pronto.completeError(StateError('o servidor recusou: ${m['mensagem']}'));
      } else if (m['tipo'] == tipo && (filtro?.call(m) ?? true)) {
        relogio.cancel();
        _ouvintes.remove(ouvir);
        pronto.complete(m);
      }
    };
    _ouvintes.add(ouvir);
    return pronto.future;
  }

  Future<Map<String, dynamic>> pedir(
    Map<String, Object?> mensagem,
    String tipo, {
    bool Function(Map<String, dynamic> m)? filtro,
  }) {
    final resposta = esperar(tipo, filtro: filtro);
    mandar(mensagem);
    return resposta;
  }

  Future<void> fechar() => _socket.close();
}

Future<Conexao> ws() async {
  final socket = await WebSocket.connect('${ambiente.servidor.replaceFirst(RegExp('^http'), 'ws')}/ws');
  return Conexao._(socket);
}

Map<String, dynamic> lerJson(String caminho) => jsonDecode(File(caminho).readAsStringSync()) as Map<String, dynamic>;

Future<String> gitDosDados(List<String> argumentos) async {
  final r = await Process.run('git', ['-C', ambiente.dados, ...argumentos]);
  if (r.exitCode != 0) throw StateError('git ${argumentos.join(' ')} falhou: ${r.stderr}');
  return '${r.stdout}';
}
