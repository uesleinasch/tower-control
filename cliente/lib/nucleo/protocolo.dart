import 'dart:convert';

import 'modelos.dart';
import 'rotinas.dart';
import 'tarefas.dart';

sealed class Entrada {
  const Entrada();

  static Entrada decodificar(String bruto) {
    final Object? decodificado;
    try {
      decodificado = jsonDecode(bruto);
    } on FormatException {
      return Desconhecida('', bruto);
    }
    if (decodificado is! Map<String, dynamic>) return Desconhecida('', bruto);
    final json = decodificado;
    final tipo = json['tipo'] as String? ?? '';
    String texto(String campo) => json[campo] as String? ?? '';
    int? inteiro(String campo) => (json[campo] as num?)?.toInt();
    return switch (tipo) {
      'atalhos' => AtalhosRecebidos(listaDeJson(json['lista'], Atalho.deJson)),
      'aviso' => Aviso(texto('texto')),
      'board-status' => BoardStatus(texto('texto')),
      'board-sintese' => BoardSintese(texto('texto'), texto('ata')),
      'chunk' => Pedaco(texto('conversaId'), texto('perfil'), texto('texto')),
      'comando' => ComandoExecutado(texto('comando')),
      'conversa' => ConversaAberta(
          MetaConversa.deJson(json['meta'] as Map<String, dynamic>),
          listaDeJson(json['mensagens'], Mensagem.deJson),
        ),
      'conversas' => Conversas(listaDeJson(json['lista'], MetaConversa.deJson)),
      'criada' => Criada(MetaConversa.deJson(json['meta'] as Map<String, dynamic>)),
      'decisao' => DecisaoAberta(texto('id'), texto('conteudo')),
      'decisoes' => Decisoes(listaDeJson(json['lista'], Decisao.deJson)),
      'equipes' => EquipesRecebidas(listaDeJson(json['lista'], EquipeResumo.deJson)),
      'erro' => Erro(texto('mensagem')),
      'excluida' => Excluida(texto('id')),
      'fim' => Fim(texto('conversaId')),
      'execucao' => ExecucaoRecebida(
          Execucao.deJson(json['execucao'] as Map<String, dynamic>),
          json['eventos'] == null ? null : listaDeJson(json['eventos'], EventoDeExecucao.deJson),
        ),
      'execucao-evento' => EventoRecebido(
          inteiro('execucaoId') ?? 0,
          inteiro('tarefaId') ?? 0,
          EventoDeExecucao.deJson(json['evento'] as Map<String, dynamic>),
        ),
      'personas' => PersonasRecebidas(listaDeJson(json['lista'], Perfil.deJson)),
      'orquestra' => OrquestraRecebida(pausadoTudo: json['pausadoTudo'] == true),
      'auditoria' => AuditoriaRecebida(listaDeJson(json['lista'], LinhaDeAuditoria.deJson)),
      'permissao' => PedidoDePermissao(texto('id'), texto('comando'), tarefaId: inteiro('tarefaId')),
      'permissao-resolvida' => PermissaoResolvida(texto('id'), texto('como')),
      'tarefa' => TarefaRecebida(
          Tarefa.deJson(json['tarefa'] as Map<String, dynamic>),
          listaDeJson(json['registros'], RegistroDeTarefa.deJson),
          execucoes: listaDeJson(json['execucoes'], Execucao.deJson),
          custoUSD: (json['custoUSD'] as num?)?.toDouble() ?? 0,
          pedida: json['pedida'] == true,
        ),
      'tarefas' => TarefasRecebidas(listaDeJson(json['lista'], Tarefa.deJson)),
      'rotinas' => RotinasRecebidas(listaDeJson(json['lista'], Rotina.deJson)),
      _ => Desconhecida(tipo, bruto),
    };
  }
}

class AtalhosRecebidos extends Entrada {
  const AtalhosRecebidos(this.lista);
  final List<Atalho> lista;
}

class Aviso extends Entrada {
  const Aviso(this.texto);
  final String texto;
}

class BoardStatus extends Entrada {
  const BoardStatus(this.texto);
  final String texto;
}

class BoardSintese extends Entrada {
  const BoardSintese(this.texto, this.ata);
  final String texto;
  final String ata;
}

class Pedaco extends Entrada {
  const Pedaco(this.conversaId, this.perfil, this.texto);
  final String conversaId;
  final String perfil;
  final String texto;
}

