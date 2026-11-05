import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../estado/equipes.dart';
import '../estado/sala.dart';
import '../nucleo/modelos.dart';
import '../nucleo/organograma.dart';
import '../nucleo/tarefas.dart';
import 'comum.dart';
import 'rotinas.dart';

bool get edicaoDisponivel =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS;

const _larguraParaPainelFixo = 900.0;
const _larguraDoPainel = 340.0;

class TelaEquipes extends StatelessWidget {
  const TelaEquipes({super.key, required this.sala, this.edicao});

  final Sala sala;
  final bool? edicao;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([sala.equipes, sala]),
        builder: (context, _) {
          final estado = sala.equipes;
          final editar = edicao ?? edicaoDisponivel;
          final equipe = estado.atual;
          final cores = Theme.of(context).colorScheme;
          return LayoutBuilder(builder: (context, limites) {
            final largo = limites.maxWidth >= _larguraParaPainelFixo;
            final personasVisiveis = estado.mostrarPersonas ?? largo;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Material(
                color: cores.surface,
                child: SafeArea(
                  bottom: false,
                  child: _Topo(estado: estado, editar: editar, personasVisiveis: personasVisiveis),
                ),
              ),
              BarraDePausa(estado: estado),
              if (estado.erro != null)
                MaterialBanner(
                  content: Text(estado.erro!),
                  backgroundColor: cores.errorContainer,
                  actions: [TextButton(onPressed: estado.limparErro, child: const Text('Ok'))],
                ),
              const Divider(height: 1),
              Expanded(
                child: !estado.carregada || equipe == null
                    ? const Center(child: CircularProgressIndicator())
                    : _corpo(context, estado, equipe, editar: editar, largo: largo, personasVisiveis: personasVisiveis),
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
    required bool largo,
    required bool personasVisiveis,
  }) {
    if (estado.vendoRotinas) return PainelDeRotinas(sala: sala, equipe: equipe, editar: editar, largo: largo);
    final selecionada = estado.selecionada == null ? null : equipe.posicao(estado.selecionada!);
    final canvas = CanvasDoOrganograma(estado: estado, equipe: equipe, editar: editar);
    if (!editar) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: canvas),
        if (selecionada != null) _DetalheDaPosicao(sala: sala, equipe: equipe, posicao: selecionada),
      ]);
    }
    final Widget? painel = selecionada != null
        ? _PainelDaPosicao(key: ValueKey('${equipe.id}/${selecionada.id}'), estado: estado, posicao: selecionada)
        : personasVisiveis
            ? _PainelDePersonas(estado: estado, personasVisiveis: personasVisiveis)
            : null;
    if (painel == null) {
      return Stack(children: [
        Positioned.fill(child: canvas),
        Positioned(
          top: 12,
          right: 12,
          child: FilledButton.tonalIcon(
            onPressed: () => estado.alternarPersonas(false),
            icon: const Icon(Icons.people_alt_outlined),
            label: const Text('Personas'),
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
    return LayoutBuilder(
      builder: (context, limites) => Stack(children: [
        Positioned.fill(child: canvas),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: limites.maxWidth * 0.9 < _larguraDoPainel ? limites.maxWidth * 0.9 : _larguraDoPainel,
          child: Material(elevation: 8, child: painel),
        ),
      ]),
    );
  }
}

class _Topo extends StatelessWidget {
  const _Topo({required this.estado, required this.editar, required this.personasVisiveis});

  final EstadoEquipes estado;
  final bool editar;
  final bool personasVisiveis;

  Future<void> _novaEquipe(BuildContext context) async {
    final nome = await pedirTexto(context, titulo: 'Nova equipe', rotulo: 'Nome da equipe');
    if (nome != null) estado.novaEquipe(nome);
  }

  Future<void> _novaPosicao(BuildContext context) async {
    final titulo = await pedirTexto(context, titulo: 'Nova posição', rotulo: 'Título (ex.: revisora)');
    if (titulo != null) estado.novaPosicao(titulo);
  }

  Future<void> _excluirEquipe(BuildContext context, EquipeResumo equipe) async {
    final ok = await confirmar(context, 'Excluir a equipe ${equipe.nome}?', 'Equipe com tarefa aberta não pode ser excluída.');
    if (ok) estado.excluirEquipe();
  }

  @override
  Widget build(BuildContext context) {
    final equipe = estado.atual;
    final ids = {for (final e in estado.equipes) e.id};
    final opcoes = [
      for (final e in estado.equipes) DropdownMenuItem(value: e.id, child: Text(e.nome, overflow: TextOverflow.ellipsis)),
      if (equipe != null && !ids.contains(equipe.id))
        DropdownMenuItem(value: equipe.id, child: Text('${equipe.nome} (nova)', overflow: TextOverflow.ellipsis)),
    ];
    return LayoutBuilder(builder: (context, limites) {
      final compacto = limites.maxWidth < 760;
      Widget acao(IconData icone, String rotulo, VoidCallback? aoTocar, {bool principal = false, bool marcado = false}) {
        if (compacto) {
          return IconButton(
            tooltip: rotulo,
            isSelected: marcado,
            onPressed: aoTocar,
            icon: Icon(icone),
            style: principal ? IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer) : null,
          );
        }
        if (principal) return FilledButton.icon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
        if (marcado) return FilledButton.tonalIcon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
        return OutlinedButton.icon(onPressed: aoTocar, icon: Icon(icone), label: Text(rotulo));
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          const Avatar(cor: Color(Perfil.corBoard), inicial: 'E', tamanho: 32),
          if (!editar)
            IconButton(
              tooltip: estado.vendoRotinas ? 'Organograma' : 'Rotinas',
              isSelected: estado.vendoRotinas,
              icon: const Icon(Icons.schedule),
              onPressed: () => estado.verRotinas(!estado.vendoRotinas),
            ),
          if (!editar && !estado.vendoRotinas)
            IconButton(
              tooltip: 'Personas',
              icon: const Icon(Icons.people_alt_outlined),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.7,
                  child: ListenableBuilder(
                    listenable: estado,
                    builder: (_, _) => _PainelDePersonas(estado: estado, personasVisiveis: true, gerenciar: false),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: DropdownButton<String>(
              value: equipe?.id,
              isExpanded: compacto,
              items: opcoes,
              underline: const SizedBox.shrink(),
              onChanged: (id) async {
                if (id == null || id == equipe?.id) return;
                if (estado.alterada && !await confirmar(context, 'Descartar as mudanças?', 'Há mudanças não salvas nesta equipe.')) {
                  return;
                }
                estado.escolher(id);
              },
            ),
          ),
          if (editar && estado.alterada && !compacto)
            const Padding(padding: EdgeInsets.only(left: 8), child: Chip(label: Text('não salvo'), visualDensity: VisualDensity.compact)),
          if (!editar) const Spacer(),
          if (editar)
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
              acao(Icons.schedule, 'Rotinas', () => estado.verRotinas(!estado.vendoRotinas), marcado: estado.vendoRotinas),
              acao(Icons.group_add_outlined, 'Nova equipe', () => _novaEquipe(context)),
              if (!estado.vendoRotinas) ...[
                acao(Icons.add_box_outlined, 'Posição', equipe == null ? null : () => _novaPosicao(context)),
                acao(Icons.account_tree_outlined, 'Organizar',
                    equipe == null || equipe.posicoes.isEmpty ? null : () => estado.aplicar(organizar)),
                acao(Icons.people_alt_outlined, 'Personas', () => estado.alternarPersonas(personasVisiveis), marcado: personasVisiveis),
              ],
              acao(Icons.save_outlined, estado.alterada ? 'Salvar' : 'Salvo', estado.alterada && !estado.salvando ? estado.salvar : null,
                  principal: true),
              if (estado.alterada) acao(Icons.undo, 'Descartar', estado.descartar),
              if (equipe != null && equipe.id != 'casa')
                IconButton(tooltip: 'Excluir equipe', onPressed: () => _excluirEquipe(context, equipe), icon: const Icon(Icons.delete_outline)),
                ],
              ),
            ),
        ]),
      );
    });
  }
}

