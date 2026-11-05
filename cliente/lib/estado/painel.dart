import 'package:flutter/foundation.dart';

import '../nucleo/painel.dart';
import '../nucleo/protocolo.dart';
import 'chat.dart';

class EstadoPainel extends ChangeNotifier {
  EstadoPainel(this._enviar);

  final Enviar _enviar;

  bool aberto = false;
  bool _informado = false;
  Retrato? retrato;
  String? filtroQuem;
  String? filtroTipo;
  String? equipePreferida;

  List<ItemDeAtividade> get atividade =>
      filtrarAtividade(retrato?.atividade ?? const [], quem: filtroQuem, tipo: filtroTipo);

  String get equipe => equipeDasTarefas(retrato ?? const Retrato(), equipePreferida);

  void definirAberto(bool valor) {
    aberto = valor;
    _informar();
  }

  void reconectou() {
    _informado = false;
    _informar();
  }

  void _informar() {
    if (_informado == aberto) return;
    if (_enviar(AssinarPainel(ativo: aberto))) _informado = aberto;
  }

  EfeitoDaAcao? agir(ItemDeAtencao item, String acao, {String? texto}) {
    final efeito = efeitoDaAcao(item, acao, texto: texto);
    if (efeito is MandarSaida) _enviar(efeito.saida);
    return efeito;
  }

  void filtrar({String? quem, String? tipo}) {
    filtroQuem = quem;
    filtroTipo = tipo;
    notifyListeners();
  }

  void escolherEquipe(String id) {
    equipePreferida = id;
    notifyListeners();
  }

  void tratar(Entrada e) {
    if (e is! PainelRecebido) return;
    retrato = e.retrato;
    notifyListeners();
  }
}
