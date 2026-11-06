import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/modelos.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/tela/raiz.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SemServidor implements Servidor {
  @override
  Future<String?> resolver() async => null;
}

Future<Sala> montar(
  WidgetTester t,
  double largura,
  Tela tela, {
  Map<String, Object> prefs = const {},
  void Function(Sala sala)? preparar,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  t.view.physicalSize = Size(largura, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor())..ir(tela);
  preparar?.call(sala);
  await t.pumpWidget(MaterialApp(
    theme: temaEscuro,
    home: Raiz(sala: sala, configuracao: (_) => const Text('tela de configuração')),
  ));
  await t.pump();
  return sala;
}

Future<void> comCtrl(WidgetTester t, LogicalKeyboardKey tecla) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(tecla);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump();
}

final _tarefa = Tarefa(
  id: 7,
  equipe: 'casa',
  posicao: 'executor',
  titulo: 'Fechar o mês',
  status: 'em_revisao',
  atualizadaEm: DateTime(2026, 11, 6, 10),
);

void comTarefaAberta(Sala sala) => sala.tarefas
  ..tratar(TarefasRecebidas([_tarefa]))
  ..tratar(TarefaRecebida(_tarefa, const [], pedida: true));

bool estendido(WidgetTester t) => t.widget<NavigationRail>(find.byType(NavigationRail)).extended;