enum _Gesto { fundo, cartao, alca }

class CanvasDoOrganograma extends StatefulWidget {
  const CanvasDoOrganograma({super.key, required this.estado, required this.equipe, required this.editar});

  final EstadoEquipes estado;
  final EquipeResumo equipe;
  final bool editar;

  @override
  State<CanvasDoOrganograma> createState() => _CanvasDoOrganogramaState();
}

class _CanvasDoOrganogramaState extends State<CanvasDoOrganograma> {
  Vista? _vista;
  String? _ajustadaPara;
  Size _tamanho = Size.zero;
  _Gesto? _gesto;
  String? _alvo;
  Ponto _pegaNoCartao = (x: 0, y: 0);
  Ponto? _cartaoEm;
  Ponto? _ponteiro;
  double _escalaNoInicio = 1;
  Offset? _pressionado;
  String? _linhaSobre;
  MouseCursor _cursor = SystemMouseCursors.grab;

  Vista get _v => _vista ?? (dx: 0, dy: 0, escala: 1);

  EquipeResumo get _mostrada {
    final id = _alvo;
    final em = _cartaoEm;
    if (_gesto == _Gesto.cartao && id != null && em != null && widget.equipe.posicao(id) != null) {
      return mover(widget.equipe, id, em.x, em.y);
    }
    return widget.equipe;
  }

