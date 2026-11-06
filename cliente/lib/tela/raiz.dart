import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../estado/equipes.dart';
import '../estado/sala.dart';
import '../nucleo/design.dart';
import 'atalhos.dart';
import 'board.dart';
import 'chat.dart';
import 'comum.dart';
import 'conversas.dart';
import 'decisoes.dart';
import 'equipes.dart';
import 'paineis.dart';
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
  final _focoDaBusca = FocusNode(debugLabel: 'busca da tela');
  bool? _trilhoEstendido;

  Sala get sala => widget.sala;

  @override
  void initState() {
    super.initState();
    _avisos = sala.avisos.listen((texto) => _mensageiro.currentState?.showSnackBar(SnackBar(content: Text(texto))));
    sala.pedidosDeNova.addListener(_abrirNova);
    SharedPreferences.getInstance().then((prefs) {
      final salvo = prefs.getBool(chaveTrilhoEstendido);
      if (mounted && salvo != null) setState(() => _trilhoEstendido = salvo);
    });
  }

  void _alternarTrilho(bool estendido) {
    setState(() => _trilhoEstendido = !estendido);
    SharedPreferences.getInstance().then((prefs) => prefs.setBool(chaveTrilhoEstendido, !estendido));
  }

  void _abrirNova() {
    final contexto = _mensageiro.currentContext;
    if (contexto != null && mounted) abrirNovaConversa(contexto, sala);
  }

  void _mostrarAtalhos() {
    final contexto = _mensageiro.currentContext;
    if (contexto != null && mounted) mostrarAtalhosDeTeclado(contexto);
  }

  void _buscar() {
    if (sala.tela != Tela.decisoes) return;
    if (_focoDaBusca.context?.mounted ?? false) {
      _focoDaBusca.requestFocus();
      return;
    }
    sala.decisoes.fecharDetalhe();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focoDaBusca.requestFocus());
  }

  bool _fecharPainel() {
    switch (sala.tela) {
      case Tela.tarefas when sala.tarefas.aberta != null:
        sala.tarefas.fecharDetalhe();
      case Tela.decisoes when sala.decisoes.aberta != null:
        sala.decisoes.fecharDetalhe();
      case Tela.equipes when sala.editorDeWorkflow.aberto:
        if (sala.editorDeWorkflow.selecionada == null) return false;
        sala.editorDeWorkflow.selecionar(null);
      case Tela.equipes when sala.equipes.vendoWorkflows && sala.workflows.caixa != null:
        sala.workflows.selecionarCaixa(null);
      case Tela.equipes when sala.equipes.aba == AbaDaEquipe.organograma && sala.equipes.selecionada != null:
        sala.equipes.selecionar(null);
      default:
        return false;
    }
    return true;
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent evento) {
    if (evento is! KeyDownEvent || evento.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    final teclado = HardwareKeyboard.instance;
    if (_digitando() || teclado.isControlPressed || teclado.isShiftPressed || teclado.isAltPressed) {
      return KeyEventResult.ignored;
    }
    return _fecharPainel() ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  void dispose() {
    sala.pedidosDeNova.removeListener(_abrirNova);
    _avisos.cancel();
    _focoDaBusca.dispose();
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
                    const SingleActivator(LogicalKeyboardKey.keyN, control: true): _abrirNova,
                    const SingleActivator(LogicalKeyboardKey.keyK, control: true): _buscar,
                    const SingleActivator(LogicalKeyboardKey.slash, control: true): _mostrarAtalhos,
                    const SingleActivator(LogicalKeyboardKey.numpadDivide, control: true): _mostrarAtalhos,
                  },
                  child: FocusScope(
                    autofocus: true,
                    onKeyEvent: _tecla,
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
        Tela.decisoes => TelaDecisoes(sala: sala, focoDaBusca: _focoDaBusca),
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
      final principal = _principal(context, compacto: false);
      conteudo = emConversa
          ? LadoALado(
              painel: 'conversas',
              rotulo: 'Largura da lista de conversas',
              maximo: 480,
              lateral: _PainelDeConversas(sala: sala),
              principal: principal,
            )
          : principal;
    } else {
      final principal = _principal(context, compacto: true);
      conteudo = sala.tela == Tela.chat || sala.tela == Tela.configuracao ? _voltaParaConversas(principal) : principal;
    }
    return Scaffold(
      body: Row(children: [
        FocusTraversalGroup(
          child: _Trilho(
            sala: sala,
            selecionado: _indice(sala.tela),
            estendido: _trilhoEstendido ?? classe.index >= ClasseDeJanela.large.index,
            configuracao: widget.configuracao != null,
            atalhos: ehDesktop ? _mostrarAtalhos : null,
            alternar: _alternarTrilho,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: FocusTraversalGroup(child: conteudo)),
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

const chaveTrilhoEstendido = 'trilhoEstendido';

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
  const _Trilho({
    required this.sala,
    required this.selecionado,
    required this.estendido,
    required this.configuracao,
    required this.atalhos,
    required this.alternar,
  });

  final Sala sala;
  final int? selecionado;
  final bool estendido;
  final bool configuracao;
  final VoidCallback? atalhos;
  final void Function(bool estendido) alternar;

  @override
  Widget build(BuildContext context) => NavigationRail(
        selectedIndex: selecionado,
        extended: estendido,
        labelType: estendido ? NavigationRailLabelType.none : NavigationRailLabelType.all,
        onDestinationSelected: (i) => sala.ir(_destinos[i].tela),
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacos.esp2),
          child: Flex(
            direction: estendido ? Axis.horizontal : Axis.vertical,
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(estendido ? Symbols.menu_open : Symbols.menu),
                tooltip: estendido ? 'Recolher menu' : 'Expandir menu',
                onPressed: () => alternar(estendido),
              ),
              if (estendido) ...[
                const SizedBox(width: Espacos.esp2),
                Text('Control Tower', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: Espacos.esp3),
              ] else
                const SizedBox(height: Espacos.esp1),
              Tooltip(message: 'Conexão com o servidor', child: PontoConexao(sala.canal.estado)),
            ],
          ),
        ),
        trailing: configuracao || atalhos != null
            ? Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Espacos.esp4),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (atalhos case final abrir?) _BotaoDeAtalhos(estendido: estendido, aoAbrir: abrir),
                      if (configuracao) _BotaoDeConfiguracao(sala: sala, estendido: estendido),
                    ]),
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

