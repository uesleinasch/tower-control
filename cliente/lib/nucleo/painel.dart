import 'modelos.dart';
import 'protocolo.dart';
import 'tarefas.dart';

String _texto(Object? v) => v is String ? v : '';
String? _textoOuNulo(Object? v) => v is String ? v : null;
int _inteiro(Object? v) => v is num ? v.toInt() : 0;
int? _inteiroOuNulo(Object? v) => v is num ? v.toInt() : null;
double _numero(Object? v) => v is num ? v.toDouble() : 0;
double? _numeroOuNulo(Object? v) => v is num ? v.toDouble() : null;
DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v) : null;
Map<String, dynamic> _mapa(Object? v) => v is Map<String, dynamic> ? v : const {};
List<T> _lista<T>(Object? v, T Function(Map<String, dynamic>) deJson) => [
  for (final e in (v is List ? v : const []).whereType<Map<String, dynamic>>()) deJson(e),
];

class ItemDeAtencao {
  const ItemDeAtencao({
    required this.tipo,
    this.titulo = '',
    this.detalhe = '',
    this.desde,
    this.acoes = const [],
    this.tarefaId,
    this.permissaoId,
    this.conversaId,
    this.persona,
    this.equipe,
    this.rotina,
    this.fluxo,
    this.ficha,
    this.opcoes = const [],
  });

  final String tipo;
  final String titulo;
  final String detalhe;
  final DateTime? desde;
  final List<String> acoes;
  final int? tarefaId;
  final String? permissaoId;
  final String? conversaId;
  final String? persona;
  final String? equipe;
  final String? rotina;
  final int? fluxo;
  final int? ficha;
  final List<String> opcoes;

  factory ItemDeAtencao.deJson(Map<String, dynamic> j) => ItemDeAtencao(
    tipo: _texto(j['tipo']),
    titulo: _texto(j['titulo']),
    detalhe: _texto(j['detalhe']),
    desde: _data(j['desde']),
    acoes: [
      for (final a in (j['acoes'] is List ? j['acoes'] as List : const []))
        if (a is String) a,
    ],
    tarefaId: _inteiroOuNulo(j['tarefaId']),
    permissaoId: _textoOuNulo(j['permissaoId']),
    conversaId: _textoOuNulo(j['conversaId']),
    persona: _textoOuNulo(j['persona']),
    equipe: _textoOuNulo(j['equipe']),
    rotina: _textoOuNulo(j['rotina']),
    fluxo: _inteiroOuNulo(j['fluxo']),
    ficha: _inteiroOuNulo(j['ficha']),
    opcoes: [
      for (final o in (j['opcoes'] is List ? j['opcoes'] as List : const []))
        if (o is String) o,
    ],
  );
}

typedef CaixaAtiva = ({int ficha, String no, String titulo, String tipo, int? tarefaId});

class FluxoNoPainel {
  const FluxoNoPainel({
    required this.fluxo,
    this.equipe = '',
    this.workflow = '',
    this.nome = '',
    this.desde,
    this.ativas = const [],
  });

  final int fluxo;
  final String equipe;
  final String workflow;
  final String nome;
  final DateTime? desde;
  final List<CaixaAtiva> ativas;

  factory FluxoNoPainel.deJson(Map<String, dynamic> j) {
    final workflow = _texto(j['workflow']);
    return FluxoNoPainel(
      fluxo: _inteiro(j['fluxo']),
      equipe: _texto(j['equipe']),
      workflow: workflow,
      nome: _textoOuNulo(j['nome']) ?? workflow,
      desde: _data(j['desde']),
      ativas: _lista(
        j['ativas'],
        (a) => (
          ficha: _inteiro(a['ficha']),
          no: _texto(a['no']),
          titulo: _textoOuNulo(a['titulo']) ?? _texto(a['no']),
          tipo: _texto(a['tipo']),
          tarefaId: _inteiroOuNulo(a['tarefaId']),
        ),
      ),
    );
  }
}

typedef UltimoEvento = ({String tipo, String conteudo, DateTime? em});

class ExecucaoViva {
  const ExecucaoViva({
    required this.execucao,
    required this.tarefaId,
    this.titulo = '',
    this.equipe = '',
    this.persona,
    this.papel = 'executa',
    this.inicio,
    this.ultimoEvento,
  });

