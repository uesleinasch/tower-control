import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/nucleo/skills.dart';
import 'package:control_tower/tela/paineis.dart';
import 'package:control_tower/tela/skills.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SemServidor implements Servidor {
  @override
  Future<String?> resolver() async => null;
}

const _relatorio = Skill(dono: 'casa', id: 'relatorio', descricao: 'Monta o relatório semanal.', corpo: '# Relatório');

Future<Sala> _montar(WidgetTester t, double largura) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = Size(largura, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor());
  sala.skills.tratar(const SkillsRecebidas([_relatorio]));
  await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Scaffold(body: TelaSkills(sala: sala))));
  await t.pump();
  return sala;
}

void main() {
  testWidgets('em 360 dp a lista tem cabeçalho e o editor abre em tela cheia, sem estouro', (t) async {
    final sala = await _montar(t, 360);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('A biblioteca de skills e as próprias de cada persona'), findsOneWidget);
    expect(find.text('relatorio'), findsOneWidget);
    expect(find.byType(DivisorArrastavel), findsNothing);

    await t.tap(find.byTooltip('Editar relatorio'));
    await t.pump();
    expect(sala.skills.rascunho?.id, 'relatorio');
    expect(find.text('Skill relatorio (biblioteca)'), findsOneWidget);
    expect(find.text('A biblioteca de skills e as próprias de cada persona'), findsNothing);
    expect(find.byTooltip('Descartar'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.tap(find.byTooltip('Voltar às skills'));
    await t.pump();
    expect(sala.skills.rascunho, isNull);
    expect(find.text('relatorio'), findsOneWidget);
  });

  testWidgets('em 360 dp a nova skill da biblioteca abre o editor pelo menu Nova skill', (t) async {
    final sala = await _montar(t, 360);
    await t.tap(find.text('Nova skill'));
    await t.pump();
    await t.tap(find.text('Na biblioteca'));
    await t.pump();
    await t.pump();
    expect(sala.skills.rascunho?.nova, isTrue);
    expect(find.text('Nova skill na biblioteca'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('em 1300 dp lista e editor ficam lado a lado', (t) async {
    final sala = await _montar(t, 1300);
    expect(find.byType(DivisorArrastavel), findsOneWidget);
    expect(find.text('Escolha uma skill para editar, ou crie uma em Nova skill.'), findsOneWidget);

    await t.tap(find.byTooltip('Editar relatorio'));
    await t.pump();
    expect(sala.skills.rascunho?.id, 'relatorio');
    expect(find.text('relatorio'), findsWidgets);
    expect(find.text('Skill relatorio (biblioteca)'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Descartar'), findsOneWidget);

    await t.tap(find.byTooltip('Fechar o editor'));
    await t.pump();
    expect(sala.skills.rascunho, isNull);
  });
}