void main() {
  testWidgets('no celular a barra tem os 3 destinos principais e o menu leva aos outros', (t) async {
    final sala = await montar(t, 400, Tela.painel);
    final barra = t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(barra.destinations.length, 3);
    expect(find.byType(NavigationRail), findsNothing);
    for (final rotulo in ['Conversas', 'Painel', 'Tarefas']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(rotulo)), findsOneWidget);
    }

    await t.tap(find.byTooltip('Menu'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    for (final rotulo in ['Equipes', 'Personas', 'Skills', 'Board', 'Decisões']) {
      expect(find.descendant(of: find.byType(NavigationDrawer), matching: find.text(rotulo)), findsOneWidget);
    }
    await t.tap(find.descendant(of: find.byType(NavigationDrawer), matching: find.text('Decisões')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(sala.tela, Tela.decisoes);
    expect(find.byType(NavigationDrawer), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a partir de 600 dp o trilho mostra os oito destinos com rótulo', (t) async {
    final sala = await montar(t, 700, Tela.painel);
    expect(find.byType(NavigationBar), findsNothing);
    final trilho = t.widget<NavigationRail>(find.byType(NavigationRail));
    expect(trilho.destinations.length, 8);
    expect(find.descendant(of: find.byType(NavigationRail), matching: find.text('Personas')), findsOneWidget);
    expect(find.descendant(of: find.byType(NavigationRail), matching: find.text('Skills')), findsOneWidget);
    expect(trilho.extended, isFalse);
    expect(trilho.labelType, NavigationRailLabelType.all);
    await t.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Board')));
    await t.pump();
    expect(sala.tela, Tela.board);
  });

  testWidgets('a partir de 1200 dp o trilho fica estendido e a conversa ganha a lista ao lado', (t) async {
    await montar(t, 1300, Tela.conversas);
    expect(t.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
    expect(find.text('Nova conversa'), findsOneWidget);
  });

  testWidgets('Ctrl+número leva ao destino na ordem do trilho', (t) async {
    final sala = await montar(t, 1300, Tela.conversas);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.digit3);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(sala.tela, Tela.tarefas);
  });

  testWidgets('Ctrl+7 leva a Personas, e Ctrl+5 e Ctrl+6 continuam no Board e em Decisões', (t) async {
    final sala = await montar(t, 1300, Tela.conversas);
    await comCtrl(t, LogicalKeyboardKey.digit7);
    expect(sala.tela, Tela.personas);
    expect(find.text('Buscar personas'), findsOneWidget);
    await comCtrl(t, LogicalKeyboardKey.digit5);
    expect(sala.tela, Tela.board);
    await comCtrl(t, LogicalKeyboardKey.digit6);
    expect(sala.tela, Tela.decisoes);
  });

  testWidgets('Ctrl+8 leva a Skills, que pede a lista ao servidor', (t) async {
    final sala = await montar(t, 1300, Tela.conversas);
    await comCtrl(t, LogicalKeyboardKey.digit8);
    expect(sala.tela, Tela.skills);
    expect(find.text('A biblioteca da Casa e as skills de cada persona'), findsOneWidget);
  });

  testWidgets('no celular Skills fica no menu, depois de Personas', (t) async {
    final sala = await montar(t, 400, Tela.painel);
    await t.tap(find.byTooltip('Menu'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    final gaveta = find.byType(NavigationDrawer);
    final rotulos = t
        .widgetList<NavigationDrawerDestination>(find.descendant(of: gaveta, matching: find.byType(NavigationDrawerDestination)))
        .map((d) => (d.label as Text).data)
        .toList();
    expect(rotulos, ['Equipes', 'Personas', 'Skills', 'Board', 'Decisões']);
    await t.tap(find.descendant(of: gaveta, matching: find.text('Skills')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(sala.tela, Tela.skills);
    expect(find.text('Nova skill'), findsOneWidget);
  });

  testWidgets('no celular a tela de personas tem o botão Nova persona e some no detalhe', (t) async {
    final sala = await montar(t, 400, Tela.personas);
    expect(find.widgetWithText(FloatingActionButton, 'Nova persona'), findsOneWidget);
    await t.tap(find.text('Nati'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(sala.personas.aberta?.chave, 'nati');
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('o botão do trilho recolhe e expande, e a escolha fica salva', (t) async {
    await montar(t, 1300, Tela.painel);
    expect(estendido(t), isTrue);
    await t.tap(find.byTooltip('Recolher menu'));
    await t.pump();
    expect(estendido(t), isFalse);
    expect((await SharedPreferences.getInstance()).getBool(chaveTrilhoEstendido), isFalse);

    await montar(t, 1300, Tela.painel, prefs: {chaveTrilhoEstendido: false});
    await t.pump();
    expect(estendido(t), isFalse);
    await t.tap(find.byTooltip('Expandir menu'));
    await t.pump();
    expect(estendido(t), isTrue);
  });

  testWidgets('a configuração no trilho mostra o nome, recolhido ou expandido', (t) async {
    final sala = await montar(t, 1300, Tela.painel);
    final noTrilho = find.descendant(of: find.byType(NavigationRail), matching: find.text('Configuração'));
    expect(noTrilho, findsOneWidget);
    await t.tap(find.byTooltip('Recolher menu'));
    await t.pump();
    expect(noTrilho, findsOneWidget);
    await t.tap(noTrilho);
    await t.pump();
    expect(sala.tela, Tela.configuracao);
  });

  testWidgets('Ctrl+N abre a folha de nova conversa de qualquer tela', (t) async {
    await montar(t, 700, Tela.painel);
    await comCtrl(t, LogicalKeyboardKey.keyN);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Nova conversa'), findsOneWidget);
    expect(find.text('CONSELHO'), findsOneWidget);
  });

  testWidgets('Esc fecha o detalhe de tarefas, mas não enquanto se digita', (t) async {
    final sala = await montar(t, 1300, Tela.tarefas, preparar: comTarefaAberta);
    expect(sala.tarefas.aberta?.tarefa.id, 7);

    await t.tap(find.byType(TextField).first);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(sala.tarefas.aberta?.tarefa.id, 7);

    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(sala.tarefas.aberta, isNull);
  });

  testWidgets('Ctrl+K põe o foco na busca de decisões', (t) async {
    await montar(
      t,
      1300,
      Tela.decisoes,
      preparar: (sala) => sala.decisoes.tratar(const Decisoes([
        Decisao(id: '1', data: '2026-11-01', titulo: 'Usar Bun', status: 'aceita', tags: [], projeto: ''),
      ])),
    );
    final busca = find.widgetWithText(TextField, 'Buscar decisões');
    expect(t.widget<TextField>(busca).focusNode?.hasFocus, isFalse);
    await comCtrl(t, LogicalKeyboardKey.keyK);
    expect(t.widget<TextField>(busca).focusNode?.hasFocus, isTrue);
  });

  testWidgets('Ctrl+/ abre a folha de atalhos, e Esc a fecha', (t) async {
    await montar(t, 1300, Tela.painel);
    await comCtrl(t, LogicalKeyboardKey.slash);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Atalhos de teclado'), findsOneWidget);
    expect(find.text('Começar uma conversa nova'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Atalhos de teclado'), findsNothing);
  });

  testWidgets('no desktop o trilho tem o botão dos atalhos de teclado', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await montar(t, 1300, Tela.painel);
    await t.tap(find.text('Atalhos de teclado'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Mostrar os atalhos de teclado'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
