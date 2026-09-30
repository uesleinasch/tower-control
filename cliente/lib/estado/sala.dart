import 'dart:async';

import 'package:flutter/foundation.dart';

import '../conexao/canal.dart';
import '../nucleo/protocolo.dart';
import 'areas.dart';
import 'chat.dart';
import 'servidor.dart';

enum Tela { conversas, chat, board, decisoes, configuracao }

class Sala extends ChangeNotifier {
  Sala(this.servidor) : canal = Canal(servidor.resolver) {
    chat = EstadoChat(canal.enviar);
    conversas = EstadoConversas(canal.enviar);
    board = EstadoBoard(canal.enviar);
    decisoes = EstadoDecisoes(canal.enviar);
    _assinaturas = [
      canal.eventos.listen(_tratar),
      canal.conexoes.listen((_) => _aoConectar()),
    ];
  }

  final Servidor servidor;
  final Canal canal;
  late final EstadoChat chat;
  late final EstadoConversas conversas;
  late final EstadoBoard board;
  late final EstadoDecisoes decisoes;
  late final List<StreamSubscription<Object?>> _assinaturas;
  final _avisos = StreamController<String>.broadcast();
  var _primeiraConexao = true;

  Tela tela = Tela.conversas;
  final pedidosDeNova = ValueNotifier(0);

  void pedirNovaConversa() => pedidosDeNova.value++;

  Stream<String> get avisos => _avisos.stream;

  void iniciar() => canal.iniciar();

  void ir(Tela nova) {
    if (tela == nova) return;
    tela = nova;
    if (nova == Tela.decisoes && !decisoes.carregada) decisoes.carregar();
    notifyListeners();
  }

  void novaConversa(String perfil, {String? foco, String? modelo}) {
    chat.novaConversa(perfil, foco: foco, modelo: modelo ?? chat.modelo);
    ir(Tela.chat);
  }

  void abrirConversa(String id) {
    chat.abrir(id);
    ir(Tela.chat);
  }

  void _aoConectar() {
    conversas.listar();
    if (_primeiraConexao) {
      _primeiraConexao = false;
      return;
    }
    chat.conexaoRestabelecida();
    board.conexaoRestabelecida();
    if (decisoes.carregada) decisoes.carregar();
  }

  void _tratar(Entrada e) {
    switch (e) {
      case Aviso(:final texto) when tela != Tela.chat:
        _avisos.add(texto);
        return;
      case Erro(:final mensagem):
        if (board.emCurso) {
          board.tratar(e);
        } else if (chat.emCurso || tela == Tela.chat) {
          chat.tratar(e);
        } else {
          _avisos.add(mensagem);
        }
        return;
      case Excluida(:final id) when id == chat.conversaId:
        chat.tratar(e);
        if (tela == Tela.chat) ir(Tela.conversas);
        return;
      case ConversaAberta():
        chat.tratar(e);
        ir(Tela.chat);
        return;
      default:
        chat.tratar(e);
        conversas.tratar(e);
        board.tratar(e);
        decisoes.tratar(e);
    }
  }

  @override
  void dispose() {
    for (final a in _assinaturas) {
      a.cancel();
    }
    _avisos.close();
    pedidosDeNova.dispose();
    chat.dispose();
    conversas.dispose();
    board.dispose();
    decisoes.dispose();
    canal.dispose();
    super.dispose();
  }
}
