import 'modelos.dart';
import 'organograma.dart';
import 'tarefas.dart';

const donoCasa = 'casa';
const limiteDaDescricao = 1024;
const limiteDoCorpo = 100000;

final _padraoDeId = RegExp(r'^[a-z][a-z0-9-]{0,63}$');

bool skillIdValido(String id) => _padraoDeId.hasMatch(id);

class UsoDaSkill {
  const UsoDaSkill({this.personas = const [], this.posicoes = const []});

  final List<String> personas;
  final List<String> posicoes;

  bool get vazio => personas.isEmpty && posicoes.isEmpty;

  factory UsoDaSkill.deJson(Object? bruto) {
    final j = bruto is Map ? bruto : const {};
    return UsoDaSkill(personas: listaDeTextos(j['personas']), posicoes: listaDeTextos(j['posicoes']));
  }
}

class Skill {
  const Skill({
    required this.dono,
    required this.id,
    this.descricao = '',
    this.corpo = '',
    this.arquivos = const [],
    this.erro,
    this.usadaPor = const UsoDaSkill(),
  });

  final String dono;
  final String id;
  final String descricao;
  final String corpo;
  final List<String> arquivos;
  final String? erro;
  final UsoDaSkill usadaPor;

  bool get daCasa => dono == donoCasa;
  bool get valida => erro == null;

  factory Skill.deJson(Map<String, dynamic> j) => Skill(
        dono: j['dono'] as String? ?? '',
        id: j['id'] as String? ?? '',
        descricao: j['descricao'] as String? ?? '',
        corpo: j['corpo'] as String? ?? '',
        arquivos: listaDeTextos(j['arquivos']),
        erro: j['erro'] is String && (j['erro'] as String).isNotEmpty ? j['erro'] as String : null,
        usadaPor: UsoDaSkill.deJson(j['usadaPor']),
      );
}

class RascunhoDeSkill {
  const RascunhoDeSkill({
    required this.dono,
    this.id = '',
    this.descricao = '',
    this.corpo = '',
    this.nova = true,
    this.arquivos = const [],
  });

  factory RascunhoDeSkill.de(Skill s) =>
      RascunhoDeSkill(dono: s.dono, id: s.id, descricao: s.descricao, corpo: s.corpo, nova: false, arquivos: s.arquivos);

  final String dono;
  final String id;
  final String descricao;
  final String corpo;
  final bool nova;
  final List<String> arquivos;

  RascunhoDeSkill copiar({String? dono, String? id, String? descricao, String? corpo}) => RascunhoDeSkill(
        dono: dono ?? this.dono,
        id: nova ? (id ?? this.id) : this.id,
        descricao: descricao ?? this.descricao,
        corpo: corpo ?? this.corpo,
        nova: nova,
        arquivos: arquivos,
      );

  Map<String, Object?> paraJson() => {'id': id.trim(), 'descricao': descricao.trim(), 'corpo': corpo};

  bool mesmoConteudo(Skill s) =>
      s.dono == dono && s.id == id.trim() && s.descricao == descricao.trim() && s.corpo.trim() == corpo.trim();
}

String rotuloDoDono(String dono, {String casa = nomePadraoDaCasa}) => dono == donoCasa ? casa : Perfil.porChave(dono).nome;

enum CampoDaSkill { id, descricao, corpo }

Map<CampoDaSkill, String> errosDosCamposDaSkill(
  RascunhoDeSkill r, {
  Iterable<Skill> existentes = const [],
  String casa = nomePadraoDaCasa,
}) {
  final id = r.id.trim();
  final descricao = r.descricao.trim();
  return {
    if (!skillIdValido(id))
      CampoDaSkill.id: 'id inválido (letras minúsculas, números e hífen, começando por letra)'
    else if (r.nova && existentes.any((s) => s.dono == r.dono && s.id == id))
      CampoDaSkill.id: 'já existe a skill $id em ${rotuloDoDono(r.dono, casa: casa)}',
    if (descricao.isEmpty)
      CampoDaSkill.descricao: 'a descrição é obrigatória'
    else if (descricao.length > limiteDaDescricao)
      CampoDaSkill.descricao: 'a descrição passa de $limiteDaDescricao caracteres',
    if (r.corpo.trim().isEmpty)
      CampoDaSkill.corpo: 'o corpo da skill está vazio'
    else if (r.corpo.length > limiteDoCorpo)
      CampoDaSkill.corpo: 'o corpo da skill passa de 100 mil caracteres',
  };
}

List<String> errosDoRascunho(RascunhoDeSkill r, {Iterable<Skill> existentes = const [], String casa = nomePadraoDaCasa}) =>
    errosDosCamposDaSkill(r, existentes: existentes, casa: casa).values.toList();

typedef GrupoDeSkills = ({String dono, List<Skill> skills});

List<GrupoDeSkills> agruparSkills(List<Skill> lista) {
  final donos = {donoCasa, for (final s in lista) if (!s.daCasa) s.dono};
  return [
    for (final dono in donos) (dono: dono, skills: [for (final s in lista) if (s.dono == dono) s]),
  ];
}

Skill? skillDaCasa(List<Skill> biblioteca, String id) => biblioteca.where((s) => s.daCasa && s.id == id).firstOrNull;

List<Skill> skillsProprias(List<Skill> biblioteca, String persona) => [for (final s in biblioteca) if (s.dono == persona) s];

List<Skill> anexaveis(List<Skill> biblioteca, List<String> anexadas) =>
    [for (final s in biblioteca) if (s.daCasa && s.valida && !anexadas.contains(s.id)) s];

List<String> comSkill(List<String> ids, String id) => ids.contains(id) ? ids : [...ids, id];

List<String> semSkill(List<String> ids, String id) => [for (final x in ids) if (x != id) x];

EquipeResumo anexarSkillNaPosicao(EquipeResumo e, String posicao, String skill) =>
    editarPosicao(e, posicao, (p) => p.copiar(skills: comSkill(p.skills, skill)));

EquipeResumo tirarSkillDaPosicao(EquipeResumo e, String posicao, String skill) =>
    editarPosicao(e, posicao, (p) => p.copiar(skills: semSkill(p.skills, skill)));

class SkillDescrita {
  const SkillDescrita({required this.id, required this.descricao, this.propria = false, this.erro});

  final String id;
  final String descricao;
  final bool propria;
  final String? erro;

  String get rotulo => erro == null ? id : '$id (inválida)';
}

SkillDescrita _anexada(List<Skill> biblioteca, String id) {
  final s = skillDaCasa(biblioteca, id);
  if (s == null) return SkillDescrita(id: id, descricao: 'não existe mais na biblioteca', erro: 'não existe mais');
  return SkillDescrita(id: id, descricao: s.descricao, erro: s.erro);
}

List<SkillDescrita> skillsDaPersona(List<Skill> biblioteca, Perfil persona) => [
      for (final s in skillsProprias(biblioteca, persona.chave))
        SkillDescrita(id: s.id, descricao: s.descricao, propria: true, erro: s.erro),
      for (final id in persona.skills) _anexada(biblioteca, id),
    ];

List<SkillDescrita> skillsDaPosicao(List<Skill> biblioteca, PosicaoResumo posicao) =>
    [for (final id in posicao.skills) _anexada(biblioteca, id)];

String descreverUso(UsoDaSkill uso, {required String Function(String) nomeDaPersona, String Function(String)? nomeDaPosicao}) {
  if (uso.vazio) return 'ninguém usa';
  return [
    for (final p in uso.personas) nomeDaPersona(p),
    for (final p in uso.posicoes) nomeDaPosicao?.call(p) ?? p,
  ].join(', ');
}
