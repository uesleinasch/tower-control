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
  'em_revisao': ['concluida', 'em_andamento', 'cancelada'],
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
      );
}

class RegistroDeTarefa {
  const RegistroDeTarefa({required this.comentario, required this.autor, required this.texto, required this.em});

  final bool comentario;
  final String autor;
  final String texto;
  final DateTime em;

  factory RegistroDeTarefa.deJson(Map<String, dynamic> j) => RegistroDeTarefa(
        comentario: j['tipo'] == 'comentario',
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
