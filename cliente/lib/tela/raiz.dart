import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../estado/sala.dart';
import '../nucleo/modelos.dart';
import 'board.dart';
import 'chat.dart';
import 'comum.dart';
import 'conversas.dart';
import 'decisoes.dart';
import 'equipes.dart';
import 'painel.dart';
import 'tarefas.dart';

const larguraDupla = 840.0;

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
                final duplo = limites.maxWidth >= larguraDupla;
                WidgetsBinding.instance.addPostFrameCallback((_) => sala.definirLayoutDuplo(duplo));
                return duplo ? _duplo(context) : _compacto(context);
              },
            );
          },
        ),
      );

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

  Widget _duplo(BuildContext context) => Scaffold(
        body: Row(children: [
          SizedBox(width: 300, child: _Lateral(sala: sala, comConfiguracao: widget.configuracao != null)),
          const VerticalDivider(width: 1),
          Expanded(child: _principal(context, compacto: false)),
        ]),
      );

  Widget _compacto(BuildContext context) {
    if (sala.tela == Tela.chat || sala.tela == Tela.configuracao) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) sala.ir(Tela.conversas);
        },
        child: Scaffold(body: _principal(context, compacto: true)),
      );
    }
    final abas = [Tela.conversas, Tela.board, Tela.decisoes, Tela.painel, Tela.tarefas, Tela.equipes];
    return Scaffold(
      appBar: sala.tela == Tela.conversas
          ? AppBar(
              title: const Text('Control Tower'),
              actions: [
                if (widget.configuracao != null)
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Configuração',
                    onPressed: () => sala.ir(Tela.configuracao),
                  ),
                Padding(padding: const EdgeInsets.only(right: 16), child: PontoConexao(sala.canal.estado)),
              ],
            )
          : null,
      body: _principal(context, compacto: true),
      floatingActionButton: sala.tela == Tela.conversas
          ? FloatingActionButton.extended(
              onPressed: () => abrirNovaConversa(context, sala),
              icon: const Icon(Icons.add),
              label: const Text('Nova'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: abas.indexOf(sala.tela).clamp(0, abas.length - 1),
        onDestinationSelected: (i) => sala.ir(abas[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: 'Conversas'),
          NavigationDestination(icon: Icon(Icons.gavel_outlined), selectedIcon: Icon(Icons.gavel), label: 'Board'),
          NavigationDestination(
              icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Decisões'),
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Painel'),
          NavigationDestination(icon: Icon(Icons.task_alt_outlined), selectedIcon: Icon(Icons.task_alt), label: 'Tarefas'),
          NavigationDestination(icon: Icon(Icons.account_tree_outlined), selectedIcon: Icon(Icons.account_tree), label: 'Equipes'),
        ],
      ),
    );
  }
}

class _Lateral extends StatelessWidget {
  const _Lateral({required this.sala, required this.comConfiguracao});

  final Sala sala;
  final bool comConfiguracao;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    Widget destino(Tela tela, Widget avatar, String rotulo) => ListTile(
          dense: true,
          selected: sala.tela == tela,
          selectedTileColor: cores.surfaceContainerHighest,
          leading: avatar,
          title: Text(rotulo),
          onTap: () => sala.ir(tela),
        );
    return Material(
      color: cores.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 4),
          child: Row(children: [
            Text('Control Tower', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            PontoConexao(sala.canal.estado),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
          child: Text('sala de decisões', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FilledButton.icon(
            onPressed: () => abrirNovaConversa(context, sala),
            icon: const Icon(Icons.add),
            label: const Text('Nova conversa'),
          ),
        ),
        const SizedBox(height: 8),
        destino(Tela.board, const Avatar(cor: Color(Perfil.corBoard), inicial: 'B', tamanho: 28), 'Convocar board'),
        destino(Tela.decisoes, const Avatar(cor: Color(Perfil.corDecisoes), inicial: 'D', tamanho: 28), 'Decisões'),
        destino(Tela.painel, const Avatar(cor: Color(Perfil.corPainel), inicial: 'P', tamanho: 28), 'Painel'),
        destino(Tela.tarefas, const Avatar(cor: Color(Perfil.corTarefas), inicial: 'T', tamanho: 28), 'Tarefas'),
        destino(Tela.equipes, const Avatar(cor: Color(Perfil.corBoard), inicial: 'E', tamanho: 28), 'Equipes'),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
          child: Text('CONVERSAS', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11, letterSpacing: 1)),
        ),
        Expanded(child: ListaConversas(sala: sala)),
        if (comConfiguracao) ...[
          const Divider(),
          ListTile(
            dense: true,
            selected: sala.tela == Tela.configuracao,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Configuração'),
            onTap: () => sala.ir(Tela.configuracao),
          ),
        ],
      ]),
    );
  }
}
