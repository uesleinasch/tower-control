import 'package:control_tower/tela/configuracao.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bloco da configuração pinta os interruptores sobre o próprio Material', (t) async {
    var ligado = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlocoDeConfiguracao(titulo: 'Espelho no TickTask', icone: Icons.sync_alt, filhos: [
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
}
