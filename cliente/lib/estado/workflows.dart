import 'package:flutter/foundation.dart';

import '../nucleo/protocolo.dart';
import '../nucleo/workflows.dart';
import 'chat.dart';

typedef GrafoVisto = ({String equipe, String workflow, int? fluxo});

class EstadoWorkflows extends ChangeNotifier {
  EstadoWorkflows(this._enviar);

  final Enviar _enviar;

  List<Workflow> definicoes = const [];
  List<Fluxo> fluxos = const [];
  bool carregada = false;
  GrafoVisto? vendo;
  String? caixa;

  void carregar() => _enviar(const PedirWorkflows());

  List<Workflow> daEquipe(String equipe) => [for (final w in definicoes) if (w.equipe == equipe) w];

  Workflow? definicao(String equipe, String id) =>
      definicoes.where((w) => w.equipe == equipe && w.id == id).firstOrNull;

  Fluxo? fluxo(int id) => fluxos.where((f) => f.id == id).firstOrNull;

  List<Fluxo> abertos(String equipe, [String? workflow]) => [
        for (final f in fluxos)
          if (f.aberto && f.equipe == equipe && (workflow == null || f.workflow == workflow)) f,
      ];

  List<Fluxo> encerrados(String equipe) => [for (final f in fluxos) if (!f.aberto && f.equipe == equipe) f];

  String nomeDoWorkflow(String? equipe, String id) =>
      definicoes.where((w) => (equipe == null || w.equipe == equipe) && w.id == id).firstOrNull?.nome ?? id;

  Fluxo? get fluxoVisto {
    final id = vendo?.fluxo;
    return id == null ? null : fluxo(id);
  }

  Workflow? get definicaoVista {
    final v = vendo;
    if (v == null) return null;
    return fluxoVisto?.definicao ?? definicao(v.equipe, v.workflow);
  }

  List<String> iniciar(Workflow w, Map<String, Object?> brutos) {
    final convertida = converterEntrada(w.entrada, brutos);
    if (convertida.erros.isEmpty) _enviar(IniciarWorkflow(w.equipe, w.id, convertida.valores));
    return convertida.erros;
  }

  void decidir(int fluxo, int ficha, String opcao, [String comentario = '']) => _enviar(
        DecidirWorkflow(fluxo, ficha, opcao, comentario: comentario.trim().isEmpty ? null : comentario.trim()),
      );

  void sinalizar(int fluxo, int ficha) => _enviar(SinalizarWorkflow(fluxo, ficha));

  void cancelar(int fluxo) => _enviar(CancelarWorkflow(fluxo));

  void recriar(int fluxo, int ficha) => _enviar(RecriarCaixa(fluxo, ficha));

  void verDefinicao(Workflow w) {
    vendo = (equipe: w.equipe, workflow: w.id, fluxo: null);
    caixa = null;
    notifyListeners();
  }

  void verFluxo(int id, {String? equipe}) {
    final f = fluxo(id);
    vendo = (equipe: f?.equipe ?? equipe ?? '', workflow: f?.workflow ?? '', fluxo: id);
    caixa = null;
    notifyListeners();
  }

  void fecharGrafo() {
    vendo = null;
    caixa = null;
    notifyListeners();
  }

  void selecionarCaixa(String? id) {
    caixa = caixa == id ? null : id;
    notifyListeners();
  }

  void tratar(Entrada e) {
    if (e is! WorkflowsRecebidos) return;
    definicoes = e.definicoes;
    fluxos = e.fluxos;
    carregada = true;
    final v = vendo;
    if (v != null && v.fluxo != null && v.workflow.isEmpty) {
      final f = fluxo(v.fluxo!);
      if (f != null) vendo = (equipe: f.equipe, workflow: f.workflow, fluxo: f.id);
    }
    notifyListeners();
  }
}
