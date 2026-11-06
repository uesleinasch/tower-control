import 'package:control_tower/estado/equipes.dart';
import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/organograma.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/tela/equipes.dart';
import 'package:control_tower/tela/skills.dart';
import 'package:control_tower/tela/tema.dart';
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
        {'id': 'tech-lead', 'titulo': 'tech lead', 'persona': 'nati', 'capacidades': ['arquivos']},
        {'id': 'executor', 'titulo': 'executor', 'persona': 'alfred', 'respondeA': 'tech-lead', 'capacidades': ['comandos']},
        {'id': 'revisora', 'titulo': 'revisora', 'persona': null, 'respondeA': 'executor', 'capacidades': ['arquivos']},
      ],
      'layout': {
        'tech-lead': {'x': 0, 'y': 0},
        'executor': {'x': 0, 'y': 160},
        'revisora': {'x': 280, 'y': 320},
      },
    });

Future<EstadoEquipes> _montar(WidgetTester t, double largura, {bool edicao = true}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = Size(largura, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor());
  sala.equipes
    ..equipes = [_codigo()]
    ..vista = 'codigo'
    ..carregada = true;
  await t.pumpWidget(MaterialApp(
    theme: temaEscuro,
    home: Scaffold(body: TelaEquipes(sala: sala, edicao: edicao)),
  ));
  await t.pump();
  return sala.equipes;
}

Future<void> _tocarNoCartao(WidgetTester t, String titulo) async {
  await t.tap(find.text(titulo).first, warnIfMissed: false);
  await t.pump();
}

