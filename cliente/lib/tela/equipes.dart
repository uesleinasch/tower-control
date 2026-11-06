import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import '../estado/equipes.dart';
import '../estado/sala.dart';
import '../estado/skills.dart';
import '../nucleo/design.dart';
import '../nucleo/modelos.dart';
import '../nucleo/organograma.dart';
import '../nucleo/skills.dart';
import '../nucleo/tarefas.dart';
import 'canvas.dart';
import 'comum.dart';
import 'editor_de_workflow.dart';
import 'importacao.dart';
import 'paineis.dart';
import 'rotinas.dart';
import 'skills.dart';
import 'tema.dart';
import 'workflows.dart';

bool get edicaoDisponivel => ehDesktop;

const _larguraDoPainel = 320.0;
const _ladoDoBotaoDeMenu = 32.0;

class TelaEquipes extends StatelessWidget {
  const TelaEquipes({super.key, required this.sala, this.edicao});

  final Sala sala;
  final bool? edicao;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([sala.equipes, sala, sala.editorDeWorkflow, sala.skills]),
        builder: (context, _) {
          final estado = sala.equipes;
          final editar = edicao ?? edicaoDisponivel;
          if (editar && sala.editorDeWorkflow.aberto) return EditorDeWorkflow(sala: sala);
          final equipe = estado.atual;
          final tema = Theme.of(context);
          final cores = tema.colorScheme;
          return LayoutBuilder(builder: (context, limites) {
            final classe = ClasseDeJanela.de(limites.maxWidth);
            final editarOrganograma = editar && classe != ClasseDeJanela.compact;
            final personasVisiveis = estado.mostrarPersonas ?? classe.comDoisPaineis;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Material(
                color: cores.surface,
                child: SafeArea(
                  bottom: false,
                  child: _Topo(
                    sala: sala,
                    estado: estado,
                    skills: sala.skills,
                    editar: editar,
                    editarOrganograma: editarOrganograma,
                    personasVisiveis: personasVisiveis,
                    classe: classe,
                  ),
                ),
              ),
              BarraDePausa(estado: estado),
              if (estado.erro != null)
                MaterialBanner(
                  leading: Icon(Symbols.error, color: cores.onErrorContainer),
                  content: Text(estado.erro!, style: tema.textTheme.bodyMedium?.copyWith(color: cores.onErrorContainer)),
                  backgroundColor: cores.errorContainer,
                  actions: [
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: cores.onErrorContainer),
                      onPressed: estado.limparErro,
                      child: const Text('Fechar'),
                    ),
                  ],
                ),
              const Divider(height: 1),
              Expanded(
                child: !estado.carregada || equipe == null
                    ? const Center(child: CircularProgressIndicator())
                    : _corpo(
                        context,
                        estado,
                        equipe,
                        editar: editar,
                        editarOrganograma: editarOrganograma,
                        classe: classe,
                        personasVisiveis: personasVisiveis,
                      ),
              ),
            ]);
          });
        },
      );

  Widget _corpo(
    BuildContext context,
    EstadoEquipes estado,
    EquipeResumo equipe, {
    required bool editar,
    required bool editarOrganograma,
    required ClasseDeJanela classe,
    required bool personasVisiveis,
  }) {
    if (estado.vendoRotinas) {
      return PainelDeRotinas(sala: sala, equipe: equipe, editar: editar, largo: classe.comDoisPaineis);
    }
    if (estado.vendoWorkflows) return PainelDeWorkflows(sala: sala, equipe: equipe, desenhar: editar);
    if (estado.vendoSkills && editar) return PainelDeSkills(sala: sala);
    final selecionada = estado.selecionada == null ? null : equipe.posicao(estado.selecionada!);
    final canvas = CanvasDoOrganograma(
      estado: estado,
      equipe: equipe,
      editar: editarOrganograma,
      aviso: editarOrganograma
          ? null
          : editar
              ? 'Alargue a janela para editar o organograma.'
              : 'A edição do organograma fica no desktop.',
      aoCriarPosicao: editarOrganograma ? () => _pedirNovaPosicao(context, estado) : null,
    );
    final Widget? apoio;
    if (selecionada != null) {
      apoio = editarOrganograma
          ? _PainelDaPosicao(
              key: ValueKey('${equipe.id}/${selecionada.id}'),
              estado: estado,
              skills: sala.skills,
              posicao: selecionada,
            )
          : _DetalheDaPosicao(sala: sala, equipe: equipe, posicao: selecionada);
    } else if (editarOrganograma && personasVisiveis) {
      apoio = _PainelDePersonas(estado: estado, skills: sala.skills, personasVisiveis: personasVisiveis);
    } else {
      apoio = null;
    }
    if (apoio == null) return canvas;
    final Widget painel = apoio;
    if (classe.comDoisPaineis) {
      return LadoALado(
        painel: 'equipes',
        rotulo: 'Largura do painel lateral',
        inicial: _larguraDoPainel,
        lateralADireita: true,
        principal: canvas,
        lateral: Material(color: Theme.of(context).colorScheme.surfaceContainer, child: painel),
      );
    }
    return LayoutBuilder(
      builder: (context, limites) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: canvas),
        SizedBox(height: limites.maxHeight * 0.45, child: _Folha(child: painel)),
      ]),
    );
  }
}

class _Folha extends StatelessWidget {
  const _Folha({required this.child});

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

Future<void> _pedirNovaPosicao(BuildContext context, EstadoEquipes estado) async {
  final titulo = await pedirTexto(context, titulo: 'Nova posição', rotulo: 'Título (ex.: revisora)', acao: 'Criar posição');
  if (titulo != null) estado.novaPosicao(titulo);
}

void _avisar(BuildContext context, String texto, {EstadoEquipes? estado, EquipeResumo? desfazerPara}) {
  final mensageiro = ScaffoldMessenger.maybeOf(context);
  if (mensageiro == null) return;
  mensageiro.hideCurrentSnackBar();
  mensageiro.showSnackBar(SnackBar(
    content: Text(texto),
    duration: const Duration(seconds: 4),
    persist: false,
    action: desfazerPara == null || estado == null
        ? null
        : SnackBarAction(label: 'Desfazer', onPressed: () => estado.aplicar((_) => desfazerPara)),
  ));
}

class _Topo extends StatelessWidget {
  const _Topo({
    required this.sala,
    required this.estado,
    required this.skills,
    required this.editar,
    required this.editarOrganograma,
    required this.personasVisiveis,
    required this.classe,
  });

  final Sala sala;
  final EstadoEquipes estado;
  final EstadoSkills skills;
  final bool editar;
  final bool editarOrganograma;
  final bool personasVisiveis;
  final ClasseDeJanela classe;

  Future<void> _novaEquipe(BuildContext context) async {
    final nome = await pedirTexto(context, titulo: 'Nova equipe', rotulo: 'Nome da equipe', acao: 'Criar equipe');
    if (nome != null) estado.novaEquipe(nome);
  }

  Future<void> _excluirEquipe(BuildContext context, EquipeResumo equipe) async {
    final ok = await confirmar(
      context,
      'Excluir a equipe ${equipe.nome}?',
      'Equipe com tarefa aberta não pode ser excluída.',
      acao: 'Excluir equipe',
      destrutivo: true,
    );
    if (ok) estado.excluirEquipe();
  }

  Future<void> _trocarDeEquipe(BuildContext context, String? id) async {
    if (id == null || id == estado.atual?.id) return;
    if (estado.alterada &&
        !await confirmar(
          context,
          'Descartar as mudanças?',
          'Há mudanças não salvas nesta equipe.',
          acao: 'Descartar mudanças',
          destrutivo: true,
        )) {
      return;
    }
    estado.escolher(id);
  }

