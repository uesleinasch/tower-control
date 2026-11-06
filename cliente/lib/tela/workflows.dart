import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import '../estado/sala.dart';
import '../estado/workflows.dart';
import '../nucleo/design.dart';
import '../nucleo/editor_de_workflow.dart';
import '../nucleo/organograma.dart' show paraMundo, passoDeMover;
import '../nucleo/painel.dart' show haQuanto;
import '../nucleo/protocolo.dart' show EscopoDoCancelamento;
import '../nucleo/tarefas.dart';
import '../nucleo/workflows.dart';
import 'canvas.dart';
import 'comum.dart' show CartaoDePedido;
import 'equipes.dart' show confirmar, pedirTexto, quandoCurto;
import 'importacao.dart';
import 'paineis.dart';
import 'tema.dart';

const _larguraDoPainel = 320.0;
const _larguraDoDialogo = 420.0;
const _ladoDoBotaoDeMenu = 32.0;
const _numeros = [FontFeature.tabularFigures()];

Future<void> cancelarFluxo(BuildContext context, EstadoWorkflows estado, int fluxo, String nome) async {
  final ok = await confirmar(
    context,
    'Cancelar o workflow $nome (#$fluxo)?',
    'As caixas e as tarefas abertas dele são canceladas. O que já foi feito fica registrado.',
    acao: 'Cancelar workflow',
    destrutivo: true,
  );
  if (ok) estado.cancelar(fluxo);
}

Future<EscopoDoCancelamento?> escolherEscopoDoCancelamento(BuildContext context, int tarefa, CaixaDaTarefa caixa) =>
    showDialog<EscopoDoCancelamento>(
      context: context,
      builder: (_) => DialogoDeCancelarTarefa(tarefa: tarefa, caixa: caixa),
    );

class DialogoDeCancelarTarefa extends StatefulWidget {
  const DialogoDeCancelarTarefa({super.key, required this.tarefa, required this.caixa});

  final int tarefa;
  final CaixaDaTarefa caixa;

  @override
  State<DialogoDeCancelarTarefa> createState() => _DialogoDeCancelarTarefaState();
}

class _DialogoDeCancelarTarefaState extends State<DialogoDeCancelarTarefa> {
  var _escopo = EscopoDoCancelamento.tarefa;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final (:fluxo, :ficha) = widget.caixa;
    final caixa = rotuloDaFicha(fluxo, ficha);
    Widget opcao(EscopoDoCancelamento valor, String titulo, String texto) {
      final escolhida = _escopo == valor;
      return Card.outlined(
        margin: EdgeInsets.zero,
        color: escolhida ? cores.surfaceContainerLow : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Raios.md),
          side: BorderSide(color: escolhida ? cores.primary : cores.outlineVariant, width: escolhida ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: RadioListTile<EscopoDoCancelamento>(
          value: valor,
          title: Text(titulo),
          subtitle: Text(texto),
          contentPadding: const EdgeInsets.symmetric(horizontal: Espacos.esp3, vertical: Espacos.esp1),
        ),
      );
    }

    return AlertDialog(
      title: Text('Cancelar a tarefa #${widget.tarefa}?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _larguraDoDialogo),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'Ela faz parte do workflow "${fluxo.nome}" (#${fluxo.id}), na caixa "$caixa".',
              style: tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant),
            ),
            const SizedBox(height: Espacos.esp4),
            RadioGroup<EscopoDoCancelamento>(
              groupValue: _escopo,
              onChanged: (v) => setState(() => _escopo = v ?? _escopo),
              child: Semantics(
                label: 'O que cancelar',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  opcao(
                    EscopoDoCancelamento.tarefa,
                    'Só esta tarefa',
                    'O workflow para na caixa "$caixa" e espera você escolher: recriar a tarefa ou cancelar o workflow.',
                  ),
                  const SizedBox(height: Espacos.esp2),
                  opcao(
                    EscopoDoCancelamento.fluxo,
                    'O workflow inteiro',
                    'Cancela o workflow #${fluxo.id} e todas as tarefas abertas dele. O que já foi feito fica registrado.',
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cores.error, foregroundColor: cores.onError),
          onPressed: () => Navigator.pop(context, _escopo),
          child: const Text('Cancelar a tarefa'),
        ),
      ],
    );
  }
}

class PedidoDeCaixaParada extends StatelessWidget {
  const PedidoDeCaixaParada({
    super.key,
    required this.fluxo,
    required this.texto,
    this.quando,
    required this.aoRecriar,
    required this.aoCancelar,
  });

  final int fluxo;
  final String texto;
  final String? quando;
  final VoidCallback aoRecriar;
  final VoidCallback aoCancelar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return CartaoDePedido(
      icone: Symbols.pause_circle,
      faixa: 'Caixa parada no workflow #$fluxo',
      quando: quando,
      conteudo: Text(texto, style: tema.textTheme.bodyMedium),
      acoes: [
        FilledButton(onPressed: aoRecriar, child: const Text('Recriar a tarefa')),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: tema.colorScheme.error),
          onPressed: aoCancelar,
          child: const Text('Cancelar o workflow'),
        ),
      ],
    );
  }
}

Widget pedidoDaCaixaParada(BuildContext context, EstadoWorkflows estado, Fluxo fluxo, Ficha ficha) => PedidoDeCaixaParada(
      key: ValueKey('parada-${fluxo.id}-${ficha.id}'),
      fluxo: fluxo.id,
      texto: textoDaCaixaParada(fluxo, ficha),
      quando: switch (ficha.concluidaEm ?? ficha.criadaEm) {
        final em? => quandoCurto(em),
        null => null,
      },
      aoRecriar: () => estado.recriar(fluxo.id, ficha.id),
      aoCancelar: () => cancelarFluxo(context, estado, fluxo.id, fluxo.nome),
    );

Future<bool> abrirIniciarWorkflow(BuildContext context, EstadoWorkflows estado, Workflow w) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoDeIniciar(estado: estado, workflow: w),
    ) ==
    true;

Future<void> abrirPaginaDoFluxo(BuildContext context, Sala sala, int fluxo) async {
  sala.workflows.verFluxo(fluxo);
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (contexto) => Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: sala.workflows,
          builder: (_, _) => _VistaDoGrafo(sala: sala, desenhar: true, aoVoltar: () => Navigator.of(contexto).pop()),
        ),
      ),
    ),
  ));
  sala.workflows.fecharGrafo();
}

const iconesDeCaixa = {
  'executar': Symbols.engineering,
  'revisar': Symbols.find_in_page,
  'aprovar': Symbols.verified_user,
  'board': Symbols.gavel,
  'decisao_humana': Symbols.fact_check,
  'condicao': Symbols.call_split,
  'paralelo': Symbols.device_hub,
  'juncao': Symbols.merge,
  'laco': Symbols.loop,
  'espera': Symbols.hourglass_empty,
  'fim': Symbols.flag,
};

IconData iconeDaCaixa(String? tipo) => iconesDeCaixa[tipo] ?? Symbols.crop_square;

String rotuloNoRascunho(WorkflowJson w, String id) {
  final titulo = caixaDe(w, id)?['titulo'];
  return titulo is String && titulo.trim().isNotEmpty ? titulo.trim() : id;
}

class FolhaDeApoio extends StatelessWidget {
  const FolhaDeApoio({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Material(
      color: cores.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Raios.lg)),
        side: BorderSide(color: cores.outlineVariant),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.icone, required this.texto, this.acao});

  final IconData icone;
  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espacos.esp7, horizontal: Espacos.esp4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icone, color: cor),
        const SizedBox(height: Espacos.esp2),
        Text(texto, textAlign: TextAlign.center, style: tema.textTheme.bodyMedium?.copyWith(color: cor)),
        if (acao case final a?) ...[const SizedBox(height: Espacos.esp3), a],
      ]),
    );
  }
}

class PainelDeWorkflows extends StatelessWidget {
  const PainelDeWorkflows({super.key, required this.sala, required this.equipe, required this.desenhar});

  final Sala sala;
  final EquipeResumo equipe;
  final bool desenhar;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sala.workflows,
        builder: (context, _) {
          final v = sala.workflows.vendo;
          if (v != null && (v.equipe == equipe.id || v.equipe.isEmpty)) {
            return _VistaDoGrafo(sala: sala, desenhar: desenhar);
          }
          return _ListaDeWorkflows(sala: sala, equipe: equipe, editar: desenhar);
        },
      );
}

class _ListaDeWorkflows extends StatelessWidget {
  const _ListaDeWorkflows({required this.sala, required this.equipe, required this.editar});

  final Sala sala;
  final EquipeResumo equipe;
  final bool editar;