  void _ajustar() => setState(() => _vista = ajustarVista(widget.equipe, _tamanho.width, _tamanho.height));

  void _zoom(double fator, {Offset? foco}) {
    final centro = foco ?? Offset(_tamanho.width / 2, _tamanho.height / 2);
    setState(() => _vista = zoomEm(_v, centro.dx, centro.dy, _v.escala * fator));
  }

  _Gesto _gestoEm(Ponto mundo) {
    if (!widget.editar) return _Gesto.fundo;
    if (alcaEm(widget.equipe, mundo.x, mundo.y) != null) return _Gesto.alca;
    return alvoEm(widget.equipe, mundo.x, mundo.y) is NaPosicao ? _Gesto.cartao : _Gesto.fundo;
  }

  void _aoPassar(PointerHoverEvent e) {
    final mundo = paraMundo(_v, e.localPosition.dx, e.localPosition.dy);
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

  void _avisar(String texto, {EquipeResumo? desfazerPara}) {
    final mensageiro = ScaffoldMessenger.maybeOf(context);
    if (mensageiro == null) return;
    mensageiro.hideCurrentSnackBar();
    mensageiro.showSnackBar(SnackBar(
      content: Text(texto),
      duration: const Duration(seconds: 4),
      action: desfazerPara == null
          ? null
          : SnackBarAction(label: 'Desfazer', onPressed: () => widget.estado.aplicar((_) => desfazerPara)),
    ));
  }

  void _ligar(String chefe, NaPosicao? destino) {
    final antes = widget.estado.atual;
    if (antes == null) return;
    if (destino == null || destino.id == chefe) {
      _avisar('Solte o + em cima de outro cartão para ligar.');
      return;
    }
    widget.estado.aplicar((e) => ligarPelaAlca(e, chefe, destino));
    if (widget.estado.erro == null) {
      _avisar('${_titulo(antes, destino.id)} agora responde a ${_titulo(antes, chefe)}.', desfazerPara: antes);
    }
  }

  void _desligar(String filho) {
    final antes = widget.estado.atual;
    final chefe = antes?.posicao(filho)?.respondeA;
    if (antes == null || chefe == null) return;
    widget.estado.aplicar((e) => soltar(e, filho));
    setState(() => _linhaSobre = null);
    _avisar('${_titulo(antes, filho)} não responde mais a ${_titulo(antes, chefe)}.', desfazerPara: antes);
  }

  Future<void> _criarSubordinada(String chefe) async {
    final nome = _titulo(widget.equipe, chefe);
    final titulo = await pedirTexto(context, titulo: 'Subordinada de $nome', rotulo: 'Título (ex.: executor)', acao: 'Criar');
    if (titulo != null) widget.estado.novaSubordinada(chefe, titulo);
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

  void _inicio(ScaleStartDetails d) {
    final ponto = d.pointerCount == 1 && _pressionado != null ? _pressionado! : d.localFocalPoint;
    final mundo = paraMundo(_v, ponto.dx, ponto.dy);
    _escalaNoInicio = _v.escala;
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
    final mundo = paraMundo(_v, d.localFocalPoint.dx, d.localFocalPoint.dy);
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
          var v = _v;
          if (d.scale != 1) v = zoomEm(v, d.localFocalPoint.dx, d.localFocalPoint.dy, _escalaNoInicio * d.scale);
          _vista = deslocarVista(v, d.focalPointDelta.dx, d.focalPointDelta.dy);
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
    final mundo = paraMundo(_v, d.localPosition.dx, d.localPosition.dy);
    final alca = widget.editar ? alcaEm(widget.equipe, mundo.x, mundo.y) : null;
    if (alca != null) {
      _criarSubordinada(alca);
      return;
    }
    final alvo = alvoEm(widget.equipe, mundo.x, mundo.y);
    if (alvo != null) {
      widget.estado.selecionar(widget.estado.selecionada == alvo.id ? null : alvo.id);
      return;
    }
    final linha = widget.editar ? ligacaoEm(widget.equipe, mundo.x, mundo.y) : null;
    if (linha != null) {
      _desligar(linha);
    } else if (widget.estado.selecionada != null) {
      widget.estado.selecionar(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    if (widget.equipe.posicoes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.editar ? 'Equipe sem posições. Use "Posição" para começar.' : 'Equipe sem posições.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cores.onSurfaceVariant),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, limites) {
      _tamanho = limites.biggest;
      if (_vista == null || _ajustadaPara != widget.equipe.id) {
        _vista = ajustarVista(widget.equipe, _tamanho.width, _tamanho.height);
        _ajustadaPara = widget.equipe.id;
      }
      final equipe = _mostrada;
      final v = _v;
      final tamanho = tamanhoDoOrganograma(equipe);
      return Listener(
        onPointerSignal: _roda,
        onPointerDown: (e) => _pressionado = e.localPosition,
        child: MouseRegion(
          cursor: _cursor,
          onHover: _aoPassar,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _toque,
            onScaleStart: _inicio,
            onScaleUpdate: _durante,
            onScaleEnd: _fim,
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
                        child: _Area(
                          equipe: equipe,
                          editar: widget.editar,
                          selecionada: widget.estado.selecionada,
                          ligandoDe: _gesto == _Gesto.alca ? _alvo : null,
                          ponteiro: _ponteiro,
                          destino: _gesto == _Gesto.alca && _ponteiro != null ? alvoEm(equipe, _ponteiro!.x, _ponteiro!.y)?.id : null,
                          linhaRealcada: _linhaSobre,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.editar)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    right: 260,
                    child: Text(
                      'Clique no + para criar uma subordinada, ou arraste-o até outro cartão para ligar · clique numa linha para desfazer a ligação · arraste o fundo para mover · Ctrl + roda para zoom',
                      style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _ControlesDeZoom(
                    escala: v.escala,
                    aoAproximar: () => _zoom(1.2),
                    aoAfastar: () => _zoom(1 / 1.2),
                    aoAjustar: _ajustar,
                    aoTamanhoReal: () => _zoom(1 / v.escala),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
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
  });

  final EquipeResumo equipe;
  final bool editar;
  final String? selecionada;
  final String? ligandoDe;
  final Ponto? ponteiro;
  final String? destino;
  final String? linhaRealcada;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _Ligacoes(
            equipe: equipe,
            cor: cores.outlineVariant,
            destaque: cores.primary,
            ligandoDe: ligandoDe,
            ponteiro: ponteiro == null ? null : Offset(ponteiro!.x, ponteiro!.y),
            linhaRealcada: linhaRealcada,
          ),
        ),
      ),
      for (final p in equipe.posicoes) ...[
        Positioned(
          left: cantoDoCartao(equipe, p.id).x,
          top: cantoDoCartao(equipe, p.id).y,
          width: larguraDoCartao,
          height: alturaDoCartao,
          child: _Cartao(posicao: p, escolhida: selecionada == p.id || destino == p.id),
        ),
        if (editar)
          Positioned(
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
              child: Icon(Icons.add, size: 16, color: cores.onPrimary),
            ),
          ),
      ],
    ]);
  }
}

class _ControlesDeZoom extends StatelessWidget {
  const _ControlesDeZoom({
    required this.escala,
    required this.aoAproximar,
    required this.aoAfastar,
    required this.aoAjustar,
    required this.aoTamanhoReal,
  });

  final double escala;
  final VoidCallback aoAproximar;
  final VoidCallback aoAfastar;
  final VoidCallback aoAjustar;
  final VoidCallback aoTamanhoReal;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 3,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: 'Afastar (Ctrl + roda)', onPressed: escala > escalaMinima ? aoAfastar : null, icon: const Icon(Icons.remove)),
          TextButton(onPressed: aoTamanhoReal, child: Text('${(escala * 100).round()}%')),
          IconButton(tooltip: 'Aproximar (Ctrl + roda)', onPressed: escala < escalaMaxima ? aoAproximar : null, icon: const Icon(Icons.add)),
          IconButton(tooltip: 'Ajustar à tela', onPressed: aoAjustar, icon: const Icon(Icons.fit_screen_outlined)),
        ]),
      );
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.posicao, required this.escolhida});

  final PosicaoResumo posicao;
  final bool escolhida;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final persona = posicao.persona;
    final nome = persona == null ? 'vaga' : (posicao.personaNome ?? Perfil.porChave(persona).nome);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: cores.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: escolhida ? cores.primary : cores.outlineVariant, width: escolhida ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          persona == null
              ? Avatar(cor: cores.outlineVariant, inicial: '?', tamanho: 26)
              : Avatar.doPerfil(persona, tamanho: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(posicao.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
        ]),
        const Spacer(),
        Text(
          posicao.capacidades.map((c) => nomesDeCapacidade[c] ?? c).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11),
        ),
      ]),
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

