import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/sala.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import 'comum.dart';

class ListaConversas extends StatelessWidget {
  const ListaConversas({super.key, required this.sala});

  final Sala sala;

  Future<void> _excluir(BuildContext context, MetaConversa meta) async {
    final apagar = await confirmar(
      context,
      'Excluir conversa',
      'Excluir "${meta.titulo}"? Somem a transcrição e os anexos desta conversa. '
          'A memória do perfil não é afetada.',
    );
    if (apagar && !sala.conversas.excluir(meta.id) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sem conexão com o servidor.')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([sala.conversas, sala.chat]),
        builder: (context, _) {
          final estado = sala.conversas;
          if (!estado.carregada) return const Center(child: CircularProgressIndicator());
          if (estado.lista.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Nenhuma conversa ainda.')));
          }
          final cores = Theme.of(context).colorScheme;
          return ListView.builder(
            itemCount: estado.lista.length,
            itemBuilder: (context, i) {
              final meta = estado.lista[i];
              final nome = Perfil.porChave(meta.perfil).nome;
              return MenuDeToque(
                itens: () => [(Symbols.delete, 'Excluir', () => _excluir(context, meta))],
                child: ListTile(
                  selected: sala.chat.conversaId == meta.id,
                  selectedTileColor: cores.surfaceContainerHighest,
                  leading: Avatar.doPerfil(meta.perfil),
                  title: Text(meta.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(nome, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
                  trailing: Text(quando(meta.criadaEm), style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
                  onTap: () => sala.abrirConversa(meta.id),
                ),
              );
            },
          );
        },
      );
}

Future<void> abrirNovaConversa(BuildContext context, Sala sala) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _FolhaNova(sala: sala),
    );

class _FolhaNova extends StatefulWidget {
  const _FolhaNova({required this.sala});

  final Sala sala;

  @override
  State<_FolhaNova> createState() => _FolhaNovaState();
}

class _FolhaNovaState extends State<_FolhaNova> {
  String _modelo = modeloPadrao;

  void _escolher(String perfil) {
    Navigator.pop(context);
    widget.sala.novaConversa(perfil, modelo: _modelo);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    Widget opcao(Widget avatar, String nome, String descricao, VoidCallback aoTocar) => ListTile(
          leading: avatar,
          title: Text(nome),
          subtitle: Text(descricao, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
          onTap: aoTocar,
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Text('Nova conversa', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  DropdownButton<String>(
                    value: _modelo,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final m in modelos.entries) DropdownMenuItem(value: m.key, child: Text(m.value)),
                    ],
                    onChanged: (v) => setState(() => _modelo = v ?? modeloPadrao),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text('CONSELHO', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11, letterSpacing: 1)),
            ),
            for (final p in Perfil.todos.where((p) => p.conversa && !p.executor))
              opcao(Avatar.doPerfil(p.chave), p.nome, p.papel, () => _escolher(p.chave)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text('EXECUÇÃO', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11, letterSpacing: 1)),
            ),
            for (final p in Perfil.todos.where((p) => p.conversa && p.executor))
              opcao(Avatar.doPerfil(p.chave), p.nome, p.papel, () => _escolher(p.chave)),
          ],
        ),
      ),
    );
  }
}