  Future<void> _novo(BuildContext context) async {
    final nome = await pedirTexto(
      context,
      titulo: 'Novo workflow',
      rotulo: 'Nome do workflow',
      explicacao: 'O id sai do nome e não muda depois: é o nome do arquivo, e as rotinas apontam para ele.',
      acao: 'Criar',
    );
    if (nome == null) return;
    final erro = sala.editorDeWorkflow.criarNovo(nome, equipe, sala.workflows.daEquipe(equipe.id).map((w) => w.id));
    if (erro != null && context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(erro)));
  }

  @override
  Widget build(BuildContext context) {
    final estado = sala.workflows;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final daEquipe = estado.daEquipe(equipe.id);
    final encerrados = estado.encerrados(equipe.id);
    return LayoutBuilder(builder: (context, limites) {
      final margem = ClasseDeJanela.de(limites.maxWidth).margemLateral;
      return ListView(padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, margem, Espacos.esp5), children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Workflows de ${equipe.nome}', style: tema.textTheme.titleMedium),
              Text(
                'Caixas ligadas que a equipe percorre sozinha, do início ao fim',
                style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant),
              ),
            ]),
          ),
          const SizedBox(width: Espacos.esp3),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Espacos.esp2,
              runSpacing: Espacos.esp2,
              children: [
                if (editar) ...[
                  OutlinedButton.icon(
                    onPressed: () => importarModelo(context, sala, destino: equipe.id),
                    icon: const Icon(Symbols.file_open),
                    label: const Text('Importar workflow…'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _novo(context),
                    icon: const Icon(Symbols.add),
                    label: const Text('Novo workflow'),
                  ),
                ],
                IconButton(tooltip: 'Recarregar', icon: const Icon(Symbols.refresh), onPressed: estado.carregar),
              ],
            ),
          ),
        ]),
        const SizedBox(height: Espacos.esp4),
        if (!estado.carregada)
          const Padding(padding: EdgeInsets.all(Espacos.esp5), child: Center(child: CircularProgressIndicator()))
        else if (daEquipe.isEmpty)
          _EstadoVazio(
            icone: Symbols.schema,
            texto: editar
                ? 'Nenhum workflow nesta equipe. Monte o primeiro no editor.'
                : 'Nenhum workflow nesta equipe. Eles ficam em equipes/${equipe.id}/workflows/ na pasta de dados.',
            acao: editar
                ? FilledButton.tonalIcon(
                    onPressed: () => _novo(context),
                    icon: const Icon(Symbols.add),
                    label: const Text('Novo workflow'),
                  )
                : null,
          ),
        for (final w in daEquipe)
          Padding(
            padding: const EdgeInsets.only(bottom: Espacos.esp3),
            child: _CartaoDoWorkflow(sala: sala, equipe: equipe, workflow: w, editar: editar),
          ),
        if (encerrados.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              'Encerrados (${encerrados.length})',
              style: tema.textTheme.titleSmall?.copyWith(fontFeatures: _numeros),
            ),
            children: [for (final f in encerrados) _LinhaDoFluxo(sala: sala, fluxo: f, comNome: true)],
          ),
      ]);
    });
  }
}

class _CartaoDoWorkflow extends StatefulWidget {
  const _CartaoDoWorkflow({required this.sala, required this.equipe, required this.workflow, required this.editar});

  final Sala sala;
  final EquipeResumo equipe;
  final Workflow workflow;
  final bool editar;

  @override
  State<_CartaoDoWorkflow> createState() => _CartaoDoWorkflowState();
}

class _CartaoDoWorkflowState extends State<_CartaoDoWorkflow> {
  final _menu = MenuController();
  final _ancora = GlobalKey();

  void _abrirMenu(BuildContext botao) {
    final origem = botao.findRenderObject();
    final cartao = _ancora.currentContext?.findRenderObject();
    if (origem is! RenderBox || cartao is! RenderBox) return _menu.open();
    _menu.open(position: origem.localToGlobal(Offset(0, origem.size.height), ancestor: cartao));
  }

  @override
  Widget build(BuildContext context) {
    final sala = widget.sala;
    final equipe = widget.equipe;
    final estado = sala.workflows;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final w = widget.workflow;
    final abertos = estado.abertos(w.equipe, w.id);
    final menu = [
      MenuItemButton(
        leadingIcon: const Icon(Symbols.content_copy),
        onPressed: () => sala.editorDeWorkflow.duplicar(w, equipe, estado.daEquipe(equipe.id).map((x) => x.id)),
        child: const Text('Duplicar'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Symbols.ios_share),
        onPressed: () => exportarWorkflowComoModelo(context, sala, equipe.id, w.id),
        child: const Text('Exportar como modelo…'),
      ),
    ];
    return MenuAnchor(
      controller: _menu,
      menuChildren: widget.editar ? menu : const [],
      child: GestureDetector(
        key: _ancora,
        onSecondaryTapUp: widget.editar ? (d) => _menu.open(position: d.localPosition) : null,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Espacos.esp4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Symbols.schema, size: 20, color: cores.onSurfaceVariant),
                const SizedBox(width: Espacos.esp2),
                Expanded(child: Text(w.nome, style: tema.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                if (widget.editar)
                  Builder(
                    builder: (botao) => IconButton(
                      tooltip: 'Mais opções de ${w.nome}',
                      onPressed: () => _menu.isOpen ? _menu.close() : _abrirMenu(botao),
                      icon: const Icon(Symbols.more_vert),
                    ),
                  ),
              ]),
              const SizedBox(height: Espacos.esp1),
              Text(
                [
                  'versão ${w.versao}',
                  '${w.nos.length} ${w.nos.length == 1 ? 'caixa' : 'caixas'}',
                  if (w.entrada.isNotEmpty) 'entrada: ${w.entrada.keys.join(', ')}',
                  if (abertos.isNotEmpty) '${abertos.length} ${abertos.length == 1 ? 'aberto' : 'abertos'}',
                ].join(' · '),
                style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros),
              ),
              const SizedBox(height: Espacos.esp3),
              Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: [
                FilledButton.tonalIcon(
                  onPressed: () => abrirIniciarWorkflow(context, estado, w),
                  icon: const Icon(Symbols.play_arrow),
                  label: const Text('Iniciar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => estado.verDefinicao(w),
                  icon: const Icon(Symbols.alt_route),
                  label: const Text('Ver'),
                ),
                if (widget.editar)
                  OutlinedButton.icon(
                    onPressed: () => sala.editorDeWorkflow.abrir(w, equipe),
                    icon: const Icon(Symbols.edit),
                    label: const Text('Editar'),
                  ),
              ]),
              if (abertos.isNotEmpty) ...[
                const SizedBox(height: Espacos.esp3),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.only(top: Espacos.esp2),
                  child: Text('Em andamento', style: tema.textTheme.titleSmall),
                ),
                for (final f in abertos) _LinhaDoFluxo(sala: sala, fluxo: f),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _IconeDoFluxo extends StatelessWidget {
  const _IconeDoFluxo({required this.status, this.tamanho = 24});

  final String status;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final estado = estadoDoFluxo(status);
    return Tooltip(
      message: nomesDeStatusDoFluxo[status] ?? status,
      child: Icon(iconeDoEstado(estado), size: tamanho, color: corDoEstado(context, estado)),
    );
  }
}

class _LinhaDoFluxo extends StatelessWidget {
  const _LinhaDoFluxo({required this.sala, required this.fluxo, this.comNome = false});

  final Sala sala;
  final Fluxo fluxo;
  final bool comNome;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final f = fluxo;
    final ativas = [
      for (final ficha in f.fichas)
        if (ficha.esperando)
          rotuloDaFicha(f, ficha)
        else if (ficha.parada)
          '${rotuloDaFicha(f, ficha)} (parada)',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _IconeDoFluxo(status: f.status),
      title: Text(
        [
          if (comNome) f.nome,
          '#${f.id}',
          nomesDeStatusDoFluxo[f.status] ?? f.status,
          haQuanto(f.criadoEm, DateTime.now()),
        ].where((p) => p.isNotEmpty).join(' · '),
        style: tema.textTheme.bodyMedium?.copyWith(fontFeatures: _numeros),
      ),
      subtitle: Text(
        f.aberto
            ? (ativas.isEmpty ? 'nenhuma caixa esperando' : 'em: ${ativas.join(', ')}')
            : f.erro ?? f.resultado ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant),
      ),
      trailing: f.aberto
          ? IconButton(
              tooltip: 'Cancelar workflow',
              color: cores.error,
              icon: const Icon(Symbols.cancel),
              onPressed: () => cancelarFluxo(context, sala.workflows, f.id, f.nome),
            )
          : null,
      onTap: () => sala.workflows.verFluxo(f.id),
    );
  }
}

class _DialogoDeIniciar extends StatefulWidget {
  const _DialogoDeIniciar({required this.estado, required this.workflow});

  final EstadoWorkflows estado;
  final Workflow workflow;

