import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/sala.dart';
import '../nucleo/design.dart';
import 'board.dart';
import 'chat.dart';
import 'comum.dart';
import 'conversas.dart';
import 'decisoes.dart';
import 'equipes.dart';
import 'painel.dart';
import 'tarefas.dart';

class Raiz extends StatefulWidget {
  const Raiz({super.key, required this.sala, this.configuracao, this.bloqueio});

  final Sala sala;
  final WidgetBuilder? configuracao;
  final Widget? Function(BuildContext context)? bloqueio;

  @override
  State<Raiz> createState() => _RaizState();
}

class _RaizState extends State<Raiz> {
  late final StreamSubscription<String> _avisos;
  final _mensageiro = GlobalKey<ScaffoldMessengerState>();

  Sala get sala => widget.sala;

  @override
  void initState() {
    super.initState();
    _avisos = sala.avisos.listen((texto) => _mensageiro.currentState?.showSnackBar(SnackBar(content: Text(texto))));
    sala.pedidosDeNova.addListener(_abrirNova);
  }

  void _abrirNova() {
    final contexto = _mensageiro.currentContext;
    if (contexto != null && mounted) abrirNovaConversa(contexto, sala);
  }

  @override
  void dispose() {
    sala.pedidosDeNova.removeListener(_abrirNova);
    _avisos.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
        key: _mensageiro,
        child: ListenableBuilder(
          listenable: Listenable.merge([sala, sala.canal]),
          builder: (context, _) {
            final bloqueio = widget.bloqueio?.call(context);
            if (bloqueio != null) return Scaffold(body: bloqueio);
            return LayoutBuilder(
              builder: (context, limites) {
                final classe = ClasseDeJanela.de(limites.maxWidth);
                WidgetsBinding.instance.addPostFrameCallback((_) => sala.definirLayoutDuplo(classe.comDoisPaineis));
                return CallbackShortcuts(
                  bindings: {
                    for (final (i, destino) in _destinos.indexed)
                      SingleActivator(_teclasDosDestinos[i], control: true): () => sala.ir(destino.tela),
                  },
                  child: Focus(
                    autofocus: true,
                    child: classe == ClasseDeJanela.compact ? _compacto(context) : _comTrilho(context, classe),
                  ),
                );
              },
            );
          },
        ),
      );

  int? _indice(Tela tela) {
    if (tela == Tela.chat) return 0;
    final i = _destinos.indexWhere((d) => d.tela == tela);
    return i < 0 ? null : i;
  }

  Widget _principal(BuildContext context, {required bool compacto}) => switch (sala.tela) {
        Tela.board => TelaBoard(sala: sala),
        Tela.decisoes => TelaDecisoes(sala: sala),
        Tela.painel => TelaPainel(sala: sala),
        Tela.tarefas => TelaTarefas(sala: sala),
        Tela.equipes => TelaEquipes(sala: sala),
        Tela.configuracao when widget.configuracao != null => widget.configuracao!(context),
        Tela.conversas when compacto => ListaConversas(sala: sala),
        _ => TelaChat(sala: sala, compacto: compacto),
      };

  Widget _voltaParaConversas(Widget filho) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) sala.ir(Tela.conversas);
        },
        child: filho,
      );

  Widget _comTrilho(BuildContext context, ClasseDeJanela classe) {
    final duplo = classe.comDoisPaineis;
    final emConversa = sala.tela == Tela.conversas || sala.tela == Tela.chat;
    final Widget conteudo;
    if (duplo) {
      conteudo = Row(children: [
        if (emConversa) ...[
          SizedBox(width: 320, child: _PainelDeConversas(sala: sala)),
          const VerticalDivider(width: 1),
        ],
        Expanded(child: _principal(context, compacto: false)),
      ]);
    } else {
      final principal = _principal(context, compacto: true);
      conteudo = sala.tela == Tela.chat || sala.tela == Tela.configuracao ? _voltaParaConversas(principal) : principal;
    }
    return Scaffold(
      body: Row(children: [
        _Trilho(
          sala: sala,
          selecionado: _indice(sala.tela),
          estendido: classe.index >= ClasseDeJanela.large.index,
          configuracao: widget.configuracao != null,
        ),
        const VerticalDivider(width: 1),
        Expanded(child: conteudo),
      ]),
    );
  }

  Widget _compacto(BuildContext context) {
    if (sala.tela == Tela.chat || sala.tela == Tela.configuracao) {
      return _voltaParaConversas(Scaffold(body: _principal(context, compacto: true)));
    }
    final indice = _indice(sala.tela);
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Symbols.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('Control Tower'),
        actions: [
          if (widget.configuracao != null)
            IconButton(
              icon: const Icon(Symbols.settings),
              tooltip: 'Configuração',
              onPressed: () => sala.ir(Tela.configuracao),
            ),
          Padding(padding: const EdgeInsets.only(right: Espacos.esp4), child: PontoConexao(sala.canal.estado)),
        ],
      ),
      drawer: _Gaveta(sala: sala, selecionado: indice),
      body: _principal(context, compacto: true),
      floatingActionButton: sala.tela == Tela.conversas
          ? FloatingActionButton.extended(
              onPressed: () => abrirNovaConversa(context, sala),
              icon: const Icon(Symbols.add),
              label: const Text('Nova'),
            )
          : null,
      bottomNavigationBar: _Barra(sala: sala, selecionado: indice != null && indice < _naBarra ? indice : null),
    );
  }
}