class ComandoExecutado extends Entrada {
  const ComandoExecutado(this.comando);
  final String comando;
}

class ConversaAberta extends Entrada {
  const ConversaAberta(this.meta, this.mensagens);
  final MetaConversa meta;
  final List<Mensagem> mensagens;
}

class Conversas extends Entrada {
  const Conversas(this.lista);
  final List<MetaConversa> lista;
}

class Criada extends Entrada {
  const Criada(this.meta);
  final MetaConversa meta;
}

class DecisaoAberta extends Entrada {
  const DecisaoAberta(this.id, this.conteudo);
  final String id;
  final String conteudo;
}

class Decisoes extends Entrada {
  const Decisoes(this.lista);
  final List<Decisao> lista;
}

class EquipesRecebidas extends Entrada {
  const EquipesRecebidas(this.lista);
  final List<EquipeResumo> lista;
}

class OrquestraRecebida extends Entrada {
  const OrquestraRecebida({required this.pausadoTudo});
  final bool pausadoTudo;
}

class AuditoriaRecebida extends Entrada {
  const AuditoriaRecebida(this.lista);
  final List<LinhaDeAuditoria> lista;
}

class PersonasRecebidas extends Entrada {
  const PersonasRecebidas(this.lista);
  final List<Perfil> lista;
}

class TarefasRecebidas extends Entrada {
  const TarefasRecebidas(this.lista);
  final List<Tarefa> lista;
}

class RotinasRecebidas extends Entrada {
  const RotinasRecebidas(this.lista);
  final List<Rotina> lista;
}

class TarefaRecebida extends Entrada {
  const TarefaRecebida(this.tarefa, this.registros, {this.execucoes = const [], this.custoUSD = 0, this.pedida = false});
  final Tarefa tarefa;
  final List<RegistroDeTarefa> registros;
  final List<Execucao> execucoes;
  final double custoUSD;
  final bool pedida;
}

class ExecucaoRecebida extends Entrada {
  const ExecucaoRecebida(this.execucao, this.eventos);
  final Execucao execucao;
  final List<EventoDeExecucao>? eventos;
}

class EventoRecebido extends Entrada {
  const EventoRecebido(this.execucaoId, this.tarefaId, this.evento);
  final int execucaoId;
  final int tarefaId;
  final EventoDeExecucao evento;
}

class Erro extends Entrada {
  const Erro(this.mensagem);
  final String mensagem;
}

class Excluida extends Entrada {
  const Excluida(this.id);
  final String id;
}

class Fim extends Entrada {
  const Fim(this.conversaId);
  final String conversaId;
}

class PedidoDePermissao extends Entrada {
  const PedidoDePermissao(this.id, this.comando, {this.tarefaId});
  final String id;
  final String comando;
  final int? tarefaId;
}

class PermissaoResolvida extends Entrada {
  const PermissaoResolvida(this.id, this.como);
  final String id;
  final String como;
}

class Desconhecida extends Entrada {
  const Desconhecida(this.tipo, this.bruto);
  final String tipo;
  final String bruto;
}

sealed class Saida {
  const Saida();

  String get tipo;
  Map<String, Object?> get campos => const {};

  String codificar() {
    final corpo = <String, Object?>{'tipo': tipo};
    campos.forEach((chave, valor) {
      if (valor != null) corpo[chave] = valor;
    });
    return jsonEncode(corpo);
  }
}

class Listar extends Saida {
  const Listar();
  @override
  String get tipo => 'listar';
}

class Nova extends Saida {
  const Nova({
    required this.perfil,
    required this.texto,
    this.citacao,
    this.anexos = const [],
    this.modelo,
    this.auto = false,
    this.foco,
  });
  final String perfil;
  final String texto;
  final String? citacao;
  final List<String> anexos;
  final String? modelo;
  final bool auto;
  final String? foco;

  @override
  String get tipo => 'nova';
  @override
  Map<String, Object?> get campos => {
        'perfil': perfil,
        'texto': texto,
        'citacao': citacao,
        'anexos': anexos,
        'modelo': modelo,
        'auto': auto,
        'foco': foco,
      };
}