  @override
  State<_DialogoDeIniciar> createState() => _DialogoDeIniciarState();
}

class _DialogoDeIniciarState extends State<_DialogoDeIniciar> {
  late final Map<String, TextEditingController> _textos = {
    for (final MapEntry(:key, :value) in widget.workflow.entrada.entries)
      if (value.nome == 'texto' || value.nome == 'numero') key: TextEditingController(),
  };
  final Map<String, Object?> _outros = {};
  List<String> _erros = const [];

  @override
  void dispose() {
    for (final c in _textos.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _iniciar() {
    final brutos = <String, Object?>{
      ..._outros,
      for (final MapEntry(:key, :value) in _textos.entries) key: value.text,
    };
    final erros = widget.estado.iniciar(widget.workflow, brutos);
    if (erros.isEmpty) {
      Navigator.pop(context, true);
    } else {
      setState(() => _erros = erros);
    }
  }

  Widget _campo(String campo, TipoDeValor tipo) => switch (tipo.nome) {
        'booleano' => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(campo),
            value: _outros[campo] == true,
            onChanged: (v) => setState(() => _outros[campo] = v),
          ),
        'escolha' => DropdownButtonFormField<String>(
            initialValue: _outros[campo] as String?,
            isExpanded: true,
            decoration: InputDecoration(labelText: campo),
            items: [for (final o in tipo.escolhas) DropdownMenuItem(value: o, child: Text(o))],
            onChanged: (v) => setState(() => _outros[campo] = v),
          ),
        'numero' => TextField(
            controller: _textos[campo],
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: campo, helperText: 'número'),
          ),
        _ => TextField(
            controller: _textos[campo],
            minLines: 1,
            maxLines: 6,
            decoration: InputDecoration(labelText: campo),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final w = widget.workflow;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    return AlertDialog(
      title: Text('Iniciar ${w.nome}'),
      content: SizedBox(
        width: _larguraDoDialogo,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (w.entrada.isEmpty)
              Text(
                'Este workflow não pede entrada.',
                style: tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant),
              ),
            for (final MapEntry(:key, :value) in w.entrada.entries)
              Padding(padding: const EdgeInsets.only(bottom: Espacos.esp3), child: _campo(key, value)),
            for (final erro in _erros)
              Padding(
                padding: const EdgeInsets.only(top: Espacos.esp1),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Symbols.error, size: 16, color: cores.error),
                  const SizedBox(width: Espacos.esp1),
                  Expanded(child: Text(erro, style: tema.textTheme.bodySmall?.copyWith(color: cores.error))),
                ]),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _iniciar, child: const Text('Iniciar')),
      ],
    );
  }
}

class _VistaDoGrafo extends StatelessWidget {
  const _VistaDoGrafo({required this.sala, required this.desenhar, this.aoVoltar});

  final Sala sala;
  final bool desenhar;
  final VoidCallback? aoVoltar;

  @override
  Widget build(BuildContext context) {
    final estado = sala.workflows;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final pequeno = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros);
    final w = estado.definicaoVista;
    final f = estado.fluxoVisto;
    final caixa = estado.caixa == null ? null : w?.caixa(estado.caixa!);
    return LayoutBuilder(builder: (context, limites) {
      final classe = ClasseDeJanela.de(limites.maxWidth);
      final margem = classe.margemLateral;
      final cabecalho = Padding(
        padding: EdgeInsets.fromLTRB(Espacos.esp1, Espacos.esp2, margem, Espacos.esp2),
        child: Row(children: [
          IconButton(tooltip: 'Voltar', icon: const Icon(Symbols.arrow_back), onPressed: aoVoltar ?? estado.fecharGrafo),
          const SizedBox(width: Espacos.esp1),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w?.nome ?? 'Workflow', style: tema.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
              Row(children: [
                if (f != null) ...[
                  _IconeDoFluxo(status: f.status, tamanho: 16),
                  const SizedBox(width: Espacos.esp1),
                ],
                Flexible(
                  child: Text(
                    f == null
                        ? 'versão ${w?.versao ?? 0} · ${w?.nos.length ?? 0} caixas'
                        : [
                            '#${f.id}',
                            nomesDeStatusDoFluxo[f.status] ?? f.status,
                            if (f.criadoEm case final em?) 'desde ${quandoCurto(em)}',
                            if (f.criadoPor.startsWith('rotina:')) 'por ${f.criadoPor}',
                          ].join(' · '),
                    style: pequeno,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: Espacos.esp2),
          if (f != null && f.aberto)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cores.error, side: BorderSide(color: cores.error)),
              onPressed: () => cancelarFluxo(context, estado, f.id, f.nome),
              icon: const Icon(Symbols.cancel),
              label: const Text('Cancelar workflow'),
            )
          else if (f == null && w != null)
            FilledButton.tonalIcon(
              onPressed: () => abrirIniciarWorkflow(context, estado, w),
              icon: const Icon(Symbols.play_arrow),
              label: const Text('Iniciar'),
            ),
        ]),
      );
      final extras = <(String, bool)>[
        if (f != null && f.entrada.isNotEmpty) ('entrada: ${resumoDasSaidas(f.entrada)}', false),
        if (f?.resultado case final r?) ('resultado: $r', false),
        if (f?.erro case final e?) ('erro: $e', true),
      ];
      final Widget corpo;
      if (w == null) {
        corpo = Center(
          child: estado.carregada
              ? _EstadoVazio(
                  icone: Symbols.schema,
                  texto: 'Workflow não encontrado.',
                  acao: OutlinedButton.icon(
                    onPressed: aoVoltar ?? estado.fecharGrafo,
                    icon: const Icon(Symbols.arrow_back),
                    label: const Text('Voltar'),
                  ),
                )
              : const CircularProgressIndicator(),
        );
      } else if (desenhar) {
        final grafo = CanvasDoGrafo(
          workflow: w,
          estados: f == null ? const {} : estadoDasCaixas(f),
          percorridas: f == null ? const {} : arestasPercorridas(f),
          selecionada: estado.caixa,
          aoTocar: estado.selecionarCaixa,
        );
        if (caixa == null) {
          corpo = grafo;
        } else {
          final detalhe = _DetalheDaCaixa(sala: sala, caixa: caixa, fluxo: f);
          corpo = classe.comDoisPaineis
              ? LadoALado(
                  painel: 'workflows',
                  rotulo: 'Largura do painel da caixa',
                  inicial: _larguraDoPainel,
                  lateralADireita: true,
                  principal: grafo,
                  lateral: Material(color: cores.surfaceContainer, child: detalhe),
                )
              : LayoutBuilder(
                  builder: (context, area) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: grafo),
                    SizedBox(height: area.maxHeight * 0.45, child: FolhaDeApoio(child: detalhe)),
                  ]),
                );
        }
      } else {
        corpo = f == null ? _CaixasEmLista(workflow: w) : _CaminhoEmLista(sala: sala, fluxo: f);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        cabecalho,
        for (final (texto, erro) in extras)
          Padding(
            padding: EdgeInsets.fromLTRB(margem, 0, margem, Espacos.esp1),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (erro) ...[
                    Icon(Symbols.error, size: 16, color: cores.error),
                    const SizedBox(width: Espacos.esp1),
                  ],
                  Flexible(
                    child: Text(
                      texto,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: erro ? pequeno?.copyWith(color: cores.error) : pequeno,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        if (f != null)
          for (final ficha in caixasParadas(f))
            Padding(
              padding: EdgeInsets.fromLTRB(margem, Espacos.esp2, margem, Espacos.esp2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
                  child: pedidoDaCaixaParada(context, estado, f, ficha),
                ),
              ),
            ),
        const Divider(height: 1),
        Expanded(child: corpo),
      ]);
    });
  }
}

