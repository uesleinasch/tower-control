import 'package:control_tower/estado/equipes.dart';
import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/modelos.dart';
import 'package:control_tower/nucleo/organograma.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/tela/equipes.dart';
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
  testWidgets('a partir de expanded o painel de personas fica ao lado e o menu do cartão liga a posição', (t) async {
    final estado = await _montar(t, 1300);
    expect(find.text('Clique num cartão para editar a posição.'), findsOneWidget);
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
    expect(find.text('Clique num cartão para editar a posição.'), findsNothing);
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

  testWidgets('equipe nova começa sem personas e "Adicionar à equipe" cria a posição da persona', (t) async {
    final estado = await _montar(t, 1300);
    estado.novaEquipe('Pesquisa');
    await t.pump();

    expect(estado.atual!.posicoes, isEmpty);
    expect(find.text('Nenhuma persona nesta equipe ainda.'), findsOneWidget);
    expect(find.text('Adicionar à equipe'), findsWidgets);

    final escolhida = Perfil.todos.first;
    await t.tap(find.text('Adicionar à equipe').first);
    await t.pump();

    expect(estado.atual!.posicoes.single.persona, escolhida.chave);
    expect(find.text('Nenhuma persona nesta equipe ainda.'), findsNothing);
    expect(find.text('Ocupa: ${escolhida.papel.trim().isEmpty ? escolhida.nome : escolhida.papel}'), findsOneWidget);
  });
}
