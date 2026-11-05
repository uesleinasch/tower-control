import 'package:flutter/foundation.dart';

import '../nucleo/protocolo.dart';
import '../nucleo/rotinas.dart';
import '../nucleo/tarefas.dart';
import 'chat.dart';

class EstadoRotinas extends ChangeNotifier {
  EstadoRotinas(this._enviar);

  final Enviar _enviar;

  List<Rotina> lista = const [];
  bool carregada = false;
  Rotina? rascunho;
  String? equipeDoRascunho;
  bool nova = false;
  bool salvando = false;
  bool _excluindo = false;
  String? erro;

  void carregar() => _enviar(const PedirRotinas());

  List<Rotina> daEquipe(String equipe) => [for (final r in lista) if (!r.sistema && r.equipe == equipe) r];

  List<Rotina> get doSistema => [for (final r in lista) if (r.sistema) r];

  Rotina? salva(String? equipe, String id) =>
      lista.where((r) => !r.sistema && r.equipe == equipe && r.id == id).firstOrNull;

  String? criadaPelaRotina(String? criadaPor) {
    final autor = rotinaDoAutor(criadaPor);
    if (autor == null) return null;
    return 'criada pela rotina ${salva(autor.equipe, autor.id)?.nome ?? autor.id}';
  }

  void disparar(Rotina r) {
    final equipe = r.equipe;
    if (r.sistema || equipe == null) return;
    _enviar(DispararRotina(equipe, r.id));
  }

  void alternarAtiva(Rotina r) {
    final equipe = r.equipe;
    if (r.sistema || equipe == null) return;
    _enviar(AtivarRotina(equipe, r.id, ativa: !r.ativa));
  }

  void editar(Rotina r) {
    if (r.sistema || r.equipe == null) return;
    rascunho = r;
    equipeDoRascunho = r.equipe;
    nova = false;
    erro = null;
    notifyListeners();
  }

  void novaRotina(EquipeResumo equipe) {
    rascunho = Rotina(
      id: idDaNovaRotina('', _usados(equipe.id)),
      nome: '',
      posicao: equipe.posicoes.firstOrNull?.id ?? '',
    );
    equipeDoRascunho = equipe.id;
    nova = true;
    erro = null;
    notifyListeners();
  }

  Iterable<String> _usados(String equipe) => daEquipe(equipe).map((r) => r.id);

  void mudar(Rotina Function(Rotina) mudanca) {
    final atual = rascunho;
    final equipe = equipeDoRascunho;
    if (atual == null || equipe == null) return;
    final mudada = mudanca(atual);
    rascunho = nova ? mudada.copiar(id: idDaNovaRotina(mudada.nome, _usados(equipe))) : mudada;
    notifyListeners();
  }

  List<String> errosDoRascunho(EquipeResumo equipe) {
    final r = rascunho;
    return r == null ? const [] : errosDaRotina(r, equipe);
  }

  void salvar(EquipeResumo equipe) {
    final r = rascunho;
    if (r == null || salvando || equipe.id != equipeDoRascunho) return;
    final erros = errosDaRotina(r, equipe);
    if (erros.isNotEmpty) {
      erro = erros.join('\n');
      notifyListeners();
      return;
    }
    salvando = true;
    erro = null;
    _enviar(SalvarRotina(equipe.id, r));
    notifyListeners();
  }

  void excluir() {
    final r = rascunho;
    final equipe = equipeDoRascunho;
    if (r == null || equipe == null || salvando) return;
    if (nova) {
      fecharEditor();
      return;
    }
    salvando = true;
    _excluindo = true;
    _enviar(ExcluirRotina(equipe, r.id));
    notifyListeners();
  }

  void trocarToken() {
    final r = rascunho;
    final equipe = equipeDoRascunho;
    if (r == null || equipe == null || salva(equipe, r.id)?.webhook != true) return;
    _enviar(TrocarTokenDaRotina(equipe, r.id));
  }

  void fecharEditor() {
    rascunho = null;
    equipeDoRascunho = null;
    nova = false;
    erro = null;
    notifyListeners();
  }

  void limparErro() {
    erro = null;
    notifyListeners();
  }

  void tratar(Entrada e) {
    switch (e) {
      case RotinasRecebidas(:final lista):
        this.lista = lista;
        carregada = true;
        if (salvando) _concluirEnvio();
      case Erro(:final mensagem) when salvando:
        salvando = false;
        _excluindo = false;
        erro = mensagem;
      default:
        return;
    }
    notifyListeners();
  }

  void _concluirEnvio() {
    final r = rascunho;
    if (_excluindo) {
      if (r != null && salva(equipeDoRascunho, r.id) != null) return;
      salvando = false;
      _excluindo = false;
      rascunho = null;
      equipeDoRascunho = null;
      nova = false;
      return;
    }
    if (r != null && nova && salva(equipeDoRascunho, r.id) == null) return;
    salvando = false;
    nova = false;
  }
}
