import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../nucleo/avisos.dart';

Stream<LinhaDeAviso> escutarAvisos(String endereco, int desde, {http.Client? cliente}) async* {
  final conexao = cliente ?? http.Client();
  try {
    final pedido = http.Request('GET', Uri.parse('http://$endereco/avisos?desde=$desde'));
    final resposta = await conexao.send(pedido).timeout(const Duration(seconds: 10));
    if (resposta.statusCode != 200) throw http.ClientException('/avisos devolveu ${resposta.statusCode}');
    // Sem dado por 60 s (o keep-alive vem a cada 25 s) a conexão morreu sem avisar,
    // comum em rede de celular.
    final linhas = resposta.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 60));
    await for (final linha in linhas) {
      final lida = lerLinha(linha);
      if (lida != null) yield lida;
    }
  } finally {
    conexao.close();
  }
}

Future<(int, Map<String, dynamic>)> postarAcao(String endereco, String id, Map<String, Object?> pedido) async {
  try {
    final resposta = await http
        .post(
          Uri.parse('http://$endereco/avisos/${Uri.encodeComponent(id)}/acao'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(pedido),
        )
        .timeout(const Duration(seconds: 15));
    final corpo = jsonDecode(resposta.body);
    return (resposta.statusCode, corpo is Map<String, dynamic> ? corpo : <String, dynamic>{});
  } on FormatException {
    return (502, <String, dynamic>{'erro': 'Resposta inválida do Control Tower'});
  } catch (_) {
    return (0, <String, dynamic>{'erro': 'Sem conexão com o Control Tower'});
  }
}
