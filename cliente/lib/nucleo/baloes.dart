final _separador = RegExp(r'\n\s*-{3,}\s*\n');

List<String> dividirBaloes(String texto) =>
    texto.split(_separador).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

({List<String> fechados, String aberto}) baloesEmCurso(String texto) {
  final partes = texto.split(_separador);
  final aberto = partes.removeLast().trim();
  return (fechados: partes.map((p) => p.trim()).where((p) => p.isNotEmpty).toList(), aberto: aberto);
}

String cortarCitacao(String texto) => texto.length > 180 ? '${texto.substring(0, 180)}…' : texto;
