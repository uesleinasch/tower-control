import 'package:flutter/foundation.dart';

import '../nucleo/modelos.dart';
import '../nucleo/organograma.dart';
import '../nucleo/protocolo.dart';
import '../nucleo/tarefas.dart';
import 'chat.dart';

class EstadoEquipes extends ChangeNotifier {
  EstadoEquipes(this._enviar);

  final Enviar _enviar;

  List<EquipeResumo> equipes = const [];
  bool carregada = false;
  String vista = 'casa';
  EquipeResumo? rascunho;
  String? selecionada;
  String? erro;
  bool salvando = false;
  bool? mostrarPersonas;
  bool pausadoTudo = false;
  List<LinhaDeAuditoria>? auditoria;
  bool vendoRotinas = false;

  void verRotinas(bool sim) {
    if (vendoRotinas == sim) return;
    vendoRotinas = sim;
    if (sim) selecionada = null;
    notifyListeners();
  }

  void pausar(String alvo) => _enviar(Pausar(alvo));

  void retomar(String alvo) => _enviar(Retomar(alvo));

  void alternarPausaGeral() => pausadoTudo ? retomar('*') : pausar('*');

  void salvarOrcamento(String persona, {required double? usd, required int? tokens}) =>
      _enviar(SalvarOrcamento(persona, usd: usd, tokens: tokens));

  void pedirAuditoria() => _enviar(const PedirAuditoria());

  bool get alterada => rascunho != null;

  EquipeResumo? get atual =>
      rascunho ?? equipes.where((e) => e.id == vista).firstOrNull ?? equipes.firstOrNull;

  Set<String> get idsDePersonas => {for (final p in Perfil.todos) p.chave};

  void carregar() {
    _enviar(const PedirEquipes());
    _enviar(const PedirPersonas());
  }

  void escolher(String id) {
    vista = id;
    rascunho = null;
    selecionada = null;
    erro = null;
    notifyListeners();
  }

  void alternarPersonas(bool visivelAgora) {
    mostrarPersonas = !visivelAgora;
    notifyListeners();
  }

  void limparErro() {
    erro = null;
    notifyListeners();
  }

  void selecionar(String? id) {
    selecionada = id;
    notifyListeners();
  }

  void aplicar(EquipeResumo Function(EquipeResumo) operacao) {
    final base = atual;
    if (base == null) return;
    try {
      rascunho = operacao(base);
      erro = null;
    } on ErroDeOrganograma catch (e) {
      erro = e.mensagem;
    }
    notifyListeners();
  }

  void novaPosicao(String titulo) {
    final base = atual;
    if (base == null) return;
    final r = adicionarPosicao(base, titulo);
    rascunho = r.equipe;
    selecionada = r.id;
    erro = null;
    notifyListeners();
  }

  void novaSubordinada(String chefe, String titulo) {
    final base = atual;
    if (base == null) return;
    try {
      final r = adicionarSubordinada(base, chefe, titulo);
      rascunho = r.equipe;
      selecionada = r.id;
      erro = null;
    } on ErroDeOrganograma catch (e) {
      erro = e.mensagem;
    }
    notifyListeners();
  }

  void novaEquipe(String nome) {
    final limpo = nome.trim();
    if (limpo.isEmpty) return;
    final id = idLivre(slugDe(limpo), equipes.map((e) => e.id));
    vista = id;
    rascunho = EquipeResumo(id: id, nome: limpo, posicoes: const []);
    selecionada = null;
    erro = null;
    notifyListeners();
  }

  void salvar() {
    final equipe = rascunho;
    if (equipe == null) return;
    final erros = validarOrganograma(equipe, idsDePersonas);
    if (erros.isNotEmpty) {
      erro = erros.join('\n');
      notifyListeners();
      return;
    }
    salvando = true;
    erro = null;
    _enviar(SalvarEquipe(equipe));
    notifyListeners();
  }

  void descartar() {
    rascunho = null;
    erro = null;
    if (!equipes.any((e) => e.id == vista)) vista = 'casa';
    if (selecionada != null && atual?.posicao(selecionada!) == null) selecionada = null;
    notifyListeners();
  }

  void excluirEquipe() {
    final id = atual?.id;
    if (id == null || id == 'casa') return;
    if (!equipes.any((e) => e.id == id)) {
      descartar();
      return;
    }
    salvando = true;
    _enviar(ExcluirEquipe(id));
  }

  void criarPersona({required String nome, required String base, String titulo = '', String? modelo, String? cor}) {
    if (nome.trim().isEmpty || base.trim().isEmpty) return;
    _enviar(CriarPersona(nome: nome.trim(), base: base.trim(), titulo: titulo.trim(), modelo: modelo, cor: cor));
  }

  void excluirPersona(String id, String confirmacao) => _enviar(ExcluirPersona(id, confirmacao));

  void tratar(Entrada e) {
    switch (e) {
      case EquipesRecebidas(:final lista):
        equipes = lista;
        carregada = true;
        if (salvando) {
          salvando = false;
          rascunho = null;
          if (!lista.any((x) => x.id == vista)) vista = 'casa';
        }
        if (selecionada != null && atual?.posicao(selecionada!) == null) selecionada = null;
      case PersonasRecebidas():
        break;
      case OrquestraRecebida(:final pausadoTudo):
        this.pausadoTudo = pausadoTudo;
      case AuditoriaRecebida(:final lista):
        auditoria = lista;
      case Erro(:final mensagem) when salvando:
        salvando = false;
        erro = mensagem;
      default:
        return;
    }
    notifyListeners();
  }
}
