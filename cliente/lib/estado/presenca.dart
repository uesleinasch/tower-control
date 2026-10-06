import '../nucleo/protocolo.dart';
import 'chat.dart';

class Presenca {
  Presenca(this._enviar);

  final Enviar _enviar;
  static const _nada = Object();

  bool _primeiroPlano = true;
  String? _naTela;
  Object? _informado = _nada;

  String? get visivel => _primeiroPlano ? _naTela : null;

  void definirPrimeiroPlano(bool valor) {
    _primeiroPlano = valor;
    _informar();
  }

  void definirNaTela(String? conversaId) {
    _naTela = conversaId;
    _informar();
  }

  void reconectou() {
    _informado = _nada;
    _informar();
  }

  void _informar() {
    final atual = visivel;
    if (atual == _informado) return;
    if (_enviar(Visivel(atual))) _informado = atual;
  }
}
