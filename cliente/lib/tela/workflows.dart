import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../estado/sala.dart';
import '../estado/workflows.dart';
import '../nucleo/editor_de_workflow.dart';
import '../nucleo/organograma.dart' show paraMundo;
import '../nucleo/painel.dart' show haQuanto;
import '../nucleo/tarefas.dart';
import '../nucleo/workflows.dart';
import 'canvas.dart';
import 'equipes.dart' show confirmar, pedirTexto, quandoCurto;
import 'importacao.dart';

Color corDaFicha(String? status, ColorScheme cores) => switch (status) {
      'concluida' => const Color(0xFF4FAE7C),
      'esperando' => const Color(0xFF9A6EE8),
      'cancelada' => const Color(0xFF8B93A7),
      _ => cores.outlineVariant,
    };

Color corDoFluxo(String status, ColorScheme cores) => switch (status) {
      'rodando' => const Color(0xFFE0A458),
      'esperando' => const Color(0xFF5B8DEF),
      'concluido' => const Color(0xFF4FAE7C),
      'falhou' => cores.error,
      _ => const Color(0xFF8B93A7),
    };

Future<void> cancelarFluxo(BuildContext context, EstadoWorkflows estado, int fluxo, String nome) async {
  final ok = await confirmar(
    context,
    'Cancelar o workflow $nome (#$fluxo)?',
    'As caixas e as tarefas abertas dele são canceladas. O que já foi feito fica registrado.',
  );
  if (ok) estado.cancelar(fluxo);
}

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
    final cores = Theme.of(context).colorScheme;
    final rotulo = TextStyle(color: cores.onSurfaceVariant, fontSize: 11, letterSpacing: 1);
    final daEquipe = estado.daEquipe(equipe.id);
    final encerrados = estado.encerrados(equipe.id);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
      Row(children: [
        Expanded(child: Text('WORKFLOWS · ${equipe.nome.toUpperCase()}', style: rotulo)),
        if (editar) ...[
          OutlinedButton.icon(
            onPressed: () => importarModelo(context, sala, destino: equipe.id),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Importar workflow…'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () => _novo(context),
            icon: const Icon(Icons.add),
            label: const Text('Novo workflow'),
          ),
        ],
        IconButton(tooltip: 'Recarregar', icon: const Icon(Icons.refresh), onPressed: estado.carregar),
      ]),
      if (!estado.carregada)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (daEquipe.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            editar
                ? 'Nenhum workflow nesta equipe. Use "Novo workflow" para montar o primeiro.'
                : 'Nenhum workflow nesta equipe. Eles ficam em equipes/${equipe.id}/workflows/ na pasta de dados.',
            style: TextStyle(color: cores.onSurfaceVariant),
          ),
        ),
      for (final w in daEquipe) _CartaoDoWorkflow(sala: sala, equipe: equipe, workflow: w, editar: editar),
      if (encerrados.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text('ENCERRADOS (${encerrados.length})', style: rotulo),
            children: [for (final f in encerrados) _LinhaDoFluxo(sala: sala, fluxo: f, comNome: true)],
          ),
        ),
    ]);
  }
}

class _CartaoDoWorkflow extends StatelessWidget {
  const _CartaoDoWorkflow({required this.sala, required this.equipe, required this.workflow, required this.editar});

  final Sala sala;
  final EquipeResumo equipe;
  final Workflow workflow;
  final bool editar;

