import 'formato.dart';
import 'tarefas.dart' show listaDeTextos;

int _inteiro(Object? v) => v is num ? v.toInt() : 0;

String _texto(Object? v) => v is String ? v : '';

Map<String, Object?> _mapa(Object? v) => v is Map ? v.cast<String, Object?>() : const {};

String _plural(int n, String um, String varios) => '$n ${n == 1 ? um : varios}';

class ResumoDoModelo {
  const ResumoDoModelo({
    required this.tipo,
    required this.nome,
    this.exportadoEm,
    this.posicoes = 0,
    this.personas = 0,
    this.workflows = 0,
    this.rotinas = 0,
    this.skills = 0,
  });

  final String tipo;
  final String nome;
  final DateTime? exportadoEm;
  final int posicoes;
  final int personas;
  final int workflows;
  final int rotinas;
  final int skills;

  bool get deWorkflow => tipo == 'workflow';

  static ResumoDoModelo? deJson(Object? bruto) {
    if (bruto is! Map) return null;
    final j = bruto.cast<String, Object?>();
    final exportado = j['exportadoEm'];
    return ResumoDoModelo(
      tipo: _texto(j['tipo']),
      nome: _texto(j['nome']),
      exportadoEm: exportado is String ? DateTime.tryParse(exportado)?.toLocal() : null,
      posicoes: _inteiro(j['posicoes']),
      personas: _inteiro(j['personas']),
      workflows: _inteiro(j['workflows']),
      rotinas: _inteiro(j['rotinas']),
      skills: _inteiro(j['skills']),
    );
  }

  String get contagem => [
        _plural(posicoes, 'posição', 'posições'),
        if (!deWorkflow) ...[
          _plural(personas, 'persona', 'personas'),
          _plural(workflows, 'workflow', 'workflows'),
          _plural(rotinas, 'rotina', 'rotinas'),
          _plural(skills, 'skill', 'skills'),
        ],
      ].join(' · ');

  String exportado({DateTime? agora}) {
    final data = exportadoEm;
    if (data == null) return '';
    final dia = quando(data, agora: agora);
    return dia == hora(data) ? 'exportado hoje, às $dia' : 'exportado $dia, às ${hora(data)}';
  }
}

class PersonaDoModelo {
  const PersonaDoModelo({required this.id, required this.nome, required this.traz});

  final String id;
  final String nome;
  final bool traz;

  factory PersonaDoModelo.deJson(Map<String, dynamic> j) =>
      PersonaDoModelo(id: _texto(j['id']), nome: _texto(j['nome']), traz: j['traz'] == true);
}

class PosicaoDoModelo {
  const PosicaoDoModelo({required this.id, required this.titulo});

  final String id;
  final String titulo;

  factory PosicaoDoModelo.deJson(Map<String, dynamic> j) => PosicaoDoModelo(id: _texto(j['id']), titulo: _texto(j['titulo']));
}

enum OpcaoDePersona { daqui, outra, criar, criarComNome, vaga }

const rotulosDeOpcaoDePersona = <OpcaoDePersona, String>{
  OpcaoDePersona.daqui: 'Usar a daqui',
  OpcaoDePersona.outra: 'Usar outra persona',
  OpcaoDePersona.criar: 'Criar nova',
  OpcaoDePersona.criarComNome: 'Criar com outro nome',
  OpcaoDePersona.vaga: 'Deixar vaga',
};

class AcaoDePersona {
  const AcaoDePersona.usar(String this.persona)
      : acao = 'usar',
        nome = null;
  const AcaoDePersona.criar({this.nome})
      : acao = 'criar',
        persona = null;
  const AcaoDePersona.vaga()
      : acao = 'vaga',
        persona = null,
        nome = null;

  final String acao;
  final String? persona;
  final String? nome;

  static AcaoDePersona? deJson(Object? bruto) {
    final j = _mapa(bruto);
    return switch (j['acao']) {
      'usar' => AcaoDePersona.usar(_texto(j['persona'])),
      'criar' => AcaoDePersona.criar(nome: j['nome'] is String ? j['nome'] as String : null),
      'vaga' => const AcaoDePersona.vaga(),
      _ => null,
    };
  }

  Map<String, Object?> paraJson() => {
        'acao': acao,
        if (persona != null) 'persona': persona,
        if (nome != null) 'nome': nome,
      };

  OpcaoDePersona opcao(String idNoModelo) => switch (acao) {
        'usar' => persona == idNoModelo ? OpcaoDePersona.daqui : OpcaoDePersona.outra,
        'criar' => nome == null ? OpcaoDePersona.criar : OpcaoDePersona.criarComNome,
        _ => OpcaoDePersona.vaga,
      };
}

enum OpcaoDeSkill { daqui, importar }

const rotulosDeOpcaoDeSkill = <OpcaoDeSkill, String>{
  OpcaoDeSkill.daqui: 'Usar a daqui',
  OpcaoDeSkill.importar: 'Importar com outro id',
};

