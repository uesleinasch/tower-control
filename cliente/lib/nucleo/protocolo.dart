import 'dart:convert';

import 'modelos.dart';

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
      'erro' => Erro(texto('mensagem')),
      'excluida' => Excluida(texto('id')),
      'fim' => Fim(texto('conversaId')),
      'permissao' => PedidoDePermissao(texto('id'), texto('comando')),
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
  const PedidoDePermissao(this.id, this.comando);
  final String id;
  final String comando;
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
  });
  final String conversaId;
  final String texto;
  final String? citacao;
  final List<String> anexos;
  final String? modelo;
  final bool? auto;

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
