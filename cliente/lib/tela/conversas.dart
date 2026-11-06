import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/sala.dart';
import '../nucleo/design.dart';
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
          if (estado.lista.isEmpty) return _ListaVazia(sala: sala);
          final cores = Theme.of(context).colorScheme;
          final texto = Theme.of(context).textTheme;
          final secundario = texto.bodySmall?.copyWith(color: cores.onSurfaceVariant);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: Espacos.esp2, vertical: Espacos.esp1),
            itemCount: estado.lista.length,
            itemBuilder: (context, i) {
              final meta = estado.lista[i];
              final nome = Perfil.porChave(meta.perfil).nome;
              return MenuDeToque(
                itens: () => [(Symbols.delete, 'Excluir conversa', () => _excluir(context, meta))],
                child: ListTile(
                  selected: sala.chat.conversaId == meta.id,
                  selectedTileColor: cores.secondaryContainer,
                  selectedColor: cores.onSecondaryContainer,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Raios.md)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: Espacos.esp3),
                  titleTextStyle: texto.titleSmall,
                  subtitleTextStyle: secundario,
                  leadingAndTrailingTextStyle: secundario?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  leading: Avatar.doPerfil(meta.perfil),
                  title: Text(meta.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(quando(meta.criadaEm)),
                  onTap: () => sala.abrirConversa(meta.id),
                ),
              );
            },
          );
        },
      );
}

class _ListaVazia extends StatelessWidget {
  const _ListaVazia({required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Espacos.esp5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.forum, size: Espacos.esp7, color: cores.onSurfaceVariant),
          const SizedBox(height: Espacos.esp4),
          Text('Nenhuma conversa ainda.', textAlign: TextAlign.center, style: texto.titleMedium),
          const SizedBox(height: Espacos.esp2),
          Text(
            'Converse com uma persona do conselho ou peça um comando ao executor.',
            textAlign: TextAlign.center,
            style: texto.bodyMedium?.copyWith(color: cores.onSurfaceVariant),
          ),
          const SizedBox(height: Espacos.esp5),
          FilledButton.tonalIcon(
            onPressed: () => abrirNovaConversa(context, sala),
            icon: const Icon(Symbols.add),
            label: const Text('Começar conversa'),
          ),
        ]),
      ),
    );
  }
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
    final texto = Theme.of(context).textTheme;
    Widget opcao(Widget avatar, String nome, String descricao, VoidCallback aoTocar) => ListTile(
          leading: avatar,
          title: Text(nome),
          subtitleTextStyle: texto.bodySmall?.copyWith(color: cores.onSurfaceVariant),
          subtitle: Text(descricao),
          onTap: aoTocar,
        );
    Widget grupo(String nome, {required double acima}) => Padding(
          padding: EdgeInsets.fromLTRB(Espacos.esp4, acima, Espacos.esp4, Espacos.esp1),
          child: Text(nome, style: texto.labelMedium?.copyWith(color: cores.onSurfaceVariant)),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Espacos.esp3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacos.esp4, 0, Espacos.esp4, Espacos.esp2),
              child: Row(
                children: [
                  Text('Nova conversa', style: texto.titleMedium),
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
            grupo('CONSELHO', acima: Espacos.esp2),
            for (final p in Perfil.todos.where((p) => p.conversa && !p.executor))
              opcao(Avatar.doPerfil(p.chave), p.nome, p.papel, () => _escolher(p.chave)),
            grupo('EXECUÇÃO', acima: Espacos.esp3),
            for (final p in Perfil.todos.where((p) => p.conversa && p.executor))
              opcao(Avatar.doPerfil(p.chave), p.nome, p.papel, () => _escolher(p.chave)),
          ],
        ),
      ),
    );
  }
}
