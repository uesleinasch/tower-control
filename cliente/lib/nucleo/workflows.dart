import 'organograma.dart';
import 'tarefas.dart';

String _texto(Object? v) => v is String ? v : '';
String? _textoOuNulo(Object? v) => v is String && v.isNotEmpty ? v : null;
int _inteiro(Object? v) => v is num ? v.toInt() : 0;
int? _inteiroOuNulo(Object? v) => v is num ? v.toInt() : null;
DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v) : null;
Map<String, dynamic> _mapa(Object? v) => v is Map<String, dynamic> ? v : const {};
List<String> _textos(Object? v) => [for (final e in (v is List ? v : const [])) if (e is String) e];
List<T> _lista<T>(Object? v, T Function(Map<String, dynamic>) deJson) => [
      for (final e in (v is List ? v : const []).whereType<Map<String, dynamic>>()) deJson(e),
    ];

const nomesDeCaixa = {
  'executar': 'executar',
  'revisar': 'revisar',
  'aprovar': 'aprovar',
  'decisao_humana': 'decisão humana',
  'condicao': 'condição',
  'paralelo': 'paralelo',
  'juncao': 'junção',
  'laco': 'laço',
  'espera': 'espera',
  'board': 'board',
  'fim': 'fim',
};

const nomesDeStatusDoFluxo = {
  'esperando': 'na fila',
  'rodando': 'rodando',
  'concluido': 'concluído',
  'falhou': 'falhou',
  'cancelado': 'cancelado',
};

const nomesDeStatusDaFicha = {
  'esperando': 'esperando',
  'concluida': 'concluída',
  'cancelada': 'cancelada',
};

class TipoDeValor {
  const TipoDeValor(this.nome, [this.escolhas = const []]);
  const TipoDeValor.texto()
      : nome = 'texto',
        escolhas = const [];

  final String nome;
  final List<String> escolhas;

  bool get escolha => nome == 'escolha';

  String get descricao => escolha ? 'uma de: ${escolhas.join(', ')}' : nome;

  static TipoDeValor deJson(Object? bruto) {
    if (bruto == 'numero' || bruto == 'booleano') return TipoDeValor(bruto as String);
    if (bruto is Map && bruto['escolha'] is List) {
      final escolhas = _textos(bruto['escolha']);
      if (escolhas.isNotEmpty) return TipoDeValor('escolha', escolhas);
    }
    return const TipoDeValor.texto();
  }

  @override
  bool operator ==(Object other) =>
      other is TipoDeValor && other.nome == nome && other.escolhas.join('\u0000') == escolhas.join('\u0000');

  @override
  int get hashCode => Object.hash(nome, escolhas.join('\u0000'));
}

class Caixa {
  const Caixa({required this.id, required this.tipo, this.titulo, this.prazo, this.campos = const {}});

  final String id;
  final String tipo;
  final String? titulo;
  final String? prazo;
  final Map<String, dynamic> campos;

  String get rotulo => titulo ?? id;

  String get nomeDoTipo => nomesDeCaixa[tipo] ?? tipo;

  List<String> get opcoes => _textos(campos['opcoes']);

  String get detalhe => switch (tipo) {
        'executar' => _texto(campos['posicao']),
        'revisar' || 'aprovar' => _texto(campos['de']).isEmpty ? '' : 'de ${_texto(campos['de'])}',
        'decisao_humana' => opcoes.join(' / '),
        'board' => opcoes.join(' / '),
        'laco' => campos['maxVoltas'] is num ? 'até ${_inteiro(campos['maxVoltas'])} voltas' : '',
        'espera' => _textoOuNulo(campos['duracao']) ??
            _textoOuNulo(campos['ate']) ??
            (_textoOuNulo(campos['sinal']) == null ? '' : 'sinal "${campos['sinal']}"'),
        'fim' => _texto(campos['resultado']),
        _ => '',
      };

  factory Caixa.deJson(Map<String, dynamic> j) => Caixa(
        id: _texto(j['id']),
        tipo: _texto(j['tipo']),
        titulo: _textoOuNulo(j['titulo']),
        prazo: _textoOuNulo(j['prazo']),
        campos: j,
      );
}

class Aresta {
  const Aresta({required this.de, required this.para, this.quando});

  final String de;
  final String para;
  final String? quando;

  String get chave => '$de>$para';

  factory Aresta.deJson(Map<String, dynamic> j) =>
      Aresta(de: _texto(j['de']), para: _texto(j['para']), quando: _textoOuNulo(j['quando']));
}

class Workflow {
  const Workflow({
    required this.id,
    required this.nome,
    this.versao = 0,
    this.entrada = const {},
    this.inicio = '',
    this.nos = const [],
    this.arestas = const [],
    this.layout = const {},
    this.equipe = '',
    this.bruto = const {},
  });

