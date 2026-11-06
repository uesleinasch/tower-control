import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/editor_de_workflow.dart';
import '../estado/sala.dart';
import '../nucleo/design.dart';
import '../nucleo/editor_de_workflow.dart';
import '../nucleo/modelos.dart';
import '../nucleo/tarefas.dart';
import '../nucleo/workflows.dart';
import 'equipes.dart' show confirmar;
import 'paineis.dart';
import 'workflows.dart';
import 'tema.dart';

const _larguraDaPaleta = 210.0;
const _larguraDoPainel = 320.0;
const _larguraDoMenuDeProblemas = 460.0;
const _numeros = [FontFeature.tabularFigures()];

typedef _AoMudarCampos = String? Function(List<CampoTipado> campos, {bool digitando});
typedef _AoMudarRegra = void Function(Map<String, dynamic> regra, {bool digitando});

String _rotuloDaPosicao(PosicaoResumo p) =>
    p.persona == null ? '${p.titulo} (vaga)' : '${p.personaNome ?? Perfil.porChave(p.persona!).nome} · ${p.titulo}';

class EditorDeWorkflow extends StatefulWidget {
  const EditorDeWorkflow({super.key, required this.sala});

  final Sala sala;

  @override
  State<EditorDeWorkflow> createState() => _EditorDeWorkflowState();
}

class _EditorDeWorkflowState extends State<EditorDeWorkflow> {
  final _canvas = GlobalKey<EstadoDoCanvasDoGrafo>();
  bool? _painelDoWorkflow;

  Sala get _sala => widget.sala;

  EstadoEditorDeWorkflow get _e => _sala.editorDeWorkflow;

  String _rotulo(String id) => rotuloNoRascunho(_e.rascunho ?? const {}, id);

  void _avisar(String texto, {bool desfazer = true}) {
    final mensageiro = ScaffoldMessenger.maybeOf(context);
    if (mensageiro == null) return;
    mensageiro.hideCurrentSnackBar();
    mensageiro.showSnackBar(SnackBar(
      content: Text(texto),
      duration: const Duration(seconds: 4),
      persist: false,
      action: desfazer ? SnackBarAction(label: 'Desfazer', onPressed: _e.desfazer) : null,
    ));
  }

  bool _mudouCom(WorkflowJson Function(WorkflowJson) operacao) {
    final antes = _e.rascunho;
    final erro = _e.aplicar(operacao);
    if (erro != null) _avisar(erro, desfazer: false);
    return erro == null && !identical(antes, _e.rascunho);
  }

  void _criar(String tipo, Ponto ponto) {
    _e.criar(tipo, ponto);
    _avisar('Caixa ${nomesDeCaixa[tipo] ?? tipo} criada.');
  }

  void _criarNoCentro(String tipo) => _criar(tipo, _canvas.currentState?.pontoNoCentro() ?? (x: 0, y: 0));

  void _criarDepois(String de, String? quando, String tipo) {
    _e.criarDepois(de, quando, tipo);
    _avisar('Caixa ${nomesDeCaixa[tipo] ?? tipo} criada depois de ${_rotulo(de)}.');
  }

  void _ligar(String de, String? quando, String? para) {
    if (para == null || para == de) {
      _avisar('Solte o ponto em cima de outra caixa para ligar.', desfazer: false);
      return;
    }
    if (_mudouCom((w) => ligar(w, de, quando, para))) {
      _avisar('${_rotulo(de)}${quando == null ? '' : ' ($quando)'} agora segue para ${_rotulo(para)}.');
    }
  }

  void _desligar(Aresta a) {
    if (_mudouCom((w) => desligar(w, a))) _avisar('Ligação de ${_rotulo(a.de)} para ${_rotulo(a.para)} desfeita.');
  }

  void _definirInicio(String id) {
    if (_mudouCom((w) => definirInicio(w, id))) _avisar('${_rotulo(id)} agora é o início.');
  }

  RelativeRect _posicaoDoMenu(Offset global) {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(global & Size.zero, Offset.zero & overlay.size);
  }

  Future<void> _tocarPonto(String caixa, PontoDeSaida ponto, Offset global) async {
    if (!ponto.livre) {
      _avisar(
        'Esse ponto já tem ligação: arraste dele até outra caixa para trocar o destino, ou clique na linha para desfazer a ligação.',
        desfazer: false,
      );
      return;
    }
    final tipo = await showMenu<String>(
      context: context,
      position: _posicaoDoMenu(global),
      items: [
        for (final t in tiposDeCaixa)
          PopupMenuItem(
            value: t,
            child: Row(children: [
              Icon(iconeDaCaixa(t), size: 20),
              const SizedBox(width: Espacos.esp3),
              Text(nomesDeCaixa[t] ?? t),
            ]),
          ),
      ],
    );
    if (tipo == null || !mounted) return;
    _criarDepois(caixa, ponto.quando, tipo);
  }

  void _remover(String id) {
    final rotulo = _rotulo(id);
    if (_mudouCom((w) => removerCaixa(w, id))) _avisar('Caixa $rotulo removida, com as ligações dela.');
  }

  void _organizar() {
    if (!_mudouCom(organizarRascunho)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _canvas.currentState?.ajustar());
    _avisar('Caixas organizadas por níveis a partir do início.');
  }

  void _salvar() {
    if (_e.podeSalvar) _e.salvar();
  }

  Future<void> _fechar() async {
    if (_e.alterado &&
        !await confirmar(
          context,
          'Descartar o rascunho?',
          'As mudanças neste workflow ainda não foram salvas.',
          acao: 'Descartar rascunho',
          destrutivo: true,
        )) {
      return;
    }
    _e.fechar();
  }

  Future<void> _excluir() async {
    final nome = _e.rascunho?['nome'] ?? _e.id;
    final ok = await confirmar(
      context,
      'Excluir o workflow $nome?',
      'O arquivo sai da pasta de dados. O servidor recusa se ele estiver rodando ou se uma rotina o disparar.',
      acao: 'Excluir workflow',
      destrutivo: true,
    );
    if (ok) _e.excluir();
  }

  Future<void> _iniciar(Workflow salvo) async {
    final antes = [for (final f in _sala.workflows.fluxos) f.id];
    if (await abrirIniciarWorkflow(context, _sala.workflows, salvo)) _e.aguardarFluxoNovo(antes);
  }

  void _irPara(String lugar) {
    if (lugar == lugarDoWorkflow) {
      _e.selecionar(null);
      setState(() => _painelDoWorkflow = true);
      return;
    }
    _e.selecionar(lugar);
    _canvas.currentState?.centralizar(lugar);
  }