  void _verPersonas(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: ListenableBuilder(
            listenable: Listenable.merge([estado, skills]),
            builder: (_, _) => _PainelDePersonas(estado: estado, skills: skills, personasVisiveis: true, gerenciar: false),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final equipe = estado.atual;
    final ids = {for (final e in estado.equipes) e.id};
    final larga = classe.comDoisPaineis;
    final compacta = classe == ClasseDeJanela.compact;
    final aba = estado.vendoSkills && !editar ? AbaDaEquipe.organograma : estado.aba;

    Widget acao(IconData icone, String rotulo, VoidCallback? aoTocar, {bool principal = false, bool marcado = false}) {
      if (!larga) {
        if (principal) return IconButton.filled(tooltip: rotulo, onPressed: aoTocar, icon: Icon(icone));
        return IconButton(
          tooltip: rotulo,
          isSelected: marcado,
          onPressed: aoTocar,
          icon: Icon(icone),
          selectedIcon: Icon(icone, fill: 1),
        );
      }
      if (principal) return FilledButton.icon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
      if (marcado) return FilledButton.tonalIcon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
      return OutlinedButton.icon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
    }

    final acoesDaEquipe = <Widget>[
      if (editarOrganograma) ...[
        acao(Symbols.group_add, 'Nova equipe', () => _novaEquipe(context)),
        acao(Symbols.file_open, 'Importar modelo…', () => importarModelo(context, sala)),
        if (equipe != null && ids.contains(equipe.id))
          IconButton(
            tooltip: 'Exportar como modelo…',
            onPressed: () => exportarEquipeComoModelo(context, sala, equipe, alterada: estado.alterada),
            icon: const Icon(Symbols.ios_share),
          ),
        if (equipe != null && equipe.id != 'casa')
          IconButton(
            tooltip: 'Excluir equipe',
            color: cores.error,
            onPressed: () => _excluirEquipe(context, equipe),
            icon: const Icon(Symbols.delete),
          ),
      ],
      if (editar && estado.alterada)
        larga
            ? TextButton.icon(onPressed: estado.descartar, icon: const Icon(Symbols.undo), label: const Text('Descartar'))
            : IconButton(tooltip: 'Descartar', onPressed: estado.descartar, icon: const Icon(Symbols.undo)),
      if (editarOrganograma || (editar && estado.alterada))
        acao(
          Symbols.save,
          estado.alterada ? 'Salvar' : 'Salvo',
          estado.alterada && !estado.salvando ? estado.salvar : null,
          principal: true,
        ),
    ];

    final opcoes = [
      for (final e in estado.equipes) DropdownMenuItem(value: e.id, child: Text(e.nome, overflow: TextOverflow.ellipsis)),
      if (equipe != null && !ids.contains(equipe.id))
        DropdownMenuItem(value: equipe.id, child: Text('${equipe.nome} (nova)', overflow: TextOverflow.ellipsis)),
    ];
    final seletor = InputDecorator(
      decoration: const InputDecoration(labelText: 'Equipe'),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: equipe?.id,
          isDense: true,
          isExpanded: true,
          items: opcoes,
          onChanged: (id) => _trocarDeEquipe(context, id),
        ),
      ),
    );

    final abas = SegmentedButton<AbaDaEquipe>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: AbaDaEquipe.organograma,
          label: const Text('Organograma'),
          icon: compacta ? null : const Icon(Symbols.account_tree),
        ),
        ButtonSegment(
          value: AbaDaEquipe.rotinas,
          label: const Text('Rotinas'),
          icon: compacta ? null : const Icon(Symbols.event_repeat),
        ),
        ButtonSegment(
          value: AbaDaEquipe.workflows,
          label: const Text('Workflows'),
          icon: compacta ? null : const Icon(Symbols.schema),
        ),
        if (editar)
          ButtonSegment(
            value: AbaDaEquipe.skills,
            label: const Text('Skills'),
            icon: compacta ? null : const Icon(Symbols.extension),
          ),
      ],
      selected: {aba},
      onSelectionChanged: (escolha) => estado.verAba(escolha.first),
    );

    final ferramentas = <Widget>[
      if (aba == AbaDaEquipe.organograma && editarOrganograma) ...[
        acao(Symbols.add_box, 'Posição', equipe == null ? null : () => _pedirNovaPosicao(context, estado)),
        acao(
          Symbols.auto_awesome_mosaic,
          'Organizar',
          equipe == null || equipe.posicoes.isEmpty ? null : () => estado.aplicar(organizar),
        ),
        acao(
          Symbols.person,
          'Personas',
          () => estado.alternarPersonas(personasVisiveis),
          marcado: personasVisiveis,
        ),
      ],
      if (aba == AbaDaEquipe.organograma && !editarOrganograma)
        larga
            ? OutlinedButton.icon(
                onPressed: () => _verPersonas(context),
                icon: const Icon(Symbols.person),
                label: const Text('Personas'),
              )
            : IconButton(tooltip: 'Personas', onPressed: () => _verPersonas(context), icon: const Icon(Symbols.person)),
    ];

    final margem = classe.margemLateral;
    return Padding(
      padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, margem, Espacos.esp3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Equipes', style: tema.textTheme.titleLarge),
              Text(
                'Organograma, rotinas, workflows e skills de cada equipe',
                style: tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant),
              ),
            ]),
          ),
          if (acoesDaEquipe.isNotEmpty) ...[
            const SizedBox(width: Espacos.esp3),
            Flexible(
              flex: 2,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Espacos.esp2,
                runSpacing: Espacos.esp2,
                children: acoesDaEquipe,
              ),
            ),
          ],
        ]),
        const SizedBox(height: Espacos.esp3),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Espacos.esp3,
          runSpacing: Espacos.esp2,
          children: [
            SizedBox(width: compacta ? double.infinity : 260, child: seletor),
            if (editar && estado.alterada)
              Chip(
                avatar: const Icon(Symbols.edit_note),
                label: const Text('não salvo'),
                labelStyle: tema.textTheme.labelMedium,
                visualDensity: VisualDensity.compact,
              ),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: abas),
            if (ferramentas.isNotEmpty) Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: ferramentas),
          ],
        ),
      ]),
    );
  }
}

enum _Gesto { fundo, cartao, alca }

class CanvasDoOrganograma extends StatefulWidget {
  const CanvasDoOrganograma({
    super.key,
    required this.estado,
    required this.equipe,
    required this.editar,
    this.aviso,
    this.aoCriarPosicao,
  });

  final EstadoEquipes estado;
  final EquipeResumo equipe;
  final bool editar;
  final String? aviso;
  final VoidCallback? aoCriarPosicao;

  @override
  State<CanvasDoOrganograma> createState() => _CanvasDoOrganogramaState();
}

class _CanvasDoOrganogramaState extends State<CanvasDoOrganograma> with PanEZoom {
  String? _ajustadaPara;
  _Gesto? _gesto;
  String? _alvo;
  Ponto _pegaNoCartao = (x: 0, y: 0);
  Ponto? _cartaoEm;
  Ponto? _ponteiro;
  Offset? _pressionado;
  String? _linhaSobre;
  MouseCursor _cursor = SystemMouseCursors.grab;
  final _menu = MenuController();
  final _primeiroItem = FocusNode(debugLabel: 'primeiro item do menu do cartão');
  final _focos = <String, FocusNode>{};
  String? _menuDe;
  bool _menuPeloTeclado = false;
  String? _movendo;
  EquipeResumo? _antesDeMover;

