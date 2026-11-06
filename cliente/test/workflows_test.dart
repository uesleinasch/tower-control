import 'package:control_tower/estado/editor_de_workflow.dart';
import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/editor_de_workflow.dart';
import 'package:control_tower/nucleo/organograma.dart' show passoDeMover;
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/nucleo/workflows.dart';
import 'package:control_tower/tela/equipes.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:control_tower/tela/workflows.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SemServidor implements Servidor {
  @override
  Future<String?> resolver() async => null;
}

EquipeResumo _codigo() => EquipeResumo.deJson({
      'id': 'codigo',
      'nome': 'Código',
      'posicoes': [
        {'id': 'executor', 'titulo': 'executor', 'persona': 'alfred', 'capacidades': ['comandos']},
      ],
    });

Future<EstadoEditorDeWorkflow> _montar(WidgetTester t, double largura) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = Size(largura, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor());
  final editor = sala.editorDeWorkflow;
  expect(editor.criarNovo('Triagem', _codigo(), const []), isNull);
  await t.pumpWidget(MaterialApp(
    theme: temaEscuro,
    home: Scaffold(body: TelaEquipes(sala: sala, edicao: true)),
  ));
  await t.pump();
  return editor;
}

Future<void> _tocarNaCaixa(WidgetTester t, String titulo) async {
  await t.tap(find.descendant(of: find.byType(CanvasDoGrafo), matching: find.text(titulo)).first, warnIfMissed: false);
  await t.pump();
}

Set<String> _ligacoes(EstadoEditorDeWorkflow e) => {
      for (final a in arestasDe(e.rascunho!)) '${a['de']}>${a['para']}',
    };

void main() {
  testWidgets('o menu da caixa desfaz a ligação e liga de novo sem arrastar', (t) async {
    final editor = await _montar(t, 1300);
    expect(find.text('Caixas'), findsOneWidget);
    expect(find.text('Workflow'), findsOneWidget);

    await t.tap(find.byTooltip('Mais opções de executar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Desfazer a ligação com fim'));
    await t.pumpAndSettle();
    expect(_ligacoes(editor), isEmpty);

    await t.tap(find.byTooltip('Mais opções de executar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ligar a…'));
    await t.pumpAndSettle();
    await t.tap(find.text('fim (fim)'));
    await t.pumpAndSettle();
    expect(_ligacoes(editor), {'executar>fim'});
    expect(find.text('executar agora segue para fim.'), findsOneWidget);
  });

  testWidgets('pelo teclado a caixa abre o menu e Mover desloca pelas setas', (t) async {
    final editor = await _montar(t, 1300);
    await _tocarNaCaixa(t, 'fim');
    await t.pump();
    expect(editor.selecionada, 'fim');
    expect(find.text('Caixa fim'), findsOneWidget);

    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.f10);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
    await t.tap(find.text('Mover'));
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(layoutDoRascunho(editor.rascunho!)['fim'], (x: passoXDoGrafo + passoDeMover, y: passoDeMover));

    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('fim mudou de lugar.'), findsOneWidget);
    editor.desfazer();
    expect(layoutDoRascunho(editor.rascunho!)['fim'], (x: passoXDoGrafo, y: 0.0));
  });

  testWidgets('o erro de validação fica preso à caixa, com texto', (t) async {
    final editor = await _montar(t, 1300);
    expect(editor.erros['executar'], isNotEmpty);
    expect(find.descendant(of: find.byType(CanvasDoGrafo), matching: find.textContaining(editor.erros['executar']!.first)), findsOneWidget);
  });

  testWidgets('abaixo de expanded o painel da caixa vira folha', (t) async {
    final editor = await _montar(t, 700);
    expect(find.text('Workflow'), findsOneWidget);
    await _tocarNaCaixa(t, 'fim');
    await t.pump();
    expect(editor.selecionada, 'fim');
    expect(find.text('Caixa fim'), findsOneWidget);
  });

  testWidgets('em compact o editor mostra o grafo só leitura e avisa onde editar', (t) async {
    await _montar(t, 400);
    expect(find.text('Alargue a janela para editar o workflow.'), findsOneWidget);
    expect(find.byTooltip('Mais opções de executar'), findsNothing);
    expect(find.text('Caixas'), findsNothing);
    expect(find.byTooltip('Desfazer (Ctrl+Z)'), findsNothing);
  });
}