  void _verFluxo(Fluxo f) {
    if (f.versao == _e.versaoBase && !_e.alterado) {
      _e.sobrepor(f.id);
    } else {
      abrirPaginaDoFluxo(context, _sala, f.id);
    }
  }

  EdicaoDoGrafo _edicao(WorkflowJson r) => EdicaoDoGrafo(
        rascunho: r,
        aoMover: (id, ponto) => _e.aplicar((x) => moverCaixa(x, id, ponto)),
        aoLigar: _ligar,
        aoDesligar: _desligar,
        aoTocarPonto: _tocarPonto,
        aoSoltarTipo: _criar,
        aoCriarDepois: _criarDepois,
        aoEditar: _e.selecionar,
        aoDefinirInicio: _definirInicio,
        aoRemover: _remover,
        aoDeslocar: (id, dx, dy, grupo) => _e.aplicar((x) => deslocarCaixa(x, id, dx, dy), grupo: grupo),
        aoMoveu: (id) => _avisar('${_rotulo(id)} mudou de lugar.'),
        aoDesfazer: _e.desfazer,
        aoRefazer: _e.refazer,
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_e, _sala.workflows, _sala.rotinas]),
        builder: (context, _) {
          final r = _e.rascunho;
          final equipe = _e.equipe;
          if (r == null || equipe == null) return const SizedBox.shrink();
          final tema = Theme.of(context);
          final cores = tema.colorScheme;
          final w = Workflow.deJson(r);
          final id = _e.id ?? '';
          final abertos = _sala.workflows.abertos(equipe.id, id);
          final salvo = _sala.workflows.definicao(equipe.id, id);
          final escolhido = _e.sobreposto == null ? null : _sala.workflows.fluxo(_e.sobreposto!);
          final sobreposto = escolhido != null && escolhido.versao == _e.versaoBase && !_e.alterado ? escolhido : null;
          return LayoutBuilder(builder: (context, limites) {
            final classe = ClasseDeJanela.de(limites.maxWidth);
            final editar = classe != ClasseDeJanela.compact;
            final ed = _edicao(r);
            return CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyS, control: true): _salvar,
                const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _salvar,
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Material(
                  color: cores.surface,
                  child: SafeArea(bottom: false, child: _topo(context, w, salvo, classe, editar)),
                ),
                if (_e.erro != null)
                  MaterialBanner(
                    leading: Icon(Symbols.error, color: cores.onErrorContainer),
                    content: Text(_e.erro!, style: tema.textTheme.bodyMedium?.copyWith(color: cores.onErrorContainer)),
                    backgroundColor: cores.errorContainer,
                    actions: [
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: cores.onErrorContainer),
                        onPressed: _e.limparErro,
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                if (abertos.isNotEmpty) _avisoDeExecucoes(context, abertos, sobreposto, classe),
                const Divider(height: 1),
                Expanded(
                  child: editar
                      ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          SizedBox(width: _larguraDaPaleta, child: _Paleta(aoCriar: _criarNoCentro)),
                          const VerticalDivider(width: 1),
                          Expanded(child: _area(w, ed, sobreposto, classe)),
                        ])
                      : CanvasDoGrafo(
                          key: _canvas,
                          workflow: w,
                          estados: sobreposto == null ? const {} : estadoDasCaixas(sobreposto),
                          percorridas: sobreposto == null ? const {} : arestasPercorridas(sobreposto),
                          erros: _e.erros,
                          aviso: 'Alargue a janela para editar o workflow.',
                        ),
                ),
              ]),
            );
          });
        },
      );

  Widget _topo(BuildContext context, Workflow w, Workflow? salvo, ClasseDeJanela classe, bool editar) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final largo = classe.comDoisPaineis;
    Widget acao(IconData icone, String rotulo, VoidCallback? aoTocar, {bool principal = false, bool tonal = false, String? dica}) {
      if (!largo) {
        if (principal) return IconButton.filled(tooltip: dica ?? rotulo, onPressed: aoTocar, icon: Icon(icone));
        if (tonal) return IconButton.filledTonal(tooltip: dica ?? rotulo, onPressed: aoTocar, icon: Icon(icone));
        return IconButton(tooltip: dica ?? rotulo, onPressed: aoTocar, icon: Icon(icone));
      }
      final Widget botao;
      if (principal) {
        botao = FilledButton.icon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
      } else if (tonal) {
        botao = FilledButton.tonalIcon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
      } else {
        botao = OutlinedButton.icon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
      }
      return dica == null ? botao : Tooltip(message: dica, child: botao);
    }

    final salvar = acao(
      Symbols.save,
      _e.salvando ? 'Salvando…' : (_e.alterado ? 'Salvar' : 'Salvo'),
      _e.podeSalvar ? _e.salvar : null,
      principal: true,
      dica: 'Salvar workflow (Ctrl+S)',
    );
    final acoes = <Widget>[
      if (editar) ...[
        IconButton(
          tooltip: 'Desfazer (Ctrl+Z)',
          onPressed: _e.podeDesfazer ? _e.desfazer : null,
          icon: const Icon(Symbols.undo),
        ),
        IconButton(
          tooltip: 'Refazer (Ctrl+Shift+Z)',
          onPressed: _e.podeRefazer ? _e.refazer : null,
          icon: const Icon(Symbols.redo),
        ),
        acao(Symbols.auto_awesome_mosaic, 'Organizar', _organizar),
        if (salvo != null && !_e.alterado) acao(Symbols.play_arrow, 'Iniciar', () => _iniciar(salvo), tonal: true),
        if (_e.mudou)
          largo
              ? TextButton.icon(onPressed: _e.descartar, icon: const Icon(Symbols.restore), label: const Text('Descartar'))
              : IconButton(tooltip: 'Descartar', onPressed: _e.descartar, icon: const Icon(Symbols.restore)),
        salvar,
        if (!_e.novo)
          IconButton(
            tooltip: 'Excluir workflow',
            color: cores.error,
            onPressed: _e.salvando ? null : _excluir,
            icon: const Icon(Symbols.delete),
          ),
      ] else if (_e.alterado)
        salvar,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(Espacos.esp1, Espacos.esp2, classe.margemLateral, Espacos.esp2),
      child: Row(children: [
        IconButton(tooltip: 'Fechar o editor', icon: const Icon(Symbols.close), onPressed: _fechar),
        const SizedBox(width: Espacos.esp1),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(w.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: tema.textTheme.titleMedium),
            Text(
              [
                _e.novo ? 'novo, ainda não salvo' : 'versão ${_e.versaoBase}',
                'id ${w.id}',
                if (_e.mudou && !_e.novo) 'não salvo',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros),
            ),
          ]),
        ),
        const SizedBox(width: Espacos.esp3),
        _problemas(context),
        const SizedBox(width: Espacos.esp3),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Espacos.esp2,
            runSpacing: Espacos.esp1,
            children: acoes,
          ),
        ),
      ]),
    );
  }

  Widget _problemas(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final n = _e.problemas;
    if (n == 0) {
      return Chip(
        avatar: Icon(Symbols.check_circle, color: CoresSemanticas.de(context).sucesso.cor),
        label: const Text('sem problemas'),
        labelStyle: tema.textTheme.labelMedium,
        visualDensity: VisualDensity.compact,
      );
    }
    final r = _e.rascunho ?? const {};
    return MenuAnchor(
      menuChildren: [
        for (final MapEntry(key: lugar, value: mensagens) in _e.erros.entries)
          for (final m in mensagens)
            MenuItemButton(
              leadingIcon: Icon(Symbols.error, color: cores.error),
              onPressed: () => _irPara(lugar),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _larguraDoMenuDeProblemas),
                child: Text('${lugar == lugarDoWorkflow ? 'Workflow' : rotuloNoRascunho(r, lugar)}: $m'),
              ),
            ),
      ],
      builder: (context, controle, _) => ActionChip(
        avatar: Icon(Symbols.error, color: cores.error),
        label: Text(n == 1 ? '1 problema' : '$n problemas', style: const TextStyle(fontFeatures: _numeros)),
        labelStyle: tema.textTheme.labelMedium,
        tooltip: 'Ver os problemas e ir até cada um',
        visualDensity: VisualDensity.compact,
        onPressed: () => controle.isOpen ? controle.close() : controle.open(),
      ),
    );
  }

  Widget _avisoDeExecucoes(BuildContext context, List<Fluxo> abertos, Fluxo? sobreposto, ClasseDeJanela classe) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final margem = classe.margemLateral;
    return Material(
      color: cores.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.fromLTRB(margem, Espacos.esp2, margem, Espacos.esp2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            abertos.length == 1
                ? '1 execução em andamento segue na versão em que começou.'
                : '${abertos.length} execuções em andamento seguem na versão em que começaram.',
            style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros),
          ),
          const SizedBox(height: Espacos.esp1),
          Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp1, children: [
            for (final f in abertos)
              FilterChip(
                selected: sobreposto?.id == f.id,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                avatar: Icon(iconeDoEstado(estadoDoFluxo(f.status)), color: corDoEstado(context, estadoDoFluxo(f.status))),
                tooltip: f.versao == _e.versaoBase && !_e.alterado
                    ? 'Mostrar o andamento no desenho'
                    : 'Abrir a execução com o desenho da versão dela',
                label: Text(
                  '#${f.id} · versão ${f.versao} · ${nomesDeStatusDoFluxo[f.status] ?? f.status}',
                  style: const TextStyle(fontFeatures: _numeros),
                ),
                labelStyle: tema.textTheme.labelMedium,
                onSelected: (_) => _verFluxo(f),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _area(Workflow w, EdicaoDoGrafo ed, Fluxo? sobreposto, ClasseDeJanela classe) {
    final largo = classe.comDoisPaineis;
    final verWorkflow = _painelDoWorkflow ?? largo;
    final canvas = CanvasDoGrafo(
      key: _canvas,
      workflow: w,
      estados: sobreposto == null ? const {} : estadoDasCaixas(sobreposto),
      percorridas: sobreposto == null ? const {} : arestasPercorridas(sobreposto),
      selecionada: _e.selecionada,
      erros: _e.erros,
      aoTocar: (id) => _e.selecionar(id == null || id == _e.selecionada ? null : id),
      edicao: ed,
    );
    final selecionada = _e.selecionada;
    final Widget? painel = selecionada != null
        ? _PainelDaCaixa(
            key: ValueKey('$selecionada/${_e.geracao}'),
            sala: _sala,
            caixa: selecionada,
            edicao: ed,
            aoMover: () => _canvas.currentState?.comecarMovimento(selecionada),
          )
        : verWorkflow
            ? _PainelDoWorkflow(
                key: ValueKey('workflow/${_e.geracao}'),
                sala: _sala,
                aoFechar: () => setState(() => _painelDoWorkflow = false),
                aoVerFluxo: _verFluxo,
              )
            : null;
    if (painel == null) {
      return Stack(children: [
        Positioned.fill(child: canvas),
        Positioned(
          top: Espacos.esp3,
          right: Espacos.esp3,
          child: FilledButton.tonalIcon(
            onPressed: () => setState(() => _painelDoWorkflow = true),
            icon: const Icon(Symbols.tune),
            label: const Text('Workflow'),
          ),
        ),
      ]);
    }
    if (largo) {
      return LadoALado(
        painel: 'editorDeWorkflow',
        rotulo: 'Largura do painel do editor',
        inicial: _larguraDoPainel,
        lateralADireita: true,
        principal: canvas,
        lateral: Material(color: Theme.of(context).colorScheme.surfaceContainer, child: painel),
      );
    }
    return LayoutBuilder(
      builder: (context, limites) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: canvas),
        SizedBox(height: limites.maxHeight * 0.45, child: FolhaDeApoio(child: painel)),
      ]),
    );
  }
}