  @override
  void didUpdateWidget(CanvasDoOrganograma antigo) {
    super.didUpdateWidget(antigo);
    final ids = {for (final p in widget.equipe.posicoes) p.id};
    final sobras = [for (final id in _focos.keys) if (!ids.contains(id)) id];
    if (sobras.isNotEmpty) {
      final nos = [for (final id in sobras) _focos.remove(id)!];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final no in nos) {
          no.dispose();
        }
      });
    }
    if (_movendo != null && !ids.contains(_movendo)) {
      _movendo = null;
      _antesDeMover = null;
    }
    if (_menuDe != null && !ids.contains(_menuDe)) {
      _menuDe = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _menu.close());
    }
  }

  @override
  void dispose() {
    for (final no in _focos.values) {
      no.dispose();
    }
    _primeiroItem.dispose();
    super.dispose();
  }

  FocusNode _focoDe(String id) => _focos.putIfAbsent(id, () => FocusNode(debugLabel: 'posição $id'));

  EquipeResumo get _mostrada {
    final id = _alvo;
    final em = _cartaoEm;
    if (_gesto == _Gesto.cartao && id != null && em != null && widget.equipe.posicao(id) != null) {
      return mover(widget.equipe, id, em.x, em.y);
    }
    return widget.equipe;
  }

  void _ajustar() => setState(() => vista = ajustarVista(widget.equipe, tamanho.width, tamanho.height));

  void _mostrar(EquipeResumo equipe, String id) =>
      setState(() => vista = vistaComCartao(v, equipe, id, tamanho.width, tamanho.height));

  _Gesto _gestoEm(Ponto mundo) {
    if (!widget.editar) return _Gesto.fundo;
    if (alcaEm(widget.equipe, mundo.x, mundo.y) != null) return _Gesto.alca;
    return alvoEm(widget.equipe, mundo.x, mundo.y) is NaPosicao ? _Gesto.cartao : _Gesto.fundo;
  }

  void _aoPassar(PointerHoverEvent e) {
    final mundo = paraMundo(v, e.localPosition.dx, e.localPosition.dy);
    final gesto = _gestoEm(mundo);
    final linha = gesto == _Gesto.fundo && widget.editar ? ligacaoEm(widget.equipe, mundo.x, mundo.y) : null;
    final cursor = switch (gesto) {
      _Gesto.alca => SystemMouseCursors.precise,
      _Gesto.cartao => SystemMouseCursors.move,
      _Gesto.fundo => linha != null || alvoEm(widget.equipe, mundo.x, mundo.y) != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.grab,
    };
    if (cursor != _cursor || linha != _linhaSobre) {
      setState(() {
        _cursor = cursor;
        _linhaSobre = linha;
      });
    }
  }

  String _titulo(EquipeResumo e, String id) => e.posicao(id)?.titulo ?? id;

  void _avisarComDesfazer(String texto, {EquipeResumo? desfazerPara}) =>
      _avisar(context, texto, estado: widget.estado, desfazerPara: desfazerPara);

  void _ligar(String chefe, NaPosicao? destino) {
    final antes = widget.estado.atual;
    if (antes == null) return;
    if (destino == null || destino.id == chefe) {
      _avisarComDesfazer('Solte o + em cima de outro cartão para ligar.');
      return;
    }
    widget.estado.aplicar((e) => ligarPelaAlca(e, chefe, destino));
    if (widget.estado.erro == null) {
      _avisarComDesfazer('${_titulo(antes, destino.id)} agora responde a ${_titulo(antes, chefe)}.', desfazerPara: antes);
    }
  }

  void _ligarA(String filho, String chefe) {
    final antes = widget.estado.atual;
    if (antes == null) return;
    widget.estado.aplicar((e) => ligarAbaixo(e, filho, chefe));
    if (widget.estado.erro == null) {
      _avisarComDesfazer('${_titulo(antes, filho)} agora responde a ${_titulo(antes, chefe)}.', desfazerPara: antes);
    }
  }

  void _desligar(String filho) {
    final antes = widget.estado.atual;
    final chefe = antes?.posicao(filho)?.respondeA;
    if (antes == null || chefe == null) return;
    widget.estado.aplicar((e) => soltar(e, filho));
    setState(() => _linhaSobre = null);
    _avisarComDesfazer('${_titulo(antes, filho)} não responde mais a ${_titulo(antes, chefe)}.', desfazerPara: antes);
  }

  void _remover(String id) {
    final antes = widget.estado.atual;
    if (antes == null) return;
    widget.estado.aplicar((e) => removerPosicao(e, id));
    if (widget.estado.selecionada == id) widget.estado.selecionar(null);
    _avisarComDesfazer('${_titulo(antes, id)} saiu do organograma.', desfazerPara: antes);
  }

  Future<void> _criarSubordinada(String chefe) async {
    final nome = _titulo(widget.equipe, chefe);
    final titulo = await pedirTexto(
      context,
      titulo: 'Subordinada de $nome',
      rotulo: 'Título (ex.: executor)',
      acao: 'Criar posição',
    );
    if (titulo != null) widget.estado.novaSubordinada(chefe, titulo);
  }

  void _ativar(String id) => widget.estado.selecionar(widget.estado.selecionada == id ? null : id);

  void _comecarMovimento(String id) {
    setState(() {
      _movendo = id;
      _antesDeMover = widget.estado.atual;
    });
    _focoDe(id).requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _movendo == id) _focoDe(id).requestFocus();
    });
  }

  void _passo(String id, double dx, double dy) {
    widget.estado.aplicar((e) => deslocar(e, id, dx * passoDeMover, dy * passoDeMover));
    final equipe = widget.estado.atual;
    if (equipe != null) _mostrar(equipe, id);
  }

  void _terminarMovimento() {
    final id = _movendo;
    final antes = _antesDeMover;
    if (id == null) return;
    setState(() {
      _movendo = null;
      _antesDeMover = null;
    });
    final depois = widget.estado.atual;
    if (antes != null && depois != null && depois.posicao(id) != null && antes.ponto(id) != depois.ponto(id)) {
      _avisarComDesfazer('${_titulo(depois, id)} mudou de lugar.', desfazerPara: antes);
    }
  }

  void _aoFocar(String id, bool focado) {
    if (!focado) return;
    if (_movendo != null && _movendo != id) _terminarMovimento();
    if (FocusManager.instance.highlightMode == FocusHighlightMode.traditional) _mostrar(widget.equipe, id);
  }

  Offset _naTela(Ponto mundo) => Offset(mundo.x * v.escala + v.dx, mundo.y * v.escala + v.dy);

  void _abrirMenu(String id, Offset local, {bool teclado = false}) {
    if (!widget.editar || widget.equipe.posicao(id) == null) return;
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

  void _abrirMenuDoCartao(String id, {bool teclado = false}) {
    final c = cantoDoCartao(widget.equipe, id);
    _abrirMenu(
      id,
      _naTela((x: c.x + larguraDoCartao - _ladoDoBotaoDeMenu - Espacos.esp1, y: c.y + Espacos.esp1 + _ladoDoBotaoDeMenu)),
      teclado: teclado,
    );
  }

  void _aoFecharMenu() {
    final id = _menuDe;
    if (_menuPeloTeclado && id != null && _movendo == null && mounted) _focoDe(id).requestFocus();
    _menuPeloTeclado = false;
  }

  List<Widget> _itensDoMenu(ColorScheme cores) {
    final id = _menuDe;
    final p = id == null ? null : widget.equipe.posicao(id);
    if (p == null || !widget.editar) return const [];
    final chefes = [for (final c in chefesPossiveis(widget.equipe, p.id)) if (c.id != p.respondeA) c];
    return [
      MenuItemButton(
        focusNode: _primeiroItem,
        leadingIcon: const Icon(Symbols.edit),
        shortcut: const SingleActivator(LogicalKeyboardKey.enter),
        onPressed: () => widget.estado.selecionar(p.id),
        child: const Text('Editar posição'),
      ),
      SubmenuButton(
        leadingIcon: const Icon(Symbols.link),
        menuChildren: [
          for (final c in chefes)
            MenuItemButton(onPressed: () => _ligarA(p.id, c.id), child: Text(_rotuloDaOpcao(c))),
        ],
        child: const Text('Ligar a…'),
      ),
      if (p.respondeA != null)
        MenuItemButton(
          leadingIcon: const Icon(Symbols.link_off),
          onPressed: () => _desligar(p.id),
          child: const Text('Desfazer a ligação'),
        ),
      MenuItemButton(
        leadingIcon: const Icon(Symbols.open_with),
        onPressed: () => _comecarMovimento(p.id),
        child: const Text('Mover'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Symbols.subdirectory_arrow_right),
        onPressed: () => _criarSubordinada(p.id),
        child: const Text('Adicionar subordinada'),
      ),
      const Divider(),
      MenuItemButton(
        leadingIcon: Icon(Symbols.delete, color: cores.error),
        style: MenuItemButton.styleFrom(foregroundColor: cores.error),
        onPressed: () => _remover(p.id),
        child: const Text('Remover posição'),
      ),
    ];
  }

  void _inicio(ScaleStartDetails d) {
    _terminarMovimento();
    final ponto = d.pointerCount == 1 && _pressionado != null ? _pressionado! : d.localFocalPoint;
    final mundo = paraMundo(v, ponto.dx, ponto.dy);
    comecarPinca();
    final gesto = d.pointerCount > 1 || d.kind == PointerDeviceKind.trackpad ? _Gesto.fundo : _gestoEm(mundo);
    setState(() {
      _gesto = gesto;
      _alvo = null;
      _cartaoEm = null;
      _ponteiro = null;
      if (gesto == _Gesto.alca) {
        _alvo = alcaEm(widget.equipe, mundo.x, mundo.y);
        _ponteiro = mundo;
      } else if (gesto == _Gesto.cartao) {
        final id = (alvoEm(widget.equipe, mundo.x, mundo.y) as NaPosicao).id;
        final canto = cantoDoCartao(widget.equipe, id);
        _alvo = id;
        _pegaNoCartao = (x: mundo.x - canto.x, y: mundo.y - canto.y);
      } else {
        _cursor = SystemMouseCursors.grabbing;
      }
    });
  }

  void _durante(ScaleUpdateDetails d) {
    final mundo = paraMundo(v, d.localFocalPoint.dx, d.localFocalPoint.dy);
    setState(() {
      switch (_gesto) {
        case _Gesto.cartao:
          _cartaoEm = (
            x: mundo.x - _pegaNoCartao.x - margemDoOrganograma,
            y: mundo.y - _pegaNoCartao.y - topoDoOrganograma,
          );
        case _Gesto.alca:
          _ponteiro = mundo;
        case _Gesto.fundo || null:
          aplicarPinca(d);
      }
    });
  }

  void _fim(ScaleEndDetails _) {
    final gesto = _gesto;
    final id = _alvo;
    final em = _cartaoEm;
    final ponteiro = _ponteiro;
    setState(() {
      _gesto = null;
      _alvo = null;
      _cartaoEm = null;
      _ponteiro = null;
      _cursor = SystemMouseCursors.grab;
    });
    if (id == null) return;
    if (gesto == _Gesto.cartao && em != null) widget.estado.aplicar((e) => mover(e, id, em.x, em.y));
    if (gesto == _Gesto.alca && ponteiro != null) _ligar(id, alvoEm(widget.equipe, ponteiro.x, ponteiro.y));
  }

  void _toque(TapUpDetails d) {
    _terminarMovimento();
    final mundo = paraMundo(v, d.localPosition.dx, d.localPosition.dy);
    final alca = widget.editar ? alcaEm(widget.equipe, mundo.x, mundo.y) : null;
    if (alca != null) {
      _criarSubordinada(alca);
      return;
    }
    final alvo = alvoEm(widget.equipe, mundo.x, mundo.y);
    if (alvo != null) {
      _focoDe(alvo.id).requestFocus();
      _ativar(alvo.id);
      return;
    }
    final linha = widget.editar ? ligacaoEm(widget.equipe, mundo.x, mundo.y) : null;
    if (linha != null) {
      _desligar(linha);
    } else if (widget.estado.selecionada != null) {
      widget.estado.selecionar(null);
    }
  }

  void _toqueSecundario(TapUpDetails d) {
    final mundo = paraMundo(v, d.localPosition.dx, d.localPosition.dy);
    final alvo = alvoEm(widget.equipe, mundo.x, mundo.y);
    if (alvo == null) return;
    _focoDe(alvo.id).requestFocus();
    _abrirMenu(alvo.id, d.localPosition);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    if (widget.equipe.posicoes.isEmpty) {
      final cor = cores.onSurfaceVariant;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Espacos.esp5),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Symbols.account_tree, color: cor),
            const SizedBox(height: Espacos.esp2),
            Text(
              widget.editar ? 'Esta equipe ainda não tem posições.' : 'Equipe sem posições.',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodyMedium?.copyWith(color: cor),
            ),
            if (widget.aoCriarPosicao case final criar?) ...[
              const SizedBox(height: Espacos.esp3),
              FilledButton.tonalIcon(onPressed: criar, icon: const Icon(Symbols.add_box), label: const Text('Nova posição')),
            ],
          ]),
        ),
      );
    }
    return LayoutBuilder(builder: (context, limites) {
      tamanho = limites.biggest;
      if (vista == null || _ajustadaPara != widget.equipe.id) {
        vista = ajustarVista(widget.equipe, tamanho.width, tamanho.height);
        _ajustadaPara = widget.equipe.id;
      }
      final equipe = _mostrada;
      final area = tamanhoDoOrganograma(equipe);
      final movendo = _movendo;
      final dica = movendo != null
          ? 'Movendo ${_titulo(equipe, movendo)}: as setas deslocam o cartão, e Enter ou Esc termina.'
          : widget.editar
              ? 'Clique no + para criar uma subordinada, ou arraste-o até outro cartão para ligar · clique numa linha para '
                  'desfazer a ligação · arraste o fundo para mover · Ctrl + roda para zoom · Tab percorre os cartões e '
                  'Shift+F10 abre o menu do cartão'
              : widget.aviso;
      return FocusTraversalGroup(
        child: MenuAnchor(
          controller: _menu,
          onClose: _aoFecharMenu,
          menuChildren: _itensDoMenu(cores),
          child: Listener(
            onPointerSignal: rodar,
            onPointerDown: (e) {
              _pressionado = e.localPosition;
              if (_menu.isOpen) _menu.close();
            },
            child: MouseRegion(
              cursor: _cursor,
              onHover: _aoPassar,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _toque,
                onSecondaryTapUp: widget.editar ? _toqueSecundario : null,
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
                        child: _Area(
                          equipe: equipe,
                          editar: widget.editar,
                          selecionada: widget.estado.selecionada,
                          ligandoDe: _gesto == _Gesto.alca ? _alvo : null,
                          ponteiro: _ponteiro,
                          destino: _gesto == _Gesto.alca && _ponteiro != null
                              ? alvoEm(equipe, _ponteiro!.x, _ponteiro!.y)?.id
                              : null,
                          linhaRealcada: _linhaSobre,
                          erguida: _gesto == _Gesto.cartao ? _alvo : movendo,
                          movendo: movendo,
                          focoDe: _focoDe,
                          aoAtivar: _ativar,
                          aoAbrirMenu: widget.editar ? (id) => _abrirMenuDoCartao(id, teclado: true) : null,
                          aoMover: _passo,
                          aoTerminar: _terminarMovimento,
                          aoFocar: _aoFocar,
                        ),
                      ),
                    ),
                    if (widget.editar)
                      mundo(
                        largura: area.largura,
                        altura: area.altura,
                        interativo: true,
                        child: _BotoesDeMenu(equipe: equipe, aoAbrir: _abrirMenuDoCartao),
                      ),
                    Positioned(
                      left: Espacos.esp3,
                      right: Espacos.esp3,
                      bottom: Espacos.esp3,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(
                          child: dica == null
                              ? const SizedBox.shrink()
                              : _Dica(texto: dica, icone: widget.editar ? null : Symbols.info),
                        ),
                        const SizedBox(width: Espacos.esp3),
                        controlesDeZoom(aoAjustar: _ajustar),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    });
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
  const _BotoesDeMenu({required this.equipe, required this.aoAbrir});

  final EquipeResumo equipe;
  final void Function(String id) aoAbrir;

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        for (final p in equipe.posicoes)
          Positioned(
            key: ValueKey(p.id),
            left: cantoDoCartao(equipe, p.id).x + larguraDoCartao - _ladoDoBotaoDeMenu - Espacos.esp1,
            top: cantoDoCartao(equipe, p.id).y + Espacos.esp1,
            width: _ladoDoBotaoDeMenu,
            height: _ladoDoBotaoDeMenu,
            child: ExcludeFocus(
              child: IconButton(
                tooltip: 'Mais opções de ${p.titulo}',
                iconSize: 20,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(_ladoDoBotaoDeMenu),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => aoAbrir(p.id),
                icon: const Icon(Symbols.more_vert),
              ),
            ),
          ),
      ]);
}

