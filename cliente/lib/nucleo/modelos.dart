class Perfil {
  const Perfil(
    this.chave,
    this.nome,
    this.inicial,
    this.cor,
    this.papel, {
    this.executor = false,
    this.conversa = true,
    this.excluivel = true,
    this.gerandoPerfil = false,
    this.modelo,
    this.orcamentoMensalUSD,
    this.orcamentoMensalTokens,
    this.gastoMesUSD = 0,
    this.gastoTotalMesUSD = 0,
    this.tokensMes = 0,
    this.tokensTotalMes = 0,
    this.pausa,
  });

  final String chave;
  final String nome;
  final String inicial;
  final int cor;
  final String papel;
  final bool executor;
  final bool conversa;
  final bool excluivel;
  final bool gerandoPerfil;
  final String? modelo;
  final double? orcamentoMensalUSD;
  final int? orcamentoMensalTokens;
  final double gastoMesUSD;
  final double gastoTotalMesUSD;
  final int tokensMes;
  final int tokensTotalMes;
  final String? pausa;

  double? get proporcaoDoOrcamento {
    double? fracao(num gasto, num? limite) {
      if (limite == null) return null;
      if (limite <= 0) return 1;
      final p = gasto / limite;
      return p > 1 ? 1 : p.toDouble();
    }

    final usd = fracao(gastoMesUSD, orcamentoMensalUSD);
    final tokens = fracao(tokensMes, orcamentoMensalTokens);
    if (usd == null) return tokens;
    if (tokens == null) return usd;
    return usd > tokens ? usd : tokens;
  }

  factory Perfil.deJson(Map<String, dynamic> j) {
    final chave = j['id'] as String? ?? '';
    final nome = j['nome'] as String? ?? chave;
    return Perfil(
      chave,
      nome,
      j['inicial'] as String? ?? (nome.isEmpty ? '?' : nome[0].toUpperCase()),
      corDeHex(j['cor'] as String?),
      j['titulo'] as String? ?? '',
      executor: j['executor'] == true,
      conversa: j['conversa'] == true,
      excluivel: j['excluivel'] == true,
      gerandoPerfil: j['gerandoPerfil'] == true,
      modelo: j['modelo'] as String?,
      orcamentoMensalUSD: (j['orcamentoMensalUSD'] as num?)?.toDouble(),
      orcamentoMensalTokens: (j['orcamentoMensalTokens'] as num?)?.toInt(),
      gastoMesUSD: (j['gastoMesUSD'] as num?)?.toDouble() ?? 0,
      gastoTotalMesUSD: (j['gastoTotalMesUSD'] as num?)?.toDouble() ?? 0,
      tokensMes: (j['tokensMes'] as num?)?.toInt() ?? 0,
      tokensTotalMes: (j['tokensTotalMes'] as num?)?.toInt() ?? 0,
      pausa: (j['pausa'] as Map?)?['motivo'] as String?,
    );
  }

  static const poe = Perfil('poe', 'Poe', 'P', 0xFFE0A458, 'o amigo');
  static const nati = Perfil('nati', 'Nati', 'N', 0xFF9A6EE8, 'engenheira sênior');
  static const lucas = Perfil('lucas', 'Lucas', 'L', 0xFF4FAE7C, 'o gestor');
  static const pami = Perfil('pami', 'Pami', 'P', 0xFFE06A8A, 'a projetista');
  static const alfred = Perfil('alfred', 'Alfred', 'A', 0xFFA9B0BF, 'executor de tarefas', executor: true);

  static List<Perfil> _registro = const [poe, nati, lucas, pami, alfred];

  static List<Perfil> get todos => _registro;

  static void registrar(List<Perfil> lista) => _registro = List.unmodifiable(lista);

  static const corBoard = 0xFF5B8DEF;
  static const corDecisoes = 0xFF58B7C9;
  static const corTarefas = 0xFFC9A227;

  static Perfil porChave(String chave) =>
      todos.firstWhere((p) => p.chave == chave, orElse: () => Perfil(chave, chave, '?', 0xFF8B93A7, ''));
}

String formatarTokens(num n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} mi tokens';
  if (n >= 1000) return '${(n / 1000).round()} mil tokens';
  return '${n.round()} tokens';
}

int corDeHex(String? hex) {
  final valor = hex != null && hex.length == 7 && hex.startsWith('#') ? int.tryParse(hex.substring(1), radix: 16) : null;
  return 0xFF000000 | (valor ?? 0x8B93A7);
}

const modelos = {'haiku': 'Haiku · padrão', 'sonnet': 'Sonnet', 'opus': 'Opus'};
const modeloPadrao = 'haiku';
const modeloDoAuto = 'Opus 5.5';

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
