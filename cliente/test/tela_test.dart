import 'package:control_tower/nucleo/design.dart';
import 'package:control_tower/nucleo/espelho.dart';
import 'package:control_tower/tela/configuracao.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bloco da configuração pinta os interruptores sobre o próprio Material', (t) async {
    var ligado = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlocoDeConfiguracao(titulo: 'Espelho no TickTask', icone: Symbols.sync_alt, filhos: [
          StatefulBuilder(
            builder: (context, mudar) => SwitchListTile(
              value: ligado,
              onChanged: (v) => mudar(() => ligado = v),
              title: const Text('Espelhar no TickTask'),
            ),
          ),
        ]),
      ),
    ));
    await t.tap(find.text('Espelhar no TickTask'));
    await t.pump();
    expect(ligado, isTrue);
  });

  test('estado do serviço vira papel e rótulo em português', () {
    expect(situacaoDoServico('active').papel, PapelDeEstado.sucesso);
    expect(situacaoDoServico('active').rotulo, 'rodando');
    expect(situacaoDoServico('inactive').rotulo, 'parado');
    expect(situacaoDoServico('failed').papel, PapelDeEstado.erro);
    expect(situacaoDoServico('…').papel, PapelDeEstado.neutro);
    expect(situacaoDoServico('desconhecido').rotulo, 'desconhecido');
    expect(situacaoDoLogin('enabled').papel, PapelDeEstado.sucesso);
    expect(situacaoDoLogin('não instalado').rotulo, 'não instalado');
    expect(situacaoDoLogin('disabled').rotulo, 'não sobe no login');
    expect(situacaoDoLinger('yes').papel, PapelDeEstado.sucesso);
    expect(situacaoDoLinger('no').rotulo, 'linger: só com login');
  });

  test('situação do espelho separa desligado, conectado, esperando e fora do ar', () {
    const ligado = ConfigDoEspelho(ativo: true, projeto: 'p', tag: 't');
    expect(situacaoDoEspelho(null, const EstadoDoEspelho()).rotulo, 'carregando…');
    expect(situacaoDoEspelho(const ConfigDoEspelho(ativo: false, projeto: '', tag: ''), const EstadoDoEspelho()).rotulo,
        'desligado');
    expect(situacaoDoEspelho(ligado, const EstadoDoEspelho()).rotulo, 'esperando a primeira volta');
    expect(situacaoDoEspelho(ligado, EstadoDoEspelho.deJson({'conectado': true})).papel, PapelDeEstado.sucesso);
    expect(situacaoDoEspelho(ligado, EstadoDoEspelho.deJson({'erro': 'sem rede'})).papel, PapelDeEstado.erro);
  });
}