void main() {
  testWidgets('a partir de expanded o menu do cartão liga a posição', (t) async {
    final estado = await _montar(t, 1300);
    expect(find.byType(SegmentedButton<AbaDaEquipe>), findsOneWidget);

    await t.tap(find.byTooltip('Mais opções de revisora'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ligar a…'));
    await t.pumpAndSettle();
    await t.tap(find.text('Nati · tech lead'));
    await t.pumpAndSettle();

    expect(estado.atual!.posicao('revisora')!.respondeA, 'tech-lead');
    expect(find.text('revisora agora responde a tech lead.'), findsOneWidget);
  });

  testWidgets('a aba troca pelo seletor segmentado', (t) async {
    final estado = await _montar(t, 1300);
    await t.tap(find.text('Rotinas'));
    await t.pump();
    expect(estado.aba, AbaDaEquipe.rotinas);
    await t.tap(find.text('Organograma'));
    await t.pump();
    expect(estado.aba, AbaDaEquipe.organograma);
  });

  testWidgets('pelo teclado o cartão abre o menu e Mover desloca pelas setas', (t) async {
    final estado = await _montar(t, 1300);
    await _tocarNoCartao(t, 'revisora');
    expect(estado.selecionada, 'revisora');

    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.f10);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
    await t.tap(find.text('Mover'));
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(estado.atual!.ponto('revisora'), (x: 280 + passoDeMover, y: 320 + passoDeMover));

    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('revisora mudou de lugar.'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(estado.atual!.ponto('revisora').x, 280 + passoDeMover);
  });

  testWidgets('abaixo de expanded o painel vira folha embaixo do organograma', (t) async {
    final estado = await _montar(t, 700);
    await _tocarNoCartao(t, 'revisora');
    expect(estado.selecionada, 'revisora');
    expect(find.byTooltip('Fechar'), findsOneWidget);
    expect(find.text('Posição revisora'), findsOneWidget);
  });

  testWidgets('em compact o organograma é só leitura e avisa onde editar', (t) async {
    await _montar(t, 400);
    expect(find.text('Alargue a janela para editar o organograma.'), findsOneWidget);
    expect(find.byTooltip('Mais opções de revisora'), findsNothing);
    expect(find.byTooltip('Posição'), findsNothing);
    expect(find.text('Posição'), findsNothing);
  });

  testWidgets('sem edição o aviso diz que a edição fica no desktop', (t) async {
    final estado = await _montar(t, 1300, edicao: false);
    expect(find.text('A edição do organograma fica no desktop.'), findsOneWidget);
    await _tocarNoCartao(t, 'revisora');
    expect(estado.selecionada, 'revisora');
    expect(find.text('Responde a'), findsOneWidget);
  });

  testWidgets('Personas da equipe abre a gaveta, Remover tira a persona e Desfazer volta', (t) async {
    final estado = await _montar(t, 1300);
    await t.tap(find.text('Personas da equipe (2)'));
    await t.pumpAndSettle();

    expect(find.text('Personas da Código'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Nati'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Alfred'), findsOneWidget);
    expect(find.text('Remover'), findsNWidgets(2));

    await t.tap(find.byTooltip('Remover Alfred da equipe'));
    await t.pumpAndSettle();
    expect(estado.atual!.posicao('executor'), isNull);
    expect(estado.atual!.posicao('revisora')!.respondeA, 'tech-lead');
    expect(find.widgetWithText(ListTile, 'Alfred'), findsNothing);
    expect(find.text('Alfred saiu da equipe.'), findsOneWidget);

    await t.tap(find.text('Desfazer'));
    await t.pumpAndSettle();
    expect(estado.atual!.posicao('executor')!.persona, 'alfred');
    expect(find.widgetWithText(ListTile, 'Alfred'), findsOneWidget);

    await t.tap(find.byTooltip('Fechar'));
    await t.pumpAndSettle();
    expect(find.text('Personas da Código'), findsNothing);
  });

  testWidgets('Adicionar personas com duas marcadas cria as duas posições', (t) async {
    final estado = await _montar(t, 1300);
    await t.tap(find.text('Adicionar personas'));
    await t.pumpAndSettle();

    expect(find.text('Adicionar personas à Código'), findsOneWidget);
    expect(find.text('Nati e Alfred já estão nesta equipe.'), findsOneWidget);
    final confirmar = find.widgetWithText(FilledButton, 'Adicionar personas').last;
    expect(t.widget<FilledButton>(confirmar).onPressed, isNull);

    await t.tap(find.text('Poe'));
    await t.tap(find.text('Lucas'));
    await t.pump();
    await t.tap(find.text('Adicionar 2 personas'));
    await t.pumpAndSettle();

    final novas = estado.atual!.posicoes.where((p) => p.persona == 'poe' || p.persona == 'lucas').toList();
    expect([for (final p in novas) p.titulo], ['o amigo', 'o gestor']);
    expect(novas.every((p) => p.respondeA == null), isTrue);
    expect(estado.selecionada, isNull);
    expect(find.text('Personas da equipe (4)'), findsOneWidget);
  });

  testWidgets('sem edição a gaveta mostra as personas sem Remover e não há Adicionar personas', (t) async {
    await _montar(t, 1300, edicao: false);
    expect(find.text('Adicionar personas'), findsNothing);
    await t.tap(find.text('Personas da equipe (2)'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Nati'), findsOneWidget);
    expect(find.text('Remover'), findsNothing);
  });

  testWidgets('renomear a Casa muda o seletor, e a biblioteca de skills não leva o nome da equipe', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(1300, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [PosicaoResumo(id: 'executor', titulo: 'executor', persona: 'alfred')]);
    final sala = Sala(_SemServidor());
    sala.equipes
      ..equipes = [casa, _codigo()]
      ..vista = 'casa'
      ..carregada = true;
    await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Scaffold(body: TelaEquipes(sala: sala, edicao: true))));
    await t.pump();
    final seletor = find.byType(DropdownButton<String>);

    await t.tap(find.byTooltip('Renomear equipe'));
    await t.pumpAndSettle();
    final campo = find.widgetWithText(TextField, 'Nome da equipe');
    expect(t.widget<TextField>(campo).controller!.text, 'Casa');
    await t.enterText(campo, '  ');
    await t.tap(find.widgetWithText(FilledButton, 'Renomear'));
    await t.pump();
    expect(find.text('Dê um nome à equipe.'), findsOneWidget);
    await t.enterText(campo, 'Sala');
    await t.tap(find.widgetWithText(FilledButton, 'Renomear'));
    await t.pumpAndSettle();

    expect(sala.equipes.rascunho?.id, 'casa');
    expect(sala.equipes.rascunho?.nome, 'Sala');
    expect(find.descendant(of: seletor, matching: find.text('Sala')), findsOneWidget);
    expect(find.descendant(of: seletor, matching: find.text('Casa')), findsNothing);
    expect(sala.equipes.nomeDaCasa, 'Casa');

    sala.equipes.salvar();
    sala.equipes.tratar(EquipesRecebidas([casa.copiar(nome: 'Sala'), _codigo()]));
    await t.pump();
    expect(sala.equipes.rascunho, isNull);
    expect(sala.equipes.atual?.id, 'casa');
    expect(sala.equipes.nomeDaCasa, 'Sala');

    sala.skills.tratar(const SkillsRecebidas([]));
    await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Scaffold(body: TelaSkills(sala: sala))));
    await t.pump();
    expect(find.text('A biblioteca de skills e as próprias de cada persona'), findsOneWidget);
    expect(find.text('Nenhuma skill na biblioteca.'), findsOneWidget);
    expect(find.textContaining('da Sala'), findsNothing);
    expect(find.textContaining('da Casa'), findsNothing);
  });
}