class _Area extends StatelessWidget {
  const _Area({
    required this.equipe,
    required this.editar,
    this.selecionada,
    this.ligandoDe,
    this.ponteiro,
    this.destino,
    this.linhaRealcada,
    this.erguida,
    this.movendo,
    required this.focoDe,
    required this.aoAtivar,
    this.aoAbrirMenu,
    required this.aoMover,
    required this.aoTerminar,
    required this.aoFocar,
  });

  final EquipeResumo equipe;
  final bool editar;
  final String? selecionada;
  final String? ligandoDe;
  final Ponto? ponteiro;
  final String? destino;
  final String? linhaRealcada;
  final String? erguida;
  final String? movendo;
  final FocusNode Function(String id) focoDe;
  final void Function(String id) aoAtivar;
  final void Function(String id)? aoAbrirMenu;
  final void Function(String id, double dx, double dy) aoMover;
  final VoidCallback aoTerminar;
  final void Function(String id, bool focado) aoFocar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final abrirMenu = aoAbrirMenu;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _Ligacoes(
            equipe: equipe,
            cor: cores.outline,
            destaque: cores.primary,
            ligandoDe: ligandoDe,
            ponteiro: ponteiro == null ? null : Offset(ponteiro!.x, ponteiro!.y),
            linhaRealcada: linhaRealcada,
          ),
        ),
      ),
      for (final p in equipe.posicoes) ...[
        Positioned(
          key: ValueKey('cartao-${p.id}'),
          left: cantoDoCartao(equipe, p.id).x,
          top: cantoDoCartao(equipe, p.id).y,
          width: larguraDoCartao,
          height: alturaDoCartao,
          child: _No(
            foco: focoDe(p.id),
            posicao: p,
            escolhida: selecionada == p.id || destino == p.id,
            erguida: erguida == p.id,
            movendo: movendo == p.id,
            comMenu: abrirMenu != null,
            aoAtivar: () => aoAtivar(p.id),
            aoAbrirMenu: abrirMenu == null ? null : () => abrirMenu(p.id),
            aoMover: (dx, dy) => aoMover(p.id, dx, dy),
            aoTerminar: aoTerminar,
            aoFocar: (focado) => aoFocar(p.id, focado),
          ),
        ),
        if (editar)
          Positioned(
            key: ValueKey('alca-${p.id}'),
            left: centroDaAlca(equipe, p.id).x - raioDaAlca,
            top: centroDaAlca(equipe, p.id).y - raioDaAlca,
            child: Container(
              width: raioDaAlca * 2,
              height: raioDaAlca * 2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cores.primary,
                shape: BoxShape.circle,
                border: Border.all(color: cores.surface, width: 2),
              ),
              child: Icon(Symbols.add, size: 16, color: cores.onPrimary),
            ),
          ),
      ],
    ]);
  }
}

