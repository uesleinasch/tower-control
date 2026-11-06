import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/design.dart';
import 'package:control_tower/nucleo/painel.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/tela/painel.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _SemServidor implements Servidor {
  @override
  Future<String?> resolver() async => null;
}

Future<Sala> montar(WidgetTester t, double largura, {Retrato? retrato}) async {
  t.view.physicalSize = Size(largura, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor());
  if (retrato != null) sala.painel.tratar(PainelRecebido(retrato));
  await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Scaffold(body: TelaPainel(sala: sala))));
  await t.pump();
  return sala;
}

final _retrato = Retrato(
  atencao: [
    ItemDeAtencao(tipo: 'aprovacao', titulo: '#7 espera sua aprovação', acoes: const ['aprovar', 'pedir-mudanca', 'abrir'], tarefaId: 7),
    ItemDeAtencao(tipo: 'bloqueada', titulo: '#9 está bloqueada', acoes: const ['abrir'], tarefaId: 9),
    ItemDeAtencao(tipo: 'comando', titulo: 'Alfred quer rodar um comando', detalhe: 'git status --short', persona: 'alfred', acoes: const ['aprovar', 'negar']),
  ],
  rodando: const [ExecucaoViva(execucao: 1, tarefaId: 3, titulo: 'Revisar o orçamento do trimestre', persona: 'nati')],
  naFila: const [Espera(execucao: 2, tarefaId: 4, titulo: 'Fechar o mês', persona: 'lucas', motivo: 'esperando a vez')],
  personas: const [
    CartaoDePersona(id: 'nati', nome: 'Natália Albuquerque', estado: 'sem_orcamento', tarefaId: 3, gastoMesUSD: 12.5, limiteUSD: 10, tokensMes: 1200000, limiteTokens: 2000000, abertas: 4),
  ],
  tarefas: const {'casa': {'em_andamento': 2, 'bloqueada': 1, 'concluida': 31}},
  gasto: const GastoDoMes(mes: '2026-11', tarefasUSD: 12.5, totalUSD: 40.25, tokensTarefas: 1200000, tokensTotal: 5400000),
  workflows: const [FluxoNoPainel(fluxo: 5, equipe: 'casa', nome: 'Triagem de pedidos', ativas: [(ficha: 1, no: 'a', titulo: 'Classificar', tipo: 'executar', tarefaId: 3)])],
);

void main() {
  test('o feed do painel tem 1 coluna em compact, 2 em medium e expanded e 3 a partir de large', () {
    expect(ClasseDeJanela.values.map(colunasDoPainel), [1, 2, 2, 3, 3]);
  });

  test('a distribuição em colunas mantém a ordem de leitura por linha', () {
    expect(emColunas([1, 2, 3, 4, 5], 1), [
      [1, 2, 3, 4, 5],
    ]);
    expect(emColunas([1, 2, 3, 4, 5], 2), [
      [1, 3, 5],
      [2, 4],
    ]);
    expect(emColunas([1, 2], 3), [
      [1],
      [2],
      <int>[],
    ]);
  });

  test('a primeira ação do pedido é a principal, abrir é de baixa ênfase salvo quando é a única', () {
    expect(enfaseDaAcao('aprovar', indice: 0, total: 3), EnfaseDaAcao.principal);
    expect(enfaseDaAcao('pedir-mudanca', indice: 1, total: 3), EnfaseDaAcao.secundaria);
    expect(enfaseDaAcao('abrir', indice: 2, total: 3), EnfaseDaAcao.baixa);
    expect(enfaseDaAcao('abrir', indice: 0, total: 1), EnfaseDaAcao.secundaria);
  });

  testWidgets('sem retrato o painel mostra o esqueleto, não um indicador girando', (t) async {
    await montar(t, 400);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Esperando a conexão com o servidor'), findsOneWidget);
  });

  testWidgets('cada pedido é um cartão com o aprovar em FilledButton e o primeiro vem antes do resto do feed', (t) async {
    final sala = await montar(t, 1300, retrato: _retrato);
    final titulo = find.text('#7 espera sua aprovação');
    final cartao = find.ancestor(of: titulo, matching: find.byType(Card)).first;
    expect(find.descendant(of: cartao, matching: find.widgetWithText(FilledButton, 'Aprovar')), findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.widgetWithText(OutlinedButton, 'Pedir mudança')), findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.widgetWithText(TextButton, 'Abrir')), findsOneWidget);
    expect(t.getTopLeft(find.text('Precisa de você')).dy, lessThan(t.getTopLeft(find.text('Agora')).dy));
    expect(t.getTopLeft(titulo).dy, lessThanOrEqualTo(t.getTopLeft(find.text('#9 está bloqueada')).dy));

    sala.painel.tratar(const PainelRecebido(Retrato()));
    await t.pump();
    expect(find.text('Nada esperando você.'), findsOneWidget);
  });

  testWidgets('em expanded o feed põe as seções lado a lado e em compact uma embaixo da outra', (t) async {
    await montar(t, 1000, retrato: _retrato);
    expect(t.getTopLeft(find.text('Workflows')).dy, t.getTopLeft(find.text('Agora')).dy);
    await montar(t, 360, retrato: _retrato);
    expect(find.text('sem orçamento'), findsOneWidget);
    expect(t.getTopLeft(find.text('Workflows')).dy, greaterThan(t.getTopLeft(find.text('Agora')).dy));
  });
}
