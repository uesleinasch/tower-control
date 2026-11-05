import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../estado/sala.dart';
import '../estado/workflows.dart';
import '../nucleo/organograma.dart' show Vista, deslocarVista, paraMundo, zoomEm;
import '../nucleo/painel.dart' show haQuanto;
import '../nucleo/tarefas.dart';
import '../nucleo/workflows.dart';
import 'equipes.dart' show ControlesDeZoom, confirmar, quandoCurto;

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

Future<void> abrirIniciarWorkflow(BuildContext context, EstadoWorkflows estado, Workflow w) => showDialog<void>(
      context: context,
      builder: (_) => _DialogoDeIniciar(estado: estado, workflow: w),
    );

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
          return _ListaDeWorkflows(sala: sala, equipe: equipe);
        },
      );
}

class _ListaDeWorkflows extends StatelessWidget {
  const _ListaDeWorkflows({required this.sala, required this.equipe});

  final Sala sala;
  final EquipeResumo equipe;

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
        IconButton(tooltip: 'Recarregar', icon: const Icon(Icons.refresh), onPressed: estado.carregar),
      ]),
      if (!estado.carregada)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (daEquipe.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Nenhum workflow nesta equipe. Eles ficam em equipes/${equipe.id}/workflows/ na pasta de dados.',
            style: TextStyle(color: cores.onSurfaceVariant),
          ),
        ),
      for (final w in daEquipe) _CartaoDoWorkflow(sala: sala, workflow: w),
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
  const _CartaoDoWorkflow({required this.sala, required this.workflow});

  final Sala sala;
  final Workflow workflow;

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
      Navigator.pop(context);
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
  const _VistaDoGrafo({required this.sala, required this.desenhar});

  final Sala sala;
  final bool desenhar;

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
        IconButton(tooltip: 'Voltar', icon: const Icon(Icons.arrow_back), onPressed: estado.fecharGrafo),
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

class CanvasDoGrafo extends StatefulWidget {
  const CanvasDoGrafo({
    super.key,
    required this.workflow,
    this.estados = const {},
    this.percorridas = const {},
    this.selecionada,
    this.aoTocar,
  });

  final Workflow workflow;
  final Map<String, String> estados;
  final Set<String> percorridas;
  final String? selecionada;
  final ValueChanged<String?>? aoTocar;

  @override
  State<CanvasDoGrafo> createState() => _CanvasDoGrafoState();
}

class _CanvasDoGrafoState extends State<CanvasDoGrafo> {
  Vista? _vista;
  String? _ajustadaPara;
  Size _tamanho = Size.zero;
  double _escalaNoInicio = 1;

  Vista get _v => _vista ?? (dx: 0, dy: 0, escala: 1);

  String get _chave => '${widget.workflow.equipe}/${widget.workflow.id}/${widget.workflow.versao}';

  void _zoom(double fator, {Offset? foco}) {
    final centro = foco ?? Offset(_tamanho.width / 2, _tamanho.height / 2);
    setState(() => _vista = zoomEm(_v, centro.dx, centro.dy, _v.escala * fator));
  }

  void _roda(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final teclado = HardwareKeyboard.instance;
    if (teclado.isControlPressed || teclado.isMetaPressed) {
      _zoom(e.scrollDelta.dy > 0 ? 0.9 : 1 / 0.9, foco: e.localPosition);
    } else if (teclado.isShiftPressed) {
      setState(() => _vista = deslocarVista(_v, -e.scrollDelta.dy, 0));
    } else {
      setState(() => _vista = deslocarVista(_v, -e.scrollDelta.dx, -e.scrollDelta.dy));
    }
  }