class _PainelDaPosicao extends StatefulWidget {
  const _PainelDaPosicao({super.key, required this.estado, required this.posicao});

  final EstadoEquipes estado;
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

  @override
  Widget build(BuildContext context) {
    final p = widget.posicao;
    final cores = Theme.of(context).colorScheme;
    final equipe = widget.estado.atual!;
    final chefe = p.respondeA == null ? null : equipe.posicao(p.respondeA!);
    final comandos = p.capacidades.contains('comandos');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('Posição ${p.id}', style: Theme.of(context).textTheme.titleSmall)),
        IconButton(tooltip: 'Fechar', icon: const Icon(Icons.close), onPressed: () => widget.estado.selecionar(null)),
      ]),
      TextField(
        controller: _titulo,
        decoration: const InputDecoration(labelText: 'Título'),
        onChanged: (v) => _editar((x) => x.copiar(titulo: v)),
      ),
      const SizedBox(height: 12),
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
      const SizedBox(height: 12),
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
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () async {
            final titulo = await pedirTexto(context, titulo: 'Subordinada de ${p.titulo}', rotulo: 'Título (ex.: executor)');
            if (titulo != null) widget.estado.novaSubordinada(p.id, titulo);
          },
          icon: const Icon(Icons.subdirectory_arrow_right),
          label: const Text('Adicionar subordinada'),
        ),
      ),
      const SizedBox(height: 8),
      Text('Capacidades', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
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
      if (comandos) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: politicasDeAprovacao.containsKey(p.aprovacao) ? p.aprovacao : 'sempre',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Aprovação de comando'),
          items: [for (final MapEntry(:key, :value) in politicasDeAprovacao.entries) DropdownMenuItem(value: key, child: Text(value))],
          onChanged: (v) => _editar((x) => x.copiar(aprovacao: v)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _diretorio,
          decoration: const InputDecoration(labelText: 'Diretório dos comandos (vazio = pasta de dados)'),
          onChanged: (v) => _editar((x) => x.copiar(diretorio: () => v.trim().isEmpty ? null : v.trim())),
        ),
      ],
      const SizedBox(height: 20),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: cores.error),
        onPressed: () {
          widget.estado.aplicar((e) => removerPosicao(e, p.id));
          widget.estado.selecionar(null);
        },
        icon: const Icon(Icons.delete_outline),
        label: const Text('Remover posição'),
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
    final cores = Theme.of(context).colorScheme;
    final politica = posicao.politica;
    final outras = [for (final x in equipe.posicoes) if (x.id != posicao.id) x];
    final erros = errosDaPolitica(equipe, posicao);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Text('Depois da entrega', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
      if (politica.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('a entrega vai direto para você', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
        ),
      for (final (i, etapa) in politica.indexed)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Text('${i + 1}.'),
          minLeadingWidth: 16,
          title: Text(rotuloDaEtapa(etapa, equipe, _nomeDaPersona)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Subir',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: i == 0 ? null : () => _aplicar((e) => moverEtapa(e, posicao.id, i, i - 1)),
            ),
            IconButton(
              tooltip: 'Descer',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_downward, size: 18),
              onPressed: i == politica.length - 1 ? null : () => _aplicar((e) => moverEtapa(e, posicao.id, i, i + 1)),
            ),
            IconButton(
              tooltip: 'Remover etapa',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => _aplicar((e) => removerEtapa(e, posicao.id, i)),
            ),
          ]),
        ),
      for (final erro in erros)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(erro, style: TextStyle(color: cores.error, fontSize: 12)),
        ),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _menu('Adicionar revisão', Icons.rate_review_outlined, [
          for (final x in outras) (_rotuloDaOpcao(x), EtapaDePolitica.revisaoPor(x.id)),
          ('Board da equipe', const EtapaDePolitica.revisaoDoBoard()),
        ]),
        _menu('Adicionar aprovação', Icons.verified_outlined, [
          for (final x in outras) (_rotuloDaOpcao(x), EtapaDePolitica.aprovacaoPor(x.id)),
          ('Ueslei', const EtapaDePolitica.aprovacaoDoUeslei()),
        ]),
      ]),
    ]);
  }
}

