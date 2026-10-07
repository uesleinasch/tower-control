import 'package:flutter/foundation.dart';

import '../nucleo/protocolo.dart';
import '../nucleo/tarefas.dart';
import 'chat.dart';

const equipeCasa = 'casa';

class EstadoTarefas extends ChangeNotifier {
  EstadoTarefas(this._enviar);

  final Enviar _enviar;

  List<Tarefa> lista = const [];
  List<EquipeResumo> equipes = const [];
  bool carregada = false;
  ({Tarefa tarefa, List<RegistroDeTarefa> registros})? aberta;

  List<PosicaoResumo> get posicoes =>
      equipes.where((e) => e.id == equipeCasa).expand((e) => e.posicoes).toList();

  String rotuloDaPosicao(String id) =>
      posicoes.where((p) => p.id == id).map((p) => p.rotulo).firstOrNull ?? id;

  void carregar() {
    _enviar(const PedirEquipes());
    _enviar(const PedirTarefas(equipe: equipeCasa));
  }

  void abrir(int id) => _enviar(PedirTarefa(id));

  void fecharDetalhe() {
    aberta = null;
    notifyListeners();
  }

  void criar({required String posicao, required String titulo, String porque = ''}) =>
      _enviar(CriarTarefa(equipe: equipeCasa, posicao: posicao, titulo: titulo, porque: porque));

  void mudarStatus(int id, String status) => _enviar(MudarStatusTarefa(id, status));

  void comentar(int id, String texto) {
    if (texto.trim().isEmpty) return;
    _enviar(ComentarTarefa(id, texto.trim()));
  }

  void tratar(Entrada e) {
    switch (e) {
      case EquipesRecebidas(:final lista):
        equipes = lista;
      case TarefasRecebidas(:final lista):
        this.lista = lista;
        carregada = true;
      case TarefaRecebida(:final tarefa, :final registros, :final pedida):
        lista = comTarefa(lista, tarefa);
        if (pedida || aberta?.tarefa.id == tarefa.id) aberta = (tarefa: tarefa, registros: registros);
      default:
        return;
    }
    notifyListeners();
  }
}