class _Paleta extends StatelessWidget {
  const _Paleta({required this.aoCriar});

  final ValueChanged<String> aoCriar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    return Material(
      color: cores.surfaceContainer,
      child: ListView(padding: const EdgeInsets.symmetric(vertical: Espacos.esp3, horizontal: Espacos.esp2), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espacos.esp2),
          child: Text('Caixas', style: tema.textTheme.titleSmall),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Espacos.esp2, Espacos.esp1, Espacos.esp2, Espacos.esp2),
          child: Text(
            'Arraste para o canvas ou clique para criar no centro.',
            style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant),
          ),
        ),
        for (final t in tiposDeCaixa) ...[
          if (t == 'decisao_humana' || t == 'paralelo') const Divider(height: Espacos.esp3),
          Draggable<String>(
            data: t,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(Raios.sm),
              color: cores.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espacos.esp3, vertical: Espacos.esp2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(iconeDaCaixa(t), size: 20),
                  const SizedBox(width: Espacos.esp2),
                  Text(nomesDeCaixa[t] ?? t, style: tema.textTheme.labelLarge),
                ]),
              ),
            ),
            child: Tooltip(
              message: 'Caixa ${nomesDeCaixa[t] ?? t}: ${descricoesDeCaixa[t] ?? ''}',
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: Espacos.esp2),
                horizontalTitleGap: Espacos.esp3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Raios.sm)),
                leading: Icon(iconeDaCaixa(t), size: 20),
                title: Text(nomesDeCaixa[t] ?? t),
                onTap: () => aoCriar(t),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _TituloDeSecao extends StatelessWidget {
  const _TituloDeSecao(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Espacos.esp4, bottom: Espacos.esp1),
        child: Text(texto, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _ListaDeErros extends StatelessWidget {
  const _ListaDeErros({required this.erros});

  final List<String> erros;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.error;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final e in erros)
        Padding(
          padding: const EdgeInsets.only(top: Espacos.esp1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Symbols.error, size: 16, color: cor),
            const SizedBox(width: Espacos.esp2),
            Expanded(child: Text(e, style: tema.textTheme.bodySmall?.copyWith(color: cor))),
          ]),
        ),
    ]);
  }
}

