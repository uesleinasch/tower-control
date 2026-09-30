class Perfil {
  const Perfil(this.chave, this.nome, this.inicial, this.cor, {this.executor = false});

  final String chave;
  final String nome;
  final String inicial;
  final int cor;
  final bool executor;

  static const poe = Perfil('poe', 'Poe', 'P', 0xFFE0A458);
  static const nati = Perfil('nati', 'Nati', 'N', 0xFF9A6EE8);
  static const lucas = Perfil('lucas', 'Lucas', 'L', 0xFF4FAE7C);
  static const pami = Perfil('pami', 'Pami', 'P', 0xFFE06A8A);
  static const alfred = Perfil('alfred', 'Alfred', 'A', 0xFFA9B0BF, executor: true);

  static const todos = [poe, nati, lucas, pami, alfred];

  static const corTicktask = 0xFFF43F5E;
  static const corBoard = 0xFF5B8DEF;
  static const corDecisoes = 0xFF58B7C9;

  static Perfil porChave(String chave) =>
      todos.firstWhere((p) => p.chave == chave, orElse: () => Perfil(chave, chave, '?', 0xFF8B93A7));
}

const modelos = {'haiku': 'Haiku · padrão', 'sonnet': 'Sonnet', 'opus': 'Opus'};
const modeloPadrao = 'haiku';

enum TipoAnexo { imagem, texto, pdf }

class Anexo {
  const Anexo({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.mime,
    required this.bytes,
  });

  final String id;
  final String nome;
  final TipoAnexo tipo;
  final String mime;
  final int bytes;

  factory Anexo.deJson(Map<String, dynamic> j) => Anexo(
        id: j['id'] as String,
        nome: j['nome'] as String? ?? '',
        tipo: TipoAnexo.values.firstWhere((t) => t.name == j['tipo'], orElse: () => TipoAnexo.texto),
        mime: j['mime'] as String? ?? '',
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      );
}

class Mensagem {
  const Mensagem({
    required this.doUsuario,
    required this.texto,
    required this.ts,
    required this.perfil,
    this.citacao,
    this.anexos = const [],
  });

  final bool doUsuario;
  final String texto;
  final DateTime? ts;
  final String perfil;
  final String? citacao;
  final List<Anexo> anexos;

  factory Mensagem.deJson(Map<String, dynamic> j) => Mensagem(
        doUsuario: j['role'] == 'user',
        texto: j['texto'] as String? ?? '',
        ts: DateTime.tryParse(j['ts'] as String? ?? '')?.toLocal(),
        perfil: j['perfil'] as String? ?? '',
        citacao: j['citacao'] as String?,
        anexos: listaDeJson(j['anexos'], Anexo.deJson),
      );
}

class MetaConversa {
  const MetaConversa({
    required this.id,
    required this.perfil,
    required this.titulo,
    required this.criadaEm,
    this.modelo,
    this.auto = false,
    this.foco,
  });

  final String id;
  final String perfil;
  final String titulo;
  final DateTime? criadaEm;
  final String? modelo;
  final bool auto;
  final String? foco;

  bool get ticktask => foco == 'ticktask';

  factory MetaConversa.deJson(Map<String, dynamic> j) => MetaConversa(
        id: j['id'] as String,
        perfil: j['perfil'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        criadaEm: DateTime.tryParse(j['criadaEm'] as String? ?? '')?.toLocal(),
        modelo: j['modelo'] as String?,
        auto: j['auto'] == true,
        foco: j['foco'] as String?,
      );
}

class Decisao {
  const Decisao({
    required this.id,
    required this.data,
    required this.titulo,
    required this.status,
    required this.tags,
    required this.projeto,
  });

  final String id;
  final String data;
  final String titulo;
  final String status;
  final List<String> tags;
  final String projeto;

  factory Decisao.deJson(Map<String, dynamic> j) => Decisao(
        id: j['id'] as String,
        data: j['date'] as String? ?? '',
        titulo: j['title'] as String? ?? '',
        status: j['status'] as String? ?? '',
        tags: (j['tags'] as List? ?? const []).map((t) => '$t').toList(),
        projeto: j['projeto'] as String? ?? '',
      );
}

class Atalho {
  const Atalho(this.rotulo, this.texto);

  final String rotulo;
  final String texto;

  factory Atalho.deJson(Map<String, dynamic> j) =>
      Atalho(j['rotulo'] as String? ?? '', j['texto'] as String? ?? '');
}

List<T> listaDeJson<T>(Object? bruto, T Function(Map<String, dynamic>) deJson) =>
    (bruto as List? ?? const []).whereType<Map<String, dynamic>>().map(deJson).toList();