class _PainelDePersonas extends StatelessWidget {
  const _PainelDePersonas({required this.estado, required this.personasVisiveis, this.gerenciar = true});

  final EstadoEquipes estado;
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
      titulo: 'Excluir ${p.nome}?',
      rotulo: 'Digite ${p.nome} para confirmar',
      explicacao: 'As posições dela ficam vagas e as conversas viram só leitura. A memória fica guardada, e o nome não pode ser reusado.',
      acao: 'Excluir',
    );
    if (confirmacao != null) estado.excluirPersona(p.chave, confirmacao);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('Personas', style: Theme.of(context).textTheme.titleSmall)),
        if (gerenciar) ...[
          FilledButton.icon(onPressed: () => _nova(context), icon: const Icon(Icons.person_add_alt), label: const Text('Nova')),
          IconButton(tooltip: 'Ocultar personas', icon: const Icon(Icons.close), onPressed: () => estado.alternarPersonas(personasVisiveis)),
        ],
      ]),
      const SizedBox(height: 4),
      if (gerenciar) Text('Clique num cartão para editar a posição.', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
      const SizedBox(height: 8),
      for (final p in Perfil.todos)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar.doPerfil(p.chave, tamanho: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.nome),
                Text(
                  [p.papel, p.modelo, if (p.gerandoPerfil) 'gerando perfil…', if (p.pausa != null) nomesDePausa[p.pausa] ?? p.pausa]
                      .whereType<String>()
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  style: TextStyle(color: p.pausa != null ? cores.error : cores.onSurfaceVariant, fontSize: 12),
                ),
                Text(
                  'tarefas no mês: US\$ ${p.gastoMesUSD.toStringAsFixed(2)}'
                  '${p.orcamentoMensalUSD != null ? ' de US\$ ${p.orcamentoMensalUSD!.toStringAsFixed(2)}' : ' · sem limite'}',
                  style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
                ),
                Text(
                  'tokens no mês: ${formatarTokens(p.tokensMes)}'
                  '${p.orcamentoMensalTokens != null ? ' de ${formatarTokens(p.orcamentoMensalTokens!)}' : ' · sem limite'}',
                  style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
                ),
                if (p.proporcaoDoOrcamento case final proporcao?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: proporcao,
                      color: proporcao >= 1 ? cores.error : proporcao >= 0.8 ? const Color(0xFFE0A458) : const Color(0xFF4FAE7C),
                    ),
                  ),
              ]),
            ),
            IconButton(
              tooltip: p.pausa == 'ueslei' ? 'Retomar ${p.nome}' : 'Pausar ${p.nome}',
              icon: Icon(p.pausa == 'ueslei' ? Icons.play_arrow : Icons.pause),
              onPressed: () => p.pausa == 'ueslei' ? estado.retomar(p.chave) : estado.pausar(p.chave),
            ),
            if (gerenciar)
              IconButton(tooltip: 'Orçamento', icon: const Icon(Icons.savings_outlined), onPressed: () => _orcamento(context, p)),
            if (gerenciar && p.excluivel)
              IconButton(tooltip: 'Excluir ${p.nome}', icon: const Icon(Icons.person_remove_outlined), onPressed: () => _excluir(context, p)),
          ]),
        ),
    ]);
  }
}