class _AbrirMenuIntent extends Intent {
  const _AbrirMenuIntent();
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
    required this.posicao,
    required this.escolhida,
    required this.erguida,
    required this.movendo,
    required this.comMenu,
    required this.aoAtivar,
    this.aoAbrirMenu,
    required this.aoMover,
    required this.aoTerminar,
    required this.aoFocar,
  });

  final FocusNode foco;
  final PosicaoResumo posicao;
  final bool escolhida;
  final bool erguida;
  final bool movendo;
  final bool comMenu;
  final VoidCallback aoAtivar;
  final VoidCallback? aoAbrirMenu;
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
        child: _Cartao(
          posicao: w.posicao,
          escolhida: w.escolhida,
          focada: _realce || w.movendo,
          erguida: w.erguida,
          comMenu: w.comMenu,
        ),
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({
    required this.posicao,
    required this.escolhida,
    this.focada = false,
    this.erguida = false,
    this.comMenu = false,
  });

  final PosicaoResumo posicao;
  final bool escolhida;
  final bool focada;
  final bool erguida;
  final bool comMenu;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final persona = posicao.persona;
    final perfil = persona == null ? null : Perfil.porChave(persona);
    final nome = persona == null ? 'vaga' : (posicao.personaNome ?? perfil!.nome);
    final pausa = perfil?.pausa;
    final estado = estadoDaPausa(pausa);
    final destaque = escolhida || focada;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espacos.esp3, vertical: Espacos.esp2),
      decoration: BoxDecoration(
        color: cores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Raios.md),
        border: Border.all(color: destaque ? cores.primary : cores.outlineVariant, width: destaque ? 2 : 1),
        boxShadow: erguida ? kElevationToShadow[4] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          persona == null ? const _AvatarVago(tamanho: 26) : Avatar.doPerfil(persona, tamanho: 26),
          const SizedBox(width: Espacos.esp2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(posicao.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: tema.textTheme.titleSmall),
              Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: secundario),
            ]),
          ),
          if (comMenu) const SizedBox(width: Espacos.esp5),
        ]),
        const Spacer(),
        Row(children: [
          if (estado != null && pausa != null) ...[
            Flexible(child: RotuloDeEstado(estado: estado, rotulo: nomesDePausa[pausa] ?? pausa)),
            const SizedBox(width: Espacos.esp2),
          ],
          Expanded(
            child: Text(
              posicao.capacidades.map((c) => nomesDeCapacidade[c] ?? c).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: secundario,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _AvatarVago extends StatelessWidget {
  const _AvatarVago({required this.tamanho});

  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Container(
      width: tamanho,
      height: tamanho,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cores.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: cores.outlineVariant),
      ),
      child: Icon(Symbols.person, size: 16, color: cores.onSurfaceVariant),
    );
  }
}

class _Ligacoes extends CustomPainter {
  _Ligacoes({required this.equipe, required this.cor, required this.destaque, this.ligandoDe, this.ponteiro, this.linhaRealcada});

  final EquipeResumo equipe;
  final Color cor;
  final Color destaque;
  final String? ligandoDe;
  final Offset? ponteiro;
  final String? linhaRealcada;

  @override
  void paint(Canvas canvas, Size size) {
    final traco = Paint()
      ..color = cor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final realce = Paint()
      ..color = destaque
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    for (final p in equipe.posicoes) {
      final caminho = caminhoDaLigacao(equipe, p.id);
      if (caminho.isEmpty) continue;
      final path = Path()..moveTo(caminho.first.x, caminho.first.y);
      for (final ponto in caminho.skip(1)) {
        path.lineTo(ponto.x, ponto.y);
      }
      canvas.drawPath(path, p.id == linhaRealcada ? realce : traco);
    }
    final origem = ligandoDe;
    if (origem != null && ponteiro != null && equipe.posicao(origem) != null) {
      final c = centroDaAlca(equipe, origem);
      canvas.drawLine(
        Offset(c.x, c.y),
        ponteiro!,
        Paint()
          ..color = destaque
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Ligacoes antigo) =>
      antigo.equipe != equipe ||
      antigo.ligandoDe != ligandoDe ||
      antigo.ponteiro != ponteiro ||
      antigo.cor != cor ||
      antigo.linhaRealcada != linhaRealcada;
}

class _CabecalhoDoPainel extends StatelessWidget {
  const _CabecalhoDoPainel({required this.titulo, this.subtitulo, this.acoes = const []});

  final String titulo;
  final String? subtitulo;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: tema.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (subtitulo != null)
            Text(subtitulo!, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
        ]),
      ),
      ...acoes,
    ]);
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

class _PainelDaPosicao extends StatefulWidget {
  const _PainelDaPosicao({super.key, required this.estado, required this.skills, required this.posicao});

  final EstadoEquipes estado;
  final EstadoSkills skills;
  final PosicaoResumo posicao;

  @override
  State<_PainelDaPosicao> createState() => _PainelDaPosicaoState();
}

class _PainelDaPosicaoState extends State<_PainelDaPosicao> {
  late final _titulo = TextEditingController(text: widget.posicao.titulo);
  late final _diretorio = TextEditingController(text: widget.posicao.diretorio ?? '');

  @override
  void dispose() {
    _titulo.dispose();
    _diretorio.dispose();
    super.dispose();
  }

  void _editar(PosicaoResumo Function(PosicaoResumo) mudar) =>
      widget.estado.aplicar((e) => editarPosicao(e, widget.posicao.id, mudar));

