import 'dart:convert';
import 'dart:io';

import '../nucleo/acoes.dart';

typedef Resultado = ({int codigo, String saida, String erro});

extension ResultadoTexto on Resultado {
  bool get ok => codigo == 0;
  String get mensagem => [saida, erro].map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n');
}

Future<Resultado> rodar(Comando comando, {Duration limite = const Duration(seconds: 30)}) async {
  try {
    final r = await Process.run(comando.executavel, comando.argumentos,
            stdoutEncoding: utf8, stderrEncoding: utf8)
        .timeout(limite);
    return (codigo: r.exitCode, saida: '${r.stdout}', erro: '${r.stderr}');
  } on ProcessException catch (e) {
    return (codigo: -1, saida: '', erro: '${comando.executavel}: ${e.message}');
  } catch (e) {
    return (codigo: -1, saida: '', erro: '$comando: $e');
  }
}

Future<Process?> acompanhar(Comando comando) async {
  try {
    return await Process.start(comando.executavel, comando.argumentos);
  } on ProcessException {
    return null;
  }
}
