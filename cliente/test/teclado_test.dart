import 'package:control_tower/nucleo/atalhos_de_teclado.dart';
import 'package:control_tower/tela/comum.dart';
import 'package:control_tower/tela/paineis.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lateral = Key('lateral');

Future<void> montar(WidgetTester t, {bool aDireita = false, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  t.view.physicalSize = const Size(1000, 600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: temaEscuro,
    home: Scaffold(
      body: LadoALado(
        painel: 'teste',
        rotulo: 'Largura da lista',
        lateralADireita: aDireita,
        lateral: const SizedBox.expand(key: _lateral),
        principal: const SizedBox.expand(),
      ),
    ),
  ));
  await t.pump();
}

double larguraDaLateral(WidgetTester t) => t.getSize(find.byKey(_lateral)).width;

Future<double?> salva() async => (await SharedPreferences.getInstance()).getDouble(chaveDaLargura('teste'));

void main() {
  test('a lista de atalhos não repete combinação dentro do grupo nem usa as globais com Ctrl nas telas', () {
    final globais = {
      for (final a in grupoGlobal.atalhos)
        for (final c in a.alternativas)
          if (c.contains('Ctrl')) textoDaCombinacao(c),
    };
    for (final texto in ['Ctrl+1', 'Ctrl+6', 'Ctrl+N', 'Ctrl+K', 'Ctrl+/']) {
      expect(globais, contains(texto));
    }
    expect(atalhosDeTeclado.first, same(grupoGlobal));
    for (final grupo in atalhosDeTeclado) {
      expect(grupo.titulo, isNotEmpty);
      expect(grupo.atalhos, isNotEmpty);
      final vistas = <String>{};
      for (final atalho in grupo.atalhos) {
        expect(atalho.acao, isNotEmpty);
        expect(atalho.acao.contains('—'), isFalse);
        for (final c in atalho.alternativas) {
          expect(c, isNotEmpty);
          expect(vistas.add(textoDaCombinacao(c)), isTrue, reason: '${grupo.titulo}: ${textoDaCombinacao(c)}');
          if (!identical(grupo, grupoGlobal)) expect(globais, isNot(contains(textoDaCombinacao(c))));
        }
      }
    }
  });

  testWidgets('arrastar o divisor muda a largura dentro dos limites e salva', (t) async {
    await montar(t);
    expect(larguraDaLateral(t), 320);
    final divisor = find.byType(DivisorArrastavel);
    await t.drag(divisor, const Offset(100, 0));
    await t.pump();
    expect(larguraDaLateral(t), closeTo(420, 1));
    expect(await salva(), closeTo(420, 1));

    await t.drag(divisor, const Offset(600, 0));
    await t.pump();
    expect(larguraDaLateral(t), 560);
    await t.drag(divisor, const Offset(-900, 0));
    await t.pump();
    expect(larguraDaLateral(t), 240);
  });

  testWidgets('com o painel à direita, arrastar para a esquerda alarga', (t) async {
    await montar(t, aDireita: true);
    await t.drag(find.byType(DivisorArrastavel), const Offset(-80, 0));
    await t.pump();
    expect(larguraDaLateral(t), closeTo(400, 1));
  });

  testWidgets('o divisor recebe foco e as setas mudam a largura de 16 em 16', (t) async {
    await montar(t);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(larguraDaLateral(t), 336);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(larguraDaLateral(t), 304);
    expect(await salva(), 304);
  });

  testWidgets('a largura salva volta ao abrir a tela', (t) async {
    await montar(t, prefs: {chaveDaLargura('teste'): 400.0});
    await t.pump();
    expect(larguraDaLateral(t), 400);
  });

  testWidgets('a barra de rolagem fica visível só no desktop', (t) async {
    Widget lista() => MaterialApp(
          home: Scaffold(
            body: RolagemDeDesktop(
              builder: (context, controle) => ListView(
                controller: controle,
                children: [for (var i = 0; i < 100; i++) Text('linha $i')],
              ),
            ),
          ),
        );
    await t.pumpWidget(lista());
    expect(find.byType(Scrollbar), findsNothing);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(lista());
    final barras = t.widgetList<Scrollbar>(find.byType(Scrollbar));
    expect(barras, hasLength(1));
    expect(barras.single.thumbVisibility, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}
