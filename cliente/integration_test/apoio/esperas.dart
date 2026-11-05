import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const prazoPadrao = Duration(seconds: 30);
const _passo = Duration(milliseconds: 100);

Future<void> esperarAte(
  WidgetTester t,
  bool Function() condicao, {
  Duration prazo = prazoPadrao,
  String descricao = 'a condição',
}) async {
  final limite = DateTime.now().add(prazo);
  Object? ultimoErro;
  while (true) {
    await t.pump();
    try {
      if (condicao()) return;
      ultimoErro = null;
    } catch (erro) {
      ultimoErro = erro;
    }
    if (DateTime.now().isAfter(limite)) {
      final motivo = ultimoErro == null ? '' : ' (último erro: $ultimoErro)';
      fail('prazo de ${prazo.inMilliseconds} ms estourado esperando $descricao$motivo\n${textosNaTela(t)}');
    }
    await Future<void>.delayed(_passo);
  }
}

String textosNaTela(WidgetTester t) {
  final textos = [
    for (final e in find.byType(Text).evaluate())
      if ((e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() case final texto?)
        texto.replaceAll('\n', ' '),
  ];
  final tamanho = t.view.physicalSize / t.view.devicePixelRatio;
  return '--- tela ${tamanho.width.round()}x${tamanho.height.round()}, textos: ${textos.take(120).join(' | ')}';
}

Future<String> esperarArquivo(String caminho, {String? contendo, Duration prazo = prazoPadrao}) async {
  final limite = DateTime.now().add(prazo);
  while (true) {
    final arquivo = File(caminho);
    if (arquivo.existsSync()) {
      final texto = await arquivo.readAsString();
      if (contendo == null || texto.contains(contendo)) return texto;
    }
    if (DateTime.now().isAfter(limite)) {
      fail(
        'prazo de ${prazo.inMilliseconds} ms estourado esperando o arquivo $caminho'
        '${contendo == null ? '' : ' com "$contendo"'}',
      );
    }
    await Future<void>.delayed(_passo);
  }
}

Future<void> esperarSumir(String caminho, {Duration prazo = prazoPadrao}) async {
  final limite = DateTime.now().add(prazo);
  while (FileSystemEntity.typeSync(caminho) != FileSystemEntityType.notFound) {
    if (DateTime.now().isAfter(limite)) fail('prazo de ${prazo.inMilliseconds} ms estourado esperando $caminho sumir');
    await Future<void>.delayed(_passo);
  }
}