typedef _NovaPersona = ({String nome, String titulo, String base, String? modelo, String? cor});

const _coresSugeridas = ['#e0a458', '#9a6ee8', '#4fae7c', '#e06a8a', '#58b7c9', '#c9a227', '#5b8def', '#d9774b'];

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

  @override
  void dispose() {
    _nome.dispose();
    _titulo.dispose();
    _base.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nova persona'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: _nome, maxLength: 40, decoration: const InputDecoration(labelText: 'Nome', counterText: '')),
              const SizedBox(height: 8),
              TextField(controller: _titulo, maxLength: 60, decoration: const InputDecoration(labelText: 'Papel curto (aparece na lista)', counterText: '')),
              const SizedBox(height: 8),
              TextField(
                controller: _base,
                minLines: 4,
                maxLines: 8,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'Quem é, que papel tem com você e qual é o jeito dela'),
              ),
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
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('cor automática'), selected: _cor == null, onSelected: (_) => setState(() => _cor = null)),
                for (final c in _coresSugeridas)
                  ChoiceChip(
                    label: const SizedBox(width: 12, height: 12),
                    avatar: CircleAvatar(backgroundColor: Color(corDeHex(c))),
                    selected: _cor == c,
                    onSelected: (_) => setState(() => _cor = c),
                  ),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (_nome.text.trim().isEmpty || _base.text.trim().isEmpty) return;
              Navigator.pop<_NovaPersona>(
                context,
                (nome: _nome.text, titulo: _titulo.text, base: _base.text, modelo: _modelo, cor: _cor),
              );
            },
            child: const Text('Criar'),
          ),
        ],
      );
}

