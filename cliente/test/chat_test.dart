import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/modelos.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/tela/raiz.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SemServidor implements Servidor {
  @override
  Future<String?> resolver() async => null;
}

Future<Sala> montar(WidgetTester t, double largura, String perfil) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = Size(largura, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor())
    ..ir(Tela.chat)
    ..chat.novaConversa(perfil);
  await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Raiz(sala: sala)));
  await t.pump();
  return sala;
}

Future<void> desmontar(WidgetTester t, Sala sala) async {
  sala.chat.fechar();
  await t.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('os chips de modo do Alfred cabem no cabeçalho com 360 dp', (t) async {
    final sala = await montar(t, 360, 'alfred');
    sala.chat
      ..alternarTicktask()
      ..alternarAuto();
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.widgetWithText(FilterChip, 'TickTask'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'auto'), findsOneWidget);
    await desmontar(t, sala);
  });

  testWidgets('o pedido de comando tem Permitir e Negar e, resolvido, só o resultado', (t) async {
    final sala = await montar(t, 1300, 'alfred');
    sala.chat.tratar(const PedidoDePermissao('p1', 'rm -rf /tmp/x'));
    await t.pump();
    expect(find.text('Alfred quer rodar um comando'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Permitir'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Negar'), findsOneWidget);

    sala.chat.tratar(const PermissaoResolvida('p1', 'aprovado'));
    await t.pump();
    expect(find.text('Alfred quer rodar um comando'), findsNothing);
    expect(find.text('Comando permitido'), findsOneWidget);
    expect(find.text('rm -rf /tmp/x'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Permitir'), findsNothing);
    await desmontar(t, sala);
  });

  testWidgets('a linha de status só aparece depois de 1 s sem texto novo', (t) async {
    final sala = await montar(t, 1300, 'nati');
    sala.chat
      ..tratar(const Criada(MetaConversa(id: 'c1', perfil: 'nati', titulo: 'teste', criadaEm: null)))
      ..emCurso = true
      ..tratar(const Pedaco('c1', 'nati', 'Olá'));
    await t.pump();
    await t.pump();
    double opacidade() => t
        .widget<AnimatedOpacity>(find.ancestor(of: find.text('Nati está pensando…'), matching: find.byType(AnimatedOpacity)))
        .opacity;
    expect(opacidade(), 0);
    await t.pump(const Duration(milliseconds: 1100));
    expect(opacidade(), 1);

    sala.chat.tratar(const Pedaco('c1', 'nati', ' de novo'));
    await t.pump();
    expect(opacidade(), 0);
    await desmontar(t, sala);
  });
}