Widget? _pedidoDaFicha(BuildContext context, Sala sala, Fluxo fluxo, Ficha ficha, Caixa? caixa) {
  if (!ficha.esperando || caixa == null) return null;
  final tema = Theme.of(context);
  final quando = ficha.criadaEm == null ? null : quandoCurto(ficha.criadaEm!);
  Widget texto(String t) => Text(t, style: tema.textTheme.bodyMedium);
  switch (caixa.tipo) {
    case 'decisao_humana':
      final pergunta = caixa.campos['pergunta'];
      return CartaoDePedido(
        icone: Symbols.fact_check,
        faixa: 'Decisão sua em ${fluxo.nome}',
        quando: quando,
        conteudo: texto(pergunta is String && pergunta.trim().isNotEmpty ? pergunta.trim() : caixa.rotulo),
        acoes: [
          for (final (i, opcao) in caixa.opcoes.indexed)
            i == 0
                ? FilledButton(onPressed: () => sala.workflows.decidir(fluxo.id, ficha.id, opcao), child: Text(opcao))
                : OutlinedButton(onPressed: () => sala.workflows.decidir(fluxo.id, ficha.id, opcao), child: Text(opcao)),
        ],
      );
    case 'aprovar' when caixa.campos['por'] is Map && (caixa.campos['por'] as Map)['ueslei'] == true:
      final tarefa = ficha.tarefa;
      if (tarefa == null) return null;
      return CartaoDePedido(
        icone: Symbols.verified_user,
        faixa: 'Aprovação sua em ${fluxo.nome}',
        quando: quando,
        conteudo: texto('A entrega espera sua aprovação na tarefa #$tarefa.'),
        acoes: [FilledButton(onPressed: () => sala.abrirTarefa(tarefa), child: Text('Abrir tarefa #$tarefa'))],
      );
    case 'espera' when caixa.campos['sinal'] is String:
      return CartaoDePedido(
        icone: Symbols.sensors,
        faixa: 'Sinal esperado em ${fluxo.nome}',
        quando: quando,
        conteudo: texto('O fluxo segue quando você mandar o sinal "${caixa.campos['sinal']}".'),
        acoes: [
          FilledButton(onPressed: () => sala.workflows.sinalizar(fluxo.id, ficha.id), child: const Text('Mandar sinal')),
        ],
      );
  }
  return null;
}

class _DetalheDaCaixa extends StatelessWidget {
  const _DetalheDaCaixa({required this.sala, required this.caixa, required this.fluxo});

  final Sala sala;
  final Caixa caixa;
  final Fluxo? fluxo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final pequeno = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final f = fluxo;
    final fichas = [for (final ficha in f?.fichas ?? const <Ficha>[]) if (ficha.no == caixa.id) ficha]
      ..sort((a, b) => b.id.compareTo(a.id));
    return ListView(padding: const EdgeInsets.all(Espacos.esp4), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: Espacos.esp1),
          child: Icon(iconeDaCaixa(caixa.tipo), size: 20, color: cores.onSurfaceVariant),
        ),
        const SizedBox(width: Espacos.esp2),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(caixa.rotulo, style: tema.textTheme.titleMedium),
            Text(
              [caixa.nomeDoTipo, if (caixa.detalhe.isNotEmpty) caixa.detalhe, if (caixa.prazo case final p?) 'prazo $p']
                  .join(' · '),
              style: pequeno,
            ),
          ]),
        ),
        IconButton(tooltip: 'Fechar', icon: const Icon(Symbols.close), onPressed: () => sala.workflows.selecionarCaixa(null)),
      ]),
      if (f == null)
        Padding(
          padding: const EdgeInsets.only(top: Espacos.esp3),
          child: Text('Abra um fluxo para ver as saídas desta caixa.', style: pequeno),
        )
      else if (fichas.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: Espacos.esp3),
          child: Text('O fluxo não passou por esta caixa.', style: pequeno),
        ),
      for (final ficha in fichas) ...[
        const Divider(height: Espacos.esp5),
        Row(children: [
          RotuloDeEstado(estado: ficha.status, rotulo: nomesDeStatusDaFicha[ficha.status] ?? ficha.status),
          const SizedBox(width: Espacos.esp2),
          Expanded(
            child: Text(
              [
                'ficha #${ficha.id}',
                if (ficha.concluidaEm ?? ficha.criadaEm case final em?) quandoCurto(em),
              ].join(' · '),
              style: pequeno?.copyWith(fontFeatures: _numeros),
            ),
          ),
          if (ficha.tarefa case final t?)
            TextButton(
              onPressed: () => sala.abrirTarefa(t),
              child: Text('#$t', style: const TextStyle(fontFeatures: _numeros)),
            ),
        ]),
        if (f != null)
          if (_pedidoDaFicha(context, sala, f, ficha, caixa) case final pedido?)
            Padding(padding: const EdgeInsets.only(top: Espacos.esp2), child: pedido),
        if (ficha.saidas.isEmpty)
          Text(ficha.esperando ? 'esperando…' : 'sem saídas', style: pequeno)
        else
          for (final MapEntry(:key, :value) in ficha.saidas.entries)
            Padding(
              padding: const EdgeInsets.only(top: Espacos.esp2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(key, style: tema.textTheme.labelMedium?.copyWith(color: cores.onSurfaceVariant)),
                SelectableText(formatarValor(value), style: tema.textTheme.bodyMedium),
              ]),
            ),
      ],
    ]);
  }
}

class _CaminhoEmLista extends StatelessWidget {
  const _CaminhoEmLista({required this.sala, required this.fluxo});

  final Sala sala;
  final Fluxo fluxo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final passos = ordemDoCaminho(fluxo);
    if (passos.isEmpty) {
      return const Center(child: _EstadoVazio(icone: Symbols.schema, texto: 'Nenhuma caixa ainda.'));
    }
    return LayoutBuilder(builder: (context, limites) {
      final margem = ClasseDeJanela.de(limites.maxWidth).margemLateral;
      return ListView(padding: EdgeInsets.fromLTRB(margem, Espacos.esp3, margem, Espacos.esp5), children: [
        for (final p in passos) ...[
          Card(
            margin: const EdgeInsets.only(bottom: Espacos.esp2),
            shape: p.destacado
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Raios.md),
                    side: BorderSide(color: corDoEstado(context, p.status), width: 2),
                  )
                : null,
            child: ListTile(
              leading: Icon(iconeDaCaixa(p.tipo), color: p.destacado ? corDoEstado(context, p.status) : cores.onSurfaceVariant),
              title: Text(
                p.titulo,
                style: tema.textTheme.titleSmall?.copyWith(fontWeight: p.destacado ? FontWeight.w600 : null),
              ),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: Espacos.esp1),
                RotuloDeEstado(estado: p.status, rotulo: nomesDeStatusDaFicha[p.status] ?? p.status),
                Text(
                  [
                    nomesDeCaixa[p.tipo] ?? p.tipo,
                    if (p.tarefa case final t?) '#$t',
                    if (p.resumo.isNotEmpty) p.resumo,
                  ].join(' · '),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros),
                ),
              ]),
              onTap: p.tarefa == null ? null : () => sala.abrirTarefa(p.tarefa!),
            ),
          ),
          if (p.destacado)
            if (fluxo.ficha(p.ficha) case final ficha?)
              if (_pedidoDaFicha(context, sala, fluxo, ficha, fluxo.definicao.caixa(p.no)) case final pedido?)
                Padding(padding: const EdgeInsets.only(bottom: Espacos.esp3), child: pedido),
        ],
      ]);
    });
  }
}

class _CaixasEmLista extends StatelessWidget {
  const _CaixasEmLista({required this.workflow});

  final Workflow workflow;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final pequeno = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    return LayoutBuilder(builder: (context, limites) {
      final margem = ClasseDeJanela.de(limites.maxWidth).margemLateral;
      return ListView(padding: EdgeInsets.fromLTRB(margem, Espacos.esp3, margem, Espacos.esp5), children: [
        for (final c in caixasEmOrdem(workflow))
          Card(
            margin: const EdgeInsets.only(bottom: Espacos.esp2),
            child: Padding(
              padding: const EdgeInsets.all(Espacos.esp4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(iconeDaCaixa(c.tipo), size: 20, color: cores.onSurfaceVariant),
                  const SizedBox(width: Espacos.esp2),
                  Expanded(child: Text(c.rotulo, style: tema.textTheme.titleSmall)),
                  if (c.id == workflow.inicio)
                    Tooltip(
                      message: 'Início do workflow',
                      child: Icon(Symbols.play_circle, size: 20, color: cores.primary),
                    ),
                ]),
                Text([c.nomeDoTipo, if (c.detalhe.isNotEmpty) c.detalhe].join(' · '), style: pequeno),
                for (final a in workflow.arestas)
                  if (a.de == c.id)
                    Text('→ ${workflow.caixa(a.para)?.rotulo ?? a.para}${a.quando == null ? '' : ' (${a.quando})'}', style: pequeno),
              ]),
            ),
          ),
      ]);
    });
  }
}

class EdicaoDoGrafo {
  const EdicaoDoGrafo({
    required this.rascunho,
    required this.aoMover,
    required this.aoLigar,
    required this.aoDesligar,
    required this.aoTocarPonto,
    required this.aoSoltarTipo,
    required this.aoCriarDepois,
    required this.aoEditar,
    required this.aoDefinirInicio,
    required this.aoRemover,
    required this.aoDeslocar,
    required this.aoMoveu,
    required this.aoDesfazer,
    required this.aoRefazer,
  });

