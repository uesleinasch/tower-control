import 'package:material_ui/material_ui.dart';

import '../estado/editor_de_workflow.dart';
import '../estado/sala.dart';
import '../nucleo/editor_de_workflow.dart';
import '../nucleo/modelos.dart';
import '../nucleo/tarefas.dart';
import '../nucleo/workflows.dart';
import 'equipes.dart' show confirmar;
import 'workflows.dart';

const _larguraDaPaleta = 210.0;
const _larguraDoPainel = 360.0;
const _larguraParaPainelFixo = 760.0;

typedef _AoMudarCampos = String? Function(List<CampoTipado> campos, {bool digitando});
typedef _AoMudarRegra = void Function(Map<String, dynamic> regra, {bool digitando});

String _rotuloDaPosicao(PosicaoResumo p) =>
    p.persona == null ? '${p.titulo} (vaga)' : '${p.personaNome ?? Perfil.porChave(p.persona!).nome} · ${p.titulo}';

String _rotuloDaCaixa(WorkflowJson w, String id) {
  final titulo = caixaDe(w, id)?['titulo'];
  return titulo is String && titulo.trim().isNotEmpty ? titulo.trim() : id;
}

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

  String _rotulo(String id) => _rotuloDaCaixa(_e.rascunho ?? const {}, id);

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

  RelativeRect _posicaoDoMenu(Offset global) {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(global & Size.zero, Offset.zero & overlay.size);
  }

  Future<void> _tocarPonto(String caixa, PontoDeSaida ponto, Offset global) async {
    if (!ponto.livre) {
      _avisar('Esse ponto já tem ligação: arraste dele até outra caixa para trocar o destino, ou clique na linha para desligar.',
          desfazer: false);
      return;
    }
    final tipo = await showMenu<String>(
      context: context,
      position: _posicaoDoMenu(global),
      items: [
        for (final t in tiposDeCaixa)
          PopupMenuItem(
            value: t,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(iconesDeCaixa[t]),
              title: Text(nomesDeCaixa[t] ?? t),
            ),
          ),
      ],
    );
    if (tipo == null || !mounted) return;
    _e.criarDepois(caixa, ponto.quando, tipo);
    _avisar('Caixa ${nomesDeCaixa[tipo] ?? tipo} criada depois de ${_rotulo(caixa)}.');
  }

  void _acaoDaCaixa(String id, String acao) {
    switch (acao) {
      case 'inicio':
        if (_mudouCom((w) => definirInicio(w, id))) _avisar('${_rotulo(id)} agora é o início.');
      case 'remover':
        _remover(id);
    }
  }

  Future<void> _menuDaCaixa(String id, Offset global) async {
    _e.selecionar(id);
    final acao = await showMenu<String>(
      context: context,
      position: _posicaoDoMenu(global),
      items: _itensDoMenuDaCaixa(_e.rascunho?['inicio'] == id),
    );
    if (acao != null && mounted) _acaoDaCaixa(id, acao);
  }

  void _remover(String id) {
    final rotulo = _rotulo(id);
    if (_mudouCom((w) => removerCaixa(w, id))) _avisar('Caixa $rotulo removida, com as ligações dela.');
  }

  void _removerSelecionada() {
    final id = _e.selecionada;
    if (id != null) _remover(id);
  }

  void _organizar() {
    if (!_mudouCom(organizarRascunho)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _canvas.currentState?.ajustar());
    _avisar('Caixas organizadas por níveis a partir do início.');
  }

  Future<void> _fechar() async {
    if (_e.alterado && !await confirmar(context, 'Descartar o rascunho?', 'As mudanças neste workflow ainda não foram salvas.')) {
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_e, _sala.workflows, _sala.rotinas]),
        builder: (context, _) {
          final r = _e.rascunho;
          final equipe = _e.equipe;
          if (r == null || equipe == null) return const SizedBox.shrink();
          final cores = Theme.of(context).colorScheme;
          final w = Workflow.deJson(r);
          final id = _e.id ?? '';
          final abertos = _sala.workflows.abertos(equipe.id, id);
          final salvo = _sala.workflows.definicao(equipe.id, id);
          final escolhido = _e.sobreposto == null ? null : _sala.workflows.fluxo(_e.sobreposto!);
          final sobreposto = escolhido != null && escolhido.versao == _e.versaoBase && !_e.alterado ? escolhido : null;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Material(color: cores.surface, child: SafeArea(bottom: false, child: _topo(context, w, salvo))),
            if (_e.erro != null)
              MaterialBanner(
                content: Text(_e.erro!),
                backgroundColor: cores.errorContainer,
                actions: [TextButton(onPressed: _e.limparErro, child: const Text('Ok'))],
              ),
            if (abertos.isNotEmpty) _avisoDeExecucoes(cores, abertos, sobreposto),
            const Divider(height: 1),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(width: _larguraDaPaleta, child: _Paleta(aoCriar: _criarNoCentro)),
                const VerticalDivider(width: 1),
                Expanded(child: _area(w, r, sobreposto)),
              ]),
            ),
          ]);
        },
      );

  Widget _topo(BuildContext context, Workflow w, Workflow? salvo) {
    final cores = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, limites) {
      final compacto = limites.maxWidth < 1000;
      Widget acao(IconData icone, String rotulo, VoidCallback? aoTocar, {bool principal = false}) {
        if (compacto) {
          return IconButton(
            tooltip: rotulo,
            onPressed: aoTocar,
            icon: Icon(icone),
            style: principal ? IconButton.styleFrom(backgroundColor: cores.primaryContainer) : null,
          );
        }
        if (principal) return FilledButton.icon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
        return OutlinedButton.icon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          IconButton(tooltip: 'Fechar o editor', icon: const Icon(Icons.close), onPressed: _fechar),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(w.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                [
                  _e.novo ? 'novo, ainda não salvo' : 'versão ${_e.versaoBase}',
                  'id ${w.id}',
                  if (_e.mudou && !_e.novo) 'não salvo',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          _problemas(cores),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                IconButton(
                  tooltip: 'Desfazer (Ctrl+Z)',
                  onPressed: _e.podeDesfazer ? _e.desfazer : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Refazer (Ctrl+Shift+Z)',
                  onPressed: _e.podeRefazer ? _e.refazer : null,
                  icon: const Icon(Icons.redo),
                ),
                acao(Icons.account_tree_outlined, 'Organizar', _organizar),
                if (salvo != null && !_e.alterado) acao(Icons.play_arrow, 'Iniciar', () => _iniciar(salvo)),
                acao(
                  Icons.save_outlined,
                  _e.salvando ? 'Salvando…' : (_e.alterado ? 'Salvar' : 'Salvo'),
                  _e.podeSalvar ? _e.salvar : null,
                  principal: true,
                ),
                if (_e.mudou) acao(Icons.restore, 'Descartar', _e.descartar),
                if (!_e.novo)
                  IconButton(
                    tooltip: 'Excluir workflow',
                    onPressed: _e.salvando ? null : _excluir,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
        ]),
      );
    });
  }

  Widget _problemas(ColorScheme cores) {
    final n = _e.problemas;
    if (n == 0) {
      return const Chip(
        avatar: Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF4FAE7C)),
        label: Text('sem problemas'),
        visualDensity: VisualDensity.compact,
      );
    }
    final r = _e.rascunho ?? const {};
    return MenuAnchor(
      menuChildren: [
        for (final MapEntry(key: lugar, value: mensagens) in _e.erros.entries)
          for (final m in mensagens)
            MenuItemButton(
              leadingIcon: Icon(Icons.error_outline, size: 18, color: cores.error),
              onPressed: () => _irPara(lugar),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text('${lugar == lugarDoWorkflow ? 'Workflow' : _rotuloDaCaixa(r, lugar)}: $m'),
              ),
            ),
      ],
      builder: (context, controle, _) => ActionChip(
        avatar: Icon(Icons.error_outline, size: 18, color: cores.error),
        label: Text(n == 1 ? '1 problema' : '$n problemas'),
        visualDensity: VisualDensity.compact,
        onPressed: () => controle.isOpen ? controle.close() : controle.open(),
      ),
    );
  }

  Widget _avisoDeExecucoes(ColorScheme cores, List<Fluxo> abertos, Fluxo? sobreposto) => Material(
        color: cores.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              abertos.length == 1
                  ? '1 execução em andamento segue na versão em que começou.'
                  : '${abertos.length} execuções em andamento seguem na versão em que começaram.',
              style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final f in abertos)
                FilterChip(
                  selected: sobreposto?.id == f.id,
                  visualDensity: VisualDensity.compact,
                  tooltip: f.versao == _e.versaoBase && !_e.alterado
                      ? 'Mostrar o andamento no desenho'
                      : 'Abrir a execução com o desenho da versão dela',
                  label: Text('#${f.id} · versão ${f.versao} · ${nomesDeStatusDoFluxo[f.status] ?? f.status}'),
                  onSelected: (_) => _verFluxo(f),
                ),
            ]),
          ]),
        ),
      );

  Widget _area(Workflow w, WorkflowJson r, Fluxo? sobreposto) => LayoutBuilder(builder: (context, limites) {
        final largo = limites.maxWidth >= _larguraParaPainelFixo;
        final verWorkflow = _painelDoWorkflow ?? largo;
        final canvas = CanvasDoGrafo(
          key: _canvas,
          workflow: w,
          estados: sobreposto == null ? const {} : estadoDasCaixas(sobreposto),
          percorridas: sobreposto == null ? const {} : arestasPercorridas(sobreposto),
          selecionada: _e.selecionada,
          comErro: {for (final k in _e.erros.keys) if (k != lugarDoWorkflow) k},
          aoTocar: (id) => _e.selecionar(id == null || id == _e.selecionada ? null : id),
          edicao: EdicaoDoGrafo(
            rascunho: r,
            aoMover: (id, ponto) => _e.aplicar((x) => moverCaixa(x, id, ponto)),
            aoLigar: _ligar,
            aoDesligar: _desligar,
            aoTocarPonto: _tocarPonto,
            aoSoltarTipo: _criar,
            aoMenuDaCaixa: _menuDaCaixa,
            aoRemover: _removerSelecionada,
            aoDesfazer: _e.desfazer,
            aoRefazer: _e.refazer,
          ),
        );
        final selecionada = _e.selecionada;
        final Widget? painel = selecionada != null
            ? _PainelDaCaixa(
                key: ValueKey('$selecionada/${_e.geracao}'),
                sala: _sala,
                caixa: selecionada,
                aoAcao: (acao) => _acaoDaCaixa(selecionada, acao),
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
              top: 12,
              right: 12,
              child: FilledButton.tonalIcon(
                onPressed: () => setState(() => _painelDoWorkflow = true),
                icon: const Icon(Icons.tune),
                label: const Text('Workflow'),
              ),
            ),
          ]);
        }
        if (largo) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: canvas),
            const VerticalDivider(width: 1),
            SizedBox(width: _larguraDoPainel, child: painel),
          ]);
        }
        final largura = limites.maxWidth * 0.9 < _larguraDoPainel ? limites.maxWidth * 0.9 : _larguraDoPainel;
        return Stack(children: [
          Positioned.fill(child: canvas),
          Positioned(top: 0, bottom: 0, right: 0, width: largura, child: Material(elevation: 8, child: painel)),
        ]);
      });
}