  @override
  Widget build(BuildContext context) {
    final estado = sala.workflows;
    final cores = Theme.of(context).colorScheme;
    final w = workflow;
    final abertos = estado.abertos(w.equipe, w.id);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(w.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            [
              'versão ${w.versao}',
              '${w.nos.length} ${w.nos.length == 1 ? 'caixa' : 'caixas'}',
              if (w.entrada.isNotEmpty) 'entrada: ${w.entrada.keys.join(', ')}',
              if (abertos.isNotEmpty) '${abertos.length} ${abertos.length == 1 ? 'aberto' : 'abertos'}',
            ].join(' · '),
            style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.tonalIcon(
                onPressed: () => abrirIniciarWorkflow(context, estado, w),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Iniciar'),
              ),
              OutlinedButton.icon(
                onPressed: () => estado.verDefinicao(w),
                icon: const Icon(Icons.alt_route, size: 18),
                label: const Text('Ver'),
              ),
              if (editar) ...[
                OutlinedButton.icon(
                  onPressed: () => sala.editorDeWorkflow.abrir(w, equipe),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => sala.editorDeWorkflow.duplicar(w, equipe, estado.daEquipe(equipe.id).map((x) => x.id)),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Duplicar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => exportarWorkflowComoModelo(context, sala, equipe.id, w.id),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Exportar como modelo…'),
                ),
              ],
            ]),
          ),
          for (final f in abertos) _LinhaDoFluxo(sala: sala, fluxo: f),
        ]),
      ),
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
    final cores = Theme.of(context).colorScheme;
    final f = fluxo;
    final ativas = [
      for (final ficha in f.fichas)
        if (ficha.esperando) f.definicao.caixa(ficha.no)?.rotulo ?? ficha.no,
    ];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(backgroundColor: corDoFluxo(f.status, cores), radius: 6),
      title: Text([
        if (comNome) f.nome,
        '#${f.id}',
        nomesDeStatusDoFluxo[f.status] ?? f.status,
        haQuanto(f.criadoEm, DateTime.now()),
      ].where((p) => p.isNotEmpty).join(' · ')),
      subtitle: Text(
        f.aberto
            ? (ativas.isEmpty ? 'nenhuma caixa esperando' : 'em: ${ativas.join(', ')}')
            : f.erro ?? f.resultado ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
      ),
      trailing: f.aberto
          ? IconButton(
              tooltip: 'Cancelar',
              icon: const Icon(Icons.cancel_outlined),
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
    final cores = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Iniciar ${w.nome}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (w.entrada.isEmpty)
              Text('Este workflow não pede entrada.', style: TextStyle(color: cores.onSurfaceVariant)),
            for (final MapEntry(:key, :value) in w.entrada.entries)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: _campo(key, value)),
            for (final erro in _erros) Text(erro, style: TextStyle(color: cores.error, fontSize: 12)),
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
    final cores = Theme.of(context).colorScheme;
    final pequeno = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    final w = estado.definicaoVista;
    final f = estado.fluxoVisto;
    final caixa = estado.caixa == null ? null : w?.caixa(estado.caixa!);
    final cabecalho = Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(children: [
        IconButton(tooltip: 'Voltar', icon: const Icon(Icons.arrow_back), onPressed: aoVoltar ?? estado.fecharGrafo),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w?.nome ?? 'Workflow', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            Text(
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
          ]),
        ),
        if (f != null && f.aberto)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cores.error),
            onPressed: () => cancelarFluxo(context, estado, f.id, f.nome),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Cancelar'),
          )
        else if (f == null && w != null)
          FilledButton.tonalIcon(
            onPressed: () => abrirIniciarWorkflow(context, estado, w),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Iniciar'),
          ),
      ]),
    );
    final extras = [
      if (f != null && f.entrada.isNotEmpty) 'entrada: ${resumoDasSaidas(f.entrada)}',
      if (f?.resultado case final r?) 'resultado: $r',
      if (f?.erro case final e?) 'erro: $e',
    ];
    final Widget corpo;
    if (w == null) {
      corpo = Center(
        child: estado.carregada
            ? Text('Workflow não encontrado.', style: TextStyle(color: cores.onSurfaceVariant))
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
      corpo = caixa == null
          ? grafo
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: grafo),
              const VerticalDivider(width: 1),
              SizedBox(width: 340, child: _DetalheDaCaixa(sala: sala, caixa: caixa, fluxo: f)),
            ]);
    } else {
      corpo = f == null ? _CaixasEmLista(workflow: w) : _CaminhoEmLista(sala: sala, fluxo: f);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      cabecalho,
      for (final e in extras)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(e, maxLines: 3, overflow: TextOverflow.ellipsis, style: pequeno),
        ),
      const Divider(height: 1),
      Expanded(child: corpo),
    ]);
  }
}

