import 'package:flutter/foundation.dart';

import '../nucleo/modelos.dart';
import '../nucleo/protocolo.dart';
import '../nucleo/skills.dart';
import 'chat.dart';

class EstadoSkills extends ChangeNotifier {
  EstadoSkills(this._enviar);

  final Enviar _enviar;

  List<Skill> lista = const [];
  bool carregada = false;
  RascunhoDeSkill? rascunho;
  bool salvando = false;
  String? erro;
  int geracao = 0;
  ({String dono, String id})? _excluindo;

  List<String> get errosDoRascunhoAtual {
    final r = rascunho;
    return r == null ? const [] : errosDoRascunho(r, existentes: lista);
  }

  bool get podeSalvar => rascunho != null && !salvando && errosDoRascunhoAtual.isEmpty;

  void carregar() => _enviar(const PedirSkills());

  void nova(String dono) => _abrir(RascunhoDeSkill(dono: dono));

  void editar(Skill s) => _abrir(RascunhoDeSkill.de(s));

  void _abrir(RascunhoDeSkill r) {
    rascunho = r;
    erro = null;
    salvando = false;
    geracao++;
    notifyListeners();
  }

  void mudar({String? id, String? descricao, String? corpo}) {
    final r = rascunho;
    if (r == null) return;
    rascunho = r.copiar(id: id, descricao: descricao, corpo: corpo);
    erro = null;
    notifyListeners();
  }

  void salvar() {
    final r = rascunho;
    if (r == null || salvando) return;
    final erros = errosDoRascunho(r, existentes: lista);
    if (erros.isNotEmpty) {
      erro = erros.join('\n');
      notifyListeners();
      return;
    }
    salvando = true;
    erro = null;
    _enviar(SalvarSkill(r));
    notifyListeners();
  }

  void descartar() {
    rascunho = null;
    erro = null;
    salvando = false;
    notifyListeners();
  }

  void excluir(Skill s) {
    if (salvando) return;
    _excluindo = (dono: s.dono, id: s.id);
    salvando = true;
    erro = null;
    _enviar(ExcluirSkill(s.dono, s.id));
    notifyListeners();
  }

  void limparErro() {
    erro = null;
    notifyListeners();
  }

  void anexarNaPersona(String persona, String id) =>
      _enviar(SalvarSkillsDaPersona(persona, comSkill(Perfil.porChave(persona).skills, id)));

  void tirarDaPersona(String persona, String id) =>
      _enviar(SalvarSkillsDaPersona(persona, semSkill(Perfil.porChave(persona).skills, id)));

  void tratar(Entrada e) {
    switch (e) {
      case SkillsRecebidas(:final lista):
        this.lista = lista;
        carregada = true;
        _aoReceber(lista);
      case Erro(:final mensagem) when salvando:
        salvando = false;
        _excluindo = null;
        erro = mensagem;
      default:
        return;
    }
    notifyListeners();
  }

  void _aoReceber(List<Skill> lista) {
    if (!salvando) return;
    final excluindo = _excluindo;
    if (excluindo != null) {
      if (lista.any((s) => s.dono == excluindo.dono && s.id == excluindo.id)) return;
      salvando = false;
      _excluindo = null;
      final r = rascunho;
      if (r != null && !r.nova && r.dono == excluindo.dono && r.id == excluindo.id) rascunho = null;
      return;
    }
    final r = rascunho;
    if (r != null && lista.any(r.mesmoConteudo)) {
      salvando = false;
      rascunho = null;
    }
  }
}