  final WorkflowJson rascunho;
  final void Function(String id, Ponto ponto) aoMover;
  final void Function(String de, String? quando, String? para) aoLigar;
  final ValueChanged<Aresta> aoDesligar;
  final void Function(String caixa, PontoDeSaida ponto, Offset global) aoTocarPonto;
  final void Function(String tipo, Ponto ponto) aoSoltarTipo;
  final void Function(String de, String? quando, String tipo) aoCriarDepois;
  final ValueChanged<String> aoEditar;
  final ValueChanged<String> aoDefinirInicio;
  final ValueChanged<String> aoRemover;
  final void Function(String id, double dx, double dy, String grupo) aoDeslocar;
  final ValueChanged<String> aoMoveu;
  final VoidCallback aoDesfazer;
  final VoidCallback aoRefazer;
}

String _nomeDaSaida(PontoDeSaida p) => p.varias ? 'Várias' : (p.rotulo.isEmpty ? 'Saída' : 'Saída "${p.rotulo}"');

List<Widget> itensDoMenuDaCaixa({
  required EdicaoDoGrafo ed,
  required String id,
  required ColorScheme cores,
  VoidCallback? aoMover,
  bool comEditar = true,
  FocusNode? primeiro,
}) {
  final r = ed.rascunho;
  if (caixaDe(r, id) == null) return const [];
  final pontos = pontosDeSaida(r, id);
  final livres = [for (final p in pontos) if (p.livre) p];
  final saindo = ligacoesQueSaem(r, id);
  String destino(String x) => '${rotuloNoRascunho(r, x)} (${nomesDeCaixa[caixaDe(r, x)?['tipo']] ?? 'caixa'})';
  List<Widget> destinos(PontoDeSaida p) => [
        for (final d in destinosDaSaida(r, id, p))
          MenuItemButton(onPressed: () => ed.aoLigar(id, p.quando, d), child: Text(destino(d))),
      ];
  List<Widget> tipos(PontoDeSaida p) => [
        for (final t in tiposDeCaixa)
          MenuItemButton(
            leadingIcon: Icon(iconeDaCaixa(t)),
            onPressed: () => ed.aoCriarDepois(id, p.quando, t),
            child: Text(nomesDeCaixa[t] ?? t),
          ),
      ];
  String ligacao(Aresta a) => '${rotuloNoRascunho(r, a.para)}${a.quando == null ? '' : ' (${a.quando})'}';
  return [
    if (comEditar)
      MenuItemButton(
        focusNode: primeiro,
        leadingIcon: const Icon(Symbols.edit),
        shortcut: const SingleActivator(LogicalKeyboardKey.enter),
        onPressed: () => ed.aoEditar(id),
        child: const Text('Editar caixa'),
      ),
    SubmenuButton(
      focusNode: comEditar ? null : primeiro,
      leadingIcon: const Icon(Symbols.link),
      menuChildren: pontos.length == 1
          ? destinos(pontos.single)
          : [for (final p in pontos) SubmenuButton(menuChildren: destinos(p), child: Text(_nomeDaSaida(p)))],
      child: const Text('Ligar a…'),
    ),
    if (saindo.length == 1)
      MenuItemButton(
        leadingIcon: const Icon(Symbols.link_off),
        onPressed: () => ed.aoDesligar(saindo.single),
        child: Text('Desfazer a ligação com ${ligacao(saindo.single)}'),
      )
    else if (saindo.length > 1)
      SubmenuButton(
        leadingIcon: const Icon(Symbols.link_off),
        menuChildren: [
          for (final a in saindo) MenuItemButton(onPressed: () => ed.aoDesligar(a), child: Text('Com ${ligacao(a)}')),
        ],
        child: const Text('Desfazer a ligação'),
      ),
    SubmenuButton(
      leadingIcon: const Icon(Symbols.add_link),
      menuChildren: livres.length == 1
          ? tipos(livres.single)
          : [for (final p in livres) SubmenuButton(menuChildren: tipos(p), child: Text(_nomeDaSaida(p)))],
      child: const Text('Criar caixa depois'),
    ),
    if (aoMover != null)
      MenuItemButton(leadingIcon: const Icon(Symbols.open_with), onPressed: aoMover, child: const Text('Mover')),
    MenuItemButton(
      leadingIcon: const Icon(Symbols.play_circle),
      onPressed: r['inicio'] == id ? null : () => ed.aoDefinirInicio(id),
      child: const Text('Definir como início'),
    ),
    const Divider(),
    MenuItemButton(
      leadingIcon: Icon(Symbols.delete, color: cores.error),
      style: MenuItemButton.styleFrom(foregroundColor: cores.error),
      shortcut: const SingleActivator(LogicalKeyboardKey.delete),
      onPressed: () => ed.aoRemover(id),
      child: const Text('Remover caixa'),
    ),
  ];
}

class CanvasDoGrafo extends StatefulWidget {
  const CanvasDoGrafo({
    super.key,
    required this.workflow,
    this.estados = const {},
    this.percorridas = const {},
    this.selecionada,
    this.aoTocar,
    this.erros = const {},
    this.edicao,
    this.aviso,
  });

  final Workflow workflow;
  final Map<String, String> estados;
  final Set<String> percorridas;
  final String? selecionada;
  final ValueChanged<String?>? aoTocar;
  final Map<String, List<String>> erros;
  final EdicaoDoGrafo? edicao;
  final String? aviso;

  Set<String> get comErro => {for (final k in erros.keys) if (k != lugarDoWorkflow) k};

  @override
  State<CanvasDoGrafo> createState() => EstadoDoCanvasDoGrafo();
}

enum _Gesto { fundo, caixa, ponto }

String _chaveDaAresta(Aresta a) => '${a.de}>${a.para}>${a.quando ?? ''}';

class EstadoDoCanvasDoGrafo extends State<CanvasDoGrafo> with PanEZoom {
  String? _ajustadaPara;
  _Gesto? _gesto;
  String? _alvo;
  int _indice = 0;
  Ponto _pega = (x: 0, y: 0);
  Ponto? _caixaEm;
  Ponto? _ponteiro;
  Offset? _pressionado;
  String? _linhaSobre;
  MouseCursor _cursor = SystemMouseCursors.grab;
  final _foco = FocusNode(debugLabel: 'canvas do grafo');
  final _menu = MenuController();
  final _primeiroItem = FocusNode(debugLabel: 'primeiro item do menu da caixa');
  final _focos = <String, FocusNode>{};
  String? _menuDe;
  bool _menuPeloTeclado = false;
  String? _movendo;
  Ponto? _pontoAntesDeMover;
  int _movimentos = 0;

  EdicaoDoGrafo? get _ed => widget.edicao;

  String get _chave =>
      '${widget.workflow.equipe}/${widget.workflow.id}${_ed == null ? '/${widget.workflow.versao}' : ''}';

  Map<String, Ponto> get _base => layoutDoGrafo(widget.workflow);

  Map<String, List<PontoDeSaida>> get _pontos => pontosDoRascunho(_ed?.rascunho ?? widget.workflow.bruto);

