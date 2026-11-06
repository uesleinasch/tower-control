import 'dart:convert';

import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/painel.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/nucleo/workflows.dart';
import 'package:control_tower/tela/comum.dart';
import 'package:control_tower/tela/painel.dart';
import 'package:control_tower/tela/tarefas.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:control_tower/tela/workflows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

class _SemServidor implements Servidor {
  @override
  Future<String?> resolver() async => null;
}

const _definicao = {
  'id': 'revisao-semanal',
  'nome': 'Revisão semanal',
  'versao': 1,
  'inicio': 'escrever',
  'nos': [
    {'id': 'escrever', 'titulo': 'Escrever resumo', 'tipo': 'executar', 'posicao': 'executor', 'instrucao': 'Resuma a semana'},
  ],
  'arestas': [],
};

WorkflowsRecebidos _workflows(String statusDaFicha) => Entrada.decodificar(jsonEncode({
      'tipo': 'workflows',
      'definicoes': [
        {..._definicao, 'equipe': 'casa'},
      ],
      'fluxos': [
        {
          'id': 7,
          'equipe': 'casa',
          'workflow': 'revisao-semanal',
          'versao': 1,
          'definicao': _definicao,
          'status': 'rodando',
          'criadoPor': 'ueslei',
          'criadoEm': '2026-11-06T09:00:00.000Z',
          'fichas': [
            {
              'id': 3,
              'fluxo': 7,
              'no': 'escrever',
              'status': statusDaFicha,
              'tarefa': 42,
              'criadaEm': '2026-11-06T09:00:00.000Z',
              if (statusDaFicha == 'parada') 'concluidaEm': '2026-11-06T09:30:00.000Z',
            },
          ],
        },
      ],
    })) as WorkflowsRecebidos;

Tarefa _tarefa({required String status, bool doFluxo = true}) => Tarefa(
      id: 42,
      equipe: 'casa',
      posicao: 'executor',
      titulo: 'Revisão semanal: Escrever resumo',
      status: status,
      atualizadaEm: DateTime(2026, 11, 6, 10),
      fluxo: doFluxo ? 7 : null,
      ficha: doFluxo ? 3 : null,
    );

Future<Sala> _montarTarefa(WidgetTester t, Tarefa tarefa, {String statusDaFicha = 'esperando'}) async {
  t.view.physicalSize = const Size(1000, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor());
  sala.workflows.tratar(_workflows(statusDaFicha));
  sala.tarefas
    ..tratar(TarefasRecebidas([tarefa]))
    ..tratar(TarefaRecebida(tarefa, const [], pedida: true));
  await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Scaffold(body: TelaTarefas(sala: sala))));
  await t.pump();
  return sala;
}