class _PainelDaCaixa extends StatefulWidget {
  const _PainelDaCaixa({super.key, required this.sala, required this.caixa, required this.edicao, required this.aoMover});

  final Sala sala;
  final String caixa;
  final EdicaoDoGrafo edicao;
  final VoidCallback aoMover;

  @override
  State<_PainelDaCaixa> createState() => _PainelDaCaixaState();
}

class _PainelDaCaixaState extends State<_PainelDaCaixa> {
  late final _id = TextEditingController(text: widget.caixa);
  String? _erroDoId;

  EstadoEditorDeWorkflow get _e => widget.sala.editorDeWorkflow;

  String get _caixa => widget.caixa;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  void _renomear() {
    final erro = _e.renomear(_caixa, _id.text);
    if (erro != null) setState(() => _erroDoId = erro);
  }

  void _campo(String chave, Object? valor, {bool digitando = false}) =>
      _e.aplicar((w) => definirCampo(w, _caixa, chave, valor), grupo: digitando ? 'campo/$_caixa/$chave' : null);

  @override
  Widget build(BuildContext context) {
    final r = _e.rascunho;
    final caixa = r == null ? null : caixaDe(r, _caixa);
    final equipe = _e.equipe;
    if (r == null || caixa == null || equipe == null) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final pequeno = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final tipo = caixa['tipo'] is String ? caixa['tipo'] as String : '';
    final referencias = referenciasDisponiveis(r, _caixa);
    final arquivos = _e.textosEmArquivo[_caixa] ?? const {};
    String texto(String chave) => caixa[chave] is String ? caixa[chave] as String : '';
    Widget campoDeTexto(String chave, String rotulo, {bool multilinha = false, bool comReferencias = false, String? ajuda}) =>
        _CampoDeTexto(
          key: ValueKey('campo/$chave'),
          valor: texto(chave),
          rotulo: rotulo,
          ajuda: ajuda,
          multilinha: multilinha,
          referencias: comReferencias ? referencias : null,
          arquivo: arquivos[chave],
          aoMudar: (v) => _campo(chave, v, digitando: true),
        );
    final implicitas = saidasDaCaixa(caixa);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Espacos.esp4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: Espacos.esp1),
            child: Icon(iconeDaCaixa(tipo), size: 20, color: cores.onSurfaceVariant),
          ),
          const SizedBox(width: Espacos.esp2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Caixa ${nomesDeCaixa[tipo] ?? tipo}', style: tema.textTheme.titleMedium),
              Text(descricoesDeCaixa[tipo] ?? '', style: pequeno),
            ]),
          ),
          if (r['inicio'] == _caixa)
            Padding(
              padding: const EdgeInsets.only(right: Espacos.esp1),
              child: Chip(
                avatar: Icon(Symbols.play_circle, color: cores.primary),
                label: const Text('início'),
                labelStyle: tema.textTheme.labelMedium,
                visualDensity: VisualDensity.compact,
              ),
            ),
          MenuAnchor(
            menuChildren: itensDoMenuDaCaixa(
              ed: widget.edicao,
              id: _caixa,
              cores: cores,
              comEditar: false,
              aoMover: widget.aoMover,
            ),
            builder: (context, controle, _) => IconButton(
              tooltip: 'Menu da caixa',
              onPressed: () => controle.isOpen ? controle.close() : controle.open(),
              icon: const Icon(Symbols.more_vert),
            ),
          ),
          IconButton(tooltip: 'Fechar', icon: const Icon(Symbols.close), onPressed: () => _e.selecionar(null)),
        ]),
        _ListaDeErros(erros: _e.erros[_caixa] ?? const []),
        const SizedBox(height: Espacos.esp4),
        campoDeTexto('titulo', 'Título (opcional)'),
        const SizedBox(height: Espacos.esp3),
        TextField(
          controller: _id,
          decoration: InputDecoration(
            labelText: 'Id',
            helperText: 'aparece nas referências {{id.saída}}; Enter renomeia',
            errorText: _erroDoId,
            errorMaxLines: 3,
            suffixIcon: IconButton(tooltip: 'Renomear', icon: const Icon(Symbols.check), onPressed: _renomear),
          ),
          onSubmitted: (_) => _renomear(),
          onChanged: (_) {
            if (_erroDoId != null) setState(() => _erroDoId = null);
          },
        ),
        const SizedBox(height: Espacos.esp3),
        campoDeTexto('prazo', tipo == 'espera' ? 'Prazo de espera (opcional)' : 'Prazo (opcional)', ajuda: 'duração, como 30m, 2h ou 1d'),
        const SizedBox(height: Espacos.esp4),
        ..._camposDoTipo(tipo, caixa, r, equipe, referencias, campoDeTexto, texto, pequeno),
        if (tipo != 'executar' && implicitas.isNotEmpty) ...[
          const _TituloDeSecao('Saídas desta caixa'),
          for (final MapEntry(:key, :value) in implicitas.entries) Text('$key · ${value.descricao}', style: pequeno),
        ],
      ]),
    );
  }

  List<Widget> _camposDoTipo(
    String tipo,
    Map<String, dynamic> caixa,
    WorkflowJson r,
    EquipeResumo equipe,
    List<ReferenciaDisponivel> referencias,
    Widget Function(String chave, String rotulo, {bool multilinha, bool comReferencias, String? ajuda}) campoDeTexto,
    String Function(String) texto,
    TextStyle? pequeno,
  ) {
    const espaco = SizedBox(height: Espacos.esp3);
    switch (tipo) {
      case 'executar':
        return [
          _SeletorDePosicao(rotulo: 'Posição', valor: texto('posicao'), equipe: equipe, aoMudar: (v) => _campo('posicao', v)),
          espaco,
          campoDeTexto('instrucao', 'Instrução', multilinha: true, comReferencias: true),
          espaco,
          campoDeTexto('criterio', 'Critério (opcional)', multilinha: true, comReferencias: true),
          _CamposTipados(
            titulo: 'Saídas que a persona devolve',
            campos: camposTipados(caixa['saidas']),
            implicitas: const {'devolutiva': TipoDeValor.texto()},
            aoMudar: (campos, {digitando = false}) =>
                _e.aplicar((w) => definirSaidas(w, _caixa, campos), grupo: digitando ? 'saidas/$_caixa' : null),
          ),
        ];
      case 'revisar' || 'aprovar':
        final executores = [for (final n in nosDe(r)) if (n['tipo'] == 'executar' && n['id'] is String) n['id'] as String];
        final de = texto('de');
        return [
          DropdownButtonFormField<String>(
            initialValue: executores.contains(de) ? de : null,
            isExpanded: true,
            hint: Text(de.isEmpty ? 'escolha a caixa executar' : '$de (não é executar)'),
            decoration: InputDecoration(labelText: tipo == 'revisar' ? 'Revisa a entrega de' : 'Aprova a entrega de'),
            items: [for (final id in executores) DropdownMenuItem(value: id, child: Text(rotuloNoRascunho(r, id)))],
            onChanged: (v) => v == null ? null : _campo('de', v),
          ),
          espaco,
          _QuemDecide(
            tipo: tipo,
            por: caixa['por'] is Map<String, dynamic> ? caixa['por'] as Map<String, dynamic> : const {},
            equipe: equipe,
            aoMudar: (por) => _campo('por', por),
          ),
        ];
      case 'decisao_humana':
        return [
          campoDeTexto('pergunta', 'Pergunta', multilinha: true, comReferencias: true),
          espaco,
          _Opcoes(editor: _e, caixa: _caixa, opcoes: opcoesDe(caixa)),
        ];
      case 'board':
        return [
          campoDeTexto('pauta', 'Pauta', multilinha: true, comReferencias: true),
          espaco,
          if (caixa.containsKey('opcoes'))
            _Opcoes(editor: _e, caixa: _caixa, opcoes: opcoesDe(caixa))
          else ...[
            Text('Sem opções, o board devolve uma síntese e segue por uma ligação só.', style: pequeno),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _campo('opcoes', ['aprovar', 'rejeitar']),
                icon: const Icon(Symbols.list),
                label: const Text('Dar opções ao board'),
              ),
            ),
          ],
        ];
      case 'condicao':
        final regras = regrasDe(caixa);
        return [
          Text('Regras em ordem: segue pela saída da primeira verdadeira; se nenhuma valer, por "senao".', style: pequeno),
          for (final (i, regra) in regras.indexed)
            Card(
              margin: const EdgeInsets.only(top: Espacos.esp2),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Espacos.esp3, Espacos.esp1, Espacos.esp1, Espacos.esp3),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        'Regra ${i + 1}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontFeatures: _numeros),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Subir',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Symbols.arrow_upward, size: 20),
                      onPressed: i == 0 ? null : () => _e.aplicar((w) => moverRegra(w, _caixa, i, i - 1)),
                    ),
                    IconButton(
                      tooltip: 'Descer',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Symbols.arrow_downward, size: 20),
                      onPressed: i == regras.length - 1 ? null : () => _e.aplicar((w) => moverRegra(w, _caixa, i, i + 1)),
                    ),
                    IconButton(
                      tooltip: 'Remover regra',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Symbols.close, size: 20),
                      onPressed: () => _e.aplicar((w) => removerRegra(w, _caixa, i)),
                    ),
                  ]),
                  _EditorDeRegra(
                    chave: 'regra/$i',
                    rascunho: r,
                    regra: regra,
                    referencias: referencias,
                    comSaida: true,
                    aoMudar: (nova, {digitando = false}) =>
                        _e.aplicar((w) => definirRegra(w, _caixa, i, nova), grupo: digitando ? 'regra/$_caixa/$i' : null),
                  ),
                ]),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _e.aplicar((w) => acrescentarRegra(w, _caixa)),
              icon: const Icon(Symbols.add),
              label: const Text('Acrescentar regra'),
            ),
          ),
        ];
      case 'laco':
        final enquanto = caixa['enquanto'];
        return [
          _CampoDeTexto(
            key: const ValueKey('maxVoltas'),
            valor: caixa['maxVoltas']?.toString() ?? '',
            rotulo: 'Máximo de voltas',
            ajuda: 'de 1 a $maxVoltasDoLaco',
            numero: true,
            aoMudar: (v) => _campo('maxVoltas', int.tryParse(v.trim()) ?? v, digitando: true),
          ),
          const _TituloDeSecao('Repete enquanto'),
          _EditorDeRegra(
            chave: 'enquanto',
            rascunho: r,
            regra: enquanto is Map<String, dynamic> ? enquanto : const {'campo': '', 'op': 'preenchido'},
            referencias: referencias,
            comSaida: false,
            aoMudar: (nova, {digitando = false}) =>
                _e.aplicar((w) => definirCampo(w, _caixa, 'enquanto', nova), grupo: digitando ? 'enquanto/$_caixa' : null),
          ),
        ];
      case 'espera':
        final forma = formasDeEspera.where(caixa.containsKey).firstOrNull ?? 'duracao';
        return [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'duracao', label: Text('Duração')),
              ButtonSegment(value: 'ate', label: Text('Horário')),
              ButtonSegment(value: 'sinal', label: Text('Sinal')),
            ],
            selected: {forma},
            onSelectionChanged: (s) => _e.aplicar(
              (w) => definirEspera(w, _caixa, s.first, switch (s.first) {
                'duracao' => '1h',
                'ate' => '09:00',
                _ => 'pronto',
              }),
            ),
          ),
          espaco,
          _CampoDeTexto(
            key: ValueKey('espera/$forma'),
            valor: texto(forma),
            rotulo: switch (forma) {
              'duracao' => 'Duração',
              'ate' => 'Horário',
              _ => 'Nome do sinal',
            },
            ajuda: switch (forma) {
              'duracao' => '30m, 2h ou 1d',
              'ate' => 'HH:MM',
              _ => 'o fluxo segue quando você mandar este sinal',
            },
            aoMudar: (v) => _e.aplicar((w) => definirEspera(w, _caixa, forma, v), grupo: 'espera/$_caixa'),
          ),
        ];
      case 'fim':
        return [campoDeTexto('resultado', 'Resultado (opcional)')];
      case 'paralelo':
        return [Text('Puxe o ponto "várias" até cada caixa que deve rodar junto.', style: pequeno)];
      case 'juncao':
        return [Text('Ligue à junção todos os caminhos que ela precisa esperar.', style: pequeno)];
      default:
        return const [];
    }
  }
}