  final String id;
  final String nome;
  final int versao;
  final Map<String, TipoDeValor> entrada;
  final String inicio;
  final List<Caixa> nos;
  final List<Aresta> arestas;
  final Map<String, Ponto> layout;
  final String equipe;
  final Map<String, dynamic> bruto;

  Caixa? caixa(String id) => nos.where((n) => n.id == id).firstOrNull;

  factory Workflow.deJson(Map<String, dynamic> j) {
    final id = _texto(j['id']);
    return Workflow(
      id: id,
      nome: _textoOuNulo(j['nome']) ?? id,
      versao: _inteiro(j['versao']),
      entrada: {
        for (final MapEntry(:key, :value) in _mapa(j['entrada']).entries) key: TipoDeValor.deJson(value),
      },
      inicio: _texto(j['inicio']),
      nos: [for (final c in _lista(j['nos'], Caixa.deJson)) if (c.id.isNotEmpty) c],
      arestas: _lista(j['arestas'], Aresta.deJson),
      layout: {
        for (final MapEntry(:key, :value) in _mapa(j['layout']).entries)
          if (value is Map && value['x'] is num && value['y'] is num)
            key: (x: (value['x'] as num).toDouble(), y: (value['y'] as num).toDouble()),
      },
      equipe: _texto(j['equipe']),
      bruto: j,
    );
  }
}

class Ficha {
  const Ficha({
    required this.id,
    this.fluxo = 0,
    required this.no,
    this.status = 'esperando',
    this.tarefa,
    this.veioDe,
    this.chegadas = const [],
    this.saidas = const {},
    this.acordaEm,
    this.prazoEm,
    this.avisada = false,
    this.criadaEm,
    this.concluidaEm,
  });

  final int id;
  final int fluxo;
  final String no;
  final String status;
  final int? tarefa;
  final int? veioDe;
  final List<String> chegadas;
  final Map<String, Object> saidas;
  final DateTime? acordaEm;
  final DateTime? prazoEm;
  final bool avisada;
  final DateTime? criadaEm;
  final DateTime? concluidaEm;

  bool get esperando => status == 'esperando';

  factory Ficha.deJson(Map<String, dynamic> j) => Ficha(
        id: _inteiro(j['id']),
        fluxo: _inteiro(j['fluxo']),
        no: _texto(j['no']),
        status: _textoOuNulo(j['status']) ?? 'esperando',
        tarefa: _inteiroOuNulo(j['tarefa']),
        veioDe: _inteiroOuNulo(j['veioDe']),
        chegadas: _textos(j['chegadas']),
        saidas: _valores(j['saidas']),
        acordaEm: _data(j['acordaEm']),
        prazoEm: _data(j['prazoEm']),
        avisada: j['avisada'] == true,
        criadaEm: _data(j['criadaEm']),
        concluidaEm: _data(j['concluidaEm']),
      );
}

Map<String, Object> _valores(Object? bruto) => {
      for (final MapEntry(:key, :value) in _mapa(bruto).entries)
        if (value is String || value is num || value is bool) key: value as Object,
    };

class Fluxo {
  const Fluxo({
    required this.id,
    this.equipe = '',
    this.workflow = '',
    this.versao = 0,
    required this.definicao,
    this.entrada = const {},
    this.status = 'rodando',
    this.resultado,
    this.criadoPor = '',
    this.depoisDe,
    this.criadoEm,
    this.atualizadoEm,
    this.erro,
    this.fichas = const [],
  });

  final int id;
  final String equipe;
  final String workflow;
  final int versao;
  final Workflow definicao;
  final Map<String, Object> entrada;
  final String status;
  final String? resultado;
  final String criadoPor;
  final int? depoisDe;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;
  final String? erro;
  final List<Ficha> fichas;

  bool get aberto => status == 'rodando' || status == 'esperando';

  String get nome => definicao.nome;

  Ficha? ficha(int id) => fichas.where((f) => f.id == id).firstOrNull;

  factory Fluxo.deJson(Map<String, dynamic> j) {
    final workflow = _texto(j['workflow']);
    final definicao = j['definicao'] is Map<String, dynamic>
        ? Workflow.deJson(j['definicao'] as Map<String, dynamic>)
        : Workflow(id: workflow, nome: workflow);
    return Fluxo(
      id: _inteiro(j['id']),
      equipe: _texto(j['equipe']),
      workflow: workflow.isEmpty ? definicao.id : workflow,
      versao: _inteiro(j['versao']),
      definicao: definicao,
      entrada: _valores(j['entrada']),
      status: _textoOuNulo(j['status']) ?? 'rodando',
      resultado: _textoOuNulo(j['resultado']),
      criadoPor: _texto(j['criadoPor']),
      depoisDe: _inteiroOuNulo(j['depoisDe']),
      criadoEm: _data(j['criadoEm']),
      atualizadoEm: _data(j['atualizadoEm']),
      erro: _textoOuNulo(j['erro']),
      fichas: _lista(j['fichas'], Ficha.deJson),
    );
  }
}