class EnviarMensagem extends Saida {
  const EnviarMensagem({
    required this.conversaId,
    required this.texto,
    this.citacao,
    this.anexos = const [],
    this.modelo,
    this.auto,
    this.foco,
  });
  final String conversaId;
  final String texto;
  final String? citacao;
  final List<String> anexos;
  final String? modelo;
  final bool? auto;
  final String? foco;

  @override
  String get tipo => 'mensagem';
  @override
  Map<String, Object?> get campos => {
        'conversaId': conversaId,
        'texto': texto,
        'citacao': citacao,
        'anexos': anexos,
        'modelo': modelo,
        'auto': auto,
        'foco': foco,
      };
}

class RespostaDePermissao extends Saida {
  const RespostaDePermissao(this.id, {required this.permitido});
  final String id;
  final bool permitido;

  @override
  String get tipo => 'permissao-resposta';
  @override
  Map<String, Object?> get campos => {'id': id, 'permitido': permitido};
}

class Excluir extends Saida {
  const Excluir(this.conversaId);
  final String conversaId;

  @override
  String get tipo => 'excluir';
  @override
  Map<String, Object?> get campos => {'conversaId': conversaId};
}

class Abrir extends Saida {
  const Abrir(this.conversaId);
  final String conversaId;

  @override
  String get tipo => 'abrir';
  @override
  Map<String, Object?> get campos => {'conversaId': conversaId};
}

class ConvocarBoard extends Saida {
  const ConvocarBoard(this.pauta, {this.contexto});
  final String pauta;
  final String? contexto;

  @override
  String get tipo => 'board';
  @override
  Map<String, Object?> get campos => {'pauta': pauta, 'contexto': contexto};
}

class PedirDecisoes extends Saida {
  const PedirDecisoes();
  @override
  String get tipo => 'decisoes';
}

class PedirDecisao extends Saida {
  const PedirDecisao(this.id);
  final String id;

  @override
  String get tipo => 'decisao';
  @override
  Map<String, Object?> get campos => {'id': id};
}

class Visivel extends Saida {
  const Visivel(this.conversaId);
  final String? conversaId;

  @override
  String get tipo => 'visivel';
  @override
  Map<String, Object?> get campos => {'conversaId': conversaId};
}

class PedirEquipes extends Saida {
  const PedirEquipes();
  @override
  String get tipo => 'equipes';
}

class PedirTarefas extends Saida {
  const PedirTarefas({this.equipe});
  final String? equipe;

  @override
  String get tipo => 'tarefas';
  @override
  Map<String, Object?> get campos => {'equipe': equipe};
}

class PedirTarefa extends Saida {
  const PedirTarefa(this.id);
  final int id;

  @override
  String get tipo => 'tarefa';
  @override
  Map<String, Object?> get campos => {'id': id};
}

class CriarTarefa extends Saida {
  const CriarTarefa({required this.equipe, required this.posicao, required this.titulo, this.porque = ''});
  final String equipe;
  final String posicao;
  final String titulo;
  final String porque;

  @override
  String get tipo => 'tarefa-criar';
  @override
  Map<String, Object?> get campos => {
        'tarefa': {'equipe': equipe, 'posicao': posicao, 'titulo': titulo, 'porque': porque},
      };
}

class PedirExecucao extends Saida {
  const PedirExecucao(this.id);
  final int id;

  @override
  String get tipo => 'execucao';
  @override
  Map<String, Object?> get campos => {'id': id};
}

class MudarStatusTarefa extends Saida {
  const MudarStatusTarefa(this.id, this.status);
  final int id;
  final String status;

  @override
  String get tipo => 'tarefa-status';
  @override
  Map<String, Object?> get campos => {'id': id, 'status': status};
}

class ComentarTarefa extends Saida {
  const ComentarTarefa(this.id, this.texto);
  final int id;
  final String texto;

  @override
  String get tipo => 'tarefa-comentar';
  @override
  Map<String, Object?> get campos => {'id': id, 'texto': texto};
}

class PedirPersonas extends Saida {
  const PedirPersonas();

  @override
  String get tipo => 'personas';
  @override
  Map<String, Object?> get campos => const {};
}

class CriarPersona extends Saida {
  const CriarPersona({required this.nome, required this.base, this.titulo = '', this.modelo, this.cor});
  final String nome;
  final String base;
  final String titulo;
  final String? modelo;
  final String? cor;