  final int execucao;
  final int tarefaId;
  final String titulo;
  final String equipe;
  final String? persona;
  final String papel;
  final DateTime? inicio;
  final UltimoEvento? ultimoEvento;

  factory ExecucaoViva.deJson(Map<String, dynamic> j) {
    final evento = j['ultimoEvento'];
    return ExecucaoViva(
      execucao: _inteiro(j['execucao']),
      tarefaId: _inteiro(j['tarefaId']),
      titulo: _texto(j['titulo']),
      equipe: _texto(j['equipe']),
      persona: _textoOuNulo(j['persona']),
      papel: _textoOuNulo(j['papel']) ?? 'executa',
      inicio: _data(j['inicio']),
      ultimoEvento: evento is Map<String, dynamic>
          ? (tipo: _texto(evento['tipo']), conteudo: _texto(evento['conteudo']), em: _data(evento['em']))
          : null,
    );
  }
}

class Espera {
  const Espera({
    required this.execucao,
    required this.tarefaId,
    this.titulo = '',
    this.persona,
    this.motivo = '',
    this.desde,
  });

  final int execucao;
  final int tarefaId;
  final String titulo;
  final String? persona;
  final String motivo;
  final DateTime? desde;

  factory Espera.deJson(Map<String, dynamic> j) => Espera(
    execucao: _inteiro(j['execucao']),
    tarefaId: _inteiro(j['tarefaId']),
    titulo: _texto(j['titulo']),
    persona: _textoOuNulo(j['persona']),
    motivo: _texto(j['motivo']),
    desde: _data(j['desde']),
  );
}

class CartaoDePersona {
  const CartaoDePersona({
    required this.id,
    required this.nome,
    this.cor = 0xFF8B93A7,
    this.estado = 'ocioso',
    this.tarefaId,
    this.gastoMesUSD = 0,
    this.limiteUSD,
    this.tokensMes = 0,
    this.limiteTokens,
    this.abertas = 0,
  });

  final String id;
  final String nome;
  final int cor;
  final String estado;
  final int? tarefaId;
  final double gastoMesUSD;
  final double? limiteUSD;
  final int tokensMes;
  final int? limiteTokens;
  final int abertas;

  String get inicial => nome.isEmpty ? '?' : nome[0].toUpperCase();

  double? get proporcaoDoLimite => proporcaoDoOrcamentoMensal(
    gastoUSD: gastoMesUSD,
    limiteUSD: limiteUSD,
    tokens: tokensMes,
    limiteTokens: limiteTokens,
  );

  factory CartaoDePersona.deJson(Map<String, dynamic> j) {
    final id = _texto(j['id']);
    return CartaoDePersona(
      id: id,
      nome: _textoOuNulo(j['nome']) ?? id,
      cor: corDeHex(_textoOuNulo(j['cor'])),
      estado: _textoOuNulo(j['estado']) ?? 'ocioso',
      tarefaId: _inteiroOuNulo(j['tarefaId']),
      gastoMesUSD: _numero(j['gastoMesUSD']),
      limiteUSD: _numeroOuNulo(j['limiteUSD']),
      tokensMes: _inteiro(j['tokensMes']),
      limiteTokens: _inteiroOuNulo(j['limiteTokens']),
      abertas: _inteiro(j['abertas']),
    );
  }
}

class GastoDoMes {
  const GastoDoMes({
    this.mes = '',
    this.tarefasUSD = 0,
    this.totalUSD = 0,
    this.tokensTarefas = 0,
    this.tokensTotal = 0,
  });

  final String mes;
  final double tarefasUSD;
  final double totalUSD;
  final int tokensTarefas;
  final int tokensTotal;

  factory GastoDoMes.deJson(Map<String, dynamic> j) => GastoDoMes(
    mes: _texto(j['mes']),
    tarefasUSD: _numero(j['tarefasUSD']),
    totalUSD: _numero(j['totalUSD']),
    tokensTarefas: _inteiro(j['tokensTarefas']),
    tokensTotal: _inteiro(j['tokensTotal']),
  );
}

typedef ProximaRotina = ({String equipe, String id, String nome, DateTime? proximo});

class ItemDeAtividade {
  const ItemDeAtividade({this.em, required this.tipo, this.quem = '', this.texto = '', this.tarefaId, this.equipe});

  final DateTime? em;
  final String tipo;
  final String quem;
  final String texto;
  final int? tarefaId;
  final String? equipe;