class _SeletorDePosicao extends StatelessWidget {
  const _SeletorDePosicao({required this.rotulo, required this.valor, required this.equipe, required this.aoMudar});

  final String rotulo;
  final String valor;
  final EquipeResumo equipe;
  final ValueChanged<String> aoMudar;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: equipe.posicao(valor) != null ? valor : null,
        isExpanded: true,
        hint: Text(valor.isEmpty ? 'escolha uma posição' : '$valor (não existe na equipe)'),
        decoration: InputDecoration(labelText: rotulo),
        items: [
          for (final p in equipe.posicoes)
            DropdownMenuItem(value: p.id, child: Text(_rotuloDaPosicao(p), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          if (v != null) aoMudar(v);
        },
      );
}

class _QuemDecide extends StatelessWidget {
  const _QuemDecide({required this.tipo, required this.por, required this.equipe, required this.aoMudar});

  final String tipo;
  final Map<String, dynamic> por;
  final EquipeResumo equipe;
  final ValueChanged<Map<String, dynamic>> aoMudar;

  Map<String, dynamic> _com(String chave, Object valor) =>
      {...por}..removeWhere((k, _) => k == 'posicao' || k == 'board' || k == 'ueslei')..[chave] = valor;

  @override
  Widget build(BuildContext context) {
    final alternativa = tipo == 'revisar' ? 'board' : 'ueslei';
    final forma = por[alternativa] == true ? alternativa : 'posicao';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<String>(
        segments: [
          const ButtonSegment(value: 'posicao', label: Text('Posição')),
          ButtonSegment(value: alternativa, label: Text(tipo == 'revisar' ? 'Board' : 'Ueslei')),
        ],
        selected: {forma},
        onSelectionChanged: (s) => aoMudar(s.first == 'posicao' ? _com('posicao', '') : _com(s.first, true)),
      ),
      if (forma == 'posicao') ...[
        const SizedBox(height: Espacos.esp3),
        _SeletorDePosicao(
          rotulo: tipo == 'revisar' ? 'Quem revisa' : 'Quem aprova',
          valor: por['posicao'] is String ? por['posicao'] as String : '',
          equipe: equipe,
          aoMudar: (v) => aoMudar(_com('posicao', v)),
        ),
      ],
    ]);
  }
}

