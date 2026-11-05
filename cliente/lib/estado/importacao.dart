import 'dart:async';

import 'package:flutter/foundation.dart';

import '../nucleo/importacao.dart';
import '../nucleo/protocolo.dart';
import 'chat.dart';

class FalhaDeExportacao implements Exception {
  const FalhaDeExportacao(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

class EstadoImportacao extends ChangeNotifier {
  EstadoImportacao(this._enviar, {this.espera = const Duration(milliseconds: 400)});

  final Enviar _enviar;
  final Duration espera;

  String? conteudo;
  String? arquivo;
  String? destino;
  EscolhasDoModelo escolhas = const EscolhasDoModelo();
  PreviaDoModelo? previa;
  bool importando = false;
  ModeloImportado? importado;
  String? erro;

  Completer<ModeloRecebido>? _exportacao;
  Timer? _digitando;
  bool _emVoo = false;
  bool _sujo = false;
  bool _descartarProxima = false;

  bool get aberta => conteudo != null;
  bool get exportando => _exportacao != null;
  bool get ocupado => importando || exportando;
  bool get pendente => _emVoo || _sujo || _digitando != null;
  bool get podeImportar =>
      aberta && !pendente && !importando && importado == null && (previa?.podeImportar ?? false);

  void abrir(String conteudo, {String? destino, String? arquivo}) {
    _limpar();
    this.conteudo = conteudo;
    this.destino = destino;
    this.arquivo = arquivo;
    _pedir();
    notifyListeners();
  }

  void fechar() {
    _limpar();
    notifyListeners();
  }

  void _limpar() {
    _digitando?.cancel();
    _digitando = null;
    if (_emVoo) _descartarProxima = true;
    _sujo = false;
    conteudo = null;
    arquivo = null;
    destino = null;
    escolhas = const EscolhasDoModelo();
    previa = null;
    importando = false;
    importado = null;
    erro = null;
  }

  void mudar(EscolhasDoModelo novas, {bool digitando = false}) {
    if (!aberta || importando) return;
    escolhas = novas;
    erro = null;
    if (digitando) {
      _digitando?.cancel();
      _digitando = Timer(espera, () {
        _digitando = null;
        _pedir();
        notifyListeners();
      });
    } else {
      _pedir();
    }
    notifyListeners();
  }

  void _pedir() {
    _digitando?.cancel();
    _digitando = null;
    final texto = conteudo;
    if (texto == null) return;
    if (_emVoo) {
      _sujo = true;
      return;
    }
    _sujo = false;
    if (!_enviar(PedirPreviaDoModelo(texto, destino: destino, escolhas: escolhas))) {
      erro = 'sem conexão com o servidor';
      return;
    }
    _emVoo = true;
  }

  void importar() {
    if (!podeImportar) return;
    if (!_enviar(ImportarModelo(conteudo!, destino: destino, escolhas: escolhas))) {
      erro = 'sem conexão com o servidor';
      notifyListeners();
      return;
    }
    importando = true;
    erro = null;
    notifyListeners();
  }

  Future<ModeloRecebido> exportar(String equipe, {String? workflow, bool personas = true, bool rotinas = true}) {
    if (_exportacao != null) return Future.error(const FalhaDeExportacao('já há uma exportação em andamento'));
    final saida = workflow == null
        ? ExportarModelo(equipe, personas: personas, rotinas: rotinas)
        : ExportarModelo.workflow(equipe, workflow);
    if (!_enviar(saida)) return Future.error(const FalhaDeExportacao('sem conexão com o servidor'));
    final pedido = _exportacao = Completer<ModeloRecebido>();
    notifyListeners();
    return pedido.future;
  }

  void _falharExportacao(String mensagem) {
    final pedido = _exportacao;
    _exportacao = null;
    pedido?.completeError(FalhaDeExportacao(mensagem));
  }

  void reconectou() {
    _emVoo = false;
    _descartarProxima = false;
    if (aberta && importado == null) _pedir();
    if (importando) {
      importando = false;
      erro = 'a conexão caiu durante a importação; confira as equipes antes de tentar de novo';
    }
    if (exportando) _falharExportacao('a conexão caiu durante a exportação');
    notifyListeners();
  }

  void tratar(Entrada e) {
    switch (e) {
      case PreviaDoModeloRecebida(:final previa):
        if (!_emVoo) return;
        _emVoo = false;
        if (_descartarProxima) {
          _descartarProxima = false;
        } else {
          this.previa = previa;
          escolhas = escolhas.completadaCom(previa.escolhas);
        }
        if (_sujo) _pedir();
      case ModeloImportado() when importando:
        importando = false;
        importado = e;
      case ModeloRecebido() when exportando:
        final pedido = _exportacao!;
        _exportacao = null;
        pedido.complete(e);
      case Erro(:final mensagem) when importando:
        importando = false;
        erro = mensagem;
      case Erro(:final mensagem) when exportando:
        _falharExportacao(mensagem);
      default:
        return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _digitando?.cancel();
    super.dispose();
  }
}
