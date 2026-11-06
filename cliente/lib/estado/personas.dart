import 'package:flutter/foundation.dart';

import '../nucleo/modelos.dart';
import '../nucleo/protocolo.dart';
import 'chat.dart';

class EstadoPersonas extends ChangeNotifier {
  EstadoPersonas(this._enviar);

  final Enviar _enviar;

  String? _aberta;
  String filtro = '';

  Perfil? get aberta => _aberta == null ? null : Perfil.todos.where((p) => p.chave == _aberta).firstOrNull;

  List<Perfil> get filtradas {
    final termo = filtro.trim().toLowerCase();
    if (termo.isEmpty) return Perfil.todos;
    return [for (final p in Perfil.todos) if (p.nome.toLowerCase().contains(termo)) p];
  }

  void abrir(String id) {
    _aberta = id;
    notifyListeners();
  }

  void fecharDetalhe() {
    if (_aberta == null) return;
    _aberta = null;
    notifyListeners();
  }

  void filtrar(String texto) {
    filtro = texto;
    notifyListeners();
  }

  void salvarDados(Perfil p, {required String nome, required String? modelo, String? cor, bool mudarCor = false}) {
    if (nome.trim().isEmpty) return;
    _enviar(SalvarDadosDaPersona(p.chave, nome: nome.trim(), modelo: modelo, cor: cor, mudarCor: mudarCor));
  }
}
