import 'package:flutter/foundation.dart';

import '../nucleo/editor_de_workflow.dart';
import '../nucleo/editor_de_workflow.dart' as nucleo show criarDepois;
import '../nucleo/protocolo.dart';
import '../nucleo/tarefas.dart';
import '../nucleo/workflows.dart';
import 'chat.dart';

class EstadoEditorDeWorkflow extends ChangeNotifier {
  EstadoEditorDeWorkflow(this._enviar);

  final Enviar _enviar;

  EquipeResumo? equipe;
  Historico<WorkflowJson>? _historico;
  WorkflowJson _original = const {};
  int versaoBase = 0;
  Map<String, Map<String, String>> textosEmArquivo = const {};
  String? selecionada;
  ErrosDoWorkflow erros = const {};
  bool salvando = false;
  bool _excluindo = false;
  String? erro;
  int? sobreposto;
  int geracao = 0;
  String? _grupo;
  Set<int>? _fluxosAntesDeIniciar;

  bool get aberto => _historico != null;

  WorkflowJson? get rascunho => _historico?.atual;

  String? get id => rascunho?['id'] is String ? rascunho!['id'] as String : null;

  bool get novo => versaoBase == 0;

  bool get mudou => aberto && !mesmoWorkflow(_original, _historico!.atual);

  bool get alterado => aberto && (novo || mudou);

  bool get podeDesfazer => _historico?.podeDesfazer ?? false;

  bool get podeRefazer => _historico?.podeRefazer ?? false;

  int get problemas => contarErros(erros);

  bool get podeSalvar => alterado && problemas == 0 && !salvando;

  bool editando(String equipe) => aberto && this.equipe?.id == equipe;

  void abrir(Workflow w, EquipeResumo equipe) =>
      _comecar(rascunhoDe(w), equipe, versao: w.versao, textos: textosEmArquivoDe(w));

  String? criarNovo(String nome, EquipeResumo equipe, Iterable<String> usados) {
    try {
      _comecar(novoWorkflow(nome, usados), equipe, versao: 0);
      return null;
    } on ErroDeWorkflow catch (e) {
      return e.mensagem;
    }
  }

  void duplicar(Workflow w, EquipeResumo equipe, Iterable<String> usados) =>
      _comecar(duplicarWorkflow(rascunhoDe(w), usados), equipe, versao: 0);

  void _comecar(WorkflowJson w, EquipeResumo equipe, {required int versao, Map<String, Map<String, String>> textos = const {}}) {
    this.equipe = equipe;
    _historico = Historico(w);
    _original = w;
    versaoBase = versao;
    textosEmArquivo = textos;
    selecionada = null;
    erro = null;
    salvando = false;
    _excluindo = false;
    sobreposto = null;
    _grupo = null;
    _fluxosAntesDeIniciar = null;
    geracao++;
    _validar();
    notifyListeners();
  }

  void _validar() {
    final r = rascunho;
    final e = equipe;
    erros = r == null || e == null ? const {} : validarRascunho(r, e);
  }

  void _depoisDeMudar() {
    final r = rascunho;
    if (selecionada != null && (r == null || caixaDe(r, selecionada!) == null)) selecionada = null;
    sobreposto = null;
    _validar();
    notifyListeners();
  }

  String? aplicar(WorkflowJson Function(WorkflowJson) operacao, {String? grupo, String? selecionar}) {
    final h = _historico;
    if (h == null) return null;
    final WorkflowJson novo;
    try {
      novo = operacao(h.atual);
    } on ErroDeWorkflow catch (e) {
      return e.mensagem;
    }
    if (mesmoWorkflow(novo, h.atual)) return null;
    if (grupo != null && grupo == _grupo) {
      h.atual = novo;
    } else {
      h.fazer(novo);
    }
    _grupo = grupo;
    if (grupo == null) geracao++;
    if (selecionar != null) selecionada = selecionar;
    erro = null;
    _depoisDeMudar();
    return null;
  }

  String? criar(String tipo, Ponto ponto) {
    final r = rascunho;
    if (r == null) return null;
    final criado = criarCaixa(r, tipo, ponto);
    aplicar((_) => criado.workflow, selecionar: criado.id);
    return criado.id;
  }