  factory ItemDeAtividade.deJson(Map<String, dynamic> j) => ItemDeAtividade(
    em: _data(j['em']),
    tipo: _texto(j['tipo']),
    quem: _texto(j['quem']),
    texto: _texto(j['texto']),
    tarefaId: _inteiroOuNulo(j['tarefaId']),
    equipe: _textoOuNulo(j['equipe']),
  );
}

class Retrato {
  const Retrato({
    this.em,
    this.pausadoTudo = false,
    this.atencao = const [],
    this.rodando = const [],
    this.naFila = const [],
    this.personas = const [],
    this.tarefas = const {},
    this.gasto = const GastoDoMes(),
    this.proximasRotinas = const [],
    this.atividade = const [],
    this.workflows = const [],
  });

  final DateTime? em;
  final bool pausadoTudo;
  final List<ItemDeAtencao> atencao;
  final List<ExecucaoViva> rodando;
  final List<Espera> naFila;
  final List<CartaoDePersona> personas;
  final Map<String, Map<String, int>> tarefas;
  final GastoDoMes gasto;
  final List<ProximaRotina> proximasRotinas;
  final List<ItemDeAtividade> atividade;
  final List<FluxoNoPainel> workflows;

  CartaoDePersona? persona(String id) => personas.where((p) => p.id == id).firstOrNull;

  factory Retrato.deJson(Map<String, dynamic> j) {
    final agora = _mapa(j['agora']);
    return Retrato(
      em: _data(j['em']),
      pausadoTudo: j['pausadoTudo'] == true,
      atencao: _lista(j['atencao'], ItemDeAtencao.deJson),
      rodando: _lista(agora['rodando'], ExecucaoViva.deJson),
      naFila: _lista(agora['naFila'], Espera.deJson),
      personas: _lista(j['personas'], CartaoDePersona.deJson),
      tarefas: {
        for (final MapEntry(:key, :value) in _mapa(j['tarefas']).entries)
          key: {
            for (final MapEntry(key: status, value: n) in _mapa(value).entries)
              if (n is num) status: n.toInt(),
          },
      },
      gasto: GastoDoMes.deJson(_mapa(j['gasto'])),
      proximasRotinas: _lista(
        j['proximasRotinas'],
        (r) =>
            (equipe: _texto(r['equipe']), id: _texto(r['id']), nome: _texto(r['nome']), proximo: _data(r['proximo'])),
      ),
      atividade: _lista(j['atividade'], ItemDeAtividade.deJson),
      workflows: _lista(j['workflows'], FluxoNoPainel.deJson),
    );
  }
}

const rotulosDeAtencao = {
  'comando': 'comando',
  'aprovacao': 'aprovação',
  'decisao': 'decisão',
  'plano': 'plano',
  'entrega': 'entrega',
  'sinal': 'sinal',
  'bloqueada': 'bloqueada',
  'atrasada': 'atrasada',
  'backlog': 'backlog',
  'orcamento': 'orçamento',
  'rotina': 'rotina',
  'vaga': 'posição vaga',
};

const rotulosDeAcao = {
  'aprovar': 'Aprovar',
  'negar': 'Negar',
  'pedir-mudanca': 'Pedir mudança',
  'aprovar-plano': 'Aprovar plano',
  'concluir': 'Concluir',
  'liberar': 'Liberar',
  'abrir': 'Abrir',
  'decidir': 'Decidir',
  'sinalizar': 'Sinalizar',
};

const rotulosDeEstado = {
  'rodando': 'rodando',
  'na_fila': 'na fila',
  'ocioso': 'livre',
  'pausada': 'pausada',
  'sem_orcamento': 'sem orçamento',
};

const rotulosDePapel = {'executa': 'executa', 'revisa': 'revisa', 'board': 'board'};

const rotulosDeAtividade = {
  'entrega': 'entrega',
  'plano': 'plano',
  'ajuda': 'pedido de ajuda',
  'decisao': 'decisão',
  'comentario': 'comentário',
  'auditoria': 'auditoria',
  'disparo': 'disparo de rotina',
};

sealed class EfeitoDaAcao {
  const EfeitoDaAcao();
}

class MandarSaida extends EfeitoDaAcao {
  const MandarSaida(this.saida);
  final Saida saida;
}

class IrParaTarefa extends EfeitoDaAcao {
  const IrParaTarefa(this.id);
  final int id;
}

