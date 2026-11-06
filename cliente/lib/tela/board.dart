import 'package:material_ui/material_ui.dart';

import '../estado/areas.dart';
import '../estado/sala.dart';
import '../nucleo/modelos.dart';
import 'chat.dart';
import 'comum.dart';

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
    final cores = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.sala.board, widget.sala.canal]),
      builder: (context, _) {
        final board = widget.sala.board;
        final podeConvocar = widget.sala.canal.conectado && !board.emCurso;
        return Column(children: [
          Material(
            color: cores.surface,
            child: SafeArea(
              bottom: false,
              child: ListTile(
                leading: const Avatar(cor: Color(Perfil.corBoard), inicial: 'B', tamanho: 32),
                title: const Text('Board'),
                subtitle: Text('deliberação em conselho', style: TextStyle(color: cores.onSurfaceVariant)),
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              reverse: true,
              padding: const EdgeInsets.all(12),
              children: [
                if (board.emCurso) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
                for (final item in board.itens.reversed) _item(context, item),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Apresente a pauta. Os quatro perfis deliberam em paralelo e você recebe a síntese; '
                    'a ata completa fica em board/minutes/.',
                    style: TextStyle(color: cores.onSurfaceVariant, fontSize: 13),
                  ),
                ),
              ].map((w) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: w))).toList(),
            ),
          ),
          Material(
            color: cores.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_comContexto)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: TextField(
                        controller: _contexto,
                        minLines: 2,
                        maxLines: 6,
                        decoration: const InputDecoration(hintText: 'Contexto adicional (opcional)'),
                      ),
                    ),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    IconButton(
                      tooltip: _comContexto ? 'Sem contexto' : 'Adicionar contexto',
                      icon: Icon(_comContexto ? Icons.notes : Icons.note_add_outlined),
                      onPressed: () => setState(() => _comContexto = !_comContexto),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _pauta,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(hintText: 'Pauta para o board…'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      tooltip: 'Convocar',
                      icon: const Icon(Icons.gavel),
                      onPressed: podeConvocar ? _convocar : null,
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _item(BuildContext context, ItemBoard item) {
    final cores = Theme.of(context).colorScheme;
    return switch (item) {
      Pauta(:final texto, :final contexto) => Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(top: 10, left: 48),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: cores.primary.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(texto),
              if (contexto != null)
                Text(contexto, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
        ),
      StatusBoard(:final texto) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Text(texto, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 13)),
        ),
      ErroBoard(:final texto) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Text(texto, style: TextStyle(color: cores.error, fontSize: 13)),
        ),
      Sintese(:final texto, :final ata) => Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cores.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Síntese do board',
                style: TextStyle(color: Color(Perfil.corBoard), fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextoMarkdown(texto),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => copiar(context, ata, aviso: 'Caminho da ata copiado'),
              child: Text('Ata completa: $ata', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
            ),
          ]),
        ),
    };
  }
}
