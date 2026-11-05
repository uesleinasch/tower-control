import 'dart:async';

import 'package:flutter/foundation.dart';

import '../conexao/canal.dart';
import '../nucleo/modelos.dart';
import '../nucleo/protocolo.dart';
import 'areas.dart';
import 'chat.dart';
import 'equipes.dart';
import 'presenca.dart';
import 'rotinas.dart';
import 'servidor.dart';
import 'tarefas.dart';

enum Tela { conversas, chat, board, decisoes, tarefas, equipes, configuracao }

class Sala extends ChangeNotifier {
  Sala(this.servidor) : canal = Canal(servidor.resolver) {
    chat = EstadoChat(canal.enviar);
    conversas = EstadoConversas(canal.enviar);
    board = EstadoBoard(canal.enviar);
    decisoes = EstadoDecisoes(canal.enviar);
    tarefas = EstadoTarefas(canal.enviar);
    equipes = EstadoEquipes(canal.enviar);
    rotinas = EstadoRotinas(canal.enviar);
    presenca = Presenca(canal.enviar);
    chat.addListener(_atualizarPresenca);
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
  late final EstadoTarefas tarefas;
  late final EstadoEquipes equipes;
  late final EstadoRotinas rotinas;
  late final Presenca presenca;
  late final List<StreamSubscription<Object?>> _assinaturas;
  final _avisos = StreamController<String>.broadcast();
  var _primeiraConexao = true;
  var _layoutDuplo = false;

  Tela tela = Tela.conversas;
  final pedidosDeNova = ValueNotifier(0);

  void pedirNovaConversa() => pedidosDeNova.value++;

  Stream<String> get avisos => _avisos.stream;

  void iniciar() => canal.iniciar();

  void ir(Tela nova) {
    if (tela == nova) return;
    tela = nova;
    if (nova == Tela.decisoes && !decisoes.carregada) decisoes.carregar();
    if (nova == Tela.tarefas && !tarefas.carregada) tarefas.carregar();
    if (nova == Tela.equipes && !equipes.carregada) equipes.carregar();
    if ((nova == Tela.equipes || nova == Tela.tarefas) && !rotinas.carregada) rotinas.carregar();
    notifyListeners();
    _atualizarPresenca();
  }

  void definirLayoutDuplo(bool duplo) {
    if (_layoutDuplo == duplo) return;
    _layoutDuplo = duplo;
    _atualizarPresenca();
  }

  void _atualizarPresenca() {
    final chatNaTela = tela == Tela.chat || (_layoutDuplo && tela == Tela.conversas);
    presenca.definirNaTela(chatNaTela ? chat.conversaId : null);
  }

  void novaConversa(String perfil, {String? modelo}) {
    chat.novaConversa(perfil, modelo: modelo ?? chat.modelo);
    ir(Tela.chat);
  }

  void novaConversaNoTickTask() {
    novaConversa('alfred');
    if (!chat.ticktask) chat.alternarTicktask();
  }

  void abrirConversa(String id) {
    chat.abrir(id);
    ir(Tela.chat);
  }

  void abrirTarefa(int id) {
    ir(Tela.tarefas);
    tarefas.abrir(id);
  }

  void _aoConectar() {
    conversas.listar();
    presenca.reconectou();
    if (_primeiraConexao) {
      _primeiraConexao = false;
      return;
    }
    chat.conexaoRestabelecida();
    board.conexaoRestabelecida();
    if (decisoes.carregada) decisoes.carregar();
    if (tarefas.carregada) tarefas.carregar();
    if (equipes.carregada) equipes.carregar();
    if (rotinas.carregada) rotinas.carregar();
  }

  void _tratar(Entrada e) {
    switch (e) {
      case PersonasRecebidas(:final lista):
        Perfil.registrar(lista);
        equipes.tratar(e);
        notifyListeners();
        return;
      case Erro() when equipes.salvando:
        equipes.tratar(e);
        return;
      case Erro() when rotinas.salvando:
        rotinas.tratar(e);
        return;
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
        tarefas.tratar(e);
        equipes.tratar(e);
        rotinas.tratar(e);
    }
  }

  @override
  void dispose() {
    for (final a in _assinaturas) {
      a.cancel();
    }
    _avisos.close();
    chat.removeListener(_atualizarPresenca);
    pedidosDeNova.dispose();
    chat.dispose();
    conversas.dispose();
    board.dispose();
    decisoes.dispose();
    tarefas.dispose();
    equipes.dispose();
    rotinas.dispose();
    canal.dispose();
    super.dispose();
  }
}
