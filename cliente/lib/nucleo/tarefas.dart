const nomesDeStatus = {
  'backlog': 'backlog',
  'a_fazer': 'a fazer',
  'em_andamento': 'em andamento',
  'em_revisao': 'em revisão',
  'bloqueada': 'bloqueada',
  'concluida': 'concluída',
  'cancelada': 'cancelada',
};

// Espelho de TRANSICOES em app/src/orquestra/tarefa.ts: só decide quais botões aparecem;
// quem valida a mudança é o servidor.
const transicoesDeTarefa = {
  'backlog': ['a_fazer', 'cancelada'],
  'a_fazer': ['em_andamento', 'backlog', 'bloqueada', 'cancelada'],
  'em_andamento': ['em_revisao', 'concluida', 'bloqueada', 'a_fazer', 'cancelada'],
  'em_revisao': ['concluida', 'em_andamento', 'a_fazer', 'cancelada'],
  'bloqueada': ['a_fazer', 'cancelada'],
  'concluida': ['a_fazer'],
  'cancelada': ['backlog'],
};

const ordemDeStatus = ['em_andamento', 'em_revisao', 'a_fazer', 'bloqueada', 'backlog', 'concluida', 'cancelada'];

class PosicaoResumo {
  const PosicaoResumo({required this.id, required this.titulo, this.persona, this.personaNome});

  final String id;
  final String titulo;
  final String? persona;
  final String? personaNome;

  String get rotulo => personaNome != null ? '$personaNome · $titulo' : '$titulo (vaga)';

  factory PosicaoResumo.deJson(Map<String, dynamic> j) => PosicaoResumo(
        id: j['id'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        persona: j['persona'] as String?,
        personaNome: j['personaNome'] as String?,
      );
}

class EquipeResumo {
  const EquipeResumo({required this.id, required this.nome, required this.posicoes});

  final String id;
  final String nome;
  final List<PosicaoResumo> posicoes;

  factory EquipeResumo.deJson(Map<String, dynamic> j) => EquipeResumo(
        id: j['id'] as String? ?? '',
        nome: j['nome'] as String? ?? '',
        posicoes: [
          for (final p in (j['posicoes'] as List? ?? const []).whereType<Map<String, dynamic>>()) PosicaoResumo.deJson(p),
        ],
      );
}

class Tarefa {
  const Tarefa({
    required this.id,
    required this.equipe,
    required this.posicao,
    required this.titulo,
    this.descricao = '',
    this.porque = '',
    this.pai,
    required this.status,
    this.dono,
    required this.atualizadaEm,
    this.dependeDe = const [],
    this.rodando = false,
  });

  final int id;
  final String equipe;
  final String posicao;
  final String titulo;
  final String descricao;
  final String porque;
  final int? pai;
  final String status;
  final String? dono;
  final DateTime atualizadaEm;
  final List<int> dependeDe;
  final bool rodando;

  List<String> get proximosStatus => transicoesDeTarefa[status] ?? const [];