  @override
  void didUpdateWidget(CanvasDoGrafo oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = {for (final c in widget.workflow.nos) c.id};
    final sobras = [for (final id in _focos.keys) if (!ids.contains(id)) id];
    if (sobras.isNotEmpty) {
      final nos = [for (final id in sobras) _focos.remove(id)!];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final no in nos) {
          no.dispose();
        }
      });
    }
    if (_movendo != null && (!ids.contains(_movendo) || _ed == null)) {
      _movendo = null;
      _pontoAntesDeMover = null;
    }
    if (_menuDe != null && (!ids.contains(_menuDe) || _ed == null)) {
      _menuDe = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _menu.close());
    }
  }

  @override
  void dispose() {
    for (final no in _focos.values) {
      no.dispose();
    }
    _foco.dispose();
    _primeiroItem.dispose();
    super.dispose();
  }

  FocusNode _focoDe(String id) => _focos.putIfAbsent(id, () => FocusNode(debugLabel: 'caixa $id'));

  void ajustar() => setState(() => vista = ajustarVistaAoGrafo(_base, tamanho.width, tamanho.height));

  Ponto pontoNoCentro() {
    final m = paraMundo(v, tamanho.width / 2, tamanho.height / 2);
    return (x: m.x - margemDoGrafo - larguraDaCaixa / 2, y: m.y - margemDoGrafo - alturaDaCaixa / 2);
  }

  void centralizar(String id) {
    final layout = _base;
    if (!layout.containsKey(id)) return;
    final c = cantoDaCaixa(layout, id);
    setState(() => vista = (
          dx: tamanho.width / 2 - (c.x + larguraDaCaixa / 2) * v.escala,
          dy: tamanho.height / 2 - (c.y + alturaDaCaixa / 2) * v.escala,
          escala: v.escala,
        ));
  }

  void _mostrar(String id) => setState(() => vista = vistaComCaixa(v, _base, id, tamanho.width, tamanho.height));

  String _rotulo(String id) => widget.workflow.caixa(id)?.rotulo ?? id;

  Map<String, Ponto> _layout() {
    final base = _base;
    final id = _alvo;
    final em = _caixaEm;
    if (_gesto == _Gesto.caixa && id != null && em != null && base.containsKey(id)) return {...base, id: em};
    return base;
  }

  _Gesto _gestoEm(Ponto m, Map<String, Ponto> layout) {
    if (_ed == null) return _Gesto.fundo;
    if (saidaEm(layout, _pontos, m.x, m.y) != null) return _Gesto.ponto;
    return caixaEm(layout, m.x, m.y) != null ? _Gesto.caixa : _Gesto.fundo;
  }

  Aresta? _arestaEm(Map<String, Ponto> layout, Ponto m) =>
      arestaEm(widget.workflow.arestas, layout, _pontos, m.x, m.y, tolerancia: 6 / v.escala);

  void _aoPassar(PointerHoverEvent e) {
    final layout = _base;
    final m = paraMundo(v, e.localPosition.dx, e.localPosition.dy);
    if (_ed == null) {
      final cursor = widget.aoTocar != null && caixaEm(layout, m.x, m.y) != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.grab;
      if (cursor != _cursor) setState(() => _cursor = cursor);
      return;
    }
    final gesto = _gestoEm(m, layout);
    final linha = gesto == _Gesto.fundo ? _arestaEm(layout, m) : null;
    final cursor = switch (gesto) {
      _Gesto.ponto => SystemMouseCursors.precise,
      _Gesto.caixa => SystemMouseCursors.move,
      _Gesto.fundo => linha != null ? SystemMouseCursors.click : SystemMouseCursors.grab,
    };
    final chave = linha == null ? null : _chaveDaAresta(linha);
    if (cursor != _cursor || chave != _linhaSobre) {
      setState(() {
        _cursor = cursor;
        _linhaSobre = chave;
      });
    }
  }

  void comecarMovimento(String id) {
    final ed = _ed;
    if (ed == null || !_base.containsKey(id)) return;
    _terminarMovimento();
    setState(() {
      _movendo = id;
      _pontoAntesDeMover = _base[id];
      _movimentos++;
    });
    _focoDe(id).requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _movendo == id) _focoDe(id).requestFocus();
    });
  }

  void _passo(String id, double dx, double dy) {
    final ed = _ed;
    if (ed == null || _movendo != id) return;
    ed.aoDeslocar(id, dx * passoDeMover, dy * passoDeMover, 'mover/$id/$_movimentos');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mostrar(id);
    });
  }

  void _terminarMovimento() {
    final id = _movendo;
    final antes = _pontoAntesDeMover;
    if (id == null) return;
    setState(() {
      _movendo = null;
      _pontoAntesDeMover = null;
    });
    final depois = _base[id];
    if (antes != null && depois != null && antes != depois) _ed?.aoMoveu(id);
  }

  void _aoFocar(String id, bool focado) {
    if (!focado) return;
    if (_movendo != null && _movendo != id) _terminarMovimento();
    if (FocusManager.instance.highlightMode == FocusHighlightMode.traditional) _mostrar(id);
  }

  Offset _naTela(Ponto mundo) => Offset(mundo.x * v.escala + v.dx, mundo.y * v.escala + v.dy);

  void _abrirMenu(String id, Offset local, {bool teclado = false}) {
    if (_ed == null || !_base.containsKey(id)) return;
    _terminarMovimento();
    setState(() {
      _menuDe = id;
      _menuPeloTeclado = teclado;
    });
    _menu.open(position: local);
    if (teclado) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _primeiroItem.requestFocus();
      });
    }
  }

  void _abrirMenuDaCaixa(String id, {bool teclado = false}) {
    final c = cantoDaCaixa(_base, id);
    _abrirMenu(
      id,
      _naTela((x: c.x + larguraDaCaixa - _ladoDoBotaoDeMenu - Espacos.esp2, y: c.y + Espacos.esp1 + _ladoDoBotaoDeMenu)),
      teclado: teclado,
    );
  }

  void _aoFecharMenu() {
    final id = _menuDe;
    if (_menuPeloTeclado && id != null && _movendo == null && mounted) _focoDe(id).requestFocus();
    _menuPeloTeclado = false;
  }

  void _inicio(ScaleStartDetails d) {
    _terminarMovimento();
    final ponto = d.pointerCount == 1 && _pressionado != null ? _pressionado! : d.localFocalPoint;
    final m = paraMundo(v, ponto.dx, ponto.dy);
    comecarPinca();
    final layout = _base;
    final gesto = d.pointerCount > 1 || d.kind == PointerDeviceKind.trackpad ? _Gesto.fundo : _gestoEm(m, layout);
    setState(() {
      _gesto = gesto;
      _alvo = null;
      _caixaEm = null;
      _ponteiro = null;
      if (gesto == _Gesto.ponto) {
        final s = saidaEm(layout, _pontos, m.x, m.y)!;
        _alvo = s.caixa;
        _indice = s.indice;
        _ponteiro = m;
      } else if (gesto == _Gesto.caixa) {
        final id = caixaEm(layout, m.x, m.y)!;
        final c = cantoDaCaixa(layout, id);
        _alvo = id;
        _pega = (x: m.x - c.x, y: m.y - c.y);
      } else {
        _cursor = SystemMouseCursors.grabbing;
      }
    });
  }

  void _durante(ScaleUpdateDetails d) {
    final m = paraMundo(v, d.localFocalPoint.dx, d.localFocalPoint.dy);
    setState(() {
      switch (_gesto) {
        case _Gesto.caixa:
          _caixaEm = (x: m.x - _pega.x - margemDoGrafo, y: m.y - _pega.y - margemDoGrafo);
        case _Gesto.ponto:
          _ponteiro = m;
        case _Gesto.fundo || null:
          aplicarPinca(d);
      }
    });
  }

  void _fim(ScaleEndDetails _) {
    final gesto = _gesto;
    final id = _alvo;
    final em = _caixaEm;
    final ponteiro = _ponteiro;
    final indice = _indice;
    setState(() {
      _gesto = null;
      _alvo = null;
      _caixaEm = null;
      _ponteiro = null;
      _cursor = SystemMouseCursors.grab;
    });
    final ed = _ed;
    if (ed == null || id == null) return;
    if (gesto == _Gesto.caixa && em != null) ed.aoMover(id, em);
    if (gesto == _Gesto.ponto && ponteiro != null) {
      final pontos = _pontos[id] ?? const <PontoDeSaida>[];
      if (indice < pontos.length) ed.aoLigar(id, pontos[indice].quando, caixaEm(_base, ponteiro.x, ponteiro.y));
    }
  }

  void _toque(TapUpDetails d) {
    _terminarMovimento();
    final layout = _base;
    final m = paraMundo(v, d.localPosition.dx, d.localPosition.dy);
    final ed = _ed;
    if (ed != null) {
      final s = saidaEm(layout, _pontos, m.x, m.y);
      if (s != null) {
        ed.aoTocarPonto(s.caixa, _pontos[s.caixa]![s.indice], d.globalPosition);
        return;
      }
    }
    final caixa = caixaEm(layout, m.x, m.y);
    if (caixa != null) {
      _focoDe(caixa).requestFocus();
      widget.aoTocar?.call(caixa);
      return;
    }
    final linha = ed == null ? null : _arestaEm(layout, m);
    if (linha != null) {
      setState(() => _linhaSobre = null);
      ed!.aoDesligar(linha);
      return;
    }
    widget.aoTocar?.call(null);
  }

  void _toqueSecundario(TapUpDetails d) {
    final m = paraMundo(v, d.localPosition.dx, d.localPosition.dy);
    final caixa = caixaEm(_base, m.x, m.y);
    if (caixa == null) return;
    _focoDe(caixa).requestFocus();
    _abrirMenu(caixa, d.localPosition);
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    final ed = _ed;
    if (ed == null || e is KeyUpEvent) return KeyEventResult.ignored;
    final teclado = HardwareKeyboard.instance;
    final ctrl = teclado.isControlPressed || teclado.isMetaPressed;
    final tecla = e.logicalKey;
    if (ctrl && tecla == LogicalKeyboardKey.keyZ) {
      teclado.isShiftPressed ? ed.aoRefazer() : ed.aoDesfazer();
      return KeyEventResult.handled;
    }
    if (ctrl && tecla == LogicalKeyboardKey.keyY) {
      ed.aoRefazer();
      return KeyEventResult.handled;
    }
    final selecionada = widget.selecionada;
    if (e is KeyDownEvent &&
        selecionada != null &&
        (tecla == LogicalKeyboardKey.delete || tecla == LogicalKeyboardKey.backspace)) {
      ed.aoRemover(selecionada);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final w = widget.workflow;
    final ed = _ed;
    return LayoutBuilder(builder: (context, limites) {
      tamanho = limites.biggest;
      if (vista == null || _ajustadaPara != _chave) {
        vista = ajustarVistaAoGrafo(_base, tamanho.width, tamanho.height);
        _ajustadaPara = _chave;
      }
      final layout = _layout();
      final pontos = _pontos;
      final area = tamanhoDoGrafo(layout);
      final ligando = _gesto == _Gesto.ponto ? _alvo : null;
      final destino = ligando != null && _ponteiro != null ? caixaEm(layout, _ponteiro!.x, _ponteiro!.y) : null;
      final origemDoArrasto = ligando != null && layout.containsKey(ligando)
          ? pontoDaSaida(layout, ligando, _indice, pontos[ligando]?.length ?? 1)
          : null;
      final movendo = _movendo;
      final dica = movendo != null
          ? 'Movendo ${_rotulo(movendo)}: as setas deslocam a caixa, e Enter ou Esc termina.'
          : ed != null
              ? 'Arraste da paleta ou clique nela para criar · puxe um ponto de saída até outra caixa para ligar, ou clique '
                  'nele para criar a seguinte · clique numa linha para desfazer a ligação · Tab percorre as caixas e '
                  'Shift+F10 abre o menu da caixa · Delete remove · Ctrl+Z desfaz'
              : widget.aviso ?? 'Toque numa caixa para ver as saídas · arraste o fundo para mover · Ctrl + roda para zoom';
      Widget conteudo = Listener(
        onPointerSignal: rodar,
        onPointerDown: (e) {
          _pressionado = e.localPosition;
          if (_menu.isOpen) _menu.close();
          if (ed != null) _foco.requestFocus();
        },
        child: MouseRegion(
          cursor: _cursor,
          onHover: _aoPassar,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _toque,
            onSecondaryTapUp: ed == null ? null : _toqueSecundario,
            onScaleStart: _inicio,
            onScaleUpdate: _durante,
            onScaleEnd: _fim,
            child: ClipRect(
              child: Stack(children: [
                Positioned.fill(child: ColoredBox(color: cores.surface)),
                mundo(
                  largura: area.largura,
                  altura: area.altura,
                  child: MediaQuery.withNoTextScaling(
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _LigacoesDoGrafo(
                            arestas: w.arestas,
                            layout: layout,
                            pontos: pontos,
                            percorridas: widget.percorridas,
                            rotulosNasLinhas: ed == null,
                            linhaRealcada: _linhaSobre,
                            arrasto: origemDoArrasto == null || _ponteiro == null ? null : (origemDoArrasto, _ponteiro!),
                            cor: cores.outline,
                            realce: cores.primary,
                            fundo: cores.surface,
                            estilo: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant) ?? const TextStyle(),
                          ),
                        ),
                      ),
                      for (final c in w.nos)
                        if (layout.containsKey(c.id))
                          Positioned(
                            key: ValueKey('caixa-${c.id}'),
                            left: cantoDaCaixa(layout, c.id).x,
                            top: cantoDaCaixa(layout, c.id).y,
                            width: larguraDaCaixa,
                            height: alturaDaCaixa,
                            child: _No(
                              foco: _focoDe(c.id),
                              caixa: c,
                              inicio: c.id == w.inicio,
                              estado: widget.estados[c.id],
                              escolhida: widget.selecionada == c.id || destino == c.id,
                              erros: widget.erros[c.id] ?? const [],
                              erguida: (_gesto == _Gesto.caixa && _alvo == c.id) || movendo == c.id,
                              movendo: movendo == c.id,
                              comMenu: ed != null,
                              aoAtivar: () => widget.aoTocar?.call(c.id),
                              aoAbrirMenu: ed == null ? null : () => _abrirMenuDaCaixa(c.id, teclado: true),
                              aoRemover: ed == null ? null : () => ed.aoRemover(c.id),
                              aoMover: (dx, dy) => _passo(c.id, dx, dy),
                              aoTerminar: _terminarMovimento,
                              aoFocar: (focado) => _aoFocar(c.id, focado),
                            ),
                          ),
                      if (ed != null)
                        for (final MapEntry(key: id, value: lista) in pontos.entries)
                          if (layout.containsKey(id))
                            for (final (i, ponto) in lista.indexed)
                              ..._pontoDeSaida(tema, pontoDaSaida(layout, id, i, lista.length), ponto),
                    ]),
                  ),
                ),
                if (ed != null)
                  mundo(
                    largura: area.largura,
                    altura: area.altura,
                    interativo: true,
                    child: _BotoesDeMenu(workflow: w, layout: layout, aoAbrir: _abrirMenuDaCaixa),
                  ),
                Positioned(
                  left: Espacos.esp3,
                  right: Espacos.esp3,
                  bottom: Espacos.esp3,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(child: _Dica(texto: dica, icone: ed == null && widget.aviso != null ? Symbols.info : null)),
                    const SizedBox(width: Espacos.esp3),
                    controlesDeZoom(aoAjustar: ajustar),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
      final menuDe = _menuDe;
      conteudo = FocusTraversalGroup(
        child: MenuAnchor(
          controller: _menu,
          onClose: _aoFecharMenu,
          menuChildren: ed == null || menuDe == null
              ? const []
              : itensDoMenuDaCaixa(
                  ed: ed,
                  id: menuDe,
                  cores: cores,
                  primeiro: _primeiroItem,
                  aoMover: () => comecarMovimento(menuDe),
                ),
          child: conteudo,
        ),
      );
      if (ed == null) return conteudo;
      conteudo = Focus(focusNode: _foco, onKeyEvent: _tecla, child: conteudo);
      return DragTarget<String>(
        onWillAcceptWithDetails: (d) => tiposDeCaixa.contains(d.data),
        onAcceptWithDetails: (d) {
          final caixa = context.findRenderObject();
          if (caixa is! RenderBox) return;
          final local = caixa.globalToLocal(d.offset);
          final m = paraMundo(v, local.dx, local.dy);
          ed.aoSoltarTipo(d.data, (x: m.x - margemDoGrafo - larguraDaCaixa / 2, y: m.y - margemDoGrafo - alturaDaCaixa / 2));
        },
        builder: (context, candidatos, _) => candidatos.isEmpty
            ? conteudo
            : DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(border: Border.all(color: cores.primary, width: 2)),
                child: conteudo,
              ),
      );
    });
  }

  List<Widget> _pontoDeSaida(ThemeData tema, Ponto centro, PontoDeSaida ponto) {
    final cores = tema.colorScheme;
    return [
      Positioned(
        left: centro.x - raioDoPonto,
        top: centro.y - raioDoPonto,
        child: Container(
          width: raioDoPonto * 2,
          height: raioDoPonto * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ponto.livre ? cores.surface : cores.primary,
            border: Border.all(color: cores.primary, width: 2),
          ),
        ),
      ),
      if (ponto.rotulo.isNotEmpty || ponto.varias)
        Positioned(
          left: centro.x + raioDoPonto + Espacos.esp1,
          top: centro.y - raioDoPonto - Espacos.esp3,
          child: Text(
            ponto.varias ? 'várias' : ponto.rotulo,
            style: tema.textTheme.labelMedium?.copyWith(color: cores.primary),
          ),
        ),
    ];
  }
}