List<PopupMenuEntry<String>> _itensDoMenuDaCaixa(bool inicio) => [
      PopupMenuItem(value: 'inicio', enabled: !inicio, child: const Text('Definir como início')),
      const PopupMenuItem(value: 'remover', child: Text('Remover caixa')),
    ];

class _Paleta extends StatelessWidget {
  const _Paleta({required this.aoCriar});

  final ValueChanged<String> aoCriar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(8, 12, 8, 12), children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('CAIXAS', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11, letterSpacing: 1)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
        child: Text('Arraste para o canvas ou clique para criar no centro.',
            style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11)),
      ),
      for (final t in tiposDeCaixa) ...[
        if (t == 'decisao_humana' || t == 'paralelo') const Divider(height: 12),
        Draggable<String>(
          data: t,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: cores.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(iconesDeCaixa[t], size: 18),
                const SizedBox(width: 6),
                Text(nomesDeCaixa[t] ?? t),
              ]),
            ),
          ),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            minLeadingWidth: 20,
            leading: Icon(iconesDeCaixa[t], size: 20),
            title: Text(nomesDeCaixa[t] ?? t),
            subtitle: Text(descricoesDeCaixa[t] ?? '', style: const TextStyle(fontSize: 11)),
            onTap: () => aoCriar(t),
          ),
        ),
      ],
    ]);
  }
}

