import 'package:control_tower/nucleo/protocolo.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/acoes.dart' show tarefaNoServidor, tarefasNoServidor;
import '../apoio/app.dart' show aparecer, aparecerNoPainel, salaDe, tocar;
import '../apoio/esperas.dart';
import '../apoio/falsos.dart';

const _tituloDaCena2 = 'conjunta 2: grave o conjunta2.txt';
const _tituloDaCena8 = 'conjunta 8: conferir pelo painel';
const _aprovador = 'desktop';

Future<void> _emRevisaoNoServidor(WidgetTester t, Conexao c, int id) => esperarAteAssincrono(
  t,
  () async {
    final tarefa = (await tarefaNoServidor(c, id))['tarefa'] as Map;
    if (tarefa['status'] == 'em_revisao' && tarefa['rodando'] != true) return true;
    throw StateError('#$id está ${tarefa['status']}');
  },
  descricao: '#$id em revisão no servidor',
  prazo: const Duration(seconds: 90),
);

void cenasConjuntas({
  required String lado,
  required Future<void> Function(WidgetTester t) subir,
  required Future<void> Function(WidgetTester t, String destino) ir,
}) {
  final pular = ladosDaConjunta.isEmpty;

  testWidgets(
    'conjunta: cena 2, comando de tarefa chega a todos e o desktop aprova',
    (t) async {
      final c = await ws();
      addTearDown(c.fechar);
      await subir(t);
      final sala = salaDe(t);
      await encontroDaConjunta('conjunta-2:pronto', lado, paciente: true);

      PedidoDePermissao? pedido;
      await esperarAte(
        t,
        () => (pedido = sala.tarefas.pedidos.values.where((p) => p.comando.contains('conjunta2.txt')).firstOrNull) != null,
        descricao: 'o pedido do comando da tarefa chegar ao $lado',
        prazo: const Duration(minutes: 3),
      );
      final recebido = pedido!;
      expect(recebido.tarefaId, isNotNull, reason: 'o pedido de comando de tarefa vem com o tarefaId');
      final id = recebido.tarefaId!;

      await ir(t, 'Tarefas');
      final linha = find.text('#$id $_tituloDaCena2');
      await aparecer(t, linha, descricao: 'a tarefa #$id na lista do $lado');
      await tocar(t, linha);
      await esperarAte(t, () => sala.tarefas.aberta?.tarefa.id == id, descricao: 'a tarefa #$id aberta no $lado');
      final cartao = find.ancestor(of: find.text('Comando pedindo aprovação'), matching: find.byType(Card));
      await aparecer(
        t,
        find.descendant(of: cartao, matching: find.text(recebido.comando)),
        descricao: 'o comando pedido na tela do $lado',
      );

      if (lado == _aprovador) {
        await tocar(t, find.descendant(of: cartao, matching: find.widgetWithText(FilledButton, 'Permitir')));
      } else {
        await esperarAte(
          t,
          () => !sala.tarefas.pedidos.containsKey(recebido.id) && cartao.evaluate().isEmpty,
          descricao: 'o pedido aprovado no $_aprovador sair da tela do $lado',
          prazo: const Duration(minutes: 5),
        );
      }
      await _emRevisaoNoServidor(t, c, id);
      await encontroDaConjunta('conjunta-2:fim', lado);
    },
    skip: pular,
    timeout: const Timeout(prazoDaConjunta),
  );

  testWidgets(
    'conjunta: cena 8, item resolvido na web some do painel',
    (t) async {
      final c = await ws();
      addTearDown(c.fechar);
      late int id;
      await esperarAteAssincrono(
        t,
        () async {
          final tarefa = (await tarefasNoServidor(c))
              .where((x) => x['titulo'] == _tituloDaCena8 && x['status'] == 'em_revisao' && x['rodando'] != true)
              .firstOrNull;
          if (tarefa == null) throw StateError('a tarefa da conjunta 8 ainda não espera a aprovação');
          id = tarefa['id'] as int;
          return true;
        },
        descricao: 'a tarefa da conjunta 8 esperando a aprovação do Ueslei',
        prazo: const Duration(minutes: 5),
      );
      await subir(t);
      final sala = salaDe(t);
      await ir(t, 'Painel');
      final item = find.text('#$id espera sua aprovação');
      await aparecerNoPainel(t, item, descricao: 'o pedido de aprovação de #$id no painel do $lado');
      DateTime? sumiuNoRetratoDe;
      void ouvir() {
        final retrato = sala.painel.retrato;
        if (sumiuNoRetratoDe != null || retrato == null || retrato.atencao.any((i) => i.tarefaId == id)) return;
        sumiuNoRetratoDe = retrato.em;
      }

      sala.painel.addListener(ouvir);
      addTearDown(() => sala.painel.removeListener(ouvir));
      await encontroDaConjunta('conjunta-8:pronto', lado, paciente: true);

      await encontroDaConjunta('conjunta-8:resolvido', lado);
      await esperarAte(
        t,
        () => sumiuNoRetratoDe != null && item.evaluate().isEmpty,
        descricao: 'o item de #$id sumir do painel do $lado depois da resolução na web',
        prazo: const Duration(seconds: 45),
      );
      final registros = ((await tarefaNoServidor(c, id))['registros'] as List).cast<Map>();
      final aprovadoEm = DateTime.parse('${registros.lastWhere((r) => r['tipo'] == 'aprovado')['em']}');
      final atraso = sumiuNoRetratoDe!.difference(aprovadoEm);
      expect(
        atraso,
        lessThan(const Duration(seconds: 5)),
        reason: 'o painel do $lado só perdeu o item ${atraso.inMilliseconds} ms depois da aprovação: veio do relógio de 30 s, e não da resolução',
      );
      await encontroDaConjunta('conjunta-8:fim', lado);
    },
    skip: pular,
    timeout: const Timeout(prazoDaConjunta),
  );
}