class IrParaEquipe extends EfeitoDaAcao {
  const IrParaEquipe(this.equipe);
  final String? equipe;
}

class IrParaFluxo extends EfeitoDaAcao {
  const IrParaFluxo(this.fluxo, this.equipe);
  final int fluxo;
  final String? equipe;
}

class IrParaRotinas extends EfeitoDaAcao {
  const IrParaRotinas(this.equipe);
  final String? equipe;
}

EfeitoDaAcao? efeitoDaAcao(ItemDeAtencao item, String acao, {String? texto, String? opcao}) {
  final tarefa = item.tarefaId;
  final permissao = item.permissaoId;
  final fluxo = item.fluxo;
  final ficha = item.ficha;
  final comentario = texto?.trim() ?? '';
  return switch (acao) {
    'decidir' when fluxo != null && ficha != null && opcao != null && item.opcoes.contains(opcao) => MandarSaida(
      DecidirWorkflow(fluxo, ficha, opcao, comentario: comentario.isEmpty ? null : comentario),
    ),
    'sinalizar' when fluxo != null && ficha != null => MandarSaida(SinalizarWorkflow(fluxo, ficha)),
    'aprovar' when item.tipo == 'comando' && permissao != null => MandarSaida(
      RespostaDePermissao(permissao, permitido: true),
    ),
    'negar' when item.tipo == 'comando' && permissao != null => MandarSaida(
      RespostaDePermissao(permissao, permitido: false),
    ),
    'aprovar' when item.tipo == 'aprovacao' && tarefa != null => MandarSaida(DecidirTarefa.aprovar(tarefa)),
    'pedir-mudanca' when tarefa != null && (texto ?? '').trim().isNotEmpty => MandarSaida(
      DecidirTarefa.mudanca(tarefa, texto!.trim()),
    ),
    'aprovar-plano' when tarefa != null => MandarSaida(AprovarPlano(tarefa)),
    'concluir' when tarefa != null => MandarSaida(MudarStatusTarefa(tarefa, 'concluida')),
    'liberar' when tarefa != null => MandarSaida(MudarStatusTarefa(tarefa, 'a_fazer')),
    'abrir' when item.tipo == 'rotina' => IrParaRotinas(item.equipe),
    'abrir' when tarefa != null => IrParaTarefa(tarefa),
    'abrir' when fluxo != null => IrParaFluxo(fluxo, item.equipe),
    'abrir' when item.tipo == 'orcamento' || item.tipo == 'vaga' => IrParaEquipe(item.equipe),
    _ => null,
  };
}

List<ItemDeAtividade> filtrarAtividade(List<ItemDeAtividade> lista, {String? quem, String? tipo}) => [
  for (final a in lista)
    if ((quem == null || a.quem == quem) && (tipo == null || a.tipo == tipo)) a,
];

List<String> quemNaAtividade(List<ItemDeAtividade> lista) =>
    [for (final a in lista) a.quem].where((q) => q.isNotEmpty).toSet().toList();

List<String> tiposNaAtividade(List<ItemDeAtividade> lista) {
  final presentes = {for (final a in lista) a.tipo};
  return [
    for (final t in rotulosDeAtividade.keys)
      if (presentes.contains(t)) t,
    for (final t in presentes)
      if (t.isNotEmpty && !rotulosDeAtividade.containsKey(t)) t,
  ];
}

String nomeDeQuem(String quem, Retrato retrato) {
  if (quem == 'ueslei') return 'Ueslei';
  return retrato.persona(quem)?.nome ?? quem;
}

String equipeDasTarefas(Retrato retrato, String? preferida) {
  if (preferida != null && retrato.tarefas.containsKey(preferida)) return preferida;
  if (retrato.tarefas.containsKey('casa')) return 'casa';
  return retrato.tarefas.keys.firstOrNull ?? preferida ?? 'casa';
}

List<({String status, int quantas})> contagemPorStatus(Map<String, int> porStatus) => [
  for (final s in ordemDeStatus)
    if ((porStatus[s] ?? 0) > 0) (status: s, quantas: porStatus[s]!),
];

String haQuanto(DateTime? desde, DateTime agora) {
  if (desde == null) return '';
  final d = agora.difference(desde);
  if (d.inMinutes < 1) return 'agora';
  if (d.inHours < 1) return 'há ${d.inMinutes} min';
  if (d.inDays < 1) return 'há ${d.inHours} h';
  return 'há ${d.inDays} d';
}