const passoXDoGrafo = 260.0;
const passoYDoGrafo = 120.0;
const larguraDaCaixa = 200.0;
const alturaDaCaixa = 72.0;
const margemDoGrafo = 24.0;

Map<String, Ponto> layoutCalculado(Workflow w) {
  final ids = {for (final n in w.nos) n.id};
  final saindo = <String, List<String>>{};
  for (final a in w.arestas) {
    if (ids.contains(a.de) && ids.contains(a.para)) (saindo[a.de] ??= []).add(a.para);
  }
  final semVoltas = <String, List<String>>{};
  final visitados = <String>{};
  final naPilha = <String>{};
  void visitar(String id) {
    visitados.add(id);
    naPilha.add(id);
    for (final para in saindo[id] ?? const <String>[]) {
      if (naPilha.contains(para)) continue;
      (semVoltas[id] ??= []).add(para);
      if (!visitados.contains(para)) visitar(para);
    }
    naPilha.remove(id);
  }

  if (ids.contains(w.inicio)) visitar(w.inicio);

  final nivel = <String, int>{};
  final ordem = <String>[];
  final feitos = <String>{};
  void topologica(String id) {
    if (!feitos.add(id)) return;
    for (final para in semVoltas[id] ?? const <String>[]) {
      topologica(para);
    }
    ordem.add(id);
  }

  for (final id in visitados) {
    topologica(id);
  }
  for (final id in ordem.reversed) {
    nivel.putIfAbsent(id, () => 0);
    for (final para in semVoltas[id] ?? const <String>[]) {
      if ((nivel[para] ?? -1) < nivel[id]! + 1) nivel[para] = nivel[id]! + 1;
    }
  }
  final extra = nivel.isEmpty ? 0 : nivel.values.reduce((a, b) => a > b ? a : b) + 1;
  final porNivel = <int, int>{};
  return {
    for (final n in w.nos)
      n.id: () {
        final nv = nivel[n.id] ?? extra;
        final i = porNivel[nv] = (porNivel[nv] ?? -1) + 1;
        return (x: nv * passoXDoGrafo, y: i * passoYDoGrafo);
      }(),
  };
}

Map<String, Ponto> layoutDoGrafo(Workflow w) {
  final faltando = w.nos.any((n) => !w.layout.containsKey(n.id));
  final calculado = faltando ? layoutCalculado(w) : const <String, Ponto>{};
  return {for (final n in w.nos) n.id: w.layout[n.id] ?? calculado[n.id]!};
}

Ponto cantoDaCaixa(Map<String, Ponto> layout, String id) {
  final p = layout[id] ?? (x: 0, y: 0);
  return (x: p.x + margemDoGrafo, y: p.y + margemDoGrafo);
}

({double largura, double altura}) tamanhoDoGrafo(Map<String, Ponto> layout) {
  var largura = 2 * margemDoGrafo;
  var altura = 2 * margemDoGrafo;
  for (final id in layout.keys) {
    final c = cantoDaCaixa(layout, id);
    if (c.x + larguraDaCaixa + margemDoGrafo > largura) largura = c.x + larguraDaCaixa + margemDoGrafo;
    if (c.y + alturaDaCaixa + margemDoGrafo > altura) altura = c.y + alturaDaCaixa + margemDoGrafo;
  }
  return (largura: largura, altura: altura + passoYDoGrafo / 2);
}

Vista ajustarVistaAoGrafo(Map<String, Ponto> layout, double largura, double altura) {
  if (layout.isEmpty) return (dx: 0, dy: 0, escala: 1);
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final id in layout.keys) {
    final c = cantoDaCaixa(layout, id);
    if (c.x < minX) minX = c.x;
    if (c.y < minY) minY = c.y;
    if (c.x + larguraDaCaixa > maxX) maxX = c.x + larguraDaCaixa;
    if (c.y + alturaDaCaixa + 20 > maxY) maxY = c.y + alturaDaCaixa + 20;
  }
  return vistaQueMostra(minX: minX, minY: minY, maxX: maxX, maxY: maxY, largura: largura, altura: altura);
}

String? caixaEm(Map<String, Ponto> layout, double x, double y) {
  for (final id in layout.keys.toList().reversed) {
    final c = cantoDaCaixa(layout, id);
    if (x >= c.x && x <= c.x + larguraDaCaixa && y >= c.y && y <= c.y + alturaDaCaixa) return id;
  }
  return null;
}

