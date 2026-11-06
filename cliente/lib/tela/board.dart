import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/areas.dart';
import '../estado/sala.dart';
import '../nucleo/design.dart';
import 'chat.dart';
import 'comum.dart';
import 'tema.dart';

class TelaBoard extends StatefulWidget {
  const TelaBoard({super.key, required this.sala});

  final Sala sala;

  @override
  State<TelaBoard> createState() => _TelaBoardState();
}

class _TelaBoardState extends State<TelaBoard> {
  final _pauta = TextEditingController();
  final _contexto = TextEditingController();
  var _comContexto = false;

  @override
  void dispose() {
    _pauta.dispose();
    _contexto.dispose();
    super.dispose();
  }

  void _convocar() {
    if (!widget.sala.board.convocar(_pauta.text, contexto: _comContexto ? _contexto.text : null)) return;
    _pauta.clear();
    _contexto.clear();
    setState(() => _comContexto = false);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.sala.board, widget.sala.canal]),
      builder: (context, _) => LayoutBuilder(builder: (context, limites) {
        final board = widget.sala.board;
        final margem = ClasseDeJanela.de(limites.maxWidth).margemLateral;
        final podeConvocar = widget.sala.canal.conectado && !board.emCurso;
        return Column(children: [
          Material(
            color: tema.colorScheme.surface,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, margem, Espacos.esp3),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Board', style: tema.textTheme.titleLarge),
                    Text(
                      'deliberação em conselho',
                      style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: board.itens.isEmpty && !board.emCurso
                ? const _SemPauta()
                : ListView(
                    reverse: true,
                    padding: EdgeInsets.symmetric(horizontal: margem, vertical: Espacos.esp3),
                    children: [
                      if (board.emCurso) const _Deliberando(),
                      for (final item in board.itens.reversed) _item(context, item),
                    ].map((w) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: larguraDeLeitura), child: w))).toList(),
                  ),
          ),
          const Divider(height: 1),
          Material(
            color: tema.colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(margem, Espacos.esp3, margem, Espacos.esp3),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (_comContexto)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Espacos.esp2),
                          child: TextField(
                            controller: _contexto,
                            minLines: 2,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'Contexto adicional',
                              helperText: 'Opcional. Entra junto com a pauta.',
                            ),
                          ),
                        ),
                      TextField(
                        controller: _pauta,
                        minLines: 2,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Pauta para o board',
                          helperText: 'Os quatro perfis deliberam em paralelo e você recebe a síntese.',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: Espacos.esp2),
                      Row(children: [
                        IconButton(
                          tooltip: _comContexto ? 'Sem contexto' : 'Adicionar contexto',
                          icon: Icon(_comContexto ? Symbols.notes : Symbols.note_add),
                          onPressed: () => setState(() => _comContexto = !_comContexto),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          icon: const Icon(Symbols.gavel),
                          label: const Text('Convocar'),
                          onPressed: podeConvocar ? _convocar : null,
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _item(BuildContext context, ItemBoard item) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    return switch (item) {
      Pauta(:final texto, :final contexto) => Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(top: Espacos.esp3, left: Espacos.esp7),
            padding: const EdgeInsets.all(Espacos.esp3),
            decoration: BoxDecoration(color: cores.primaryContainer, borderRadius: BorderRadius.circular(Raios.lg)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(texto, style: tema.textTheme.bodyLarge?.copyWith(color: cores.onPrimaryContainer)),
              if (contexto != null)
                Text(contexto, style: tema.textTheme.bodySmall?.copyWith(color: cores.onPrimaryContainer)),
            ]),
          ),
        ),
      StatusBoard(:final texto) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacos.esp1, horizontal: Espacos.esp2),
          child: Text(texto, style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant)),
        ),
      ErroBoard(:final texto) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacos.esp1, horizontal: Espacos.esp2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Symbols.error, size: 16, color: cores.error),
            const SizedBox(width: Espacos.esp2),
            Expanded(child: Text(texto, style: tema.textTheme.bodySmall?.copyWith(color: cores.error))),
          ]),
        ),
      Sintese(:final texto, :final ata) => Card(
          margin: const EdgeInsets.only(top: Espacos.esp3),
          child: Padding(
            padding: const EdgeInsets.all(Espacos.esp4),
            child: SelectionArea(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Symbols.gavel, size: 20, color: cores.primary),
                  const SizedBox(width: Espacos.esp2),
                  Text('Síntese do board', style: tema.textTheme.titleSmall?.copyWith(color: cores.primary)),
                ]),
                const SizedBox(height: Espacos.esp2),
                TextoMarkdown(texto),
                const SizedBox(height: Espacos.esp2),
                InkWell(
                  onTap: () => copiar(context, ata, aviso: 'Caminho da ata copiado'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Espacos.esp1),
                    child: Text('Ata completa: $ata',
                        style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant, fontFamily: familiaMono)),
                  ),
                ),
              ]),
            ),
          ),
        ),
    };
  }
}

class _Deliberando extends StatelessWidget {
  const _Deliberando();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espacos.esp3, horizontal: Espacos.esp2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'Os conselheiros estão respondendo. A síntese chega quando todos terminarem.',
          style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Espacos.esp2),
        const LinearProgressIndicator(),
      ]),
    );
  }
}

class _SemPauta extends StatelessWidget {
  const _SemPauta();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.gavel, color: cor),
          const SizedBox(height: Espacos.esp2),
          Text(
            'Apresente a pauta. Os quatro perfis deliberam em paralelo e você recebe a síntese; '
            'a ata completa fica em board/minutes/.',
            textAlign: TextAlign.center,
            style: tema.textTheme.bodyMedium?.copyWith(color: cor),
          ),
        ]),
      ),
    );
  }
}