class _Dica extends StatelessWidget {
  const _Dica({required this.texto, this.icone});

  final String texto;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.onSurfaceVariant;
    return Row(children: [
      if (icone != null) ...[
        Icon(icone, size: 20, color: cor),
        const SizedBox(width: Espacos.esp2),
      ],
      Flexible(child: Text(texto, style: tema.textTheme.bodySmall?.copyWith(color: cor))),
    ]);
  }
}

class _BotoesDeMenu extends StatelessWidget {
  const _BotoesDeMenu({required this.workflow, required this.layout, required this.aoAbrir});

  final Workflow workflow;
  final Map<String, Ponto> layout;
  final void Function(String id) aoAbrir;

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        for (final c in workflow.nos)
          if (layout.containsKey(c.id))
            Positioned(
              key: ValueKey(c.id),
              left: cantoDaCaixa(layout, c.id).x + larguraDaCaixa - _ladoDoBotaoDeMenu - Espacos.esp2,
              top: cantoDaCaixa(layout, c.id).y + Espacos.esp1,
              width: _ladoDoBotaoDeMenu,
              height: _ladoDoBotaoDeMenu,
              child: ExcludeFocus(
                child: IconButton(
                  tooltip: 'Mais opções de ${c.rotulo}',
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(_ladoDoBotaoDeMenu),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => aoAbrir(c.id),
                  icon: const Icon(Symbols.more_vert),
                ),
              ),
            ),
      ]);
}

class _AbrirMenuIntent extends Intent {
  const _AbrirMenuIntent();
}

class _RemoverIntent extends Intent {
  const _RemoverIntent();
}

class _MoverIntent extends Intent {
  const _MoverIntent(this.dx, this.dy);

  final double dx;
  final double dy;
}

class _TerminarIntent extends Intent {
  const _TerminarIntent();
}