  void _remover() {
    final antes = widget.estado.atual;
    final p = widget.posicao;
    widget.estado.aplicar((e) => removerPosicao(e, p.id));
    widget.estado.selecionar(null);
    if (antes != null) _avisar(context, '${p.titulo} saiu do organograma.', estado: widget.estado, desfazerPara: antes);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.posicao;
    final cores = Theme.of(context).colorScheme;
    final equipe = widget.estado.atual!;
    final chefe = p.respondeA == null ? null : equipe.posicao(p.respondeA!);
    final comandos = p.capacidades.contains('comandos');
    return ListView(padding: const EdgeInsets.all(Espacos.esp4), children: [
      _CabecalhoDoPainel(
        titulo: p.titulo.trim().isEmpty ? 'Posição' : p.titulo,
        subtitulo: 'Posição ${p.id}',
        acoes: [
          IconButton(tooltip: 'Fechar', icon: const Icon(Symbols.close), onPressed: () => widget.estado.selecionar(null)),
        ],
      ),
      const SizedBox(height: Espacos.esp4),
      TextField(
        controller: _titulo,
        decoration: const InputDecoration(labelText: 'Título'),
        onChanged: (v) => _editar((x) => x.copiar(titulo: v)),
      ),
      const SizedBox(height: Espacos.esp3),
      DropdownButtonFormField<String>(
        initialValue: p.persona ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Persona'),
        items: [
          const DropdownMenuItem(value: '', child: Text('vaga')),
          for (final persona in Perfil.todos) DropdownMenuItem(value: persona.chave, child: Text(persona.nome)),
        ],
        onChanged: (v) => _editar((x) => x.copiar(persona: () => v == null || v.isEmpty ? null : v)),
      ),
      const SizedBox(height: Espacos.esp3),
      DropdownButtonFormField<String>(
        key: ValueKey('chefe-${p.id}-${chefe?.id}'),
        initialValue: chefe?.id ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Responde a'),
        items: [
          const DropdownMenuItem(value: '', child: Text('ninguém (solta, responde a você)')),
          for (final c in chefesPossiveis(equipe, p.id)) DropdownMenuItem(value: c.id, child: Text(c.titulo)),
        ],
        onChanged: (v) => widget.estado.aplicar((e) => v == null || v.isEmpty ? soltar(e, p.id) : ligarAbaixo(e, p.id, v)),
      ),
      const SizedBox(height: Espacos.esp2),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () async {
            final titulo = await pedirTexto(
              context,
              titulo: 'Subordinada de ${p.titulo}',
              rotulo: 'Título (ex.: executor)',
              acao: 'Criar posição',
            );
            if (titulo != null) widget.estado.novaSubordinada(p.id, titulo);
          },
          icon: const Icon(Symbols.subdirectory_arrow_right),
          label: const Text('Adicionar subordinada'),
        ),
      ),
      const _TituloDeSecao('Capacidades'),
      for (final c in capacidadesDePosicao)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: p.capacidades.contains(c),
          title: Text(nomesDeCapacidade[c] ?? c),
          onChanged: (marcado) => _editar((x) => x.copiar(
                capacidades: [
                  for (final k in capacidadesDePosicao)
                    if (k == c ? marcado == true : x.capacidades.contains(k)) k,
                ],
              )),
        ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: p.aprovarPlano,
        title: const Text('Exigir plano aprovado'),
        subtitle: const Text('primeiro propõe um plano; executa depois que você aprovar'),
        onChanged: (v) => _editar((x) => x.copiar(aprovarPlano: v)),
      ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: p.delegaDireto,
        title: const Text('Delegação roda sem aprovação'),
        subtitle: const Text('a subtarefa que esta posição delega já entra na fila'),
        onChanged: (v) => _editar((x) => x.copiar(delegaDireto: v)),
      ),
      _DepoisDaEntrega(estado: widget.estado, equipe: equipe, posicao: p),
      const SizedBox(height: Espacos.esp3),
      SecaoDeSkills(
        itens: skillsDaPosicao(widget.skills.lista, p),
        anexaveis: anexaveis(widget.skills.lista, p.skills),
        aoAnexar: (id) => widget.estado.aplicar((e) => anexarSkillNaPosicao(e, p.id, id)),
        aoTirar: (id) => widget.estado.aplicar((e) => tirarSkillDaPosicao(e, p.id, id)),
      ),
      if (comandos) ...[
        const SizedBox(height: Espacos.esp3),
        DropdownButtonFormField<String>(
          initialValue: politicasDeAprovacao.containsKey(p.aprovacao) ? p.aprovacao : 'sempre',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Aprovação de comando'),
          items: [
            for (final MapEntry(:key, :value) in politicasDeAprovacao.entries) DropdownMenuItem(value: key, child: Text(value)),
          ],
          onChanged: (v) => _editar((x) => x.copiar(aprovacao: v)),
        ),
        const SizedBox(height: Espacos.esp3),
        TextField(
          controller: _diretorio,
          decoration: const InputDecoration(
            labelText: 'Diretório dos comandos',
            helperText: 'Vazio usa a pasta de dados.',
          ),
          onChanged: (v) => _editar((x) => x.copiar(diretorio: () => v.trim().isEmpty ? null : v.trim())),
        ),
      ],
      const SizedBox(height: Espacos.esp5),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: cores.error, side: BorderSide(color: cores.error)),
          onPressed: _remover,
          icon: const Icon(Symbols.delete),
          label: const Text('Remover posição'),
        ),
      ),
    ]);
  }
}

String _nomeDaPersona(String id) => Perfil.porChave(id).nome;

String _rotuloDaOpcao(PosicaoResumo p) =>
    p.persona == null ? '${p.titulo} (vaga)' : '${_nomeDaPersona(p.persona!)} · ${p.titulo}';

class _DepoisDaEntrega extends StatelessWidget {
  const _DepoisDaEntrega({required this.estado, required this.equipe, required this.posicao});

  final EstadoEquipes estado;
  final EquipeResumo equipe;
  final PosicaoResumo posicao;

  void _aplicar(EquipeResumo Function(EquipeResumo) operacao) => estado.aplicar(operacao);

  Widget _menu(String rotulo, IconData icone, List<(String, EtapaDePolitica)> opcoes) => MenuAnchor(
        menuChildren: [
          for (final (texto, etapa) in opcoes)
            MenuItemButton(
              onPressed: () => _aplicar((e) => adicionarEtapa(e, posicao.id, etapa)),
              child: Text(texto),
            ),
        ],
        builder: (context, controle, _) => OutlinedButton.icon(
          onPressed: () => controle.isOpen ? controle.close() : controle.open(),
          icon: Icon(icone),
          label: Text(rotulo),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final politica = posicao.politica;
    final outras = [for (final x in equipe.posicoes) if (x.id != posicao.id) x];
    final erros = errosDaPolitica(equipe, posicao);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _TituloDeSecao('Depois da entrega'),
      if (politica.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacos.esp1),
          child: Text('a entrega vai direto para você', style: secundario),
        ),
      for (final (i, etapa) in politica.indexed)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Text(
            '${i + 1}.',
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
          minLeadingWidth: Espacos.esp4,
          title: Text(rotuloDaEtapa(etapa, equipe, _nomeDaPersona)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Subir',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Symbols.arrow_upward, size: 20),
              onPressed: i == 0 ? null : () => _aplicar((e) => moverEtapa(e, posicao.id, i, i - 1)),
            ),
            IconButton(
              tooltip: 'Descer',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Symbols.arrow_downward, size: 20),
              onPressed: i == politica.length - 1 ? null : () => _aplicar((e) => moverEtapa(e, posicao.id, i, i + 1)),
            ),
            IconButton(
              tooltip: 'Remover etapa',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Symbols.close, size: 20),
              onPressed: () => _aplicar((e) => removerEtapa(e, posicao.id, i)),
            ),
          ]),
        ),
      for (final erro in erros)
        Padding(
          padding: const EdgeInsets.only(bottom: Espacos.esp1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Symbols.error, size: 16, color: cores.error),
            const SizedBox(width: Espacos.esp1),
            Expanded(child: Text(erro, style: tema.textTheme.bodySmall?.copyWith(color: cores.error))),
          ]),
        ),
      const SizedBox(height: Espacos.esp1),
      Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: [
        _menu('Adicionar revisão', Symbols.rate_review, [
          for (final x in outras) (_rotuloDaOpcao(x), EtapaDePolitica.revisaoPor(x.id)),
          ('Board da equipe', const EtapaDePolitica.revisaoDoBoard()),
        ]),
        _menu('Adicionar aprovação', Symbols.verified, [
          for (final x in outras) (_rotuloDaOpcao(x), EtapaDePolitica.aprovacaoPor(x.id)),
          ('Ueslei', const EtapaDePolitica.aprovacaoDoUeslei()),
        ]),
      ]),
    ]);
  }
}

class _PainelDePersonas extends StatelessWidget {
  const _PainelDePersonas({
    required this.estado,
    required this.skills,
    required this.personasVisiveis,
    this.gerenciar = true,
  });

  final EstadoEquipes estado;
  final EstadoSkills skills;
  final bool personasVisiveis;
  final bool gerenciar;

  Future<void> _orcamento(BuildContext context, Perfil p) async {
    final limites = await showDialog<({double? usd, int? tokens})>(
      context: context,
      builder: (_) => _DialogoDeOrcamento(persona: p),
    );
    if (limites != null) estado.salvarOrcamento(p.chave, usd: limites.usd, tokens: limites.tokens);
  }

  Future<void> _nova(BuildContext context) async {
    final dados = await showDialog<_NovaPersona>(context: context, builder: (_) => const _DialogoNovaPersona());
    if (dados == null) return;
    estado.criarPersona(nome: dados.nome, base: dados.base, titulo: dados.titulo, modelo: dados.modelo, cor: dados.cor);
  }

