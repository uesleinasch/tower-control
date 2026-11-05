import 'formato.dart';
import 'tarefas.dart';

const rotulosDoEspelho = <String, String>{
  'aprovacao': 'aprovação de entrega',
  'plano': 'plano para aprovar',
  'entrega': 'entrega para concluir',
  'decisao': 'decisão de workflow',
  'sinal': 'sinal de workflow',
  'bloqueada': 'tarefa bloqueada',
  'backlog': 'delegada esperando liberar',
  'atrasada': 'caixa atrasada',
  'orcamento': 'orçamento estourado',
  'rotina': 'rotina que falhou',
  'vaga': 'tarefa em posição vaga',
};

final tiposDoEspelho = rotulosDoEspelho.keys.toList(growable: false);

const tiposPadraoDoEspelho = ['aprovacao', 'plano', 'entrega', 'decisao', 'sinal', 'bloqueada'];

class ConfigDoEspelho {
  const ConfigDoEspelho({
    this.ativo = false,
    this.projeto = 'Control Tower',
    this.tag = 'control-tower',
    this.tipos = tiposPadraoDoEspelho,
  });

  final bool ativo;
  final String projeto;
  final String tag;
  final List<String> tipos;

  factory ConfigDoEspelho.deJson(Object? bruto) {
    final j = bruto is Map ? bruto : const {};
    return ConfigDoEspelho(
      ativo: j['ativo'] == true,
      projeto: j['projeto'] as String? ?? '',
      tag: j['tag'] as String? ?? '',
      tipos: listaDeTextos(j['tipos']),
    );
  }

  ConfigDoEspelho copiar({bool? ativo, String? projeto, String? tag, List<String>? tipos}) => ConfigDoEspelho(
        ativo: ativo ?? this.ativo,
        projeto: projeto ?? this.projeto,
        tag: tag ?? this.tag,
        tipos: tipos ?? this.tipos,
      );

  ConfigDoEspelho comTipo(String tipo, bool marcado) =>
      copiar(tipos: _ordenados({...tipos.where((t) => t != tipo), if (marcado) tipo}));

  ConfigDoEspelho get normalizada =>
      ConfigDoEspelho(ativo: ativo, projeto: projeto.trim(), tag: tag.trim(), tipos: _ordenados(tipos));

  Map<String, Object?> paraJson() {
    final n = normalizada;
    return {'ativo': n.ativo, 'projeto': n.projeto, 'tag': n.tag, 'tipos': n.tipos};
  }

  bool mesmaQue(ConfigDoEspelho? outra) {
    if (outra == null) return false;
    final a = normalizada;
    final b = outra.normalizada;
    return a.ativo == b.ativo &&
        a.projeto == b.projeto &&
        a.tag == b.tag &&
        a.tipos.join(',') == b.tipos.join(',');
  }
}

List<String> _ordenados(Iterable<String> tipos) {
  final unicos = tipos.toSet();
  return [
    for (final t in tiposDoEspelho)
      if (unicos.contains(t)) t,
    for (final t in unicos)
      if (!rotulosDoEspelho.containsKey(t)) t,
  ];
}

class EstadoDoEspelho {
  const EstadoDoEspelho({
    this.conectado = false,
    this.ultimaVolta,
    this.erro,
    this.abertos = 0,
    this.pendentes = 0,
  });

  final bool conectado;
  final DateTime? ultimaVolta;
  final String? erro;
  final int abertos;
  final int pendentes;

  factory EstadoDoEspelho.deJson(Object? bruto) {
    final j = bruto is Map ? bruto : const {};
    final volta = j['ultimaVolta'];
    final erro = j['erro'];
    return EstadoDoEspelho(
      conectado: j['conectado'] == true,
      ultimaVolta: volta is String ? DateTime.tryParse(volta)?.toLocal() : null,
      erro: erro is String && erro.isNotEmpty ? erro : null,
      abertos: (j['abertos'] as num?)?.toInt() ?? 0,
      pendentes: (j['pendentes'] as num?)?.toInt() ?? 0,
    );
  }
}

List<String> errosDaConfigDoEspelho(ConfigDoEspelho c) {
  final estranhos = [for (final t in c.tipos) if (!rotulosDoEspelho.containsKey(t)) t];
  return [
    if (c.projeto.trim().isEmpty) 'o projeto do TickTask é obrigatório',
    if (c.tag.trim().isEmpty) 'a tag é obrigatória',
    for (final t in estranhos) 'tipo desconhecido ($t)',
  ];
}

String resumoDoEspelho(ConfigDoEspelho config, EstadoDoEspelho estado) {
  if (!config.ativo) return 'desligado';
  if (!estado.conectado) {
    if (estado.erro != null) return 'fora do ar: ${estado.erro}';
    return estado.ultimaVolta == null ? 'esperando a primeira volta' : 'fora do ar';
  }
  return [
    'conectado',
    '${estado.abertos} no TickTask',
    if (estado.pendentes > 0) '${estado.pendentes} esperando',
  ].join(' · ');
}

String ultimaVoltaDoEspelho(EstadoDoEspelho estado, {DateTime? agora}) {
  final volta = estado.ultimaVolta;
  if (volta == null) return 'nenhuma volta ainda';
  final dia = quando(volta, agora: agora);
  return dia == hora(volta) ? 'última volta às $dia' : 'última volta $dia, às ${hora(volta)}';
}