class AcaoDeSkill {
  const AcaoDeSkill.usar()
      : acao = 'usar',
        id = null;
  const AcaoDeSkill.importar(String this.id) : acao = 'importar';

  final String acao;
  final String? id;

  static AcaoDeSkill? deJson(Object? bruto) {
    final j = _mapa(bruto);
    return switch (j['acao']) {
      'usar' => const AcaoDeSkill.usar(),
      'importar' => AcaoDeSkill.importar(_texto(j['id'])),
      _ => null,
    };
  }

  Map<String, Object?> paraJson() => {'acao': acao, if (id != null) 'id': id};

  OpcaoDeSkill get opcao => acao == 'importar' ? OpcaoDeSkill.importar : OpcaoDeSkill.daqui;
}

class EscolhasDoModelo {
  const EscolhasDoModelo({
    this.equipeId,
    this.equipeNome,
    this.personas = const {},
    this.skills = const {},
    this.posicoes = const {},
    this.workflowId,
  });

  final String? equipeId;
  final String? equipeNome;
  final Map<String, AcaoDePersona> personas;
  final Map<String, AcaoDeSkill> skills;
  final Map<String, String?> posicoes;
  final String? workflowId;

  factory EscolhasDoModelo.deJson(Object? bruto) {
    final j = _mapa(bruto);
    final equipe = j['equipe'];
    final workflow = j['workflow'];
    return EscolhasDoModelo(
      equipeId: equipe is Map ? _texto(equipe['id']) : null,
      equipeNome: equipe is Map ? _texto(equipe['nome']) : null,
      personas: {
        for (final MapEntry(:key, :value) in _mapa(j['personas']).entries)
          key: ?AcaoDePersona.deJson(value),
      },
      skills: {
        for (final MapEntry(:key, :value) in _mapa(j['skills']).entries)
          key: ?AcaoDeSkill.deJson(value),
      },
      posicoes: {
        for (final MapEntry(:key, :value) in _mapa(j['posicoes']).entries) key: value is String && value.isNotEmpty ? value : null,
      },
      workflowId: workflow is Map ? _texto(workflow['id']) : null,
    );
  }

  bool get vazia =>
      equipeId == null && equipeNome == null && personas.isEmpty && skills.isEmpty && posicoes.isEmpty && workflowId == null;

  Map<String, Object?> paraJson() => {
        if (equipeId != null || equipeNome != null) 'equipe': {'id': equipeId ?? '', 'nome': equipeNome ?? ''},
        if (personas.isNotEmpty) 'personas': {for (final MapEntry(:key, :value) in personas.entries) key: value.paraJson()},
        if (skills.isNotEmpty) 'skills': {for (final MapEntry(:key, :value) in skills.entries) key: value.paraJson()},
        if (posicoes.isNotEmpty) 'posicoes': posicoes,
        if (workflowId != null) 'workflow': {'id': workflowId},
      };

  EscolhasDoModelo copiar({
    String? equipeId,
    String? equipeNome,
    Map<String, AcaoDePersona>? personas,
    Map<String, AcaoDeSkill>? skills,
    Map<String, String?>? posicoes,
    String? workflowId,
  }) =>
      EscolhasDoModelo(
        equipeId: equipeId ?? this.equipeId,
        equipeNome: equipeNome ?? this.equipeNome,
        personas: personas ?? this.personas,
        skills: skills ?? this.skills,
        posicoes: posicoes ?? this.posicoes,
        workflowId: workflowId ?? this.workflowId,
      );

  EscolhasDoModelo completadaCom(EscolhasDoModelo doServidor) => EscolhasDoModelo(
        equipeId: equipeId ?? doServidor.equipeId,
        equipeNome: equipeNome ?? doServidor.equipeNome,
        personas: {...doServidor.personas, ...personas},
        skills: {...doServidor.skills, ...skills},
        posicoes: {...doServidor.posicoes, ...posicoes},
        workflowId: workflowId ?? doServidor.workflowId,
      );

  EscolhasDoModelo comEquipe({String? id, String? nome}) => copiar(equipeId: id, equipeNome: nome);

  EscolhasDoModelo comWorkflow(String id) => copiar(workflowId: id);

  EscolhasDoModelo comOpcaoDePersona(
    String id,
    OpcaoDePersona opcao, {
    required String nomeNoModelo,
    required List<String> personasDaqui,
  }) {
    final atual = personas[id];
    final AcaoDePersona nova = switch (opcao) {
      OpcaoDePersona.daqui => AcaoDePersona.usar(id),
      OpcaoDePersona.outra => atual != null && atual.opcao(id) == OpcaoDePersona.outra
          ? atual
          : AcaoDePersona.usar(personasDaqui.where((p) => p != id).firstOrNull ?? id),
      OpcaoDePersona.criar => const AcaoDePersona.criar(),
      OpcaoDePersona.criarComNome => AcaoDePersona.criar(nome: atual?.nome ?? nomeNoModelo),
      OpcaoDePersona.vaga => const AcaoDePersona.vaga(),
    };
    return copiar(personas: {...personas, id: nova});
  }