class _DetalheDaCaixa extends StatelessWidget {
  const _DetalheDaCaixa({required this.sala, required this.caixa, required this.fluxo});

  final Sala sala;
  final Caixa caixa;
  final Fluxo? fluxo;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final pequeno = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    final fichas = [for (final f in fluxo?.fichas ?? const <Ficha>[]) if (f.no == caixa.id) f]
      ..sort((a, b) => b.id.compareTo(a.id));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text(caixa.rotulo, style: Theme.of(context).textTheme.titleSmall)),
        IconButton(tooltip: 'Fechar', icon: const Icon(Icons.close), onPressed: () => sala.workflows.selecionarCaixa(null)),
      ]),
      Text(
        [caixa.nomeDoTipo, if (caixa.detalhe.isNotEmpty) caixa.detalhe, if (caixa.prazo case final p?) 'prazo $p'].join(' · '),
        style: pequeno,
      ),
      if (fluxo == null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Abra um fluxo para ver as saídas desta caixa.', style: pequeno),
        )
      else if (fichas.isEmpty)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text('O fluxo não passou por esta caixa.', style: pequeno)),
      for (final ficha in fichas) ...[
        const Divider(height: 24),
        Row(children: [
          CircleAvatar(backgroundColor: corDaFicha(ficha.status, cores), radius: 6),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                'ficha #${ficha.id}',
                nomesDeStatusDaFicha[ficha.status] ?? ficha.status,
                if (ficha.concluidaEm ?? ficha.criadaEm case final em?) quandoCurto(em),
              ].join(' · '),
              style: pequeno,
            ),
          ),
          if (ficha.tarefa case final t?)
            TextButton(onPressed: () => sala.abrirTarefa(t), child: Text('#$t')),
        ]),
        if (ficha.saidas.isEmpty)
          Text(ficha.esperando ? 'esperando…' : 'sem saídas', style: pequeno)
        else
          for (final MapEntry(:key, :value) in ficha.saidas.entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(key, style: pequeno),
                SelectableText(formatarValor(value)),
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
    final cores = Theme.of(context).colorScheme;
    final passos = ordemDoCaminho(fluxo);
    if (passos.isEmpty) {
      return Center(child: Text('Nenhuma caixa ainda.', style: TextStyle(color: cores.onSurfaceVariant)));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
      for (final p in passos)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: p.destacado ? corDaFicha('esperando', cores).withValues(alpha: 0.16) : null,
          shape: p.destacado
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: corDaFicha('esperando', cores)),
                )
              : null,
          child: ListTile(
            leading: CircleAvatar(backgroundColor: corDaFicha(p.status, cores), radius: 7),
            title: Text(p.titulo),
            subtitle: Text(
              [
                nomesDeCaixa[p.tipo] ?? p.tipo,
                nomesDeStatusDaFicha[p.status] ?? p.status,
                if (p.tarefa case final t?) '#$t',
                if (p.resumo.isNotEmpty) p.resumo,
              ].join(' · '),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
            ),
            onTap: p.tarefa == null ? null : () => sala.abrirTarefa(p.tarefa!),
          ),
        ),
    ]);
  }
}

class _CaixasEmLista extends StatelessWidget {
  const _CaixasEmLista({required this.workflow});