class _ListaDeErros extends StatelessWidget {
  const _ListaDeErros({required this.erros});

  final List<String> erros;

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.error;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final e in erros)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.error_outline, size: 16, color: cor),
            const SizedBox(width: 6),
            Expanded(child: Text(e, style: TextStyle(color: cor, fontSize: 12))),
          ]),
        ),
    ]);
  }
}

class _PainelDaCaixa extends StatefulWidget {
  const _PainelDaCaixa({super.key, required this.sala, required this.caixa, required this.aoAcao});

  final Sala sala;
  final String caixa;
  final ValueChanged<String> aoAcao;

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
    final cores = Theme.of(context).colorScheme;
    final pequeno = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
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
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(iconesDeCaixa[tipo] ?? Icons.crop_square, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(nomesDeCaixa[tipo] ?? tipo, style: Theme.of(context).textTheme.titleSmall)),
          if (r['inicio'] == _caixa)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Chip(label: Text('início'), visualDensity: VisualDensity.compact),
            ),
          PopupMenuButton<String>(
            tooltip: 'Menu da caixa',
            itemBuilder: (_) => _itensDoMenuDaCaixa(r['inicio'] == _caixa),
            onSelected: widget.aoAcao,
          ),
          IconButton(tooltip: 'Fechar', icon: const Icon(Icons.close), onPressed: () => _e.selecionar(null)),
        ]),
        Text(descricoesDeCaixa[tipo] ?? '', style: pequeno),
        _ListaDeErros(erros: _e.erros[_caixa] ?? const []),
        const SizedBox(height: 12),
        campoDeTexto('titulo', 'Título (opcional)'),
        const SizedBox(height: 8),
        TextField(
          controller: _id,
          decoration: InputDecoration(
            labelText: 'Id',
            helperText: 'aparece nas referências {{id.saída}}; Enter renomeia',
            errorText: _erroDoId,
            errorMaxLines: 3,
            suffixIcon: IconButton(tooltip: 'Renomear', icon: const Icon(Icons.check), onPressed: _renomear),
          ),
          onSubmitted: (_) => _renomear(),
          onChanged: (_) {
            if (_erroDoId != null) setState(() => _erroDoId = null);
          },
        ),
        const SizedBox(height: 8),
        campoDeTexto('prazo', tipo == 'espera' ? 'Prazo de espera (opcional)' : 'Prazo (opcional)', ajuda: 'duração, como 30m, 2h ou 1d'),
        const SizedBox(height: 16),
        ..._camposDoTipo(tipo, caixa, r, equipe, referencias, campoDeTexto, texto, pequeno),
        if (tipo != 'executar' && implicitas.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Saídas desta caixa', style: pequeno),
          for (final MapEntry(:key, :value) in implicitas.entries)
            Text('$key · ${value.descricao}', style: pequeno.copyWith(color: cores.outline)),
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
    TextStyle pequeno,
  ) {
    const espaco = SizedBox(height: 12);
    switch (tipo) {
      case 'executar':
        return [
          _SeletorDePosicao(rotulo: 'Posição', valor: texto('posicao'), equipe: equipe, aoMudar: (v) => _campo('posicao', v)),
          espaco,
          campoDeTexto('instrucao', 'Instrução', multilinha: true, comReferencias: true),
          espaco,
          campoDeTexto('criterio', 'Critério (opcional)', multilinha: true, comReferencias: true),
          const SizedBox(height: 16),
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
            items: [for (final id in executores) DropdownMenuItem(value: id, child: Text(_rotuloDaCaixa(r, id)))],
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
                icon: const Icon(Icons.list),
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
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text('Regra ${i + 1}', style: pequeno)),
                    IconButton(
                      tooltip: 'Subir',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: i == 0 ? null : () => _e.aplicar((w) => moverRegra(w, _caixa, i, i - 1)),
                    ),
                    IconButton(
                      tooltip: 'Descer',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      onPressed: i == regras.length - 1 ? null : () => _e.aplicar((w) => moverRegra(w, _caixa, i, i + 1)),
                    ),
                    IconButton(
                      tooltip: 'Remover regra',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 18),
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
              icon: const Icon(Icons.add),
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
          espaco,
          Text('Repete enquanto', style: pequeno),
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
        const SizedBox(height: 12),
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
  Widget build(BuildContext context) {
    final pequeno = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Opções (cada uma vira um ponto de ligação)', style: pequeno),
      for (final (i, o) in opcoes.indexed)
        Row(children: [
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
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: i == 0 ? null : () => editor.aplicar((w) => moverOpcao(w, caixa, i, i - 1)),
          ),
          IconButton(
            tooltip: 'Descer',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed: i == opcoes.length - 1 ? null : () => editor.aplicar((w) => moverOpcao(w, caixa, i, i + 1)),
          ),
          IconButton(
            tooltip: 'Remover opção',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => editor.aplicar((w) => removerOpcao(w, caixa, i)),
          ),
        ]),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => editor.aplicar((w) => acrescentarOpcao(w, caixa, 'opção ${opcoes.length + 1}')),
          icon: const Icon(Icons.add),
          label: const Text('Acrescentar opção'),
        ),
      ),
    ]);
  }
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
    final cores = Theme.of(context).colorScheme;
    final pequeno = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    final campos = widget.campos;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.titulo, style: pequeno),
      for (final MapEntry(:key, :value) in widget.implicitas.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('$key · ${value.descricao} · sempre devolvida', style: pequeno.copyWith(color: cores.outline)),
        ),
      for (final (i, c) in campos.indexed) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            flex: 3,
            child: _CampoDeTexto(
              key: ValueKey('nome/$i'),
              valor: c.nome,
              rotulo: 'Nome',
              aoMudar: (v) => _mudar(_trocar(i, (nome: v.trim(), tipo: c.tipo)), digitando: true),
            ),
          ),
          const SizedBox(width: 8),
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
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => _mudar([...campos]..removeAt(i)),
          ),
        ]),
        if (tipoDoCampoTipado(c.tipo) == 'escolha')
          _CampoDeTexto(
            key: ValueKey('escolhas/$i'),
            valor: escolhasDoCampoTipado(c.tipo).join(', '),
            rotulo: 'Valores, separados por vírgula',
            aoMudar: (v) => _mudar(_trocar(i, (nome: c.nome, tipo: tipoComEscolhas(v))), digitando: true),
          ),
      ],
      if (_erro != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_erro!, style: TextStyle(color: cores.error, fontSize: 12))),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _mudar([
            ...campos,
            (nome: nomeDeCampoLivre([...campos.map((c) => c.nome), ...widget.implicitas.keys]), tipo: 'texto'),
          ]),
          icon: const Icon(Icons.add),
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
    final cores = Theme.of(context).colorScheme;
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
              child: Text(caixa == 'entrada' ? 'entrada do workflow' : _rotuloDaCaixa(rascunho, caixa),
                  style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
            ),
            for (final r in lista)
              DropdownMenuItem(value: r.campoDaRegra, child: Text('   ${r.campo} · ${r.tipo.descricao}', overflow: TextOverflow.ellipsis)),
          ],
        ],
        onChanged: (v) {
          if (v == null || v.startsWith('#')) return;
          final t = tipoDoCampo(rascunho, v);
          final novaOp = opsPara(t).contains(op) ? op : 'igual';
          aoMudar(_com({'campo': v, 'op': novaOp, 'valor': opPedeValor(novaOp) ? _valorPadrao(t) : null}));
        },
      ),
      const SizedBox(height: 8),
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
        const SizedBox(height: 8),
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
        const SizedBox(height: 8),
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
    final cores = Theme.of(context).colorScheme;
    final pequeno = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    final id = e.id ?? '';
    final rotinas = [for (final x in sala.rotinas.daEquipe(equipe.id)) if (x.workflow == id) x];
    final abertos = sala.workflows.abertos(equipe.id, id);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Workflow', style: Theme.of(context).textTheme.titleSmall)),
          IconButton(tooltip: 'Fechar', icon: const Icon(Icons.close), onPressed: aoFechar),
        ]),
        Text('Clique numa caixa para editá-la.', style: pequeno),
        _ListaDeErros(erros: e.erros[lugarDoWorkflow] ?? const []),
        const SizedBox(height: 12),
        _CampoDeTexto(
          key: const ValueKey('nome'),
          valor: r['nome'] is String ? r['nome'] as String : '',
          rotulo: 'Nome',
          aoMudar: (v) => e.aplicar((w) => editarWorkflow(w, (c) => c['nome'] = v), grupo: 'workflow/nome'),
        ),
        const SizedBox(height: 4),
        Text('id $id (não muda: é o nome do arquivo)', style: pequeno),
        const SizedBox(height: 16),
        _CamposTipados(
          titulo: 'Entrada: o que se informa ao iniciar',
          campos: camposTipados(r['entrada']),
          aoMudar: (campos, {digitando = false}) =>
              e.aplicar((w) => definirEntrada(w, campos), grupo: digitando ? 'workflow/entrada' : null),
        ),
        const Divider(height: 32),
        Text('Versão', style: pequeno),
        Text(e.novo ? 'ainda não salvo' : '${e.versaoBase}'),
        const SizedBox(height: 12),
        Text('Rotinas que disparam este workflow', style: pequeno),
        if (rotinas.isEmpty) const Text('nenhuma'),
        for (final x in rotinas) Text('${x.nome}${x.ativa ? '' : ' (desativada)'}'),
        const SizedBox(height: 12),
        Text('Execuções abertas', style: pequeno),
        if (abertos.isEmpty) const Text('nenhuma'),
        for (final f in abertos)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: e.sobreposto == f.id,
            leading: CircleAvatar(backgroundColor: corDoFluxo(f.status, cores), radius: 6),
            title: Text('#${f.id} · versão ${f.versao} · ${nomesDeStatusDoFluxo[f.status] ?? f.status}'),
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
            Tooltip(
              message: 'No disco este texto fica em $arquivo; ao salvar, ele volta para o arquivo.',
              child: Chip(
                avatar: const Icon(Icons.description_outlined, size: 16),
                label: Text('em $arquivo'),
                visualDensity: VisualDensity.compact,
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
        icon: const Icon(Icons.data_object, size: 18),
        label: const Text('Inserir valor'),
      ),
    );
  }
}
