import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import '../nucleo/organograma.dart' show Vista, deslocarVista, escalaMaxima, escalaMinima, zoomEm;

mixin PanEZoom<T extends StatefulWidget> on State<T> {
  Vista? vista;
  Size tamanho = Size.zero;
  double _escalaNoInicio = 1;

  Vista get v => vista ?? (dx: 0, dy: 0, escala: 1);

  void zoom(double fator, {Offset? foco}) {
    final centro = foco ?? Offset(tamanho.width / 2, tamanho.height / 2);
    setState(() => vista = zoomEm(v, centro.dx, centro.dy, v.escala * fator));
  }

  void rodar(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final teclado = HardwareKeyboard.instance;
    if (teclado.isControlPressed || teclado.isMetaPressed) {
      zoom(e.scrollDelta.dy > 0 ? 0.9 : 1 / 0.9, foco: e.localPosition);
    } else if (teclado.isShiftPressed) {
      setState(() => vista = deslocarVista(v, -e.scrollDelta.dy, 0));
    } else {
      setState(() => vista = deslocarVista(v, -e.scrollDelta.dx, -e.scrollDelta.dy));
    }
  }

  void comecarPinca() => _escalaNoInicio = v.escala;

  void aplicarPinca(ScaleUpdateDetails d) {
    var nova = v;
    if (d.scale != 1) nova = zoomEm(nova, d.localFocalPoint.dx, d.localFocalPoint.dy, _escalaNoInicio * d.scale);
    vista = deslocarVista(nova, d.focalPointDelta.dx, d.focalPointDelta.dy);
  }

  Widget mundo({required double largura, required double altura, required Widget child, bool interativo = false}) {
    final area = SizedBox(width: largura, height: altura, child: child);
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Transform(
        transform: Matrix4.identity()
          ..translateByDouble(v.dx, v.dy, 0, 1)
          ..scaleByDouble(v.escala, v.escala, 1, 1),
        child: interativo ? area : IgnorePointer(child: area),
      ),
    );
  }

  Widget controlesDeZoom({required VoidCallback aoAjustar}) => ControlesDeZoom(
        escala: v.escala,
        aoAproximar: () => zoom(1.2),
        aoAfastar: () => zoom(1 / 1.2),
        aoAjustar: aoAjustar,
        aoTamanhoReal: () => zoom(1 / v.escala),
      );
}

class ControlesDeZoom extends StatelessWidget {
  const ControlesDeZoom({
    super.key,
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
        margin: EdgeInsets.zero,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Afastar (Ctrl + roda)',
            onPressed: escala > escalaMinima ? aoAfastar : null,
            icon: const Icon(Symbols.zoom_out),
          ),
          Tooltip(
            message: 'Tamanho real',
            child: TextButton(
              onPressed: aoTamanhoReal,
              child: Text(
                '${(escala * 100).round()}%',
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Aproximar (Ctrl + roda)',
            onPressed: escala < escalaMaxima ? aoAproximar : null,
            icon: const Icon(Symbols.zoom_in),
          ),
          IconButton(tooltip: 'Ajustar à tela', onPressed: aoAjustar, icon: const Icon(Symbols.fit_screen)),
        ]),
      );
}
