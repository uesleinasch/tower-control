import 'dart:async';

import 'package:flutter/foundation.dart';

import '../nucleo/baloes.dart';
import '../nucleo/modelos.dart';
import '../nucleo/protocolo.dart';

typedef Enviar = bool Function(Saida saida);

sealed class ItemChat {
  const ItemChat();
}

class DoUsuario extends ItemChat {
  const DoUsuario(this.texto, {this.citacao, this.ts, this.anexos = const []});
  final String texto;
  final String? citacao;
  final DateTime? ts;
  final List<Anexo> anexos;
}

class BalaoPerfil extends ItemChat {
  const BalaoPerfil(this.perfil, this.texto, {this.primeiro = false, this.ts});
  final String perfil;
  final String texto;
  final bool primeiro;
  final DateTime? ts;
}

class Registro extends ItemChat {
  const Registro(this.comando);
  final String comando;
}

class AvisoChat extends ItemChat {
  const AvisoChat(this.texto);
  final String texto;
}

class ErroChat extends ItemChat {
  const ErroChat(this.texto);
  final String texto;
}

enum SituacaoPermissao { pendente, permitido, negado, expirado, conexaoCaiu }

class Permissao extends ItemChat {
  Permissao(this.id, this.comando) : criadoEm = DateTime.now();
  final String id;
  final String comando;
  final DateTime criadoEm;
  SituacaoPermissao situacao = SituacaoPermissao.pendente;

  static const prazo = Duration(seconds: 120);
}

List<ItemChat> baloesDe(String perfil, String texto, {DateTime? ts}) {
  final partes = dividirBaloes(texto);
  return [
    for (var i = 0; i < partes.length; i++) BalaoPerfil(perfil, partes[i], primeiro: i == 0, ts: ts),
  ];
}

class EstadoChat extends ChangeNotifier {
  EstadoChat(this._enviar);

  final Enviar _enviar;

  String? perfil;
  String? foco;
  String? conversaId;
  String titulo = '';
  String modelo = modeloPadrao;
  bool auto = false;
  bool emCurso = false;
  String? citacao;
  final anexos = <Anexo>[];
  int subindo = 0;
  final itens = <ItemChat>[];

  String _streaming = '';
  String? _perfilStreaming;
  final _prazos = <String, Timer>{};

  bool get ativo => perfil != null;
  bool get executor => perfil != null && Perfil.porChave(perfil!).executor;
  bool get ticktask => foco == 'ticktask';
  String? get perfilStreaming => _perfilStreaming;
  ({List<String> fechados, String aberto}) get emStreaming => baloesEmCurso(_streaming);

  void novaConversa(String perfil, {String modelo = modeloPadrao}) {
    _limpar();
    this.perfil = perfil;
    this.modelo = modelo;
    final nome = Perfil.porChave(perfil).nome;
    titulo = 'Nova conversa com $nome';
    itens.add(AvisoChat('Você está falando com $nome. A conversa é criada na primeira mensagem.'));
    notifyListeners();
  }

  void abrir(String id) => _enviar(Abrir(id));

  void fechar() {
    _limpar();
    notifyListeners();
  }

  void definirModelo(String valor) {
    modelo = valor;
    notifyListeners();
  }

  void alternarTicktask() {
    foco = ticktask ? null : 'ticktask';
    itens.add(AvisoChat(ticktask
        ? 'TickTask ligado: o Alfred registra direto no app.'
        : 'TickTask desligado: o Alfred volta a executar comandos.'));
    notifyListeners();
  }

  void alternarAuto() {
    auto = !auto;
    notifyListeners();
  }

  void definirCitacao(String texto) {
    citacao = cortarCitacao(texto);
    notifyListeners();
  }

  void limparCitacao() {
    citacao = null;
    notifyListeners();
  }

  void anexoSubindo(int delta) {
    subindo += delta;
    notifyListeners();
  }

  void adicionarAnexo(Anexo anexo) {
    anexos.add(anexo);
    notifyListeners();
  }

