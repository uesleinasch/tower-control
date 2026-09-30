import 'package:flutter/foundation.dart';

import '../nucleo/modelos.dart';
import '../nucleo/protocolo.dart';
import 'chat.dart';

class EstadoConversas extends ChangeNotifier {
  EstadoConversas(this._enviar);

  final Enviar _enviar;

  List<MetaConversa> lista = const [];
  List<Atalho> atalhos = const [];
  bool carregada = false;

  void listar() => _enviar(const Listar());
  bool excluir(String id) => _enviar(Excluir(id));

  void tratar(Entrada e) {
    switch (e) {
      case Conversas(:final lista):
        this.lista = lista;
        carregada = true;
      case AtalhosRecebidos(:final lista):
        atalhos = lista;
      case Criada():
        listar();
        return;
      default:
        return;
    }
    notifyListeners();
  }
}

sealed class ItemBoard {
  const ItemBoard();
}

class Pauta extends ItemBoard {
  const Pauta(this.texto, this.contexto);
  final String texto;
  final String? contexto;
}

class StatusBoard extends ItemBoard {
  const StatusBoard(this.texto);
  final String texto;
}

class Sintese extends ItemBoard {
  const Sintese(this.texto, this.ata);
  final String texto;
  final String ata;
}

class ErroBoard extends ItemBoard {
  const ErroBoard(this.texto);
  final String texto;
}

class EstadoBoard extends ChangeNotifier {
  EstadoBoard(this._enviar);

  final Enviar _enviar;

  final itens = <ItemBoard>[];
  bool emCurso = false;

  bool convocar(String pauta, {String? contexto}) {
    final texto = pauta.trim();
    final ctx = contexto?.trim();
    if (emCurso || texto.isEmpty) return false;
    if (!_enviar(ConvocarBoard(texto, contexto: ctx == null || ctx.isEmpty ? null : ctx))) return false;
    itens
      ..add(Pauta(texto, ctx))
      ..add(const StatusBoard('Board convocado — colhendo pareceres…'));
    emCurso = true;
    notifyListeners();
    return true;
  }

  void conexaoRestabelecida() {
    if (!emCurso) return;
    emCurso = false;
    itens.add(const ErroBoard('A conexão caiu durante a deliberação. A ata, se concluída, fica em board/minutes/.'));
    notifyListeners();
  }

  void tratar(Entrada e) {
    switch (e) {
      case BoardStatus(:final texto):
        itens.add(StatusBoard(texto));
      case BoardSintese(:final texto, :final ata):
        itens.add(Sintese(texto, ata));
        emCurso = false;
      case Erro(:final mensagem) when emCurso:
        itens.add(ErroBoard(mensagem));
        emCurso = false;
      default:
        return;
    }
    notifyListeners();
  }
}

class EstadoDecisoes extends ChangeNotifier {
  EstadoDecisoes(this._enviar);

  final Enviar _enviar;

  List<Decisao> lista = const [];
  bool carregada = false;
  String filtro = '';
  ({String id, String conteudo})? aberta;

  List<Decisao> get filtradas {
    final f = filtro.trim().toLowerCase();
    if (f.isEmpty) return lista;
    return lista
        .where((d) =>
            d.titulo.toLowerCase().contains(f) ||
            d.projeto.toLowerCase().contains(f) ||
            d.tags.any((t) => t.toLowerCase().contains(f)))
        .toList();
  }

  void carregar() => _enviar(const PedirDecisoes());
  void abrir(String id) => _enviar(PedirDecisao(id));

  void fecharDetalhe() {
    aberta = null;
    notifyListeners();
  }

  void filtrar(String texto) {
    filtro = texto;
    notifyListeners();
  }

  void tratar(Entrada e) {
    switch (e) {
      case Decisoes(:final lista):
        this.lista = lista;
        carregada = true;
      case DecisaoAberta(:final id, :final conteudo):
        aberta = (id: id, conteudo: conteudo);
      default:
        return;
    }
    notifyListeners();
  }
}
