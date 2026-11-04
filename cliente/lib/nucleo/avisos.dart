import 'dart:convert';

sealed class LinhaDeAviso {
  const LinhaDeAviso(this.id, this.seq);
  final String id;
  final int seq;
}

class Notificacao extends LinhaDeAviso {
  const Notificacao({
    required String id,
    required int seq,
    required this.tipo,
    required this.titulo,
    required this.corpo,
    this.conversaId,
    this.tarefaId,
    this.acoes = const [],
    this.criadoEm,
    this.expiraEm,
  }) : super(id, seq);

  final String tipo;
  final String titulo;
  final String corpo;
  final String? conversaId;
  final int? tarefaId;
  final List<String> acoes;
  final DateTime? criadoEm;
  final DateTime? expiraEm;

  bool expirou(DateTime agora) => expiraEm != null && !agora.isBefore(expiraEm!);

  static Notificacao? deJson(Map<String, dynamic> json) {
    final id = json['id'];
    final seq = json['seq'];
    final tipo = json['tipo'];
    if (id is! String || seq is! num || tipo is! String) return null;
    final alvo = json['alvo'] is Map ? json['alvo'] as Map : const {};
    return Notificacao(
      id: id,
      seq: seq.toInt(),
      tipo: tipo,
      titulo: json['titulo'] as String? ?? '',
      corpo: json['corpo'] as String? ?? '',
      conversaId: alvo['conversaId'] as String?,
      tarefaId: (alvo['tarefaId'] as num?)?.toInt(),
      acoes: [for (final a in json['acoes'] is List ? json['acoes'] as List : const []) if (a is String) a],
      criadoEm: DateTime.tryParse(json['criadoEm'] as String? ?? ''),
      expiraEm: DateTime.tryParse(json['expiraEm'] as String? ?? ''),
    );
  }

  String paraCarga() => jsonEncode({
        'id': id,
        'seq': seq,
        'tipo': tipo,
        'titulo': titulo,
        'corpo': corpo,
        'alvo': {'conversaId': ?conversaId, 'tarefaId': ?tarefaId},
        'acoes': acoes,
        'criadoEm': ?criadoEm?.toIso8601String(),
        'expiraEm': ?expiraEm?.toIso8601String(),
      });

  static Notificacao? daCarga(String? carga) {
    if (carga == null) return null;
    try {
      final json = jsonDecode(carga);
      return json is Map<String, dynamic> ? deJson(json) : null;
    } on FormatException {
      return null;
    }
  }
}

class Resolucao extends LinhaDeAviso {
  const Resolucao({required String id, required int seq, required this.como, this.aparelho}) : super(id, seq);
  final String como;
  final String? aparelho;
}

LinhaDeAviso? lerLinha(String linha) {
  if (linha.trim().isEmpty) return null;
  final Object? json;
  try {
    json = jsonDecode(linha);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, dynamic>) return null;
  if (json['tipo'] == 'resolvido') {
    final id = json['id'];
    final seq = json['seq'];
    final como = json['como'];
    if (id is! String || seq is! num || como is! String) return null;
    return Resolucao(id: id, seq: seq.toInt(), como: como, aparelho: json['aparelho'] as String?);
  }
  return Notificacao.deJson(json);
}

enum Canal {
  aprovacoes('avisos-aprovacoes', 'Aprovações', alta: true),
  lembretes('avisos-lembretes', 'Lembretes', alta: true),
  respostas('avisos-respostas', 'Respostas', alta: false),
  resumo('avisos-resumo', 'Resumo do dia', alta: false, baixa: true);

  const Canal(this.id, this.nome, {required this.alta, this.baixa = false});
  final String id;
  final String nome;
  final bool alta;
  final bool baixa;
}

Canal canalDe(String tipo) => switch (tipo) {
      'aprovacao' => Canal.aprovacoes,
      'lembrete' || 'atrasada' => Canal.lembretes,
      'resumo' => Canal.resumo,
      _ => Canal.respostas,
    };