class _Destino {
  const _Destino(this.tela, this.icone, this.rotulo);

  final Tela tela;
  final IconData icone;
  final String rotulo;
}

const _destinos = [
  _Destino(Tela.conversas, Symbols.forum, 'Conversas'),
  _Destino(Tela.painel, Symbols.dashboard, 'Painel'),
  _Destino(Tela.tarefas, Symbols.task_alt, 'Tarefas'),
  _Destino(Tela.equipes, Symbols.account_tree, 'Equipes'),
  _Destino(Tela.board, Symbols.gavel, 'Board'),
  _Destino(Tela.decisoes, Symbols.fact_check, 'Decisões'),
];

const _naBarra = 3;

const _teclasDosDestinos = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
];

class _Barra extends StatelessWidget {
  const _Barra({required this.sala, required this.selecionado});

  final Sala sala;
  final int? selecionado;

  @override
  Widget build(BuildContext context) {
    final semSelecao = selecionado == null;
    final barra = NavigationBar(
      selectedIndex: selecionado ?? 0,
      onDestinationSelected: (i) => sala.ir(_destinos[i].tela),
      destinations: [
        for (final d in _destinos.take(_naBarra))
          NavigationDestination(
            icon: Icon(d.icone),
            selectedIcon: Icon(d.icone, fill: semSelecao ? 0 : 1),
            label: d.rotulo,
          ),
      ],
    );
    if (!semSelecao) return barra;
    final tema = Theme.of(context);
    final neutro = tema.colorScheme.onSurfaceVariant;
    return NavigationBarTheme(
      data: NavigationBarTheme.of(context).copyWith(
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: neutro)),
        labelTextStyle: WidgetStatePropertyAll(tema.textTheme.labelMedium?.copyWith(color: neutro)),
      ),
      child: barra,
    );
  }
}

class _Gaveta extends StatelessWidget {
  const _Gaveta({required this.sala, required this.selecionado});

  final Sala sala;
  final int? selecionado;

  @override
  Widget build(BuildContext context) {
    final naGaveta = _destinos.skip(_naBarra).toList();
    return NavigationDrawer(
      selectedIndex: selecionado != null && selecionado! >= _naBarra ? selecionado! - _naBarra : null,
      onDestinationSelected: (i) {
        Scaffold.of(context).closeDrawer();
        sala.ir(naGaveta[i].tela);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Espacos.esp6, Espacos.esp4, Espacos.esp4, Espacos.esp3),
          child: Text('Control Tower', style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final d in naGaveta)
          NavigationDrawerDestination(
            icon: Icon(d.icone),
            selectedIcon: Icon(d.icone, fill: 1),
            label: Text(d.rotulo),
          ),
      ],
    );
  }
}

class _Trilho extends StatelessWidget {
  const _Trilho({required this.sala, required this.selecionado, required this.estendido, required this.configuracao});

  final Sala sala;
  final int? selecionado;
  final bool estendido;
  final bool configuracao;

  @override
  Widget build(BuildContext context) => NavigationRail(
        selectedIndex: selecionado,
        extended: estendido,
        labelType: estendido ? NavigationRailLabelType.none : NavigationRailLabelType.all,
        onDestinationSelected: (i) => sala.ir(_destinos[i].tela),
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacos.esp3),
          child: Tooltip(message: 'Conexão com o servidor', child: PontoConexao(sala.canal.estado)),
        ),
        trailing: configuracao
            ? Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Espacos.esp4),
                    child: IconButton(
                      icon: Icon(Symbols.settings, fill: sala.tela == Tela.configuracao ? 1 : 0),
                      isSelected: sala.tela == Tela.configuracao,
                      tooltip: 'Configuração',
                      onPressed: () => sala.ir(Tela.configuracao),
                    ),
                  ),
                ),
              )
            : null,
        destinations: [
          for (final d in _destinos)
            NavigationRailDestination(
              icon: Icon(d.icone),
              selectedIcon: Icon(d.icone, fill: 1),
              label: Text(d.rotulo),
            ),
        ],
      );
}

class _PainelDeConversas extends StatelessWidget {
  const _PainelDeConversas({required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Espacos.esp4, Espacos.esp4, Espacos.esp4, Espacos.esp3),
            child: Text('Conversas', style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Espacos.esp3, 0, Espacos.esp3, Espacos.esp2),
            child: FilledButton.icon(
              onPressed: () => abrirNovaConversa(context, sala),
              icon: const Icon(Symbols.add),
              label: const Text('Nova conversa'),
            ),
          ),
          Expanded(child: ListaConversas(sala: sala)),
        ]),
      );
}