class _Opcoes extends StatelessWidget {
  const _Opcoes({required this.editor, required this.caixa, required this.opcoes});

  final EstadoEditorDeWorkflow editor;
  final String caixa;
  final List<String> opcoes;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _TituloDeSecao('Opções (cada uma vira um ponto de ligação)'),
        for (final (i, o) in opcoes.indexed)
          Padding(
            padding: const EdgeInsets.only(top: Espacos.esp2),
            child: Row(children: [
              Expanded(
                child: _CampoDeTexto(
                  key: ValueKey('opcao/$i'),
                  valor: o,
                  rotulo: 'Opção ${i + 1}',
                  aoMudar: (v) => editor.aplicar((w) => renomearOpcao(w, caixa, i, v), grupo: 'opcao/$caixa/$i'),
                ),
              ),
              IconButton(
                tooltip: 'Subir',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.arrow_upward, size: 20),
                onPressed: i == 0 ? null : () => editor.aplicar((w) => moverOpcao(w, caixa, i, i - 1)),
              ),
              IconButton(
                tooltip: 'Descer',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.arrow_downward, size: 20),
                onPressed: i == opcoes.length - 1 ? null : () => editor.aplicar((w) => moverOpcao(w, caixa, i, i + 1)),
              ),
              IconButton(
                tooltip: 'Remover opção',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.close, size: 20),
                onPressed: () => editor.aplicar((w) => removerOpcao(w, caixa, i)),
              ),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => editor.aplicar((w) => acrescentarOpcao(w, caixa, 'opção ${opcoes.length + 1}')),
            icon: const Icon(Symbols.add),
            label: const Text('Acrescentar opção'),
          ),
        ),
      ]);
}

class _CamposTipados extends StatefulWidget {
  const _CamposTipados({required this.titulo, required this.campos, required this.aoMudar, this.implicitas = const {}});

  final String titulo;
  final List<CampoTipado> campos;
  final Map<String, TipoDeValor> implicitas;
  final _AoMudarCampos aoMudar;

  @override
  State<_CamposTipados> createState() => _CamposTipadosState();
}

class _CamposTipadosState extends State<_CamposTipados> {
  String? _erro;

  void _mudar(List<CampoTipado> campos, {bool digitando = false}) {
    final erro = widget.aoMudar(campos, digitando: digitando);
    if (erro != _erro) setState(() => _erro = erro);
  }

  List<CampoTipado> _trocar(int i, CampoTipado novo) => [...widget.campos]..[i] = novo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final pequeno = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final campos = widget.campos;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _TituloDeSecao(widget.titulo),
      for (final MapEntry(:key, :value) in widget.implicitas.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacos.esp1),
          child: Text('$key · ${value.descricao} · sempre devolvida', style: pequeno),
        ),
      for (final (i, c) in campos.indexed) ...[
        Padding(
          padding: const EdgeInsets.only(top: Espacos.esp2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              flex: 3,
              child: _CampoDeTexto(
                key: ValueKey('nome/$i'),
                valor: c.nome,
                rotulo: 'Nome',
                aoMudar: (v) => _mudar(_trocar(i, (nome: v.trim(), tipo: c.tipo)), digitando: true),
              ),
            ),
            const SizedBox(width: Espacos.esp2),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: tipoDoCampoTipado(c.tipo),
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final t in tiposDeCampo) DropdownMenuItem(value: t, child: Text(nomesDeTipoDeCampo[t] ?? t)),
                ],
                onChanged: (t) {
                  if (t != null) _mudar(_trocar(i, (nome: c.nome, tipo: tipoPadrao(t))));
                },
              ),
            ),
            IconButton(
              tooltip: 'Remover campo',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Symbols.close, size: 20),
              onPressed: () => _mudar([...campos]..removeAt(i)),
            ),
          ]),
        ),
        if (tipoDoCampoTipado(c.tipo) == 'escolha')
          Padding(
            padding: const EdgeInsets.only(top: Espacos.esp2),
            child: _CampoDeTexto(
              key: ValueKey('escolhas/$i'),
              valor: escolhasDoCampoTipado(c.tipo).join(', '),
              rotulo: 'Valores, separados por vírgula',
              aoMudar: (v) => _mudar(_trocar(i, (nome: c.nome, tipo: tipoComEscolhas(v))), digitando: true),
            ),
          ),
      ],
      if (_erro != null)
        Padding(
          padding: const EdgeInsets.only(top: Espacos.esp1),
          child: Text(_erro!, style: tema.textTheme.bodySmall?.copyWith(color: cores.error)),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _mudar([
            ...campos,
            (nome: nomeDeCampoLivre([...campos.map((c) => c.nome), ...widget.implicitas.keys]), tipo: 'texto'),
          ]),
          icon: const Icon(Symbols.add),
          label: const Text('Acrescentar campo'),
        ),
      ),
    ]);
  }
}