class _DetalheDaPosicao extends StatelessWidget {
  const _DetalheDaPosicao({required this.sala, required this.equipe, required this.posicao});

  final Sala sala;
  final EquipeResumo equipe;
  final PosicaoResumo posicao;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final chefe = posicao.respondeA == null ? null : equipe.posicao(posicao.respondeA!);
    final abertas = sala.tarefas.lista
        .where((t) => t.equipe == equipe.id && t.posicao == posicao.id && t.status != 'concluida' && t.status != 'cancelada')
        .toList();
    return Material(
      color: cores.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(posicao.titulo, style: Theme.of(context).textTheme.titleSmall)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => sala.equipes.selecionar(null)),
            ]),
            Text('Persona: ${posicao.persona == null ? 'vaga' : Perfil.porChave(posicao.persona!).nome}'),
            Text('Responde a: ${chefe?.titulo ?? 'ninguém (solta, responde a você)'}'),
            Text('Capacidades: ${posicao.capacidades.map((c) => nomesDeCapacidade[c] ?? c).join(', ')}'),
            if (posicao.capacidades.contains('comandos')) Text('Aprovação: ${politicasDeAprovacao[posicao.aprovacao] ?? posicao.aprovacao}'),
            if (posicao.politica.isNotEmpty) ...[
              const Text('Depois da entrega:'),
              for (final (i, etapa) in posicao.politica.indexed)
                Text('${i + 1}. ${rotuloDaEtapa(etapa, equipe, _nomeDaPersona)}'),
            ],
            if (abertas.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final t in abertas.take(5))
                InkWell(
                  onTap: () {
                    sala.tarefas.escolherEquipe(equipe.id);
                    sala.ir(Tela.tarefas);
                    sala.tarefas.abrir(t.id);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('#${t.id} ${t.titulo} · ${nomesDeStatus[t.status] ?? t.status}',
                        style: TextStyle(color: cores.primary)),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String rotulo,
  String? explicacao,
  String acao = 'Ok',
  bool vazioVale = false,
  bool multilinha = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _DialogoDeTexto(
        titulo: titulo,
        rotulo: rotulo,
        explicacao: explicacao,
        acao: acao,
        vazioVale: vazioVale,
        multilinha: multilinha,
      ),
    );

class _DialogoDeTexto extends StatefulWidget {
  const _DialogoDeTexto({
    required this.titulo,
    required this.rotulo,
    this.explicacao,
    required this.acao,
    this.vazioVale = false,
    this.multilinha = false,
  });

  final String titulo;
  final String rotulo;
  final String? explicacao;
  final String acao;
  final bool vazioVale;
  final bool multilinha;

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
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.titulo),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.explicacao != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.explicacao!)),
          TextField(
            controller: _controle,
            autofocus: true,
            minLines: widget.multilinha ? 3 : 1,
            maxLines: widget.multilinha ? 8 : 1,
            decoration: InputDecoration(labelText: widget.rotulo),
            onSubmitted: (_) => _confirmar(),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _confirmar, child: Text(widget.acao)),
        ],
      );
}

