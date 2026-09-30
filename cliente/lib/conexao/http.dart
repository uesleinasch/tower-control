import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../nucleo/modelos.dart';

Future<Map<String, dynamic>?> sondar(String endereco) async {
  try {
    final r = await http.get(Uri.parse('http://$endereco/enderecos')).timeout(const Duration(seconds: 3));
    if (r.statusCode != 200) return null;
    final corpo = jsonDecode(r.body);
    return corpo is Map<String, dynamic> ? corpo : null;
  } catch (_) {
    return null;
  }
}

Uri urlDoAnexo(String endereco, String id) => Uri.parse('http://$endereco/anexo/${Uri.encodeComponent(id)}');

Future<Anexo> subirAnexo(String endereco, List<int> bytes, String nome, {String? mime}) async {
  final pedido = http.MultipartRequest('POST', Uri.parse('http://$endereco/anexo'))
    ..files.add(http.MultipartFile.fromBytes(
      'arquivo',
      bytes,
      filename: nome,
      contentType: mime == null ? null : MediaType.parse(mime),
    ));
  final resposta = await http.Response.fromStream(await pedido.send().timeout(const Duration(seconds: 60)));
  Map<String, dynamic> corpo;
  try {
    corpo = jsonDecode(resposta.body) as Map<String, dynamic>;
  } catch (_) {
    corpo = const {};
  }
  if (resposta.statusCode != 200) {
    throw Exception(corpo['erro'] ?? 'falha no upload (${resposta.statusCode})');
  }
  return Anexo.deJson(corpo);
}