  final Workflow workflow;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final pequeno = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
      for (final c in caixasEmOrdem(workflow))
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (c.id == workflow.inicio)
                  Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.play_arrow, size: 16, color: cores.primary)),
                Expanded(child: Text(c.rotulo, style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
              Text([c.nomeDoTipo, if (c.detalhe.isNotEmpty) c.detalhe].join(' · '), style: pequeno),
              for (final a in workflow.arestas)
                if (a.de == c.id)
                  Text('→ ${workflow.caixa(a.para)?.rotulo ?? a.para}${a.quando == null ? '' : ' (${a.quando})'}', style: pequeno),
            ]),
          ),
        ),
    ]);
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
    required this.aoMenuDaCaixa,
    required this.aoRemover,
    required this.aoDesfazer,
    required this.aoRefazer,
  });

  final WorkflowJson rascunho;
  final void Function(String id, Ponto ponto) aoMover;
  final void Function(String de, String? quando, String? para) aoLigar;
  final ValueChanged<Aresta> aoDesligar;
  final void Function(String caixa, PontoDeSaida ponto, Offset global) aoTocarPonto;
  final void Function(String tipo, Ponto ponto) aoSoltarTipo;
  final void Function(String caixa, Offset global) aoMenuDaCaixa;
  final VoidCallback aoRemover;
  final VoidCallback aoDesfazer;
  final VoidCallback aoRefazer;
}

const iconesDeCaixa = {
  'executar': Icons.engineering_outlined,
  'revisar': Icons.rate_review_outlined,
  'aprovar': Icons.verified_outlined,
  'board': Icons.groups_outlined,
  'decisao_humana': Icons.help_outline,
  'condicao': Icons.call_split,
  'paralelo': Icons.device_hub,
  'juncao': Icons.merge_type,
  'laco': Icons.loop,
  'espera': Icons.hourglass_empty,
  'fim': Icons.flag_outlined,
};

class CanvasDoGrafo extends StatefulWidget {
  const CanvasDoGrafo({
    super.key,
    required this.workflow,
    this.estados = const {},
    this.percorridas = const {},
    this.selecionada,
    this.aoTocar,
    this.comErro = const {},
    this.edicao,
  });

  final Workflow workflow;
  final Map<String, String> estados;
  final Set<String> percorridas;
  final String? selecionada;
  final ValueChanged<String?>? aoTocar;
  final Set<String> comErro;
  final EdicaoDoGrafo? edicao;

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

  EdicaoDoGrafo? get _ed => widget.edicao;

  String get _chave =>
      '${widget.workflow.equipe}/${widget.workflow.id}${_ed == null ? '/${widget.workflow.versao}' : ''}';

  Map<String, Ponto> get _base => layoutDoGrafo(widget.workflow);

  Map<String, List<PontoDeSaida>> get _pontos => pontosDoRascunho(_ed?.rascunho ?? widget.workflow.bruto);

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

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
    if (_ed == null) return;
    final layout = _base;
    final m = paraMundo(v, e.localPosition.dx, e.localPosition.dy);
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