  Future<void> _excluir(BuildContext context, Perfil p) async {
    final confirmacao = await pedirTexto(
      context,
      titulo: 'Excluir persona ${p.nome}?',
      rotulo: 'Digite ${p.nome} para confirmar',
      explicacao: 'As posições dela ficam vagas e as conversas viram só leitura. A memória fica guardada, e o nome não pode ser reusado.',
      acao: 'Excluir persona',
      destrutivo: true,
    );
    if (confirmacao != null) estado.excluirPersona(p.chave, confirmacao);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final semanticas = CoresSemanticas.de(context);
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final numeros = secundario?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return ListView(padding: const EdgeInsets.all(Espacos.esp4), children: [
      _CabecalhoDoPainel(
        titulo: 'Personas',
        acoes: [
          if (gerenciar) ...[
            FilledButton.tonalIcon(onPressed: () => _nova(context), icon: const Icon(Symbols.person_add), label: const Text('Nova')),
            IconButton(
              tooltip: 'Ocultar personas',
              icon: const Icon(Symbols.close),
              onPressed: () => estado.alternarPersonas(personasVisiveis),
            ),
          ],
        ],
      ),
      if (gerenciar)
        Padding(
          padding: const EdgeInsets.only(top: Espacos.esp1),
          child: Text('Clique num cartão para editar a posição.', style: secundario),
        ),
      const SizedBox(height: Espacos.esp2),
      for (final p in Perfil.todos)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacos.esp2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar.doPerfil(p.chave, tamanho: 28),
            const SizedBox(width: Espacos.esp3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.nome, style: tema.textTheme.titleSmall),
                Text(
                  [p.papel, p.modelo, if (p.gerandoPerfil) 'gerando perfil…']
                      .whereType<String>()
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  style: secundario,
                ),
                if (estadoDaPausa(p.pausa) case final estadoDaPersona?)
                  Padding(
                    padding: const EdgeInsets.only(top: Espacos.esp1),
                    child: RotuloDeEstado(estado: estadoDaPersona, rotulo: nomesDePausa[p.pausa] ?? p.pausa!),
                  ),
                Text(
                  'tarefas no mês: US\$ ${p.gastoMesUSD.toStringAsFixed(2)}'
                  '${p.orcamentoMensalUSD != null ? ' de US\$ ${p.orcamentoMensalUSD!.toStringAsFixed(2)}' : ' · sem limite'}',
                  style: numeros,
                ),
                Text(
                  'tokens no mês: ${formatarTokens(p.tokensMes)}'
                  '${p.orcamentoMensalTokens != null ? ' de ${formatarTokens(p.orcamentoMensalTokens!)}' : ' · sem limite'}',
                  style: numeros,
                ),
                if (p.proporcaoDoOrcamento case final proporcao?)
                  Padding(
                    padding: const EdgeInsets.only(top: Espacos.esp1),
                    child: LinearProgressIndicator(
                      value: proporcao,
                      backgroundColor: cores.surfaceContainerHighest,
                      color: proporcao >= 1
                          ? cores.error
                          : proporcao >= 0.8
                              ? semanticas.aviso.cor
                              : semanticas.sucesso.cor,
                    ),
                  ),
                if (gerenciar || skillsDaPersona(skills.lista, p).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Espacos.esp2),
                    child: SecaoDeSkills(
                      itens: skillsDaPersona(skills.lista, p),
                      anexaveis: anexaveis(skills.lista, p.skills),
                      aoAnexar: gerenciar ? (id) => skills.anexarNaPersona(p.chave, id) : null,
                      aoTirar: gerenciar ? (id) => skills.tirarDaPersona(p.chave, id) : null,
                    ),
                  ),
              ]),
            ),
            IconButton(
              tooltip: p.pausa == 'ueslei' ? 'Retomar ${p.nome}' : 'Pausar ${p.nome}',
              icon: Icon(p.pausa == 'ueslei' ? Symbols.play_arrow : Symbols.pause),
              onPressed: () => p.pausa == 'ueslei' ? estado.retomar(p.chave) : estado.pausar(p.chave),
            ),
            if (gerenciar)
              IconButton(tooltip: 'Orçamento', icon: const Icon(Symbols.savings), onPressed: () => _orcamento(context, p)),
            if (gerenciar && p.excluivel)
              IconButton(
                tooltip: 'Excluir ${p.nome}',
                color: cores.error,
                icon: const Icon(Symbols.person_remove),
                onPressed: () => _excluir(context, p),
              ),
          ]),
        ),
    ]);
  }
}

typedef _NovaPersona = ({String nome, String titulo, String base, String? modelo, String? cor});

const _coresSugeridas = [
  ('#e0a458', 'âmbar'),
  ('#9a6ee8', 'roxo'),
  ('#4fae7c', 'verde'),
  ('#e06a8a', 'rosa'),
  ('#58b7c9', 'ciano'),
  ('#c9a227', 'mostarda'),
  ('#5b8def', 'azul'),
  ('#d9774b', 'laranja'),
];

class _DialogoNovaPersona extends StatefulWidget {
  const _DialogoNovaPersona();

  @override
  State<_DialogoNovaPersona> createState() => _DialogoNovaPersonaState();
}

class _DialogoNovaPersonaState extends State<_DialogoNovaPersona> {
  final _nome = TextEditingController();
  final _titulo = TextEditingController();
  final _base = TextEditingController();
  String? _modelo;
  String? _cor;
  bool _tentou = false;

  @override
  void dispose() {
    _nome.dispose();
    _titulo.dispose();
    _base.dispose();
    super.dispose();
  }

  String? get _erroDoNome =>
      _tentou && _nome.text.trim().isEmpty ? 'Falta o nome. Escreva como ela vai aparecer nas conversas.' : null;

  String? get _erroDaBase =>
      _tentou && _base.text.trim().isEmpty ? 'Falta a descrição. Sem ela não dá para gerar o perfil.' : null;

  void _revalidar(String _) {
    if (_tentou) setState(() {});
  }

  void _criar() {
    if (_nome.text.trim().isEmpty || _base.text.trim().isEmpty) {
      setState(() => _tentou = true);
      return;
    }
    Navigator.pop<_NovaPersona>(
      context,
      (nome: _nome.text, titulo: _titulo.text, base: _base.text, modelo: _modelo, cor: _cor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return AlertDialog(
      title: const Text('Nova persona'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _nome,
              maxLength: 40,
              onChanged: _revalidar,
              decoration: InputDecoration(
                labelText: 'Nome',
                helperText: 'Aparece nas conversas e no organograma.',
                errorText: _erroDoNome,
                counterText: '',
              ),
            ),
            const SizedBox(height: Espacos.esp3),
            TextField(
              controller: _titulo,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Papel curto (aparece na lista)', counterText: ''),
            ),
            const SizedBox(height: Espacos.esp3),
            TextField(
              controller: _base,
              minLines: 4,
              maxLines: 8,
              maxLength: 4000,
              onChanged: _revalidar,
              decoration: InputDecoration(
                labelText: 'Quem é, que papel tem com você e qual é o jeito dela',
                helperText: 'O perfil completo é gerado a partir deste texto.',
                errorText: _erroDaBase,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Espacos.esp3),
            DropdownButtonFormField<String>(
              initialValue: _modelo,
              decoration: const InputDecoration(labelText: 'Modelo'),
              items: const [
                DropdownMenuItem(value: null, child: Text('padrão')),
                DropdownMenuItem(value: 'sonnet', child: Text('Sonnet')),
                DropdownMenuItem(value: 'opus', child: Text('Opus')),
              ],
              onChanged: (v) => setState(() => _modelo = v),
            ),
            const SizedBox(height: Espacos.esp4),
            Text('Cor', style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
            const SizedBox(height: Espacos.esp2),
            Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: [
              ChoiceChip(
                label: const Text('automática'),
                selected: _cor == null,
                onSelected: (_) => setState(() => _cor = null),
              ),
              for (final (hex, nome) in _coresSugeridas)
                ChoiceChip(
                  label: Text(nome),
                  avatar: CircleAvatar(backgroundColor: Color(corDeHex(hex))),
                  selected: _cor == hex,
                  onSelected: (_) => setState(() => _cor = hex),
                ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _criar, child: const Text('Criar')),
      ],
    );
  }
}

class _DetalheDaPosicao extends StatelessWidget {
  const _DetalheDaPosicao({required this.sala, required this.equipe, required this.posicao});

  final Sala sala;
  final EquipeResumo equipe;
  final PosicaoResumo posicao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final secundario = tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant);
    final chefe = posicao.respondeA == null ? null : equipe.posicao(posicao.respondeA!);
    final abertas = sala.tarefas.lista
        .where((t) => t.equipe == equipe.id && t.posicao == posicao.id && t.status != 'concluida' && t.status != 'cancelada')
        .toList();
    Widget campo(String rotulo, String valor) => Padding(
          padding: const EdgeInsets.only(bottom: Espacos.esp2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: secundario),
            Text(valor, style: tema.textTheme.bodyMedium),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(Espacos.esp4), children: [
      _CabecalhoDoPainel(
        titulo: posicao.titulo,
        subtitulo: 'Posição ${posicao.id}',
        acoes: [
          IconButton(tooltip: 'Fechar', icon: const Icon(Symbols.close), onPressed: () => sala.equipes.selecionar(null)),
        ],
      ),
      const SizedBox(height: Espacos.esp3),
      campo('Persona', posicao.persona == null ? 'vaga' : Perfil.porChave(posicao.persona!).nome),
      campo('Responde a', chefe?.titulo ?? 'ninguém (solta, responde a você)'),
      campo('Capacidades', posicao.capacidades.map((c) => nomesDeCapacidade[c] ?? c).join(', ')),
      if (posicao.capacidades.contains('comandos'))
        campo('Aprovação', politicasDeAprovacao[posicao.aprovacao] ?? posicao.aprovacao),
      if (posicao.politica.isNotEmpty)
        campo(
          'Depois da entrega',
          [
            for (final (i, etapa) in posicao.politica.indexed) '${i + 1}. ${rotuloDaEtapa(etapa, equipe, _nomeDaPersona)}',
          ].join('\n'),
        ),
      if (posicao.skills.isNotEmpty) ...[
        const SizedBox(height: Espacos.esp2),
        SecaoDeSkills(itens: skillsDaPosicao(sala.skills.lista, posicao), anexaveis: const []),
      ],
      if (abertas.isNotEmpty) ...[
        const _TituloDeSecao('Tarefas abertas'),
        for (final t in abertas.take(5))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('#${t.id} ${t.titulo}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Align(
              alignment: Alignment.centerLeft,
              child: RotuloDeEstado(estado: t.status, rotulo: nomesDeStatus[t.status] ?? t.status),
            ),
            trailing: const Icon(Symbols.chevron_right),
            onTap: () {
              sala.tarefas.escolherEquipe(equipe.id);
              sala.ir(Tela.tarefas);
              sala.tarefas.abrir(t.id);
            },
          ),
      ],
    ]);
  }
}

Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String rotulo,
  String? explicacao,
  String? ajuda,
  String acao = 'Ok',
  bool vazioVale = false,
  bool multilinha = false,
  bool destrutivo = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _DialogoDeTexto(
        titulo: titulo,
        rotulo: rotulo,
        explicacao: explicacao,
        ajuda: ajuda,
        acao: acao,
        vazioVale: vazioVale,
        multilinha: multilinha,
        destrutivo: destrutivo,
      ),
    );

