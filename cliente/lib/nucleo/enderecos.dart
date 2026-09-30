import 'dart:async';
import 'dart:convert';

typedef Sonda = Future<Map<String, dynamic>?> Function(String endereco);

final _hostPorta = RegExp(r'^[A-Za-z0-9.\-]+:\d{1,5}$');

String? normalizarEndereco(String bruto) {
  var s = bruto.trim();
  final esquema = RegExp(r'^[a-z]+://').firstMatch(s);
  if (esquema != null) s = s.substring(esquema.end);
  s = s.split('/').first;
  if (!s.contains(':')) s = '$s:7878';
  return _hostPorta.hasMatch(s) ? s : null;
}

List<String> enderecosDoPareamento(String json) {
  final Object? lista;
  try {
    lista = jsonDecode(json);
  } on FormatException {
    return const [];
  }
  if (lista is! List) return const [];
  return _semRepetir(lista.map((e) => normalizarEndereco('$e')).whereType<String>());
}

List<String> enderecosDaResposta(Map<String, dynamic> resposta) {
  final porta = (resposta['porta'] as num?)?.toInt() ?? 7878;
  return [
    for (final chave in ['lan', 'tailscale'])
      if (resposta[chave] is String && (resposta[chave] as String).isNotEmpty) '${resposta[chave]}:$porta',
  ];
}

List<String> renovar(List<String> anteriores, Map<String, dynamic> resposta) =>
    _semRepetir([...enderecosDaResposta(resposta), ...anteriores]);

Future<({String endereco, Map<String, dynamic> resposta})?> disputar(List<String> candidatos, Sonda sonda) {
  if (candidatos.isEmpty) return Future.value(null);
  final vencedor = Completer<({String endereco, Map<String, dynamic> resposta})?>();
  var pendentes = candidatos.length;
  for (final endereco in candidatos) {
    sonda(endereco).then((resposta) {
      if (resposta != null && !vencedor.isCompleted) {
        vencedor.complete((endereco: endereco, resposta: resposta));
      }
    }, onError: (_) {}).whenComplete(() {
      pendentes--;
      if (pendentes == 0 && !vencedor.isCompleted) vencedor.complete(null);
    });
  }
  return vencedor.future;
}

List<String> _semRepetir(Iterable<String> itens) {
  final vistos = <String>{};
  return [for (final i in itens) if (vistos.add(i)) i];
}