  void removerAnexo(String id) {
    anexos.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void mostrarErro(String texto) {
    itens.add(ErroChat(texto));
    notifyListeners();
  }

  bool enviar(String bruto) {
    final texto = bruto.trim();
    if (emCurso || perfil == null || subindo > 0) return false;
    if (texto.isEmpty && anexos.isEmpty) return false;
    final ids = [for (final a in anexos) a.id];
    final Saida saida = conversaId == null
        ? Nova(
            perfil: perfil!,
            texto: texto,
            citacao: citacao,
            anexos: ids,
            modelo: modelo,
            auto: auto,
            foco: foco,
          )
        : EnviarMensagem(
            conversaId: conversaId!,
            texto: texto,
            citacao: citacao,
            anexos: ids,
            modelo: modelo,
            auto: auto,
            foco: executor ? (foco ?? '') : null,
          );
    if (!_enviar(saida)) return false;
    itens.add(DoUsuario(texto, citacao: citacao, ts: DateTime.now(), anexos: List.of(anexos)));
    citacao = null;
    anexos.clear();
    emCurso = true;
    _perfilStreaming = perfil;
    notifyListeners();
    return true;
  }

  void responderPermissao(Permissao p, {required bool permitido}) {
    if (p.situacao != SituacaoPermissao.pendente) return;
    if (!_enviar(RespostaDePermissao(p.id, permitido: permitido))) return;
    _prazos.remove(p.id)?.cancel();
    p.situacao = permitido ? SituacaoPermissao.permitido : SituacaoPermissao.negado;
    notifyListeners();
  }

  void conexaoRestabelecida() {
    for (final item in itens) {
      if (item is Permissao && item.situacao == SituacaoPermissao.pendente) {
        item.situacao = SituacaoPermissao.conexaoCaiu;
      }
    }
    _cancelarPrazos();
    _encerrarStreaming();
    emCurso = false;
    if (conversaId != null) _enviar(Abrir(conversaId!));
    notifyListeners();
  }

  void tratar(Entrada e) {
    switch (e) {
      case Criada(:final meta):
        conversaId = meta.id;
        titulo = '${Perfil.porChave(meta.perfil).nome} — ${meta.titulo}';
      case ConversaAberta(:final meta, :final mensagens):
        final mesma = meta.id == conversaId;
        final rascunho = (citacao: citacao, anexos: List.of(anexos));
        _limpar();
        if (mesma) {
          citacao = rascunho.citacao;
          anexos.addAll(rascunho.anexos);
        }
        perfil = meta.perfil;
        foco = meta.foco;
        conversaId = meta.id;
        auto = meta.auto;
        modelo = meta.modelo ?? modeloPadrao;
        titulo = '${Perfil.porChave(meta.perfil).nome} — ${meta.titulo}';
        for (final m in mensagens) {
          if (m.doUsuario) {
            itens.add(DoUsuario(m.texto, citacao: m.citacao, ts: m.ts, anexos: m.anexos));
          } else {
            itens.addAll(baloesDe(m.perfil, m.texto, ts: m.ts));
          }
        }
      case Pedaco(:final conversaId, :final perfil, :final texto):
        if (conversaId != this.conversaId) return;
        _perfilStreaming = perfil;
        _streaming += texto;
      case Fim(:final conversaId):
        if (conversaId != this.conversaId) return;
        _encerrarStreaming();
        emCurso = false;
      case PedidoDePermissao(:final id, :final comando):
        final p = Permissao(id, comando);
        itens.add(p);
        _prazos[id] = Timer(Permissao.prazo, () {
          _prazos.remove(id);
          if (p.situacao != SituacaoPermissao.pendente) return;
          p.situacao = SituacaoPermissao.expirado;
          notifyListeners();
        });
      case PermissaoResolvida(:final id, :final como):
        final p = itens.whereType<Permissao>().where((p) => p.id == id).firstOrNull;
        if (p == null || p.situacao != SituacaoPermissao.pendente) return;
        _prazos.remove(id)?.cancel();
        p.situacao = switch (como) {
          'aprovado' => SituacaoPermissao.permitido,
          'negado' => SituacaoPermissao.negado,
          _ => SituacaoPermissao.expirado,
        };
      case ComandoExecutado(:final comando):
        itens.add(Registro(comando));
      case Aviso(:final texto):
        itens.add(AvisoChat(texto));
      case Erro(:final mensagem):
        _encerrarStreaming();
        emCurso = false;
        itens.add(ErroChat(mensagem));
      case Excluida(:final id):
        if (id == conversaId) _limpar();
      default:
        return;
    }
    notifyListeners();
  }

  void _encerrarStreaming() {
    if (_streaming.isNotEmpty && _perfilStreaming != null) {
      itens.addAll(baloesDe(_perfilStreaming!, _streaming, ts: DateTime.now()));
    }
    _streaming = '';
    _perfilStreaming = null;
  }

  void _cancelarPrazos() {
    for (final t in _prazos.values) {
      t.cancel();
    }
    _prazos.clear();
  }

  void _limpar() {
    _cancelarPrazos();
    perfil = null;
    foco = null;
    conversaId = null;
    titulo = '';
    auto = false;
    emCurso = false;
    citacao = null;
    anexos.clear();
    itens.clear();
    _streaming = '';
    _perfilStreaming = null;
  }

  @override
  void dispose() {
    _cancelarPrazos();
    super.dispose();
  }
}
