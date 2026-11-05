import 'package:control_tower/estado/editor_de_workflow.dart';
import 'package:control_tower/nucleo/editor_de_workflow.dart';
import 'package:control_tower/nucleo/tarefas.dart' show Ponto;
import 'package:control_tower/nucleo/workflows.dart';
import 'package:control_tower/tela/workflows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app.dart';
import 'esperas.dart';

EstadoEditorDeWorkflow editorDe(WidgetTester t) => salaDe(t).editorDeWorkflow;

WorkflowJson rascunhoNaTela(WidgetTester t) => editorDe(t).rascunho!;

Set<String> ligacoesDe(WorkflowJson w) => {
  for (final a in arestasDe(w)) '${a['de']}>${a['para']}${a['quando'] == null ? '' : ' (${a['quando']})'}',
};

Future<void> ajustarGrafo(WidgetTester t) async {
  ScaffoldMessenger.of(t.element(find.byType(CanvasDoGrafo))).clearSnackBars();
  await t.pump();
  await tocar(t, find.byTooltip('Ajustar à tela'));
  await t.pump();
}

Offset naTela(WidgetTester t, Ponto mundo, String oQue) {
  final canvas = find.byType(CanvasDoGrafo);
  final v = t.state<EstadoDoCanvasDoGrafo>(canvas).v;
  final posicao = t.getTopLeft(canvas) + Offset(mundo.x * v.escala + v.dx, mundo.y * v.escala + v.dy);
  final alvo = t.renderObject(canvas);
  if (!t.hitTestOnBinding(posicao).path.any((e) => identical(e.target, alvo))) {
    fail('$oQue fica em $posicao, fora do canvas ou coberto por outro widget');
  }
  return posicao;
}

Ponto centroDaCaixa(WidgetTester t, String id) {
  final c = cantoDaCaixa(layoutDoRascunho(rascunhoNaTela(t)), id);
  return (x: c.x + larguraDaCaixa / 2, y: c.y + alturaDaCaixa / 2);
}

Ponto pontoDeSaidaDe(WidgetTester t, String id, String? quando) {
  final r = rascunhoNaTela(t);
  final pontos = pontosDeSaida(r, id);
  final i = pontos.indexWhere((p) => p.varias || p.quando == quando);
  if (i < 0) fail('a caixa $id não tem o ponto de saída ${quando ?? 'de saída'}: ${pontos.map((p) => p.rotulo)}');
  return pontoDaSaida(layoutDoRascunho(r), id, i, pontos.length);
}

Future<void> selecionarCaixa(WidgetTester t, String id) async {
  final editor = editorDe(t);
  if (editor.selecionada == id) return;
  await ajustarGrafo(t);
  await t.tapAt(naTela(t, centroDaCaixa(t, id), 'a caixa $id'));
  await t.pump();
  await esperarAte(t, () => editor.selecionada == id, descricao: 'a caixa $id selecionada');
}

Future<String> criarPeloPonto(WidgetTester t, String de, String? quando, String tipo) async {
  final antes = idsDe(rascunhoNaTela(t));
  await ajustarGrafo(t);
  await t.tapAt(naTela(t, pontoDeSaidaDe(t, de, quando), 'o ponto ${quando ?? 'de saída'} de $de'));
  await t.pump();
  await tocar(t, find.widgetWithText(PopupMenuItem<String>, nomesDeCaixa[tipo]!));
  late String novo;
  await esperarAte(t, () {
    final criados = idsDe(rascunhoNaTela(t)).difference(antes);
    if (criados.length != 1) return false;
    novo = criados.single;
    return editorDe(t).selecionada == novo;
  }, descricao: 'a caixa $tipo criada depois de $de');
  final ligacao = '$de>$novo${quando == null ? '' : ' ($quando)'}';
  expect(ligacoesDe(rascunhoNaTela(t)), contains(ligacao));
  return novo;
}

Future<void> ligarArrastando(WidgetTester t, String de, String? quando, String para) async {
  await ajustarGrafo(t);
  final origem = naTela(t, pontoDeSaidaDe(t, de, quando), 'o ponto ${quando ?? 'de saída'} de $de');
  final destino = naTela(t, centroDaCaixa(t, para), 'a caixa $para');
  await arrastar(t, origem, destino);
}

Future<void> escolherOpcao(WidgetTester t, Finder seletor, Finder opcao) async {
  await tocar(t, seletor);
  await aparecer(t, opcao);
  await t.tap(opcao.last);
  await t.pump();
}
