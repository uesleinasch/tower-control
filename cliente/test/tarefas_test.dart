import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/tela/tarefas.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _SemServidor implements Servidor {
  @override
  Future<String?> resolver() async => null;
}

final _tarefa = Tarefa(
  id: 7,
  equipe: 'casa',
  posicao: 'executor',
  titulo: 'Fechar o mês',
  status: 'em_revisao',
  atualizadaEm: DateTime(2026, 11, 6, 10),
);

final _plano = RegistroDeTarefa(tipo: 'plano', autor: 'Alfred', texto: 'Somar as notas e conferir.', em: DateTime(2026, 11, 6, 9));

void largura(WidgetTester t, double valor) {
  t.view.physicalSize = Size(valor, 900);
  t.view.devicePixelRatio = 1;
}

Future<Sala> montar(WidgetTester t, double valor) async {
  largura(t, valor);
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor());
  sala.tarefas
    ..tratar(TarefasRecebidas([_tarefa]))
    ..tratar(TarefaRecebida(_tarefa, [_plano], pedida: true));
  await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Scaffold(body: TelaTarefas(sala: sala))));
  await t.pump();
  return sala;
}

void main() {
  testWidgets('a partir de expanded lista e detalhe ficam lado a lado e a seleção sobrevive à largura', (t) async {
    final sala = await montar(t, 1000);
    expect(find.text('#7 Fechar o mês'), findsOneWidget);
    expect(find.text('#7'), findsOneWidget);

    largura(t, 500);
    await t.pump();
    expect(find.text('#7 Fechar o mês'), findsNothing);
    expect(find.text('#7'), findsOneWidget);

    largura(t, 1000);
    await t.pump();
    expect(sala.tarefas.aberta?.tarefa.id, 7);
    expect(find.text('#7 Fechar o mês'), findsOneWidget);

    await t.tap(find.byTooltip('Fechar'));
    await t.pump();
    expect(find.text('Escolha uma tarefa na lista para ver o andamento.'), findsOneWidget);
  });

  testWidgets('plano pendente vira pedido de aprovação com a ação principal em FilledButton', (t) async {
    await montar(t, 1000);
    expect(find.text('Plano de Alfred espera sua aprovação'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Aprovar plano'), findsOneWidget);
    expect(find.text('Somar as notas e conferir.'), findsOneWidget);
  });

  testWidgets('o menu da tarefa traz a troca de status e o cancelamento', (t) async {
    await montar(t, 1000);
    await t.tap(find.byTooltip('Mais opções'));
    await t.pumpAndSettle();
    expect(find.text('Concluir tarefa'), findsOneWidget);
    expect(find.text('Cancelar tarefa'), findsOneWidget);
  });
}