  @override
  String get tipo => 'persona-criar';
  @override
  Map<String, Object?> get campos => {
        'persona': {'nome': nome, 'base': base, 'titulo': titulo, 'modelo': ?modelo, 'cor': ?cor},
      };
}

class ExcluirPersona extends Saida {
  const ExcluirPersona(this.id, this.confirmacao);
  final String id;
  final String confirmacao;

  @override
  String get tipo => 'persona-excluir';
  @override
  Map<String, Object?> get campos => {'id': id, 'confirmacao': confirmacao};
}

class SalvarEquipe extends Saida {
  const SalvarEquipe(this.equipe);
  final EquipeResumo equipe;

  @override
  String get tipo => 'equipe-salvar';
  @override
  Map<String, Object?> get campos => {'equipe': equipe.paraJson()};
}

class ExcluirEquipe extends Saida {
  const ExcluirEquipe(this.id);
  final String id;

  @override
  String get tipo => 'equipe-excluir';
  @override
  Map<String, Object?> get campos => {'id': id};
}

class SalvarOrcamento extends Saida {
  const SalvarOrcamento(this.id, {required this.usd, required this.tokens});
  final String id;
  final double? usd;
  final int? tokens;

  @override
  String get tipo => 'persona-salvar';
  @override
  Map<String, Object?> get campos => {
        'persona': {'id': id, 'orcamentoMensalUSD': usd, 'orcamentoMensalTokens': tokens},
      };
}

class Pausar extends Saida {
  const Pausar(this.alvo);
  final String alvo;

  @override
  String get tipo => 'pausar';
  @override
  Map<String, Object?> get campos => {'alvo': alvo};
}

class Retomar extends Saida {
  const Retomar(this.alvo);
  final String alvo;

  @override
  String get tipo => 'retomar';
  @override
  Map<String, Object?> get campos => {'alvo': alvo};
}

class AprovarPlano extends Saida {
  const AprovarPlano(this.id);
  final int id;

  @override
  String get tipo => 'tarefa-aprovar-plano';
  @override
  Map<String, Object?> get campos => {'id': id};
}

class PedirAuditoria extends Saida {
  const PedirAuditoria();

  @override
  String get tipo => 'auditoria';
  @override
  Map<String, Object?> get campos => const {};
}

class DecidirTarefa extends Saida {
  const DecidirTarefa.aprovar(this.id, {this.texto}) : decisao = 'aprovar';
  const DecidirTarefa.mudanca(this.id, String this.texto) : decisao = 'mudanca';
  final int id;
  final String decisao;
  final String? texto;

  @override
  String get tipo => 'tarefa-decidir';
  @override
  Map<String, Object?> get campos => {'id': id, 'decisao': decisao, 'texto': texto};
}

class PedirRotinas extends Saida {
  const PedirRotinas();

  @override
  String get tipo => 'rotinas';
}

class DispararRotina extends Saida {
  const DispararRotina(this.equipe, this.id);
  final String equipe;
  final String id;

  @override
  String get tipo => 'rotina-disparar';
  @override
  Map<String, Object?> get campos => {'equipe': equipe, 'id': id};
}

class AtivarRotina extends Saida {
  const AtivarRotina(this.equipe, this.id, {required this.ativa});
  final String equipe;
  final String id;
  final bool ativa;

  @override
  String get tipo => 'rotina-ativar';
  @override
  Map<String, Object?> get campos => {'equipe': equipe, 'id': id, 'ativa': ativa};
}

class SalvarRotina extends Saida {
  const SalvarRotina(this.equipe, this.rotina);
  final String equipe;
  final Rotina rotina;

  @override
  String get tipo => 'rotina-salvar';
  @override
  Map<String, Object?> get campos => {'equipe': equipe, 'rotina': rotina.paraJson()};
}

class ExcluirRotina extends Saida {
  const ExcluirRotina(this.equipe, this.id);
  final String equipe;
  final String id;

  @override
  String get tipo => 'rotina-excluir';
  @override
  Map<String, Object?> get campos => {'equipe': equipe, 'id': id};
}

class TrocarTokenDaRotina extends Saida {
  const TrocarTokenDaRotina(this.equipe, this.id);
  final String equipe;
  final String id;

  @override
  String get tipo => 'rotina-token';
  @override
  Map<String, Object?> get campos => {'equipe': equipe, 'id': id};
}