  String? criarDepois(String de, String? quando, String tipo) {
    final r = rascunho;
    if (r == null) return null;
    final criado = nucleo.criarDepois(r, de, quando, tipo);
    aplicar((_) => criado.workflow, selecionar: criado.id);
    return criado.id;
  }

  String? renomear(String de, String para) {
    final limpo = para.trim();
    return aplicar((w) => renomearCaixa(w, de, limpo), selecionar: selecionada == de ? limpo : null);
  }

  void remover(String id) => aplicar((w) => removerCaixa(w, id));

  void selecionar(String? id) {
    if (selecionada == id) return;
    selecionada = id;
    notifyListeners();
  }

  void desfazer() {
    if (_historico?.desfazer() != true) return;
    _grupo = null;
    geracao++;
    _depoisDeMudar();
  }

  void refazer() {
    if (_historico?.refazer() != true) return;
    _grupo = null;
    geracao++;
    _depoisDeMudar();
  }

  void sobrepor(int? fluxo) {
    sobreposto = sobreposto == fluxo ? null : fluxo;
    notifyListeners();
  }

  void aguardarFluxoNovo(Iterable<int> existentes) => _fluxosAntesDeIniciar = existentes.toSet();

  void salvar() {
    final r = rascunho;
    final e = equipe;
    if (r == null || e == null || salvando) return;
    _validar();
    if (problemas > 0) {
      erro = problemas == 1 ? 'Corrija o problema antes de salvar.' : 'Corrija os $problemas problemas antes de salvar.';
      notifyListeners();
      return;
    }
    salvando = true;
    erro = null;
    _enviar(SalvarWorkflow(e.id, comLayoutCompleto(r)..['versao'] = versaoBase));
    notifyListeners();
  }

  void descartar() {
    if (!aberto) return;
    _historico = Historico(_original);
    _grupo = null;
    erro = null;
    geracao++;
    _depoisDeMudar();
  }

  void excluir() {
    final e = equipe;
    final id = this.id;
    if (e == null || id == null || salvando) return;
    if (novo) {
      fechar();
      return;
    }
    salvando = true;
    _excluindo = true;
    erro = null;
    _enviar(ExcluirWorkflow(e.id, id));
    notifyListeners();
  }

  void fechar() {
    _historico = null;
    _original = const {};
    equipe = null;
    versaoBase = 0;
    textosEmArquivo = const {};
    selecionada = null;
    erros = const {};
    salvando = false;
    _excluindo = false;
    erro = null;
    sobreposto = null;
    _grupo = null;
    _fluxosAntesDeIniciar = null;
    notifyListeners();
  }

  void limparErro() {
    erro = null;
    notifyListeners();
  }

  void tratar(Entrada e) {
    if (!aberto) return;
    switch (e) {
      case WorkflowsRecebidos(:final definicoes, :final fluxos):
        _aoReceber(definicoes, fluxos);
        return;
      case EquipesRecebidas(:final lista):
        final nova = lista.where((x) => x.id == equipe?.id).firstOrNull;
        if (nova == null) return;
        equipe = nova;
        _validar();
      case Erro(:final mensagem) when salvando:
        salvando = false;
        _excluindo = false;
        erro = mensagem;
      default:
        return;
    }
    notifyListeners();
  }

  void _aoReceber(List<Workflow> definicoes, List<Fluxo> fluxos) {
    final e = equipe;
    final id = this.id;
    if (e == null || id == null) return;
    final salvo = definicoes.where((w) => w.equipe == e.id && w.id == id).firstOrNull;
    if (_excluindo) {
      if (salvo == null) fechar();
      return;
    }
    if (salvo != null && salvo.versao > versaoBase && (salvando || !alterado)) {
      final antes = selecionada;
      _comecar(rascunhoDe(salvo), e, versao: salvo.versao, textos: textosEmArquivoDe(salvo));
      if (antes != null && caixaDe(rascunho!, antes) != null) selecionada = antes;
    }
    final esperando = _fluxosAntesDeIniciar;
    if (esperando != null) {
      final iniciado = fluxos
          .where((f) => f.equipe == e.id && f.workflow == id && f.versao == versaoBase && !esperando.contains(f.id))
          .firstOrNull;
      if (iniciado != null) {
        _fluxosAntesDeIniciar = null;
        sobreposto = iniciado.id;
      }
    }
    notifyListeners();
  }
}