class _EditorDeRegra extends StatelessWidget {
  const _EditorDeRegra({
    required this.chave,
    required this.rascunho,
    required this.regra,
    required this.referencias,
    required this.comSaida,
    required this.aoMudar,
  });

  final String chave;
  final WorkflowJson rascunho;
  final Map<String, dynamic> regra;
  final List<ReferenciaDisponivel> referencias;
  final bool comSaida;
  final _AoMudarRegra aoMudar;

  Map<String, dynamic> _com(Map<String, Object?> mudancas) =>
      <String, dynamic>{...regra, ...mudancas}..removeWhere((_, v) => v == null);

  static Object? _valorPadrao(TipoDeValor? tipo) => switch (tipo?.nome) {
        'numero' => 0,
        'booleano' => true,
        'escolha' => tipo!.escolhas.firstOrNull ?? '',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final campo = regra['campo'] is String ? regra['campo'] as String : '';
    final tipo = tipoDoCampo(rascunho, campo);
    final op = regra['op'] is String ? regra['op'] as String : 'igual';
    final grupos = <String, List<ReferenciaDisponivel>>{};
    for (final r in referencias) {
      (grupos[r.caixa] ??= []).add(r);
    }
    final validos = {for (final r in referencias) r.campoDaRegra};
    final valor = regra['valor'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        initialValue: validos.contains(campo) ? campo : null,
        isExpanded: true,
        hint: Text(campo.isEmpty ? 'escolha um valor' : '$campo (não vale aqui)'),
        decoration: const InputDecoration(labelText: 'Campo'),
        items: [
          for (final MapEntry(key: caixa, value: lista) in grupos.entries) ...[
            DropdownMenuItem(
              value: '#$caixa',
              enabled: false,
              child: Text(
                caixa == 'entrada' ? 'entrada do workflow' : rotuloNoRascunho(rascunho, caixa),
                style: tema.textTheme.labelMedium?.copyWith(color: cores.onSurfaceVariant),
              ),
            ),
            for (final r in lista)
              DropdownMenuItem(
                value: r.campoDaRegra,
                child: Padding(
                  padding: const EdgeInsets.only(left: Espacos.esp3),
                  child: Text('${r.campo} · ${r.tipo.descricao}', overflow: TextOverflow.ellipsis),
                ),
              ),
          ],
        ],
        onChanged: (v) {
          if (v == null || v.startsWith('#')) return;
          final t = tipoDoCampo(rascunho, v);
          final novaOp = opsPara(t).contains(op) ? op : 'igual';
          aoMudar(_com({'campo': v, 'op': novaOp, 'valor': opPedeValor(novaOp) ? _valorPadrao(t) : null}));
        },
      ),
      const SizedBox(height: Espacos.esp2),
      DropdownButtonFormField<String>(
        initialValue: op,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Operação'),
        items: [
          for (final o in {...opsPara(tipo), op}) DropdownMenuItem(value: o, child: Text(nomesDeOp[o] ?? o)),
        ],
        onChanged: (v) {
          if (v == null) return;
          aoMudar(_com({'op': v, 'valor': opPedeValor(v) ? (valor ?? _valorPadrao(tipo)) : null}));
        },
      ),
      if (opPedeValor(op)) ...[
        const SizedBox(height: Espacos.esp2),
        switch (tipo?.nome) {
          'escolha' => DropdownButtonFormField<String>(
              initialValue: tipo!.escolhas.contains('$valor') ? '$valor' : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Valor'),
              items: [for (final e in tipo.escolhas) DropdownMenuItem(value: e, child: Text(e))],
              onChanged: (v) => v == null ? null : aoMudar(_com({'valor': v})),
            ),
          'booleano' => DropdownButtonFormField<bool>(
              initialValue: valor is bool ? valor : null,
              decoration: const InputDecoration(labelText: 'Valor'),
              items: const [
                DropdownMenuItem(value: true, child: Text('sim')),
                DropdownMenuItem(value: false, child: Text('não')),
              ],
              onChanged: (v) => v == null ? null : aoMudar(_com({'valor': v})),
            ),
          'numero' => _CampoDeTexto(
              key: ValueKey('$chave/valor/numero'),
              valor: valor == null ? '' : formatarValor(valor),
              rotulo: 'Valor (número)',
              numero: true,
              aoMudar: (t) => aoMudar(_com({'valor': num.tryParse(t.trim().replaceAll(',', '.')) ?? t}), digitando: true),
            ),
          _ => _CampoDeTexto(
              key: ValueKey('$chave/valor/texto'),
              valor: valor == null ? '' : formatarValor(valor),
              rotulo: 'Valor',
              aoMudar: (t) => aoMudar(_com({'valor': t}), digitando: true),
            ),
        },
      ],
      if (comSaida) ...[
        const SizedBox(height: Espacos.esp2),
        _CampoDeTexto(
          key: ValueKey('$chave/saida'),
          valor: regra['saida'] is String ? regra['saida'] as String : '',
          rotulo: 'Saída (vira o ponto de ligação)',
          aoMudar: (t) => aoMudar(_com({'saida': t}), digitando: true),
        ),
      ],
    ]);
  }
}

class _PainelDoWorkflow extends StatelessWidget {
  const _PainelDoWorkflow({super.key, required this.sala, required this.aoFechar, required this.aoVerFluxo});

  final Sala sala;
  final VoidCallback aoFechar;
  final ValueChanged<Fluxo> aoVerFluxo;

