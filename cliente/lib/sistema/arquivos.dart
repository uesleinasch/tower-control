import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

typedef EscolherArquivos = Future<List<({String nome, String caminho})>?> Function({List<String>? extensoes});
typedef SalvarArquivo = Future<String?> Function({required String nome, required List<int> bytes});

EscolherArquivos escolherArquivos = _escolherPeloFilePicker;
SalvarArquivo salvarArquivo = _salvarPeloFilePicker;

Future<List<({String nome, String caminho})>?> _escolherPeloFilePicker({List<String>? extensoes}) async {
  final arquivos = await FilePicker.pickFiles(
    type: extensoes == null ? FileType.any : FileType.custom,
    allowedExtensions: extensoes,
  );
  if (arquivos.isEmpty) return null;
  return [for (final f in arquivos) (nome: f.name, caminho: f.xFile.path)];
}

Future<String?> _salvarPeloFilePicker({required String nome, required List<int> bytes}) async {
  final conteudo = Uint8List.fromList(bytes);
  final ponto = nome.lastIndexOf('.');
  final extensao = ponto < 0 ? null : nome.substring(ponto + 1);
  final destino = await FilePicker.saveFile(
    fileName: nome,
    bytes: conteudo,
    mimeType: extensao == 'json' ? 'application/json' : 'application/octet-stream',
    type: extensao == null ? FileType.any : FileType.custom,
    allowedExtensions: extensao == null ? null : [extensao],
  );
  if (destino == null) return null;
  if (destino.scheme != 'file') return '$destino';
  await File.fromUri(destino).writeAsBytes(conteudo);
  return destino.toFilePath();
}
