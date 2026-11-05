import 'package:flutter/foundation.dart';

import '../nucleo/espelho.dart';
import '../nucleo/protocolo.dart';
import 'chat.dart';

class EstadoEspelho extends ChangeNotifier {
  EstadoEspelho(this._enviar);

  final Enviar _enviar;

  ConfigDoEspelho? config;
  EstadoDoEspelho estado = const EstadoDoEspelho();
  ConfigDoEspelho? rascunho;
  bool salvando = false;
  bool sincronizando = false;
  String? erro;
  bool aberto = false;
  ConfigDoEspelho? _enviada;

  bool get carregado => config != null;
  bool get ocupado => salvando || sincronizando;
  ConfigDoEspelho get vista => rascunho ?? config ?? const ConfigDoEspelho();
  bool get alterado => rascunho != null && !rascunho!.mesmaQue(config);

  List<String> get errosDoRascunho {
    final r = rascunho;
    return r == null ? const [] : errosDaConfigDoEspelho(r);
  }

  bool get podeSalvar => alterado && !salvando && errosDoRascunho.isEmpty;

  String get resumo => carregado ? resumoDoEspelho(config!, estado) : 'carregando…';

  void definirAberto(bool valor) {
    aberto = valor;
    if (valor) carregar();
  }

  void reconectou() {
    if (!aberto) return;
    if (salvando || sincronizando) {
      salvando = false;
      sincronizando = false;
      _enviada = null;
      notifyListeners();
    }
    carregar();
  }

  void carregar() => _enviar(const PedirEspelho());

  void mudar({bool? ativo, String? projeto, String? tag}) {
    rascunho = vista.copiar(ativo: ativo, projeto: projeto, tag: tag);
    erro = null;
    notifyListeners();
  }

  void marcarTipo(String tipo, bool marcado) {
    rascunho = vista.comTipo(tipo, marcado);
    erro = null;
    notifyListeners();
  }

  void salvar() {
    final r = rascunho;
    if (r == null || salvando) return;
    final erros = errosDaConfigDoEspelho(r);
    if (erros.isNotEmpty) {
      erro = erros.join('\n');
      notifyListeners();
      return;
    }
    if (!_enviar(SalvarEspelho(r))) {
      erro = 'sem conexão com o servidor';
      notifyListeners();
      return;
    }
    _enviada = r.normalizada;
    salvando = true;
    erro = null;
    notifyListeners();
  }

  void descartar() {
    rascunho = null;
    erro = null;
    notifyListeners();
  }

  void sincronizar() {
    if (sincronizando) return;
    if (!_enviar(const SincronizarEspelho())) {
      erro = 'sem conexão com o servidor';
      notifyListeners();
      return;
    }
    sincronizando = true;
    erro = null;
    notifyListeners();
  }

  void tratar(Entrada e) {
    switch (e) {
      case EspelhoRecebido(:final config, :final estado):
        this.config = config;
        this.estado = estado;
        sincronizando = false;
        final enviada = _enviada;
        if (salvando && enviada != null && enviada.mesmaQue(config)) {
          salvando = false;
          _enviada = null;
          if (rascunho?.mesmaQue(enviada) ?? false) rascunho = null;
        }
      case Erro(:final mensagem) when ocupado:
        salvando = false;
        sincronizando = false;
        _enviada = null;
        erro = mensagem;
      default:
        return;
    }
    notifyListeners();
  }
}
