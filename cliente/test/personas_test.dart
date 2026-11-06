import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/tela/paineis.dart';
import 'package:control_tower/tela/personas.dart';
import 'package:control_tower/tela/tema.dart';
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
        {'id': 'tech-lead', 'titulo': 'tech lead', 'persona': 'nati', 'capacidades': ['arquivos']},
        {'id': 'executor', 'titulo': 'executor', 'persona': 'alfred', 'respondeA': 'tech-lead', 'capacidades': ['comandos']},
      ],
    });

Future<Sala> _montar(WidgetTester t, double largura) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = Size(largura, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor());
  sala.equipes
    ..equipes = [_codigo()]
    ..carregada = true;
  await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Scaffold(body: TelaPersonas(sala: sala))));
  await t.pump();
  return sala;
}

void main() {
  testWidgets('a lista mostra as personas com as posições, e a busca filtra pelo nome', (t) async {
    await _montar(t, 400);
    for (final nome in ['Poe', 'Nati', 'Lucas', 'Pami', 'Alfred']) {
      expect(find.text(nome), findsOneWidget);
    }
    expect(find.text('engenheira sênior · 1 posição'), findsOneWidget);
    expect(find.text('o amigo · nenhuma posição'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextField, 'Buscar personas'), 'na');
    await t.pump();
    expect(find.text('Nati'), findsOneWidget);
    expect(find.text('Poe'), findsNothing);
    expect(find.text('Alfred'), findsNothing);

    await t.enterText(find.widgetWithText(TextField, 'Buscar personas'), 'zz');
    await t.pump();
    expect(find.text('Nenhuma persona com essa busca.'), findsOneWidget);
    await t.tap(find.text('Limpar busca'));
    await t.pump();
    expect(find.text('Poe'), findsOneWidget);
  });

  testWidgets('em 1300 dp lista e detalhe ficam lado a lado, e o cartão Equipes leva à equipe', (t) async {
    final sala = await _montar(t, 1300);
    expect(find.text('Escolha uma persona na lista para ver e editar.'), findsOneWidget);
    expect(find.byType(DivisorArrastavel), findsOneWidget);

    await t.tap(find.text('Nati'));
    await t.pump();
    expect(find.text('Buscar personas'), findsOneWidget);
    expect(find.text('Pausar Nati'), findsOneWidget);
    expect(find.text('Dados'), findsOneWidget);
    expect(find.text('Orçamento do mês'), findsOneWidget);
    expect(find.text('Código'), findsOneWidget);
    expect(find.text('tech lead'), findsOneWidget);

    await t.ensureVisible(find.text('Abrir equipe'));
    await t.tap(find.text('Abrir equipe'));
    await t.pump();
    expect(sala.tela, Tela.equipes);
    expect(sala.equipes.atual?.id, 'codigo');
  });

  testWidgets('persona sem equipe diz como entrar numa', (t) async {
    final sala = await _montar(t, 1300);
    sala.personas.abrir('poe');
    await t.pump();
    expect(find.text('Poe ainda não está em nenhuma equipe.'), findsOneWidget);
    expect(find.text('Para pôr Poe numa equipe, use "Adicionar personas" na tela da equipe.'), findsOneWidget);
  });
}
