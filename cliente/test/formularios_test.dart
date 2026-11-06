import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/importacao.dart';
import 'package:control_tower/nucleo/protocolo.dart' show RotinasRecebidas;
import 'package:control_tower/nucleo/rotinas.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/tela/importacao.dart';
import 'package:control_tower/tela/rotinas.dart';
import 'package:control_tower/tela/skills.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SemServidor implements Servidor {
  @override
  Future<String?> resolver() async => null;
}

const _casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [PosicaoResumo(id: 'executor', titulo: 'executor')]);

Future<Sala> _montar(WidgetTester t, double largura, Widget Function(Sala) tela, {void Function(Sala)? preparar}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = Size(largura, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor());
  preparar?.call(sala);
  await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Scaffold(body: tela(sala))));
  await t.pump();
  return sala;
}

Finder _campo(String rotulo) => find.ancestor(of: find.text(rotulo), matching: find.byType(TextField));

final _rolagem = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;

Future<void> _rolarAte(WidgetTester t, Finder alvo) =>
    t.scrollUntilVisible(alvo, 200, scrollable: _rolagem);

void main() {
  testWidgets('rotina: último disparo com estado, cron validado na hora com prévia e nome só ao sair do campo', (t) async {
    final sala = await _montar(t, 1300, (s) => PainelDeRotinas(sala: s, equipe: _casa, editar: true, largo: true));
    sala.rotinas.tratar(RotinasRecebidas([
      Rotina.deJson({
        'id': 'plano',
        'nome': 'Plano do dia',
        'equipe': 'casa',
        'posicao': 'executor',
        'tarefa': {'titulo': 'Plano'},
        'cron': '30 8 * * 1-5',
        'ultimoDisparo': {'id': 1, 'origem': 'manual', 'em': '2026-11-05T08:30:00', 'resultado': 'falhou', 'motivo': 'sem posição'},
      }),
    ]));
    await t.pump();
    expect(find.byType(RotuloDeEstado), findsOneWidget);
    expect(find.textContaining('manual · falhou'), findsOneWidget);

    sala.rotinas.novaRotina(_casa);
    await t.pump();
    await _rolarAte(t, _campo('Cron (minuto hora dia mês dia-da-semana)'));
    await t.enterText(_campo('Cron (minuto hora dia mês dia-da-semana)'), '*/5 * * * *');
    await t.pump();
    expect(find.text('o cron dispara com menos de 15 minutos de intervalo'), findsOneWidget);
    expect(find.text('*/5 * * * *'), findsOneWidget);

    await t.enterText(_campo('Cron (minuto hora dia mês dia-da-semana)'), '0 9 * * 1');
    await t.pump();
    expect(find.textContaining('Próximas: seg'), findsOneWidget);

    expect(find.text('nome obrigatório'), findsNothing);
    await t.scrollUntilVisible(_campo('Nome'), -200, scrollable: _rolagem);
    await t.showKeyboard(_campo('Nome'));
    await t.pump();
    await t.showKeyboard(_campo('Título'));
    await t.pump();
    expect(find.text('nome obrigatório'), findsOneWidget);
    expect(find.text('título da tarefa obrigatório'), findsNothing);

    await _rolarAte(t, find.widgetWithText(FilledButton, 'Salvar'));
    await t.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await t.pump();
    await t.scrollUntilVisible(find.text('título da tarefa obrigatório'), -200, scrollable: _rolagem);
    expect(find.text('título da tarefa obrigatório'), findsOneWidget);
    expect(sala.rotinas.salvando, isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('rotina em compact: editor em coluna única, sem estouro', (t) async {
    final sala = await _montar(t, 360, (s) => PainelDeRotinas(sala: s, equipe: _casa, editar: true, largo: false));
    sala.rotinas.tratar(const RotinasRecebidas([]));
    sala.rotinas.novaRotina(_casa);
    await t.pump();
    await _rolarAte(t, find.text('Pular'));
    expect(find.text('Pular'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('skill: salvar vazio marca os campos e não envia', (t) async {
    final sala = await _montar(t, 900, (s) => PainelDeSkills(sala: s));
    sala.skills.nova('casa');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await t.pump();
    expect(find.text('a descrição é obrigatória'), findsOneWidget);
    expect(find.text('o corpo da skill está vazio'), findsOneWidget);
    expect(sala.skills.salvando, isFalse);
  });

  for (final largura in [360.0, 1300.0]) {
    testWidgets('importação em $largura dp: escolhas segmentadas e erro preso ao campo', (t) async {
      final previa = PreviaDoModelo.deJson({
        'resumo': {'tipo': 'equipe', 'nome': 'Work', 'posicoes': 1, 'personas': 1},
        'personasDoModelo': [
          {'id': 'eva', 'nome': 'Eva', 'traz': true},
        ],
        'escolhas': {
          'equipe': {'id': 'casa', 'nome': 'Work'},
          'personas': {
            'eva': {'acao': 'criar'},
          },
          'skills': {
            'relatorio': {'acao': 'usar'},
          },
        },
        'avisos': ['as rotinas entram desligadas'],
        'erros': ['equipe: já existe uma equipe com o id casa'],
      });
      final sala = await _montar(
        t,
        largura,
        (s) => TelaDeImportacao(sala: s),
        preparar: (s) => s.importacao
          ..conteudo = '{"m":1}'
          ..previa = previa
          ..escolhas = previa.escolhas,
      );
      expect(find.text('Personas'), findsOneWidget);
      expect(find.text('já existe uma equipe com o id casa'), findsOneWidget);
      expect(find.text('Erros'), findsNothing);
      expect(find.byType(SegmentedButton<OpcaoDePersona>), findsOneWidget);
      await t.scrollUntilVisible(find.byType(SegmentedButton<OpcaoDeSkill>), 200, scrollable: _rolagem);
      expect(find.byType(SegmentedButton<OpcaoDeSkill>), findsOneWidget);
      await t.scrollUntilVisible(find.text(rotulosDeOpcaoDePersona[OpcaoDePersona.vaga]!), -200, scrollable: _rolagem);
      await t.tap(find.text(rotulosDeOpcaoDePersona[OpcaoDePersona.vaga]!));
      await t.pump();
      expect(sala.importacao.escolhas.personas['eva']?.acao, 'vaga');
      expect(find.text('As posições de Eva ficam vagas.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