  void _inicio(ScaleStartDetails d) {
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
    final ed = _ed;
    if (ed == null) return;
    final m = paraMundo(v, d.localPosition.dx, d.localPosition.dy);
    final caixa = caixaEm(_base, m.x, m.y);
    if (caixa != null) ed.aoMenuDaCaixa(caixa, d.globalPosition);
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
    if (e is KeyDownEvent && (tecla == LogicalKeyboardKey.delete || tecla == LogicalKeyboardKey.backspace)) {
      ed.aoRemover();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
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
      Widget conteudo = Listener(
        onPointerSignal: rodar,
        onPointerDown: (e) {
          _pressionado = e.localPosition;
          if (ed != null) _foco.requestFocus();
        },
        child: MouseRegion(
          cursor: ed == null ? MouseCursor.defer : _cursor,
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
                Positioned.fill(child: ColoredBox(color: cores.surfaceContainerLowest)),
                mundo(
                  largura: area.largura,
                  altura: area.altura,
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
                          fundo: cores.surfaceContainerLowest,
                          texto: cores.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final c in w.nos)
                      if (layout.containsKey(c.id))
                        Positioned(
                          left: cantoDaCaixa(layout, c.id).x,
                          top: cantoDaCaixa(layout, c.id).y,
                          width: larguraDaCaixa,
                          height: alturaDaCaixa,
                          child: _CaixaDoGrafo(
                            caixa: c,
                            inicio: c.id == w.inicio,
                            estado: widget.estados[c.id],
                            escolhida: widget.selecionada == c.id || destino == c.id,
                            comErro: widget.comErro.contains(c.id),
                          ),
                        ),
                    if (ed != null)
                      for (final MapEntry(key: id, value: lista) in pontos.entries)
                        if (layout.containsKey(id))
                          for (final (i, ponto) in lista.indexed) ..._pontoDeSaida(cores, pontoDaSaida(layout, id, i, lista.length), ponto),
                  ]),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  right: 260,
                  child: Text(
                    ed == null
                        ? 'Toque numa caixa para ver as saídas · arraste o fundo para mover · Ctrl + roda para zoom'
                        : 'Arraste da paleta ou clique nela para criar · puxe um ponto de saída até outra caixa para ligar, '
                            'ou clique nele para criar a seguinte · clique numa linha para desligar · botão direito na caixa abre o menu · '
                            'Delete remove · Ctrl+Z desfaz',
                    style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
                  ),
                ),
                Positioned(right: 12, bottom: 12, child: controlesDeZoom(aoAjustar: ajustar)),
              ]),
            ),
          ),
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

  List<Widget> _pontoDeSaida(ColorScheme cores, Ponto centro, PontoDeSaida ponto) => [
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
            left: centro.x + raioDoPonto + 2,
            top: centro.y - 15,
            child: Text(
              ponto.varias ? 'várias' : ponto.rotulo,
              style: TextStyle(color: cores.primary, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
      ];
}

class _CaixaDoGrafo extends StatelessWidget {
  const _CaixaDoGrafo({
    required this.caixa,
    required this.inicio,
    required this.estado,
    required this.escolhida,
    this.comErro = false,
  });

  final Caixa caixa;
  final bool inicio;
  final String? estado;
  final bool escolhida;
  final bool comErro;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final cor = estado == null ? null : corDaFicha(estado, cores);
    final borda = escolhida ? cores.primary : (comErro ? cores.error : cor ?? cores.outlineVariant);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: cor == null ? cores.surfaceContainerHighest : Color.alphaBlend(cor.withValues(alpha: 0.22), cores.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(caixa.tipo == 'condicao' || caixa.tipo == 'decisao_humana' ? 18 : 8),
        border: Border.all(color: borda, width: escolhida || comErro || cor != null ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          if (inicio) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.play_arrow, size: 14, color: cores.primary)),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(iconesDeCaixa[caixa.tipo] ?? Icons.crop_square, size: 12, color: cores.onSurfaceVariant),
          ),
          Expanded(
            child: Text(
              caixa.nomeDoTipo.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cores.onSurfaceVariant, fontSize: 10, letterSpacing: 0.8),
            ),
          ),
          if (comErro) Icon(Icons.error_outline, size: 14, color: cores.error),
          if (estado case final e?)
            Text(nomesDeStatusDaFicha[e] ?? e, style: TextStyle(color: cor, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
        Text(caixa.rotulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (caixa.detalhe.isNotEmpty)
          Text(caixa.detalhe, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11)),
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
    required this.texto,
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
  final Color texto;

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
        text: TextSpan(text: quando, style: TextStyle(color: destacada ? realce : texto, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 140);
      final caixa = Rect.fromCenter(center: meio, width: pintor.width + 8, height: pintor.height + 4);
      canvas.drawRRect(RRect.fromRectAndRadius(caixa, const Radius.circular(4)), Paint()..color = fundo);
      pintor.paint(canvas, Offset(caixa.left + 4, caixa.top + 2));
    }
    final (de, ate) = arrasto ?? ((x: 0.0, y: 0.0), (x: 0.0, y: 0.0));
    if (arrasto != null) {
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