List<Caixa> caixasEmOrdem(Workflow w) {
  final layout = layoutDoGrafo(w);
  return [...w.nos]..sort((a, b) {
      final pa = layout[a.id]!;
      final pb = layout[b.id]!;
      final x = pa.x.compareTo(pb.x);
      return x != 0 ? x : pa.y.compareTo(pb.y);
    });
}

Map<String, String> estadoDasCaixas(Fluxo f) {
  final estado = <String, String>{};
  for (final ficha in [...f.fichas]..sort((a, b) => a.id.compareTo(b.id))) {
    if (estado[ficha.no] == 'esperando') continue;
    estado[ficha.no] = ficha.status;
  }
  return estado;
}

Set<String> arestasPercorridas(Fluxo f) {
  final porId = {for (final ficha in f.fichas) ficha.id: ficha};
  final existentes = {for (final a in f.definicao.arestas) a.chave};
  return {
    for (final ficha in f.fichas)
      if (porId[ficha.veioDe] case final anterior? when existentes.contains('${anterior.no}>${ficha.no}'))
        '${anterior.no}>${ficha.no}',
  };
}

String formatarValor(Object? v) => switch (v) {
      true => 'sim',
      false => 'não',
      null => '',
      final num n when n == n.roundToDouble() => n.toInt().toString(),
      _ => v.toString(),
    };

String resumoDasSaidas(Map<String, Object> saidas, {int limite = 80}) => [
      for (final MapEntry(:key, :value) in saidas.entries)
        () {
          final texto = formatarValor(value).replaceAll(RegExp(r'\s+'), ' ').trim();
          return '$key: ${texto.length > limite ? '${texto.substring(0, limite)}…' : texto}';
        }(),
    ].join(' · ');

class PassoDoCaminho {
  const PassoDoCaminho({
    required this.ficha,
    required this.no,
    required this.titulo,
    required this.tipo,
    required this.status,
    required this.resumo,
    this.tarefa,
  });

  final int ficha;
  final String no;
  final String titulo;
  final String tipo;
  final String status;
  final String resumo;
  final int? tarefa;

  bool get destacado => status == 'esperando';
}

List<PassoDoCaminho> ordemDoCaminho(Fluxo f) {
  final fichas = [...f.fichas]..sort((a, b) => a.id.compareTo(b.id));
  PassoDoCaminho passo(Ficha ficha) {
    final caixa = f.definicao.caixa(ficha.no);
    return PassoDoCaminho(
      ficha: ficha.id,
      no: ficha.no,
      titulo: caixa?.rotulo ?? ficha.no,
      tipo: caixa?.tipo ?? '',
      status: ficha.status,
      resumo: resumoDasSaidas(ficha.saidas),
      tarefa: ficha.tarefa,
    );
  }

  return [
    for (final ficha in fichas)
      if (ficha.esperando) passo(ficha),
    for (final ficha in fichas)
      if (!ficha.esperando) passo(ficha),
  ];
}

bool aceitaRotina(Workflow w) => w.entrada.entries.every((e) => e.key == 'dados' && e.value.nome == 'texto');

typedef EntradaConvertida = ({Map<String, Object> valores, List<String> erros});

EntradaConvertida converterEntrada(Map<String, TipoDeValor> entrada, Map<String, Object?> brutos) {
  final valores = <String, Object>{};
  final erros = <String>[];
  for (final MapEntry(key: campo, value: tipo) in entrada.entries) {
    final bruto = brutos[campo];
    switch (tipo.nome) {
      case 'numero':
        final texto = (bruto is num ? bruto.toString() : bruto is String ? bruto : '').trim().replaceAll(',', '.');
        final n = num.tryParse(texto);
        if (n == null || !n.isFinite) {
          erros.add('$campo precisa ser um número');
        } else {
          valores[campo] = n == n.roundToDouble() && !texto.contains('.') ? n.toInt() : n.toDouble();
        }
      case 'booleano':
        valores[campo] = bruto == true;
      case 'escolha':
        if (bruto is String && tipo.escolhas.contains(bruto)) {
          valores[campo] = bruto;
        } else {
          erros.add('$campo: escolha uma das opções');
        }
      default:
        valores[campo] = bruto is String ? bruto.trim() : '';
    }
  }
  return (valores: valores, erros: erros);
}

String descricaoDaCaixaDaTarefa(Tarefa t, List<Fluxo> fluxos) {
  final id = t.fluxo;
  if (id == null) return '';
  final fluxo = fluxos.where((f) => f.id == id).firstOrNull;
  if (fluxo == null) return 'parte do workflow #$id';
  final ficha = t.ficha == null ? null : fluxo.ficha(t.ficha!);
  final no = ficha?.no;
  if (no == null) return 'parte do workflow ${fluxo.nome}';
  return 'caixa ${fluxo.definicao.caixa(no)?.rotulo ?? no} do workflow ${fluxo.nome}';
}