  @override
  Widget build(BuildContext context) {
    final e = sala.editorDeWorkflow;
    final r = e.rascunho;
    final equipe = e.equipe;
    if (r == null || equipe == null) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final pequeno = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final id = e.id ?? '';
    final rotinas = [for (final x in sala.rotinas.daEquipe(equipe.id)) if (x.workflow == id) x];
    final abertos = sala.workflows.abertos(equipe.id, id);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Espacos.esp4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: Espacos.esp1),
            child: Icon(Symbols.schema, size: 20, color: cores.onSurfaceVariant),
          ),
          const SizedBox(width: Espacos.esp2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Workflow', style: tema.textTheme.titleMedium),
              Text('Clique numa caixa para editá-la.', style: pequeno),
            ]),
          ),
          IconButton(tooltip: 'Fechar', icon: const Icon(Symbols.close), onPressed: aoFechar),
        ]),
        _ListaDeErros(erros: e.erros[lugarDoWorkflow] ?? const []),
        const SizedBox(height: Espacos.esp4),
        _CampoDeTexto(
          key: const ValueKey('nome'),
          valor: r['nome'] is String ? r['nome'] as String : '',
          rotulo: 'Nome',
          aoMudar: (v) => e.aplicar((w) => editarWorkflow(w, (c) => c['nome'] = v), grupo: 'workflow/nome'),
        ),
        const SizedBox(height: Espacos.esp1),
        Text('id $id (não muda: é o nome do arquivo)', style: pequeno),
        _CamposTipados(
          titulo: 'Entrada: o que se informa ao iniciar',
          campos: camposTipados(r['entrada']),
          aoMudar: (campos, {digitando = false}) =>
              e.aplicar((w) => definirEntrada(w, campos), grupo: digitando ? 'workflow/entrada' : null),
        ),
        const Divider(height: Espacos.esp6),
        const _TituloDeSecao('Versão'),
        Text(e.novo ? 'ainda não salvo' : '${e.versaoBase}', style: const TextStyle(fontFeatures: _numeros)),
        const _TituloDeSecao('Rotinas que disparam este workflow'),
        if (rotinas.isEmpty) Text('nenhuma', style: pequeno),
        for (final x in rotinas) Text('${x.nome}${x.ativa ? '' : ' (desativada)'}'),
        const _TituloDeSecao('Execuções abertas'),
        if (abertos.isEmpty) Text('nenhuma', style: pequeno),
        for (final f in abertos)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: e.sobreposto == f.id,
            leading: Tooltip(
              message: nomesDeStatusDoFluxo[f.status] ?? f.status,
              child: Icon(iconeDoEstado(estadoDoFluxo(f.status)), color: corDoEstado(context, estadoDoFluxo(f.status))),
            ),
            title: Text(
              '#${f.id} · versão ${f.versao} · ${nomesDeStatusDoFluxo[f.status] ?? f.status}',
              style: const TextStyle(fontFeatures: _numeros),
            ),
            onTap: () => aoVerFluxo(f),
          ),
      ]),
    );
  }
}

class _CampoDeTexto extends StatefulWidget {
  const _CampoDeTexto({
    super.key,
    required this.valor,
    required this.rotulo,
    required this.aoMudar,
    this.ajuda,
    this.multilinha = false,
    this.numero = false,
    this.referencias,
    this.arquivo,
  });

  final String valor;
  final String rotulo;
  final ValueChanged<String> aoMudar;
  final String? ajuda;
  final bool multilinha;
  final bool numero;
  final List<ReferenciaDisponivel>? referencias;
  final String? arquivo;

  @override
  State<_CampoDeTexto> createState() => _CampoDeTextoState();
}

class _CampoDeTextoState extends State<_CampoDeTexto> {
  late final _controle = TextEditingController(text: widget.valor);

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  void _inserir(ReferenciaDisponivel ref) {
    final texto = _controle.text;
    final selecao = _controle.selection;
    final inicio = selecao.isValid ? selecao.start : texto.length;
    final fim = selecao.isValid ? selecao.end : texto.length;
    final novo = texto.replaceRange(inicio, fim, ref.texto);
    _controle.value = TextEditingValue(text: novo, selection: TextSelection.collapsed(offset: inicio + ref.texto.length));
    widget.aoMudar(novo);
  }

  @override
  Widget build(BuildContext context) {
    final referencias = widget.referencias;
    final arquivo = widget.arquivo;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _controle,
        minLines: widget.multilinha ? 2 : 1,
        maxLines: widget.multilinha ? 8 : 1,
        keyboardType: widget.numero ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
        decoration: InputDecoration(labelText: widget.rotulo, helperText: widget.ajuda),
        onChanged: widget.aoMudar,
      ),
      if (arquivo != null || referencias != null)
        Row(children: [
          if (arquivo != null)
            Flexible(
              child: Tooltip(
                message: 'No disco este texto fica em $arquivo; ao salvar, ele volta para o arquivo.',
                child: Chip(
                  avatar: const Icon(Symbols.description),
                  label: Text('em $arquivo', overflow: TextOverflow.ellipsis),
                  labelStyle: Theme.of(context).textTheme.labelMedium,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          const Spacer(),
          if (referencias != null) _InserirValor(referencias: referencias, aoEscolher: _inserir),
        ]),
    ]);
  }
}

class _InserirValor extends StatelessWidget {
  const _InserirValor({required this.referencias, required this.aoEscolher});

  final List<ReferenciaDisponivel> referencias;
  final ValueChanged<ReferenciaDisponivel> aoEscolher;

  @override
  Widget build(BuildContext context) {
    final grupos = <String, List<ReferenciaDisponivel>>{};
    for (final r in referencias) {
      (grupos[r.caixa] ??= []).add(r);
    }
    return MenuAnchor(
      menuChildren: grupos.isEmpty
          ? const [MenuItemButton(child: Text('nenhum valor disponível antes desta caixa'))]
          : [
              for (final MapEntry(key: caixa, value: lista) in grupos.entries)
                SubmenuButton(
                  menuChildren: [
                    for (final r in lista)
                      MenuItemButton(onPressed: () => aoEscolher(r), child: Text('${r.campo} · ${r.tipo.descricao}')),
                  ],
                  child: Text(caixa == 'entrada' ? 'entrada do workflow' : caixa),
                ),
            ],
      builder: (context, controle, _) => TextButton.icon(
        onPressed: () => controle.isOpen ? controle.close() : controle.open(),
        icon: const Icon(Symbols.data_object),
        label: const Text('Inserir valor'),
      ),
    );
  }
}
