import 'package:material_ui/material_ui.dart';

import '../nucleo/atalhos_de_teclado.dart';
import '../nucleo/design.dart';

const _larguraDaFolha = 560.0;
const _larguraDasTeclas = 200.0;

Future<void> mostrarAtalhosDeTeclado(BuildContext context) =>
    showDialog<void>(context: context, builder: (context) => const FolhaDeAtalhos());

class FolhaDeAtalhos extends StatelessWidget {
  const FolhaDeAtalhos({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return AlertDialog(
      title: const Text('Atalhos de teclado'),
      contentPadding: const EdgeInsets.fromLTRB(Espacos.esp5, Espacos.esp4, Espacos.esp5, 0),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _larguraDaFolha),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final grupo in atalhosDeTeclado) ...[
                Padding(
                  padding: const EdgeInsets.only(top: Espacos.esp3, bottom: Espacos.esp2),
                  child: Semantics(header: true, child: Text(grupo.titulo, style: tema.textTheme.titleSmall)),
                ),
                for (final atalho in grupo.atalhos) _Linha(atalho),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.atalho);

  final AtalhoDeTeclado atalho;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ou = tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant);
    final leitura = atalho.alternativas.map(textoDaCombinacao).join(' ou ');
    return MergeSemantics(
      child: Semantics(
        label: '$leitura: ${atalho.acao}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacos.esp1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: _larguraDasTeclas,
                child: Wrap(
                  spacing: Espacos.esp1,
                  runSpacing: Espacos.esp1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final (i, combinacao) in atalho.alternativas.indexed) ...[
                      if (i > 0) Text('ou', style: ou),
                      for (final (j, tecla) in combinacao.indexed) ...[if (j > 0) Text('+', style: ou), _Tecla(tecla)],
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Espacos.esp3),
              Expanded(child: Text(atalho.acao, style: tema.textTheme.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tecla extends StatelessWidget {
  const _Tecla(this.rotulo);

  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cores.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Raios.xs),
        border: Border.all(color: cores.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Espacos.esp2, vertical: Espacos.esp1 / 2),
        child: Text(rotulo, style: tema.textTheme.labelMedium?.copyWith(color: cores.onSurface)),
      ),
    );
  }
}