class _BotaoDeAtalhos extends StatelessWidget {
  const _BotaoDeAtalhos({required this.estendido, required this.aoAbrir});

  final bool estendido;
  final VoidCallback aoAbrir;

  @override
  Widget build(BuildContext context) {
    if (!estendido) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Espacos.esp2),
        child: IconButton(
          tooltip: 'Atalhos de teclado (Ctrl+/)',
          icon: const Icon(Symbols.keyboard),
          onPressed: aoAbrir,
        ),
      );
    }
    final tema = Theme.of(context);
    final cor = tema.colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 224,
      child: Tooltip(
        message: 'Ctrl+/',
        child: TextButton.icon(
          onPressed: aoAbrir,
          icon: Icon(Symbols.keyboard, color: cor),
          label: Text('Atalhos de teclado', style: tema.textTheme.labelLarge?.copyWith(color: cor)),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: Espacos.esp4, vertical: Espacos.esp4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Raios.xl)),
          ),
        ),
      ),
    );
  }
}

bool _digitando() {
  final contexto = FocusManager.instance.primaryFocus?.context;
  if (contexto == null) return false;
  return contexto.widget is EditableText || contexto.findAncestorWidgetOfExactType<EditableText>() != null;
}

class _BotaoDeConfiguracao extends StatelessWidget {
  const _BotaoDeConfiguracao({required this.sala, required this.estendido});

  final Sala sala;
  final bool estendido;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final selecionada = sala.tela == Tela.configuracao;
    final cor = selecionada ? cores.onSecondaryContainer : cores.onSurfaceVariant;
    final icone = Icon(Symbols.settings, fill: selecionada ? 1 : 0, color: cor);
    final rotulo = Text('Configuração', style: tema.textTheme.labelLarge?.copyWith(color: cor));
    void abrir() => sala.ir(Tela.configuracao);
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Raios.xl));
    if (estendido) {
      return SizedBox(
        width: 224,
        child: TextButton.icon(
          onPressed: abrir,
          icon: icone,
          label: rotulo,
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: Espacos.esp4, vertical: Espacos.esp4),
            backgroundColor: selecionada ? cores.secondaryContainer : null,
            shape: forma,
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      selected: selecionada,
      child: InkWell(
        onTap: abrir,
        customBorder: forma,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espacos.esp1, vertical: Espacos.esp2),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Espacos.esp4, vertical: Espacos.esp1),
              decoration: BoxDecoration(
                color: selecionada ? cores.secondaryContainer : null,
                borderRadius: BorderRadius.circular(Raios.lg),
              ),
              child: icone,
            ),
            const SizedBox(height: Espacos.esp1),
            SizedBox(
              width: 72,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Configuração', style: tema.textTheme.labelMedium?.copyWith(color: cor)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
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