  EscolhasDoModelo comPersonaDaqui(String id, String persona) =>
      copiar(personas: {...personas, id: AcaoDePersona.usar(persona)});

  EscolhasDoModelo comNomeDePersona(String id, String nome) =>
      copiar(personas: {...personas, id: AcaoDePersona.criar(nome: nome)});

  EscolhasDoModelo comOpcaoDeSkill(String id, OpcaoDeSkill opcao) {
    final atual = skills[id];
    final nova = switch (opcao) {
      OpcaoDeSkill.daqui => const AcaoDeSkill.usar(),
      OpcaoDeSkill.importar => atual?.opcao == OpcaoDeSkill.importar ? atual! : AcaoDeSkill.importar('$id-2'),
    };
    return copiar(skills: {...skills, id: nova});
  }

  EscolhasDoModelo comIdDeSkill(String id, String novo) => copiar(skills: {...skills, id: AcaoDeSkill.importar(novo)});

  EscolhasDoModelo comPosicao(String idNoModelo, String? alvo) =>
      copiar(posicoes: {...posicoes, idNoModelo: alvo == null || alvo.isEmpty ? null : alvo});
}

class PreviaDoModelo {
  const PreviaDoModelo({
    this.resumo,
    this.personas = const [],
    this.posicoes = const [],
    this.entra = const [],
    this.escolhas = const EscolhasDoModelo(),
    this.avisos = const [],
    this.erros = const [],
  });

  final ResumoDoModelo? resumo;
  final List<PersonaDoModelo> personas;
  final List<PosicaoDoModelo> posicoes;
  final List<String> entra;
  final EscolhasDoModelo escolhas;
  final List<String> avisos;
  final List<String> erros;

  factory PreviaDoModelo.deJson(Map<String, dynamic> j) => PreviaDoModelo(
        resumo: ResumoDoModelo.deJson(j['resumo']),
        personas: [
          for (final p in j['personasDoModelo'] is List ? j['personasDoModelo'] as List : const [])
            if (p is Map<String, dynamic>) PersonaDoModelo.deJson(p),
        ],
        posicoes: [
          for (final p in j['posicoesDoModelo'] is List ? j['posicoesDoModelo'] as List : const [])
            if (p is Map<String, dynamic>) PosicaoDoModelo.deJson(p),
        ],
        entra: listaDeTextos(j['entra']),
        escolhas: EscolhasDoModelo.deJson(j['escolhas']),
        avisos: listaDeTextos(j['avisos']),
        erros: listaDeTextos(j['erros']),
      );

  bool get valida => resumo != null;

  bool get deWorkflow => resumo?.deWorkflow ?? false;

  bool get podeImportar => valida && erros.isEmpty;

  List<String> get skillsEmColisao => escolhas.skills.keys.toList()..sort();

  List<String> get prefixosDosCampos => [
        if (resumo != null && !deWorkflow) prefixoDaEquipe,
        if (deWorkflow) prefixoDoWorkflow,
        for (final p in personas) ...prefixosDaPersona(p),
        for (final id in skillsEmColisao) prefixoDaSkill(id),
        if (deWorkflow)
          for (final p in posicoes) prefixoDaPosicao(p),
      ];

  List<String> get errosSoltos {
    final prefixos = prefixosDosCampos;
    return [for (final e in erros) if (_resto(e, prefixos) == null) e];
  }
}

const prefixoDaEquipe = 'equipe: ';
const prefixoDoWorkflow = 'workflow: ';

List<String> prefixosDaPersona(PersonaDoModelo p) => {'persona ${p.nome}: ', 'persona ${p.id}: '}.toList();

String prefixoDaSkill(String id) => 'skill $id: ';

String prefixoDaPosicao(PosicaoDoModelo p) => 'posição ${p.titulo}: ';

String? _resto(String erro, Iterable<String> prefixos) {
  for (final p in prefixos) {
    if (erro.startsWith(p)) return erro.substring(p.length);
  }
  return null;
}

List<String> errosDoCampo(List<String> erros, Iterable<String> prefixos) => [for (final e in erros) ?_resto(e, prefixos)];

final _idDoModelo = RegExp(r'^[a-z][a-z0-9-]*$');

String? erroDeId(String id, {int maximo = 48}) {
  if (id.isEmpty) return 'o id é obrigatório';
  if (!_idDoModelo.hasMatch(id)) return 'id inválido: use letras minúsculas, números e hífen, começando por letra';
  if (id.length > maximo) return 'id longo demais: no máximo $maximo caracteres';
  return null;
}
