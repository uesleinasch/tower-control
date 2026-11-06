import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../nucleo/design.dart';

const _espessuraAtiva = 3.0;

String chaveDaLargura(String painel) => 'larguraDoPainel.$painel';

class _Passo extends Intent {
  const _Passo(this.sentido);

  final double sentido;
}

class DivisorArrastavel extends StatefulWidget {
  const DivisorArrastavel({
    super.key,
    required this.rotulo,
    required this.largura,
    required this.aoMover,
    this.aoTerminar,
    this.minimo = 0,
    this.maximo = double.infinity,
    this.painelADireita = false,
  });

  final String rotulo;
  final double largura;
  final ValueChanged<double> aoMover;
  final VoidCallback? aoTerminar;
  final double minimo;
  final double maximo;
  final bool painelADireita;

  @override
  State<DivisorArrastavel> createState() => _DivisorArrastavelState();
}

class _DivisorArrastavelState extends State<DivisorArrastavel> {
  bool _sobre = false;
  bool _focado = false;
  bool _arrastando = false;

  void _passo(double sentido) {
    widget.aoMover(sentido * passoDoDivisor);
    widget.aoTerminar?.call();
  }

  String _pontos(double largura) =>
      '${limitarLargura(largura, minimo: widget.minimo, maximo: widget.maximo).round()} pontos';

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final ativo = _sobre || _focado || _arrastando;
    final alargar = widget.painelADireita ? -1.0 : 1.0;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.resizeColumn,
      onShowHoverHighlight: (v) => setState(() => _sobre = v),
      onShowFocusHighlight: (v) => setState(() => _focado = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _Passo(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _Passo(1),
      },
      actions: {
        _Passo: CallbackAction<_Passo>(onInvoke: (i) {
          _passo(i.sentido);
          return null;
        }),
      },
      child: Semantics(
        slider: true,
        label: widget.rotulo,
        value: _pontos(widget.largura),
        increasedValue: _pontos(widget.largura + passoDoDivisor),
        decreasedValue: _pontos(widget.largura - passoDoDivisor),
        onIncrease: () => _passo(alargar),
        onDecrease: () => _passo(-alargar),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _arrastando = true),
          onHorizontalDragUpdate: (d) => widget.aoMover(d.delta.dx),
          onHorizontalDragEnd: (_) {
            setState(() => _arrastando = false);
            widget.aoTerminar?.call();
          },
          onHorizontalDragCancel: () => setState(() => _arrastando = false),
          child: SizedBox(
            width: Espacos.esp2,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: ativo ? _espessuraAtiva : 1,
                color: ativo ? cores.primary : cores.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LadoALado extends StatefulWidget {
  const LadoALado({
    super.key,
    required this.painel,
    required this.rotulo,
    required this.lateral,
    required this.principal,
    this.inicial = 320,
    this.minimo = 240,
    this.maximo = 560,
    this.restoMinimo = 320,
    this.lateralADireita = false,
  });

  final String painel;
  final String rotulo;
  final Widget lateral;
  final Widget principal;
  final double inicial;
  final double minimo;
  final double maximo;
  final double restoMinimo;
  final bool lateralADireita;

  @override
  State<LadoALado> createState() => _LadoALadoState();
}

class _LadoALadoState extends State<LadoALado> {
  double? _largura;
  double _disponivel = double.infinity;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final salva = (await SharedPreferences.getInstance()).getDouble(chaveDaLargura(widget.painel));
      if (mounted && salva != null && _largura == null) setState(() => _largura = salva);
    } on Exception {
      return;
    }
  }

  Future<void> _salvar() async {
    final largura = _largura;
    if (largura == null) return;
    try {
      await (await SharedPreferences.getInstance()).setDouble(chaveDaLargura(widget.painel), largura);
    } on Exception {
      return;
    }
  }

  double get _teto => limitarLargura(
        double.infinity,
        minimo: widget.minimo,
        maximo: widget.maximo,
        disponivel: _disponivel,
        restoMinimo: widget.restoMinimo + Espacos.esp2,
      );

  double _limitar(double desejada) => limitarLargura(desejada, minimo: widget.minimo, maximo: _teto);

  void _mover(double dx) {
    final atual = _limitar(_largura ?? widget.inicial);
    setState(() => _largura = _limitar(atual + (widget.lateralADireita ? -dx : dx)));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, limites) {
        _disponivel = limites.maxWidth;
        final largura = _limitar(_largura ?? widget.inicial);
        final lateral = SizedBox(width: largura, child: FocusTraversalGroup(child: widget.lateral));
        final divisor = DivisorArrastavel(
          rotulo: widget.rotulo,
          largura: largura,
          minimo: widget.minimo,
          maximo: _teto,
          painelADireita: widget.lateralADireita,
          aoMover: _mover,
          aoTerminar: _salvar,
        );
        final principal = Expanded(child: FocusTraversalGroup(child: widget.principal));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widget.lateralADireita ? [principal, divisor, lateral] : [lateral, divisor, principal],
        );
      });
}