class Botao {
  const Botao(this.id, this.rotulo, {this.comTexto = false});
  final String id;
  final String rotulo;
  final bool comTexto;
}

const abrirConversa = 'abrir';

List<Botao> botoesDe(Notificacao n, {required bool campoDeTexto, required DateTime agora}) {
  if (n.expirou(agora)) return const [];
  final pode = n.acoes.toSet();
  return [
    if (pode.contains('aprovar')) const Botao('aprovar', 'Aprovar'),
    if (pode.contains('negar')) const Botao('negar', 'Negar'),
    if (pode.contains('concluir')) const Botao('concluir', 'Concluir'),
    if (pode.contains('adiar')) ...const [Botao('adiar-1h', '+1 h'), Botao('adiar-amanha', 'Amanhã 09:00')],
    if (pode.contains('responder'))
      campoDeTexto ? const Botao('responder', 'Responder', comTexto: true) : const Botao(abrirConversa, 'Responder'),
  ];
}

Map<String, Object?>? pedidoDoBotao(String botao, {String? texto, required String aparelho}) {
  final base = <String, Object?>{'aparelho': aparelho};
  return switch (botao) {
    'aprovar' || 'negar' || 'concluir' => {...base, 'acao': botao},
    'adiar-1h' => {...base, 'acao': 'adiar', 'adiarPara': '1h'},
    'adiar-amanha' => {...base, 'acao': 'adiar', 'adiarPara': 'amanha'},
    'responder' when texto != null && texto.trim().isNotEmpty => {...base, 'acao': 'responder', 'texto': texto.trim()},
    _ => null,
  };
}

const _rotulosDoComo = {
  'aprovado': 'Aprovado',
  'negado': 'Negado',
  'concluida': 'Concluída',
  'adiada': 'Adiada',
  'respondido': 'Resposta enviada',
  'lido': 'Lido',
  'expirado': 'Expirou',
};

String textoDoResultado(int status, Map<String, dynamic> corpo) {
  final como = _rotulosDoComo[corpo['como']] ?? corpo['como'] as String?;
  if (status == 200) return como ?? 'Feito';
  if (status == 409) {
    final aparelho = corpo['aparelho'] as String?;
    return 'Já resolvido${aparelho == null ? '' : ' no $aparelho'}${como == null ? '' : ': $como'}';
  }
  if (status == 404) return 'Este aviso não existe mais';
  return corpo['erro'] as String? ?? 'Falhou ($status)';
}

enum Alerta { ignorar, silencioso, tocar }

Alerta alertaDe(Notificacao n, DateTime agora) {
  final criado = n.criadoEm;
  if (criado == null) return Alerta.silencioso;
  final idade = agora.difference(criado);
  if (idade > const Duration(hours: 24)) return Alerta.ignorar;
  if (idade > const Duration(minutes: 2)) return Alerta.silencioso;
  return Alerta.tocar;
}

String corpoDe(Notificacao n, DateTime agora) =>
    n.tipo == 'aprovacao' && n.expirou(agora) ? '${n.corpo}\nExpirou sem resposta.' : n.corpo;

int idDaNotificacao(String id) {
  var hash = 0x811c9dc5;
  for (final unidade in utf8.encode(id)) {
    hash = ((hash ^ unidade) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

sealed class Destino {
  const Destino();
}

class AbrirConversa extends Destino {
  const AbrirConversa(this.conversaId);
  final String conversaId;
}

class NovaComAlfredNoTickTask extends Destino {
  const NovaComAlfredNoTickTask();
}

class AbrirTarefa extends Destino {
  const AbrirTarefa(this.tarefaId);
  final int tarefaId;
}

Destino? destinoDe(Notificacao n) => switch (n.tipo) {
      'lembrete' || 'atrasada' || 'resumo' => const NovaComAlfredNoTickTask(),
      _ when n.conversaId != null => AbrirConversa(n.conversaId!),
      'tarefa' || 'aprovacao' when n.tarefaId != null => AbrirTarefa(n.tarefaId!),
      _ => null,
    };
