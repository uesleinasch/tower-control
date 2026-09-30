import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../conexao/canal.dart';
import '../nucleo/modelos.dart';

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.cor, required this.inicial, this.tamanho = 36});

  factory Avatar.doPerfil(String perfil, {String? foco, double tamanho = 36}) {
    if (foco == 'ticktask') return Avatar(cor: const Color(Perfil.corTicktask), inicial: 'T', tamanho: tamanho);
    final p = Perfil.porChave(perfil);
    return Avatar(cor: Color(p.cor), inicial: p.inicial, tamanho: tamanho);
  }

  final Color cor;
  final String inicial;
  final double tamanho;

  @override
  Widget build(BuildContext context) => Container(
        width: tamanho,
        height: tamanho,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
        child: Text(
          inicial,
          style: TextStyle(color: const Color(0xFF10131A), fontWeight: FontWeight.w700, fontSize: tamanho * 0.42),
        ),
      );
}

class PontoConexao extends StatelessWidget {
  const PontoConexao(this.estado, {super.key});

  final EstadoConexao estado;

  @override
  Widget build(BuildContext context) {
    final (cor, rotulo) = switch (estado) {
      EstadoConexao.conectado => (const Color(0xFF4FAE7C), 'Conectado'),
      EstadoConexao.reconectando => (const Color(0xFFE0A458), 'Reconectando…'),
      EstadoConexao.semServidor => (const Color(0xFFE05A5A), 'Sem servidor'),
    };
    return Tooltip(
      message: rotulo,
      child: Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
    );
  }
}

Future<bool> confirmar(BuildContext context, String titulo, String texto, {String acao = 'Excluir'}) async {
  final sim = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: Text(acao),
        ),
      ],
    ),
  );
  return sim ?? false;
}

Future<void> copiar(BuildContext context, String texto, {String aviso = 'Copiado'}) async {
  await Clipboard.setData(ClipboardData(text: texto));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso), duration: const Duration(seconds: 2)));
  }
}

class MenuDeToque extends StatelessWidget {
  const MenuDeToque({super.key, required this.child, required this.itens});

  final Widget child;
  final List<(IconData, String, VoidCallback)> Function() itens;

  Future<void> _abrir(BuildContext context, Offset posicao) async {
    final lista = itens();
    if (lista.isEmpty) return;
    final tela = MediaQuery.sizeOf(context);
    final escolhido = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(posicao.dx, posicao.dy, tela.width - posicao.dx, tela.height - posicao.dy),
      items: [
        for (var i = 0; i < lista.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(children: [Icon(lista[i].$1, size: 18), const SizedBox(width: 12), Text(lista[i].$2)]),
          ),
      ],
    );
    if (escolhido != null) lista[escolhido].$3();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => _abrir(context, d.globalPosition),
        onSecondaryTapDown: (d) => _abrir(context, d.globalPosition),
        child: child,
      );
}
