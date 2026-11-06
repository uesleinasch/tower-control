import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/areas.dart';
import '../estado/sala.dart';
import '../nucleo/design.dart';
import 'chat.dart';
import 'comum.dart';
import 'tema.dart';

const _larguraDaLista = 360.0;
const _numeros = [FontFeature.tabularFigures()];

String estadoDaDecisao(String status) => switch (status) {
      'aceita' => 'aprovado',
      'revogada' => 'recusada',
      _ => 'em_revisao',
    };

class TelaDecisoes extends StatelessWidget {
  const TelaDecisoes({super.key, required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sala.decisoes,
        builder: (context, _) => LayoutBuilder(builder: (context, limites) {
          final classe = ClasseDeJanela.de(limites.maxWidth);
          final aberta = sala.decisoes.aberta;
          if (!classe.comDoisPaineis) {
            return aberta == null
                ? _Lista(sala: sala, margem: classe.margemLateral, comCabecalho: true)
                : _Detalhe(sala: sala, conteudo: aberta.conteudo, emPainel: false);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Cabecalho(estado: sala.decisoes, margem: classe.margemLateral),
            const Divider(height: 1),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(width: _larguraDaLista, child: _Lista(sala: sala, margem: Espacos.esp3, comCabecalho: false)),
                const VerticalDivider(width: 1),
                Expanded(
                  child: aberta == null
                      ? _NadaSelecionado(estado: sala.decisoes)
                      : _Detalhe(key: ValueKey(aberta.id), sala: sala, conteudo: aberta.conteudo, emPainel: true),
                ),
              ]),
            ),
          ]);
        }),
      );
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.estado, required this.margem});

  final EstadoDecisoes estado;
  final double margem;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      color: tema.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, Espacos.esp2, Espacos.esp3),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Decisões', style: tema.textTheme.titleLarge),
                Text(
                  'registro e consulta',
                  style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                ),
              ]),
            ),
            IconButton(tooltip: 'Recarregar', icon: const Icon(Symbols.refresh), onPressed: estado.carregar),
          ]),
        ),
      ),
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio({required this.icone, required this.texto, this.acao});

  final IconData icone;
  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, color: cor),
          const SizedBox(height: Espacos.esp2),
          Text(texto, textAlign: TextAlign.center, style: tema.textTheme.bodyMedium?.copyWith(color: cor)),
          if (acao != null) ...[const SizedBox(height: Espacos.esp3), acao!],
        ]),
      ),
    );
  }
}

class _NadaSelecionado extends StatelessWidget {
  const _NadaSelecionado({required this.estado});

  final EstadoDecisoes estado;

  @override
  Widget build(BuildContext context) {
    final lista = estado.filtradas;
    return _Vazio(
      icone: Symbols.gavel,
      texto: estado.lista.isEmpty
          ? 'Nenhuma decisão registrada ainda.'
          : 'Escolha uma decisão na lista para ler o registro.',
      acao: lista.isEmpty
          ? null
          : OutlinedButton(onPressed: () => estado.abrir(lista.first.id), child: const Text('Abrir a primeira')),
    );
  }
}

class _Lista extends StatefulWidget {
  const _Lista({required this.sala, required this.margem, required this.comCabecalho});

  final Sala sala;
  final double margem;
  final bool comCabecalho;

  @override
  State<_Lista> createState() => _ListaState();
}

class _ListaState extends State<_Lista> {
  late final _busca = TextEditingController(text: widget.sala.decisoes.filtro);

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _limpar() {
    _busca.clear();
    widget.sala.decisoes.filtrar('');
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.sala.decisoes;
    final tema = Theme.of(context);
    final lista = estado.filtradas;
    final aberta = estado.aberta?.id;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.comCabecalho) ...[
        _Cabecalho(estado: estado, margem: widget.margem),
      ],
      Padding(
        padding: EdgeInsets.fromLTRB(widget.margem, Espacos.esp2, widget.margem, Espacos.esp3),
        child: TextField(
          controller: _busca,
          onChanged: estado.filtrar,
          decoration: InputDecoration(
            prefixIcon: const Icon(Symbols.search),
            labelText: 'Buscar decisões',
            hintText: 'Título, tag ou projeto',
            suffixIcon: _busca.text.isEmpty
                ? null
                : IconButton(tooltip: 'Limpar busca', icon: const Icon(Symbols.close), onPressed: _limpar),
          ),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: !estado.carregada
            ? const Center(child: CircularProgressIndicator())
            : lista.isEmpty
                ? (estado.lista.isEmpty
                    ? _Vazio(
                        icone: Symbols.gavel,
                        texto: 'Nenhuma decisão registrada ainda.',
                        acao: OutlinedButton(onPressed: estado.carregar, child: const Text('Recarregar')),
                      )
                    : _Vazio(
                        icone: Symbols.search_off,
                        texto: 'Nenhuma decisão com essa busca.',
                        acao: OutlinedButton(onPressed: _limpar, child: const Text('Limpar busca')),
                      ))
                : ListView.separated(
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: Espacos.esp4, endIndent: Espacos.esp4),
                    itemBuilder: (context, i) {
                      final d = lista[i];
                      final detalhes = [if (d.projeto.isNotEmpty) d.projeto, if (d.tags.isNotEmpty) d.tags.join(', ')];
                      return ListTile(
                        selected: d.id == aberta,
                        title: Text(d.titulo, style: tema.textTheme.titleSmall),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.data, style: tema.textTheme.bodySmall?.copyWith(fontFeatures: _numeros)),
                          if (detalhes.isNotEmpty) Text(detalhes.join(' · '), style: tema.textTheme.bodySmall),
                        ]),
                        trailing: RotuloDeEstado(estado: estadoDaDecisao(d.status), rotulo: d.status),
                        onTap: () => estado.abrir(d.id),
                      );
                    },
                  ),
      ),
    ]);
  }
}

class _Detalhe extends StatelessWidget {
  const _Detalhe({super.key, required this.sala, required this.conteudo, required this.emPainel});

  final Sala sala;
  final String conteudo;
  final bool emPainel;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final corpo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Material(
        color: tema.colorScheme.surface,
        child: SafeArea(
          bottom: false,
          child: Row(children: [
            if (!emPainel)
              IconButton(
                tooltip: 'Voltar',
                icon: const Icon(Symbols.arrow_back),
                onPressed: sala.decisoes.fecharDetalhe,
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: emPainel ? Espacos.esp5 : 0),
                child: Text('Decisão', style: tema.textTheme.titleLarge),
              ),
            ),
            IconButton(
              tooltip: 'Copiar',
              icon: const Icon(Symbols.content_copy),
              onPressed: () => copiar(context, conteudo),
            ),
          ]),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Espacos.esp4),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
              child: SelectionArea(child: TextoMarkdown(conteudo)),
            ),
          ),
        ),
      ),
    ]);
    if (emPainel) return corpo;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) sala.decisoes.fecharDetalhe();
      },
      child: corpo,
    );
  }
}