class _DialogoDeTexto extends StatefulWidget {
  const _DialogoDeTexto({
    required this.titulo,
    required this.rotulo,
    this.explicacao,
    this.ajuda,
    required this.acao,
    this.vazioVale = false,
    this.multilinha = false,
    this.destrutivo = false,
  });

  final String titulo;
  final String rotulo;
  final String? explicacao;
  final String? ajuda;
  final String acao;
  final bool vazioVale;
  final bool multilinha;
  final bool destrutivo;

  @override
  State<_DialogoDeTexto> createState() => _DialogoDeTextoState();
}

class _DialogoDeTextoState extends State<_DialogoDeTexto> {
  final _controle = TextEditingController();

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  void _confirmar() => Navigator.pop(context, _controle.text.trim().isEmpty && !widget.vazioVale ? null : _controle.text);

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.explicacao != null)
          Padding(padding: const EdgeInsets.only(bottom: Espacos.esp3), child: Text(widget.explicacao!)),
        TextField(
          controller: _controle,
          autofocus: true,
          minLines: widget.multilinha ? 3 : 1,
          maxLines: widget.multilinha ? 8 : 1,
          decoration: InputDecoration(labelText: widget.rotulo, helperText: widget.ajuda),
          onSubmitted: widget.destrutivo ? null : (_) => _confirmar(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: widget.destrutivo
              ? FilledButton.styleFrom(backgroundColor: cores.error, foregroundColor: cores.onError)
              : null,
          onPressed: _confirmar,
          child: Text(widget.acao),
        ),
      ],
    );
  }
}

Future<bool> confirmar(
  BuildContext context,
  String titulo,
  String texto, {
  String acao = 'Confirmar',
  bool destrutivo = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (contexto) {
        final cores = Theme.of(contexto).colorScheme;
        return AlertDialog(
          title: Text(titulo),
          content: Text(texto),
          actions: [
            TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
            FilledButton(
              style: destrutivo ? FilledButton.styleFrom(backgroundColor: cores.error, foregroundColor: cores.onError) : null,
              onPressed: () => Navigator.pop(contexto, true),
              child: Text(acao),
            ),
          ],
        );
      },
    ) ==
    true;

class BarraDePausa extends StatelessWidget {
  const BarraDePausa({super.key, required this.estado});

  final EstadoEquipes estado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final aviso = CoresSemanticas.de(context).aviso;
    return ListenableBuilder(
      listenable: estado,
      builder: (context, _) {
        final pausado = estado.pausadoTudo;
        final cor = pausado ? aviso.sobreContainer : cores.onSurfaceVariant;
        return Material(
          color: pausado ? aviso.container : cores.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Espacos.esp4, vertical: Espacos.esp1),
            child: Row(children: [
              Icon(pausado ? Symbols.pause_circle : Symbols.play_circle, size: 20, color: cor),
              const SizedBox(width: Espacos.esp2),
              Expanded(
                child: Text(
                  pausado ? 'Tudo pausado: nenhuma tarefa começa.' : 'Personas trabalhando normalmente.',
                  style: tema.textTheme.bodyMedium?.copyWith(color: cor),
                ),
              ),
              if (pausado)
                FilledButton.icon(
                  onPressed: estado.alternarPausaGeral,
                  icon: const Icon(Symbols.play_arrow),
                  label: const Text('Retomar tudo'),
                )
              else
                TextButton.icon(
                  onPressed: estado.alternarPausaGeral,
                  icon: const Icon(Symbols.pause),
                  label: const Text('Pausar tudo'),
                ),
            ]),
          ),
        );
      },
    );
  }
}

String quandoCurto(DateTime em) {
  final l = em.toLocal();
  String d(int n) => n.toString().padLeft(2, '0');
  return '${d(l.day)}/${d(l.month)} ${d(l.hour)}:${d(l.minute)}';
}

class _DialogoDeOrcamento extends StatefulWidget {
  const _DialogoDeOrcamento({required this.persona});

  final Perfil persona;

  @override
  State<_DialogoDeOrcamento> createState() => _DialogoDeOrcamentoState();
}

class _DialogoDeOrcamentoState extends State<_DialogoDeOrcamento> {
  late final _usd = TextEditingController(text: widget.persona.orcamentoMensalUSD?.toString() ?? '');
  late final _tokens = TextEditingController(text: widget.persona.orcamentoMensalTokens?.toString() ?? '');
  String? _erro;

  @override
  void dispose() {
    _usd.dispose();
    _tokens.dispose();
    super.dispose();
  }

  void _salvar() {
    final usdTexto = _usd.text.trim().replaceAll(',', '.');
    final tokensTexto = _tokens.text.trim().replaceAll('.', '').replaceAll(' ', '');
    final usd = usdTexto.isEmpty ? null : double.tryParse(usdTexto);
    final tokens = tokensTexto.isEmpty ? null : int.tryParse(tokensTexto);
    if ((usdTexto.isNotEmpty && (usd == null || usd < 0)) || (tokensTexto.isNotEmpty && (tokens == null || tokens < 0))) {
      setState(() => _erro = 'Use números positivos; tokens sem casas decimais.');
      return;
    }
    Navigator.pop<({double? usd, int? tokens})>(context, (usd: usd, tokens: tokens));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.persona;
    return AlertDialog(
      title: Text('Orçamento de ${p.nome}'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'Neste mês, em tarefas: US\$ ${p.gastoMesUSD.toStringAsFixed(2)} e ${formatarTokens(p.tokensMes)}. '
            'O que estourar primeiro segura as tarefas.',
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: Espacos.esp4),
          TextField(
            controller: _usd,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Limite mensal em US\$', helperText: 'Vazio fica sem limite.'),
          ),
          const SizedBox(height: Espacos.esp3),
          TextField(
            controller: _tokens,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Limite mensal em tokens (ex.: 2000000)',
              helperText: 'Vazio fica sem limite.',
              errorText: _erro,
            ),
            onSubmitted: (_) => _salvar(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