  void _toque(TapUpDetails d, Map<String, Ponto> layout) {
    final mundo = paraMundo(_v, d.localPosition.dx, d.localPosition.dy);
    widget.aoTocar?.call(caixaEm(layout, mundo.x, mundo.y));
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final w = widget.workflow;
    final layout = layoutDoGrafo(w);
    final tamanho = tamanhoDoGrafo(layout);
    return LayoutBuilder(builder: (context, limites) {
      _tamanho = limites.biggest;
      if (_vista == null || _ajustadaPara != _chave) {
        _vista = ajustarVistaAoGrafo(layout, _tamanho.width, _tamanho.height);
        _ajustadaPara = _chave;
      }
      final v = _v;
      return Listener(
        onPointerSignal: _roda,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _toque(d, layout),
          onScaleStart: (_) => _escalaNoInicio = _v.escala,
          onScaleUpdate: (d) => setState(() {
            var nova = _v;
            if (d.scale != 1) nova = zoomEm(nova, d.localFocalPoint.dx, d.localFocalPoint.dy, _escalaNoInicio * d.scale);
            _vista = deslocarVista(nova, d.focalPointDelta.dx, d.focalPointDelta.dy);
          }),
          child: ClipRect(
            child: Stack(children: [
              Positioned.fill(child: ColoredBox(color: cores.surfaceContainerLowest)),
              OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform(
                  transform: Matrix4.identity()
                    ..translateByDouble(v.dx, v.dy, 0, 1)
                    ..scaleByDouble(v.escala, v.escala, 1, 1),
                  child: IgnorePointer(
                    child: SizedBox(
                      width: tamanho.largura,
                      height: tamanho.altura,
                      child: Stack(clipBehavior: Clip.none, children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _LigacoesDoGrafo(
                              workflow: w,
                              layout: layout,
                              percorridas: widget.percorridas,
                              cor: cores.outline,
                              realce: cores.primary,
                              fundo: cores.surfaceContainerLowest,
                              texto: cores.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final c in w.nos)
                          Positioned(
                            left: cantoDaCaixa(layout, c.id).x,
                            top: cantoDaCaixa(layout, c.id).y,
                            width: larguraDaCaixa,
                            height: alturaDaCaixa,
                            child: _CaixaDoGrafo(
                              caixa: c,
                              inicio: c.id == w.inicio,
                              estado: widget.estados[c.id],
                              escolhida: widget.selecionada == c.id,
                            ),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 12,
                right: 260,
                child: Text(
                  'Toque numa caixa para ver as saídas · arraste o fundo para mover · Ctrl + roda para zoom',
                  style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: ControlesDeZoom(
                  escala: v.escala,
                  aoAproximar: () => _zoom(1.2),
                  aoAfastar: () => _zoom(1 / 1.2),
                  aoAjustar: () => setState(() => _vista = ajustarVistaAoGrafo(layout, _tamanho.width, _tamanho.height)),
                  aoTamanhoReal: () => _zoom(1 / v.escala),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

class _CaixaDoGrafo extends StatelessWidget {
  const _CaixaDoGrafo({required this.caixa, required this.inicio, required this.estado, required this.escolhida});

  final Caixa caixa;
  final bool inicio;
  final String? estado;
  final bool escolhida;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final cor = estado == null ? null : corDaFicha(estado, cores);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: cor == null ? cores.surfaceContainerHighest : Color.alphaBlend(cor.withValues(alpha: 0.22), cores.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(caixa.tipo == 'condicao' || caixa.tipo == 'decisao_humana' ? 18 : 8),
        border: Border.all(
          color: escolhida ? cores.primary : cor ?? cores.outlineVariant,
          width: escolhida || cor != null ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          if (inicio) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.play_arrow, size: 14, color: cores.primary)),
          Expanded(
            child: Text(
              caixa.nomeDoTipo.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cores.onSurfaceVariant, fontSize: 10, letterSpacing: 0.8),
            ),
          ),
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
    required this.workflow,
    required this.layout,
    required this.percorridas,
    required this.cor,
    required this.realce,
    required this.fundo,
    required this.texto,
  });

  final Workflow workflow;
  final Map<String, Ponto> layout;
  final Set<String> percorridas;
  final Color cor;
  final Color realce;
  final Color fundo;
  final Color texto;

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in workflow.arestas) {
      if (!layout.containsKey(a.de) || !layout.containsKey(a.para)) continue;
      final de = cantoDaCaixa(layout, a.de);
      final para = cantoDaCaixa(layout, a.para);
      final percorrida = percorridas.contains(a.chave);
      final tinta = Paint()
        ..color = percorrida ? realce : cor
        ..strokeWidth = percorrida ? 3 : 1.5
        ..style = PaintingStyle.stroke;
      late Offset p0, p1, p2, p3;
      if (para.x > de.x + larguraDaCaixa / 2) {
        p0 = Offset(de.x + larguraDaCaixa, de.y + alturaDaCaixa / 2);
        p3 = Offset(para.x, para.y + alturaDaCaixa / 2);
        final meio = (p3.dx - p0.dx) / 2;
        p1 = Offset(p0.dx + meio, p0.dy);
        p2 = Offset(p3.dx - meio, p3.dy);
      } else {
        p0 = Offset(de.x + larguraDaCaixa / 2, de.y + alturaDaCaixa);
        p3 = Offset(para.x + larguraDaCaixa / 2, para.y + alturaDaCaixa);
        final baixo = (p0.dy > p3.dy ? p0.dy : p3.dy) + 50;
        p1 = Offset(p0.dx, baixo);
        p2 = Offset(p3.dx, baixo);
      }
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
      if (quando == null) continue;
      final meio = (p0 + p1 * 3 + p2 * 3 + p3) / 8;
      final pintor = TextPainter(
        text: TextSpan(text: quando, style: TextStyle(color: percorrida ? realce : texto, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 140);
      final caixa = Rect.fromCenter(center: meio, width: pintor.width + 8, height: pintor.height + 4);
      canvas.drawRRect(RRect.fromRectAndRadius(caixa, const Radius.circular(4)), Paint()..color = fundo);
      pintor.paint(canvas, Offset(caixa.left + 4, caixa.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _LigacoesDoGrafo antigo) =>
      antigo.workflow != workflow ||
      antigo.percorridas.length != percorridas.length ||
      !antigo.percorridas.containsAll(percorridas) ||
      antigo.cor != cor ||
      antigo.realce != realce ||
      antigo.fundo != fundo ||
      antigo.texto != texto;
}
