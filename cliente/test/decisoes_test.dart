import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/estado/servidor.dart';
import 'package:control_tower/nucleo/modelos.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/tela/board.dart';
import 'package:control_tower/tela/decisoes.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _SemServidor implements Servidor {
  @override
  Future<String?> resolver() async => null;
}

const _a = Decisao(id: '1', data: '2026-11-01', titulo: 'Usar Bun', status: 'aceita', tags: ['runtime'], projeto: 'tower');
const _b = Decisao(id: '2', data: '2026-11-02', titulo: 'Outra escolha', status: 'proposta', tags: [], projeto: '');

Future<Sala> montar(WidgetTester t, double largura, Widget Function(Sala) tela) async {
  t.view.physicalSize = Size(largura, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sala = Sala(_SemServidor());
  sala.decisoes.tratar(const Decisoes([_a, _b]));
  await t.pumpWidget(MaterialApp(theme: temaEscuro, home: Scaffold(body: tela(sala))));
  await t.pump();
  return sala;
}

void main() {
  test('estadoDaDecisao mapeia o status do ADR', () {
    expect(estadoDaDecisao('aceita'), 'aprovado');
    expect(estadoDaDecisao('revogada'), 'recusada');
    expect(estadoDaDecisao('proposta'), 'em_revisao');
  });

  testWidgets('compact mostra só a lista, e a busca sem resultado oferece Limpar busca', (t) async {
    final sala = await montar(t, 400, (s) => TelaDecisoes(sala: s));
    expect(find.text('Usar Bun'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'zzz');
    await t.pump();
    expect(find.text('Nenhuma decisão com essa busca.'), findsOneWidget);
    await t.tap(find.text('Limpar busca'));
    await t.pump();
    expect(sala.decisoes.filtro, '');
    expect(find.text('Usar Bun'), findsOneWidget);
  });

  testWidgets('expanded mostra lista e estado de nada selecionado lado a lado', (t) async {
    await montar(t, 1000, (s) => TelaDecisoes(sala: s));
    expect(find.text('Usar Bun'), findsOneWidget);
    expect(find.text('Escolha uma decisão na lista para ler o registro.'), findsOneWidget);
  });

  testWidgets('expanded mostra o detalhe ao lado da lista', (t) async {
    final sala = await montar(t, 1000, (s) => TelaDecisoes(sala: s));
    sala.decisoes.tratar(const DecisaoAberta('1', '# Usar Bun\n\nTexto da decisão.'));
    await t.pump();
    expect(find.text('Usar Bun'), findsWidgets);
    expect(find.text('Outra escolha'), findsOneWidget);
    expect(find.text('Copiar'), findsNothing);
    expect(find.byTooltip('Copiar'), findsOneWidget);
  });

  testWidgets('board mostra o aviso enquanto delibera', (t) async {
    final sala = await montar(t, 400, (s) => TelaBoard(sala: s));
    expect(find.text('Convocar'), findsOneWidget);
    sala.board.emCurso = true;
    sala.board.notifyListeners();
    await t.pump();
    expect(find.textContaining('conselheiros estão respondendo'), findsOneWidget);
  });
}