Future<void> _escolherCancelar(WidgetTester t) async {
  await t.tap(find.byTooltip('Mais opções'));
  await t.pumpAndSettle();
  await t.tap(find.text('Cancelar tarefa'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('cancelar uma tarefa de workflow pergunta se é só a tarefa ou o workflow inteiro', (t) async {
    await _montarTarefa(t, _tarefa(status: 'em_andamento'));
    await _escolherCancelar(t);
    final dialogo = find.byType(AlertDialog);
    expect(dialogo, findsOneWidget);
    expect(find.text('Cancelar a tarefa #42?'), findsOneWidget);
    expect(find.text('Ela faz parte do workflow "Revisão semanal" (#7), na caixa "Escrever resumo".'), findsOneWidget);
    expect(
      find.text('O workflow para na caixa "Escrever resumo" e espera você escolher: recriar a tarefa ou cancelar o workflow.'),
      findsOneWidget,
    );
    expect(find.text('Cancela o workflow #7 e todas as tarefas abertas dele. O que já foi feito fica registrado.'), findsOneWidget);
    expect(find.byType(RadioGroup<EscopoDoCancelamento>), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Voltar'), findsOneWidget);
    final confirmar = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Cancelar a tarefa'));
    final cores = Theme.of(t.element(dialogo)).colorScheme;
    expect(confirmar.style?.backgroundColor?.resolve({}), cores.error);
  });

  testWidgets('a janela começa em "Só esta tarefa", troca de escolha e Voltar não cancela nada', (t) async {
    t.view.physicalSize = const Size(1000, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final caixa = caixaVivaDaTarefa(_tarefa(status: 'em_andamento'), _workflows('esperando').fluxos)!;
    final respostas = <EscopoDoCancelamento?>[];
    await t.pumpWidget(MaterialApp(
      theme: temaEscuro,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => respostas.add(await escolherEscopoDoCancelamento(context, 42, caixa)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    Future<void> abrir() async {
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
    }

    await abrir();
    await t.tap(find.text('Cancelar a tarefa'));
    await t.pumpAndSettle();
    await abrir();
    await t.tap(find.text('O workflow inteiro'));
    await t.pump();
    await t.tap(find.text('Cancelar a tarefa'));
    await t.pumpAndSettle();
    await abrir();
    await t.tap(find.text('Voltar'));
    await t.pumpAndSettle();
    expect(respostas, [EscopoDoCancelamento.tarefa, EscopoDoCancelamento.fluxo, null]);
  });

  testWidgets('tarefa fora de workflow cancela sem a janela de escolha', (t) async {
    await _montarTarefa(t, _tarefa(status: 'em_andamento', doFluxo: false));
    await _escolherCancelar(t);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a tarefa cancelada de uma caixa parada mostra o pedido com Recriar e Cancelar o workflow', (t) async {
    await _montarTarefa(t, _tarefa(status: 'cancelada'), statusDaFicha: 'parada');
    final faixa = find.text('Caixa parada no workflow #7');
    expect(faixa, findsOneWidget);
    final cartao = find.ancestor(of: faixa, matching: find.byType(CartaoDePedido));
    expect(
      find.descendant(
        of: cartao,
        matching: find.text('A tarefa #42 da caixa "Escrever resumo" foi cancelada. O workflow "Revisão semanal" está esperando você decidir.'),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: cartao, matching: find.byIcon(Symbols.pause_circle)), findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.widgetWithText(FilledButton, 'Recriar a tarefa')), findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.widgetWithText(OutlinedButton, 'Cancelar o workflow')), findsOneWidget);
    await t.tap(find.text('Cancelar o workflow'));
    await t.pumpAndSettle();
    expect(find.text('Cancelar o workflow Revisão semanal (#7)?'), findsOneWidget);
  });

  testWidgets('no painel o pedido de caixa parada usa o mesmo cartão', (t) async {
    t.view.physicalSize = const Size(1300, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final sala = Sala(_SemServidor());
    sala.painel.tratar(PainelRecebido(Retrato(
      atencao: [
        ItemDeAtencao(
          tipo: 'parada',
          titulo: 'Caixa parada no workflow #7',
          detalhe: 'A tarefa #42 da caixa "Escrever resumo" foi cancelada. O workflow "Revisão semanal" está esperando você decidir.',
          acoes: const ['recriar', 'cancelar-fluxo'],
          fluxo: 7,
          ficha: 3,
          tarefaId: 42,
        ),
      ],
      workflows: const [
        FluxoNoPainel(
          fluxo: 7,
          equipe: 'casa',
          nome: 'Revisão semanal',
          ativas: [(ficha: 3, no: 'escrever', titulo: 'Escrever resumo', tipo: 'executar', tarefaId: 42, parada: true)],
        ),
      ],
    )));
    await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Scaffold(body: TelaPainel(sala: sala))));
    await t.pump();
    final cartao = find.ancestor(of: find.text('Caixa parada no workflow #7'), matching: find.byType(PedidoDeCaixaParada));
    expect(cartao, findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.widgetWithText(FilledButton, 'Recriar a tarefa')), findsOneWidget);
    expect(find.textContaining('Escrever resumo (parada #42)'), findsOneWidget);
    await t.tap(find.descendant(of: cartao, matching: find.text('Cancelar o workflow')));
    await t.pumpAndSettle();
    expect(find.text('Cancelar o workflow Revisão semanal (#7)?'), findsOneWidget);
  });
}