class _No extends StatefulWidget {
  const _No({
    required this.foco,
    required this.caixa,
    required this.inicio,
    required this.estado,
    required this.escolhida,
    required this.erros,
    required this.erguida,
    required this.movendo,
    required this.comMenu,
    required this.aoAtivar,
    this.aoAbrirMenu,
    this.aoRemover,
    required this.aoMover,
    required this.aoTerminar,
    required this.aoFocar,
  });

  final FocusNode foco;
  final Caixa caixa;
  final bool inicio;
  final String? estado;
  final bool escolhida;
  final List<String> erros;
  final bool erguida;
  final bool movendo;
  final bool comMenu;
  final VoidCallback aoAtivar;
  final VoidCallback? aoAbrirMenu;
  final VoidCallback? aoRemover;
  final void Function(double dx, double dy) aoMover;
  final VoidCallback aoTerminar;
  final ValueChanged<bool> aoFocar;

  @override
  State<_No> createState() => _NoState();
}

class _NoState extends State<_No> {
  bool _realce = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return FocusableActionDetector(
      focusNode: w.foco,
      onShowFocusHighlight: (realce) => setState(() => _realce = realce),
      onFocusChange: w.aoFocar,
      shortcuts: {
        if (w.aoAbrirMenu != null) ...{
          const SingleActivator(LogicalKeyboardKey.f10, shift: true): const _AbrirMenuIntent(),
          const SingleActivator(LogicalKeyboardKey.contextMenu): const _AbrirMenuIntent(),
        },
        if (w.aoRemover != null && !w.movendo) ...{
          const SingleActivator(LogicalKeyboardKey.delete): const _RemoverIntent(),
          const SingleActivator(LogicalKeyboardKey.backspace): const _RemoverIntent(),
        },
        if (w.movendo) ...{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): const _MoverIntent(-1, 0),
          const SingleActivator(LogicalKeyboardKey.arrowRight): const _MoverIntent(1, 0),
          const SingleActivator(LogicalKeyboardKey.arrowUp): const _MoverIntent(0, -1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): const _MoverIntent(0, 1),
          const SingleActivator(LogicalKeyboardKey.enter): const _TerminarIntent(),
          const SingleActivator(LogicalKeyboardKey.escape): const _TerminarIntent(),
        },
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          w.aoAtivar();
          return null;
        }),
        _AbrirMenuIntent: CallbackAction<_AbrirMenuIntent>(onInvoke: (_) {
          w.aoAbrirMenu?.call();
          return null;
        }),
        _RemoverIntent: CallbackAction<_RemoverIntent>(onInvoke: (_) {
          w.aoRemover?.call();
          return null;
        }),
        _MoverIntent: CallbackAction<_MoverIntent>(onInvoke: (i) {
          w.aoMover(i.dx, i.dy);
          return null;
        }),
        _TerminarIntent: CallbackAction<_TerminarIntent>(onInvoke: (_) {
          w.aoTerminar();
          return null;
        }),
      },
      child: Semantics(
        button: true,
        selected: w.escolhida,
        child: _CaixaDoGrafo(
          caixa: w.caixa,
          inicio: w.inicio,
          estado: w.estado,
          escolhida: w.escolhida,
          focada: _realce || w.movendo,
          erguida: w.erguida,
          comMenu: w.comMenu,
          erros: w.erros,
        ),
      ),
    );
  }
}

class _CaixaDoGrafo extends StatelessWidget {
  const _CaixaDoGrafo({
    required this.caixa,
    required this.inicio,
    required this.estado,
    required this.escolhida,
    this.focada = false,
    this.erguida = false,
    this.comMenu = false,
    this.erros = const [],
  });

  final Caixa caixa;
  final bool inicio;
  final String? estado;
  final bool escolhida;
  final bool focada;
  final bool erguida;
  final bool comMenu;
  final List<String> erros;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final ativa = estado == 'esperando' || estado == 'parada';
    final corAtiva = ativa ? corDoEstado(context, estado) : null;
    final destaque = escolhida || focada;
    final comErro = erros.isNotEmpty;
    final borda = destaque ? cores.primary : (comErro ? cores.error : corAtiva ?? cores.outlineVariant);
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espacos.esp3, vertical: Espacos.esp2),
      decoration: BoxDecoration(
        color: cores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Raios.md),
        border: Border.all(color: borda, width: destaque || comErro || ativa ? 2 : 1),
        boxShadow: erguida ? kElevationToShadow[4] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(iconeDaCaixa(caixa.tipo), size: 20, color: corAtiva ?? cores.onSurfaceVariant),
          const SizedBox(width: Espacos.esp2),
          Expanded(
            child: Text(
              caixa.rotulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.titleSmall?.copyWith(fontWeight: ativa ? FontWeight.w600 : null),
            ),
          ),
          if (inicio)
            Tooltip(message: 'Início do workflow', child: Icon(Symbols.play_circle, size: 16, color: cores.primary)),
          if (comMenu) const SizedBox(width: Espacos.esp5),
        ]),
        Text(
          [caixa.nomeDoTipo, if (caixa.detalhe.isNotEmpty) caixa.detalhe].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: secundario,
        ),
        const Spacer(),
        if (comErro)
          Tooltip(
            message: erros.join('\n'),
            child: Row(children: [
              Icon(Symbols.error, size: 16, color: cores.error),
              const SizedBox(width: Espacos.esp1),
              Expanded(
                child: Text(
                  erros.length == 1 ? erros.single : '${erros.first} (+${erros.length - 1})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.labelMedium?.copyWith(color: cores.error),
                ),
              ),
            ]),
          )
        else if (estado case final e?)
          RotuloDeEstado(estado: e, rotulo: nomesDeStatusDaFicha[e] ?? e),
      ]),
    );
  }
}

class _LigacoesDoGrafo extends CustomPainter {
  _LigacoesDoGrafo({
    required this.arestas,
    required this.layout,
    required this.pontos,
    required this.percorridas,
    required this.rotulosNasLinhas,
    required this.linhaRealcada,
    required this.arrasto,
    required this.cor,
    required this.realce,
    required this.fundo,
    required this.estilo,
  });

  final List<Aresta> arestas;
  final Map<String, Ponto> layout;
  final Map<String, List<PontoDeSaida>> pontos;
  final Set<String> percorridas;
  final bool rotulosNasLinhas;
  final String? linhaRealcada;
  final (Ponto, Ponto)? arrasto;
  final Color cor;
  final Color realce;
  final Color fundo;
  final TextStyle estilo;

  Offset _o(Ponto p) => Offset(p.x, p.y);

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in arestas) {
      if (!layout.containsKey(a.de) || !layout.containsKey(a.para)) continue;
      final curva = curvaDaLigacao(layout, origemDaLigacao(layout, pontos, a), a.para);
      final destacada = percorridas.contains(a.chave) || _chaveDaAresta(a) == linhaRealcada;
      final tinta = Paint()
        ..color = destacada ? realce : cor
        ..strokeWidth = destacada ? 3 : 1.5
        ..style = PaintingStyle.stroke;
      final p0 = _o(curva.p0), p1 = _o(curva.p1), p2 = _o(curva.p2), p3 = _o(curva.p3);
      canvas.drawPath(
        Path()
          ..moveTo(p0.dx, p0.dy)
          ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy),
        tinta,
      );
      final direcao = p3 - p2;
      final unidade = direcao.distance == 0 ? const Offset(1, 0) : direcao / direcao.distance;
      final normal = Offset(-unidade.dy, unidade.dx);
      final ponta = Path()
        ..moveTo(p3.dx, p3.dy)
        ..lineTo((p3 - unidade * 9 + normal * 4.5).dx, (p3 - unidade * 9 + normal * 4.5).dy)
        ..lineTo((p3 - unidade * 9 - normal * 4.5).dx, (p3 - unidade * 9 - normal * 4.5).dy)
        ..close();
      canvas.drawPath(ponta, Paint()..color = tinta.color);
      final quando = a.quando;
      if (quando == null || !rotulosNasLinhas) continue;
      final meio = _o(pontoNaCurva(curva, 0.5));
      final pintor = TextPainter(
        text: TextSpan(text: quando, style: destacada ? estilo.copyWith(color: realce) : estilo),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 140);
      final caixa = Rect.fromCenter(
        center: meio,
        width: pintor.width + Espacos.esp2,
        height: pintor.height + Espacos.esp1,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(caixa, const Radius.circular(Raios.xs)), Paint()..color = fundo);
      pintor.paint(canvas, Offset(caixa.left + Espacos.esp1, caixa.top + Espacos.esp1 / 2));
    }
    if (arrasto case (final de, final ate)) {
      canvas.drawLine(
        _o(de),
        _o(ate),
        Paint()
          ..color = realce
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LigacoesDoGrafo antigo) => true;
}
