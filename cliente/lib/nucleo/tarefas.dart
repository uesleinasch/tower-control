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
  const PosicaoResumo({
    required this.id,
    required this.titulo,
    this.persona,
    this.personaNome,
    this.respondeA,
    this.capacidades = const [],
    this.aprovacao = 'sempre',
    this.diretorio,
    this.aprovarPlano = false,
    this.delegaDireto = false,
  });

  final String id;
  final String titulo;
  final String? persona;
  final String? personaNome;
  final String? respondeA;
  final List<String> capacidades;
  final String aprovacao;
  final String? diretorio;
  final bool aprovarPlano;
  final bool delegaDireto;

  String get rotulo => personaNome != null ? '$personaNome · $titulo' : '$titulo (vaga)';

  PosicaoResumo copiar({
    String? titulo,
    String? Function()? persona,
    String? Function()? respondeA,
    List<String>? capacidades,
    String? aprovacao,
    String? Function()? diretorio,
    bool? aprovarPlano,
    bool? delegaDireto,
  }) =>
      PosicaoResumo(
        id: id,
        titulo: titulo ?? this.titulo,
        persona: persona != null ? persona() : this.persona,
        personaNome: persona != null ? null : personaNome,
        respondeA: respondeA != null ? respondeA() : this.respondeA,
        capacidades: capacidades ?? this.capacidades,
        aprovacao: aprovacao ?? this.aprovacao,
        diretorio: diretorio != null ? diretorio() : this.diretorio,
        aprovarPlano: aprovarPlano ?? this.aprovarPlano,
        delegaDireto: delegaDireto ?? this.delegaDireto,
      );

  Map<String, Object?> paraJson() => {
        'id': id,
        'titulo': titulo,
        'persona': persona,
        'respondeA': respondeA,
        'capacidades': capacidades,
        'aprovacao': aprovacao,
        if (diretorio != null && diretorio!.trim().isNotEmpty) 'diretorio': diretorio!.trim(),
        if (aprovarPlano) 'aprovarPlano': true,
        if (delegaDireto) 'delegaDireto': true,
      };

  factory PosicaoResumo.deJson(Map<String, dynamic> j) => PosicaoResumo(
        id: j['id'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        persona: j['persona'] as String?,
        personaNome: j['personaNome'] as String?,
        respondeA: j['respondeA'] as String?,
        capacidades: [for (final c in (j['capacidades'] as List? ?? const [])) c as String],
        aprovacao: j['aprovacao'] as String? ?? 'sempre',
        diretorio: j['diretorio'] as String?,
        aprovarPlano: j['aprovarPlano'] == true,
        delegaDireto: j['delegaDireto'] == true,
      );
}

typedef Ponto = ({double x, double y});

class EquipeResumo {
  const EquipeResumo({required this.id, required this.nome, required this.posicoes, this.layout = const {}});

  final String id;
  final String nome;
  final List<PosicaoResumo> posicoes;
  final Map<String, Ponto> layout;

  PosicaoResumo? posicao(String id) => posicoes.where((p) => p.id == id).firstOrNull;

  Ponto ponto(String id) => layout[id] ?? (x: 0, y: 0);

  EquipeResumo copiar({String? nome, List<PosicaoResumo>? posicoes, Map<String, Ponto>? layout}) => EquipeResumo(
        id: id,
        nome: nome ?? this.nome,
        posicoes: posicoes ?? this.posicoes,
        layout: layout ?? this.layout,
      );

  Map<String, Object?> paraJson() => {
        'id': id,
        'nome': nome,
        'posicoes': [for (final p in posicoes) p.paraJson()],
        'layout': {
          for (final MapEntry(:key, :value) in layout.entries)
            if (posicao(key) != null) key: {'x': value.x, 'y': value.y},
        },
      };

  factory EquipeResumo.deJson(Map<String, dynamic> j) => EquipeResumo(
        id: j['id'] as String? ?? '',
        nome: j['nome'] as String? ?? '',
        posicoes: [
          for (final p in (j['posicoes'] as List? ?? const []).whereType<Map<String, dynamic>>()) PosicaoResumo.deJson(p),
        ],
        layout: {
          for (final MapEntry(:key, :value) in ((j['layout'] as Map?) ?? const {}).entries)
            if (value is Map && value['x'] is num && value['y'] is num)
              key as String: (x: (value['x'] as num).toDouble(), y: (value['y'] as num).toDouble()),
        },
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
  bool get destacado => tipo == 'entrega' || tipo == 'ajuda' || tipo == 'plano';

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
  'plano_aprovado': 'plano aprovado',
};

const nomesDePausa = {'ueslei': 'pausada', 'tudo': 'tudo pausado', 'orcamento': 'orçamento estourado'};

bool planoPendente(List<RegistroDeTarefa> registros) {
  final plano = registros.lastIndexWhere((r) => r.tipo == 'plano');
  return plano >= 0 && registros.lastIndexWhere((r) => r.tipo == 'plano-aprovado') < plano;
}

class LinhaDeAuditoria {
  const LinhaDeAuditoria({required this.em, required this.quem, required this.acao, required this.alvo, this.detalhe = ''});

  final DateTime em;
  final String quem;
  final String acao;
  final String alvo;
  final String detalhe;

  factory LinhaDeAuditoria.deJson(Map<String, dynamic> j) => LinhaDeAuditoria(
        em: DateTime.tryParse(j['em'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        quem: j['quem'] as String? ?? '',
        acao: j['acao'] as String? ?? '',
        alvo: j['alvo'] as String? ?? '',
        detalhe: j['detalhe'] as String? ?? '',
      );
}

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