  factory Tarefa.deJson(Map<String, dynamic> j) => Tarefa(
        id: (j['id'] as num?)?.toInt() ?? 0,
        equipe: j['equipe'] as String? ?? '',
        posicao: j['posicao'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        descricao: j['descricao'] as String? ?? '',
        porque: j['porque'] as String? ?? '',
        pai: (j['pai'] as num?)?.toInt(),
        status: j['status'] as String? ?? 'a_fazer',
        dono: j['dono'] as String?,
        atualizadaEm: DateTime.tryParse(j['atualizadaEm'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        dependeDe: [for (final d in (j['dependeDe'] as List? ?? const [])) (d as num).toInt()],
        rodando: j['rodando'] == true,
      );
}

class RegistroDeTarefa {
  const RegistroDeTarefa({required this.tipo, required this.autor, required this.texto, required this.em});

  final String tipo;
  final String autor;
  final String texto;
  final DateTime em;

  bool get comentario => tipo == 'comentario';
  bool get destacado => tipo == 'entrega' || tipo == 'ajuda';

  factory RegistroDeTarefa.deJson(Map<String, dynamic> j) => RegistroDeTarefa(
        tipo: j['tipo'] as String? ?? 'status',
        autor: j['autor'] as String? ?? '',
        texto: j['texto'] as String? ?? '',
        em: DateTime.tryParse(j['em'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

List<({String status, List<Tarefa> tarefas})> agruparPorStatus(List<Tarefa> tarefas) => [
      for (final status in ordemDeStatus)
        if (tarefas.any((t) => t.status == status))
          (status: status, tarefas: tarefas.where((t) => t.status == status).toList()),
    ];

List<Tarefa> comTarefa(List<Tarefa> lista, Tarefa tarefa) {
  final i = lista.indexWhere((t) => t.id == tarefa.id);
  if (i < 0) return [tarefa, ...lista];
  return [...lista]..[i] = tarefa;
}

const nomesDeExecucao = {
  'na_fila': 'na fila',
  'rodando': 'rodando',
  'concluida': 'concluída',
  'falhou': 'falhou',
  'interrompida': 'interrompida',
};

const nomesDeGatilho = {
  'atribuicao': 'atribuição',
  'comentario': 'comentário',
  'dependencia': 'dependência',
  'retomada': 'retomada',
  'nova_tentativa': 'nova tentativa',
};

DateTime? _data(Object? bruto) => bruto is String ? DateTime.tryParse(bruto) : null;

class Execucao {
  const Execucao({
    required this.id,
    required this.tarefa,
    this.persona,
    required this.gatilho,
    required this.status,
    this.modelo,
    this.inicio,
    this.fim,
    this.erro,
    this.custoUSD,
  });

  final int id;
  final int tarefa;
  final String? persona;
  final String gatilho;
  final String status;
  final String? modelo;
  final DateTime? inicio;
  final DateTime? fim;
  final String? erro;
  final double? custoUSD;

  bool get comecou => inicio != null;

  Duration? duracao(DateTime agora) => inicio == null ? null : (fim ?? agora).difference(inicio!);

  factory Execucao.deJson(Map<String, dynamic> j) => Execucao(
        id: (j['id'] as num?)?.toInt() ?? 0,
        tarefa: (j['tarefa'] as num?)?.toInt() ?? 0,
        persona: j['persona'] as String?,
        gatilho: j['gatilho'] as String? ?? '',
        status: j['status'] as String? ?? 'na_fila',
        modelo: j['modelo'] as String?,
        inicio: _data(j['inicio']),
        fim: _data(j['fim']),
        erro: j['erro'] as String?,
        custoUSD: (j['custoUSD'] as num?)?.toDouble(),
      );
}

class EventoDeExecucao {
  const EventoDeExecucao({required this.id, required this.tipo, required this.conteudo, required this.em});

  final int id;
  final String tipo;
  final String conteudo;
  final DateTime em;

  factory EventoDeExecucao.deJson(Map<String, dynamic> j) => EventoDeExecucao(
        id: (j['id'] as num?)?.toInt() ?? 0,
        tipo: j['tipo'] as String? ?? 'texto',
        conteudo: j['conteudo'] as String? ?? '',
        em: _data(j['em']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

List<Execucao> comExecucao(List<Execucao> lista, Execucao execucao) {
  final i = lista.indexWhere((e) => e.id == execucao.id);
  if (i < 0) return [...lista, execucao];
  return [...lista]..[i] = execucao;
}

Execucao? ultimaIniciada(List<Execucao> lista) => lista.where((e) => e.comecou).lastOrNull;

String dinheiro(double? usd) {
  if (usd == null || usd == 0) return r'US$ 0';
  return 'US\$ ${usd.toStringAsFixed(usd < 0.1 ? 3 : 2)}';
}

String duracaoCurta(Duration d) {
  final s = d.inSeconds;
  return s < 60 ? '${s}s' : '${s ~/ 60}min ${s % 60}s';
}