Future<bool> confirmar(BuildContext context, String titulo, String texto) async =>
    await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Confirmar')),
        ],
      ),
    ) ==
    true;

class BarraDePausa extends StatelessWidget {
  const BarraDePausa({super.key, required this.estado});

  final EstadoEquipes estado;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: estado,
      builder: (context, _) => Material(
        color: estado.pausadoTudo ? cores.errorContainer : cores.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Icon(estado.pausadoTudo ? Icons.pause_circle : Icons.play_circle_outline, size: 18,
                color: estado.pausadoTudo ? cores.onErrorContainer : cores.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                estado.pausadoTudo ? 'Tudo pausado: nenhuma tarefa começa.' : 'Personas trabalhando normalmente.',
                style: TextStyle(fontSize: 12, color: estado.pausadoTudo ? cores.onErrorContainer : cores.onSurfaceVariant),
              ),
            ),
            TextButton.icon(
              onPressed: estado.alternarPausaGeral,
              icon: Icon(estado.pausadoTudo ? Icons.play_arrow : Icons.pause),
              label: Text(estado.pausadoTudo ? 'Retomar tudo' : 'Pausar tudo'),
            ),
          ]),
        ),
      ),
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
            'O que estourar primeiro segura as tarefas. Vazio = sem limite.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usd,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Limite mensal em US\$'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tokens,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Limite mensal em tokens (ex.: 2000000)'),
            onSubmitted: (_) => _salvar(),
          ),
          if (_erro != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
