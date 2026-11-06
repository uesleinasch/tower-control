import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../conexao/canal.dart';
import '../nucleo/design.dart';
import '../nucleo/modelos.dart';
import 'tema.dart';

const _proporcaoDaInicial = 0.42;
const _tamanhoDoPonto = 10.0;

bool get ehDesktop => switch (defaultTargetPlatform) {
      TargetPlatform.linux || TargetPlatform.windows || TargetPlatform.macOS => true,
      _ => false,
    };

class RolagemDeDesktop extends StatefulWidget {
  const RolagemDeDesktop({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController? controle) builder;

  @override
  State<RolagemDeDesktop> createState() => _RolagemDeDesktopState();
}

class _RolagemDeDesktopState extends State<RolagemDeDesktop> {
  ScrollController? _controle;

  @override
  void dispose() {
    _controle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ehDesktop) return widget.builder(context, null);
    final controle = _controle ??= ScrollController();
    return Scrollbar(
      controller: controle,
      thumbVisibility: true,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: widget.builder(context, controle),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.cor, required this.inicial, this.tamanho = 36});

  factory Avatar.doPerfil(String perfil, {double tamanho = 36}) {
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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            inicial,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: corDoTextoSobre(cor),
                  fontSize: tamanho * _proporcaoDaInicial,
                  height: 1,
                ),
          ),
        ),
      );
}

class PontoConexao extends StatelessWidget {
  const PontoConexao(this.estado, {super.key});

  final EstadoConexao estado;

  @override
  Widget build(BuildContext context) {
    final semanticas = CoresSemanticas.de(context);
    final (cor, rotulo) = switch (estado) {
      EstadoConexao.conectado => (semanticas.sucesso.cor, 'Conectado'),
      EstadoConexao.reconectando => (semanticas.aviso.cor, 'Reconectando…'),
      EstadoConexao.semServidor => (Theme.of(context).colorScheme.error, 'Sem servidor'),
    };
    return Semantics(
      label: 'Conexão com o servidor: $rotulo',
      child: Tooltip(
        message: rotulo,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: _tamanhoDoPonto,
          child: DecoratedBox(decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
        ),
      ),
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
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
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

class CartaoDePedido extends StatelessWidget {
  const CartaoDePedido({
    super.key,
    required this.icone,
    required this.faixa,
    this.quando,
    this.conteudo,
    required this.acoes,
  });

  final IconData icone;
  final String faixa;
  final String? quando;
  final Widget? conteudo;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final estilo = tema.textTheme.labelMedium?.copyWith(color: cores.onTertiaryContainer);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: cores.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacos.esp4, vertical: Espacos.esp2),
              child: Row(children: [
                Icon(icone, size: 16, color: cores.onTertiaryContainer),
                const SizedBox(width: Espacos.esp2),
                Expanded(child: Text(faixa, style: estilo)),
                if (quando case final q?)
                  Text(q, style: estilo?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Espacos.esp4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (conteudo case final c?) ...[c, const SizedBox(height: Espacos.esp3)],
                Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: acoes),
              ],
            ),
          ),
        ],
      ),
    );
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
            child: Row(children: [
              Icon(lista[i].$1, size: 20),
              const SizedBox(width: Espacos.esp3),
              Text(lista[i].$2),
            ]),
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
