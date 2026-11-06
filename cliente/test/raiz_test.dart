import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/tela/raiz.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SemServidor implements Servidor {
  @override
  Future<String?> resolver() async => null;
}

Future<Sala> montar(WidgetTester t, double largura, Tela tela, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  t.view.physicalSize = Size(largura, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor())..ir(tela);
  await t.pumpWidget(MaterialApp(
    theme: temaEscuro,
    home: Raiz(sala: sala, configuracao: (_) => const Text('tela de configuração')),
  ));
  await t.pump();
  return sala;
}

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
    for (final rotulo in ['Equipes', 'Board', 'Decisões']) {
      expect(find.descendant(of: find.byType(NavigationDrawer), matching: find.text(rotulo)), findsOneWidget);
    }
    await t.tap(find.descendant(of: find.byType(NavigationDrawer), matching: find.text('Decisões')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(sala.tela, Tela.decisoes);
    expect(find.byType(NavigationDrawer), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a partir de 600 dp o trilho mostra os seis destinos com rótulo', (t) async {
    final sala = await montar(t, 700, Tela.painel);
    expect(find.byType(NavigationBar), findsNothing);
    final trilho = t.widget<NavigationRail>(find.byType(NavigationRail));
    expect(trilho.destinations.length, 6);
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
}
