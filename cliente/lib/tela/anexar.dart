import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../conexao/http.dart';
import '../estado/sala.dart';
import '../nucleo/formato.dart';

enum FonteAnexo { arquivo, camera, galeria }

typedef _Escolhido = ({String nome, Future<List<int>> Function() ler, int bytes});

Future<List<_Escolhido>> _escolher(FonteAnexo fonte) async {
  final imagens = ImagePicker();
  switch (fonte) {
    case FonteAnexo.camera:
      final foto = await imagens.pickImage(
          source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      return foto == null ? [] : [(nome: foto.name, ler: foto.readAsBytes, bytes: await foto.length())];
    case FonteAnexo.galeria:
      final fotos = await imagens.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      return [for (final f in fotos) (nome: f.name, ler: f.readAsBytes, bytes: await f.length())];
    case FonteAnexo.arquivo:
      final arquivos = await FilePicker.pickFiles();
      return [
        for (final f in arquivos) (nome: f.name, ler: f.xFile.readAsBytes, bytes: await f.xFile.length()),
      ];
  }
}

Future<void> anexar(Sala sala, FonteAnexo fonte) async {
  final chat = sala.chat;
  final List<_Escolhido> escolhidos;
  try {
    escolhidos = await _escolher(fonte);
  } catch (erro) {
    chat.mostrarErro('Não consegui abrir o seletor: $erro');
    return;
  }
  for (final e in escolhidos) {
    if (e.bytes > limiteAnexo) {
      chat.mostrarErro('"${e.nome}" tem ${formatarBytes(e.bytes)}; o limite é 10 MB.');
      continue;
    }
    final endereco = sala.canal.endereco;
    if (endereco == null || !sala.canal.conectado) {
      chat.mostrarErro('${e.nome}: sem conexão com o servidor.');
      continue;
    }
    chat.anexoSubindo(1);
    try {
      chat.adicionarAnexo(await subirAnexo(endereco, await e.ler(), e.nome, mime: mimePorNome(e.nome)));
    } catch (erro) {
      chat.mostrarErro('${e.nome}: ${'$erro'.replaceFirst('Exception: ', '')}');
    } finally {
      chat.anexoSubindo(-1);
    }
  }
}
