import 'dart:convert';

import 'organograma.dart' show idLivre, slugDe;
import 'tarefas.dart';
import 'workflows.dart';

typedef WorkflowJson = Map<String, dynamic>;
typedef ErrosDoWorkflow = Map<String, List<String>>;

const lugarDoWorkflow = 'workflow';
const quandoSenao = 'senao';
const maxVoltasDoLaco = 20;

const tiposDeCaixa = [
  'executar',
  'revisar',
  'aprovar',
  'board',
  'decisao_humana',
  'condicao',
  'paralelo',
  'juncao',
  'laco',
  'espera',
  'fim',
];

const descricoesDeCaixa = {
  'executar': 'uma persona faz o trabalho e devolve',
  'revisar': 'outra posição ou o board revisa a entrega',
  'aprovar': 'uma posição ou o Ueslei aprova a entrega',
  'board': 'o board delibera sobre uma pauta',
  'decisao_humana': 'o Ueslei escolhe uma opção',
  'condicao': 'segue pela primeira regra verdadeira',
  'paralelo': 'segue por todas as ligações juntas',
  'juncao': 'espera todas as ligações chegarem',
  'laco': 'repete enquanto a regra valer',
  'espera': 'espera um tempo, um horário ou um sinal',
  'fim': 'encerra o caminho',
};

const opsDeRegra = ['igual', 'diferente', 'contem', 'maior', 'menor', 'vazio', 'preenchido'];

const nomesDeOp = {
  'igual': 'é igual a',
  'diferente': 'é diferente de',
  'contem': 'contém',
  'maior': 'é maior que',
  'menor': 'é menor que',
  'vazio': 'está vazio',
  'preenchido': 'está preenchido',
};

const camposDeTexto = ['instrucao', 'criterio', 'pergunta', 'pauta'];
const _camposOpcionais = {'titulo', 'prazo', 'criterio', 'resultado'};
const formasDeEspera = ['duracao', 'ate', 'sinal'];

final _slug = RegExp(r'^[a-z][a-z0-9-]{0,47}$');
final _nomeDeCampo = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
final _duracao = RegExp(r'^(\d{1,4})(m|h|d)$');
final _horario = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
final _referencia = RegExp(r'\{\{\s*([a-z][a-z0-9-]*)\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}');
final _campoDeRegra = RegExp(r'^([a-z][a-z0-9-]*)\.([a-zA-Z_][a-zA-Z0-9_]*)$');

class ErroDeWorkflow implements Exception {
  const ErroDeWorkflow(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

dynamic copiaProfunda(dynamic v) => switch (v) {
      Map() => <String, dynamic>{for (final e in v.entries) e.key as String: copiaProfunda(e.value)},
      List() => [for (final x in v) copiaProfunda(x)],
      _ => v,
    };

bool mesmoWorkflow(WorkflowJson a, WorkflowJson b) => jsonEncode(a) == jsonEncode(b);

String _t(Object? v) => v is String ? v.trim() : '';

List<Map<String, dynamic>> nosDe(WorkflowJson w) =>
    [for (final n in (w['nos'] is List ? w['nos'] as List : const [])) if (n is Map<String, dynamic>) n];

List<Map<String, dynamic>> arestasDe(WorkflowJson w) =>
    [for (final a in (w['arestas'] is List ? w['arestas'] as List : const [])) if (a is Map<String, dynamic>) a];

Map<String, dynamic>? caixaDe(WorkflowJson w, String id) => nosDe(w).where((n) => n['id'] == id).firstOrNull;

Set<String> idsDe(WorkflowJson w) => {for (final n in nosDe(w)) if (n['id'] is String) n['id'] as String};

String? _quando(Map<String, dynamic> a) => _t(a['quando']).isEmpty ? null : _t(a['quando']);

WorkflowJson _copia(WorkflowJson w) {
  final c = copiaProfunda(w) as WorkflowJson;
  c['nos'] = nosDe(c);
  c['arestas'] = arestasDe(c);
  c['layout'] = c['layout'] is Map<String, dynamic> ? c['layout'] : <String, dynamic>{};
  return c;
}

// ── abrir, criar, duplicar ─────────────────────────────────────────

WorkflowJson rascunhoDe(Workflow w) {
  final j = _copia(w.bruto);
  j.remove('equipe');
  j.remove('textosEmArquivo');
  return j;
}

Map<String, Map<String, String>> textosEmArquivoDe(Workflow w) {
  final bruto = w.bruto['textosEmArquivo'];
  if (bruto is! Map) return const {};
  return {
    for (final MapEntry(:key, :value) in bruto.entries)
      if (value is Map) key as String: {for (final e in value.entries) if (e.value is String) e.key as String: e.value as String},
  };
}

WorkflowJson novoWorkflow(String nome, Iterable<String> usados) {
  final limpo = nome.trim();
  if (limpo.isEmpty) throw const ErroDeWorkflow('Dê um nome ao workflow.');
  return {
    'id': idLivre(slugDe(limpo), usados),
    'nome': limpo,
    'versao': 0,
    'entrada': <String, dynamic>{},
    'inicio': 'executar',
    'nos': [
      {'id': 'executar', 'tipo': 'executar', 'posicao': '', 'instrucao': ''},
      {'id': 'fim', 'tipo': 'fim'},
    ],
    'arestas': [
      {'de': 'executar', 'para': 'fim'},
    ],
    'layout': {
      'executar': {'x': 0.0, 'y': 0.0},
      'fim': {'x': passoXDoGrafo, 'y': 0.0},
    },
  };
}

WorkflowJson duplicarWorkflow(WorkflowJson w, Iterable<String> usados) {
  final c = _copia(w);
  final nome = '${_t(w['nome']).isEmpty ? _t(w['id']) : _t(w['nome'])} (cópia)';
  c['nome'] = nome;
  c['id'] = idLivre(slugDe(nome), usados);
  c['versao'] = 0;
  return c;
}

WorkflowJson editarWorkflow(WorkflowJson w, void Function(WorkflowJson) mudar) {
  final c = _copia(w);
  mudar(c);
  return c;
}

// ── caixas ─────────────────────────────────────────────────────────

const _baseDoId = {
  'executar': 'executar',
  'revisar': 'revisar',
  'aprovar': 'aprovar',
  'board': 'board',
  'decisao_humana': 'decisao',
  'condicao': 'condicao',
  'paralelo': 'paralelo',
  'juncao': 'juncao',
  'laco': 'laco',
  'espera': 'espera',
  'fim': 'fim',
};

Map<String, dynamic> _caixaPadrao(String tipo, String id) => {
      'id': id,
      'tipo': tipo,
      ...switch (tipo) {
        'executar' => {'posicao': '', 'instrucao': ''},
        'revisar' => {
            'de': '',
            'por': {'posicao': ''},
          },
        'aprovar' => {
            'de': '',
            'por': {'ueslei': true},
          },
        'decisao_humana' => {
            'pergunta': '',
            'opcoes': ['sim', 'não'],
          },
        'condicao' => {
            'regras': [
              {'campo': '', 'op': 'igual', 'valor': '', 'saida': 'sim'},
            ],
          },
        'laco' => {
            'maxVoltas': 3,
            'enquanto': {'campo': '', 'op': 'preenchido'},
          },
        'espera' => {'duracao': '1h'},
        'board' => {'pauta': ''},
        _ => <String, dynamic>{},
      },
    };

Map<String, Ponto> layoutDoRascunho(WorkflowJson w) => layoutDoGrafo(Workflow.deJson(w));

void _gravarPonto(WorkflowJson c, String id, Ponto p) => (c['layout'] as Map<String, dynamic>)[id] = {'x': p.x, 'y': p.y};

({WorkflowJson workflow, String id}) criarCaixa(WorkflowJson w, String tipo, Ponto ponto) {
  if (!tiposDeCaixa.contains(tipo)) throw ErroDeWorkflow('Tipo de caixa desconhecido: $tipo.');
  final c = _copia(w);
  final layout = layoutDoRascunho(w);
  final id = idLivre(_baseDoId[tipo]!, idsDe(w));
  (c['nos'] as List).add(_caixaPadrao(tipo, id));
  for (final MapEntry(:key, :value) in layout.entries) {
    (c['layout'] as Map<String, dynamic>).putIfAbsent(key, () => {'x': value.x, 'y': value.y});
  }
  _gravarPonto(c, id, ponto);
  if (!idsDe(w).contains(_t(w['inicio']))) c['inicio'] = id;
  return (workflow: c, id: id);
}

Ponto pontoDepois(WorkflowJson w, String de, int indiceDaSaida) {
  final layout = layoutDoRascunho(w);
  final origem = layout[de] ?? (x: 0.0, y: 0.0);
  var y = origem.y + indiceDaSaida * passoYDoGrafo;
  final x = origem.x + passoXDoGrafo;
  bool ocupado(double y) =>
      layout.values.any((p) => (p.x - x).abs() < larguraDaCaixa && (p.y - y).abs() < alturaDaCaixa + 8);
  while (ocupado(y)) {
    y += passoYDoGrafo;
  }
  return (x: x, y: y);
}

({WorkflowJson workflow, String id}) criarDepois(WorkflowJson w, String de, String? quando, String tipo) {
  final pontos = pontosDeSaida(w, de);
  final indice = pontos.indexWhere((p) => p.quando == quando);
  final criado = criarCaixa(w, tipo, pontoDepois(w, de, indice < 0 ? 0 : indice));
  return (workflow: ligar(criado.workflow, de, quando, criado.id), id: criado.id);
}

WorkflowJson removerCaixa(WorkflowJson w, String id) {
  final c = _copia(w);
  c['nos'] = [for (final n in nosDe(c)) if (n['id'] != id) n];
  c['arestas'] = [for (final a in arestasDe(c)) if (a['de'] != id && a['para'] != id) a];
  (c['layout'] as Map<String, dynamic>).remove(id);
  if (c['inicio'] == id) c['inicio'] = '';
  return c;
}

WorkflowJson moverCaixa(WorkflowJson w, String id, Ponto ponto) {
  final c = _copia(w);
  final layout = layoutDoRascunho(w);
  for (final MapEntry(:key, :value) in layout.entries) {
    (c['layout'] as Map<String, dynamic>).putIfAbsent(key, () => {'x': value.x, 'y': value.y});
  }
  _gravarPonto(c, id, ponto);
  return c;
}

WorkflowJson organizarRascunho(WorkflowJson w) {
  final c = _copia(w);
  final layout = layoutCalculado(Workflow.deJson(w));
  c['layout'] = <String, dynamic>{
    for (final MapEntry(:key, :value) in layout.entries) key: {'x': value.x, 'y': value.y},
  };
  return c;
}

WorkflowJson comLayoutCompleto(WorkflowJson w) {
  final c = _copia(w);
  final layout = layoutDoRascunho(w);
  c['layout'] = <String, dynamic>{
    for (final MapEntry(:key, :value) in layout.entries) key: {'x': value.x, 'y': value.y},
  };
  return c;
}

WorkflowJson definirInicio(WorkflowJson w, String id) => editarWorkflow(w, (c) => c['inicio'] = id);

WorkflowJson editarCaixa(WorkflowJson w, String id, void Function(Map<String, dynamic>) mudar) {
  final c = _copia(w);
  final caixa = caixaDe(c, id);
  if (caixa != null) mudar(caixa);
  return c;
}

WorkflowJson definirCampo(WorkflowJson w, String id, String chave, Object? valor) => editarCaixa(w, id, (caixa) {
      final vazio = valor == null || (valor is String && valor.trim().isEmpty && _camposOpcionais.contains(chave));
      if (vazio) {
        caixa.remove(chave);
      } else {
        caixa[chave] = copiaProfunda(valor);
      }
    });

WorkflowJson definirEspera(WorkflowJson w, String id, String forma, String valor) => editarCaixa(w, id, (caixa) {
      for (final f in formasDeEspera) {
        caixa.remove(f);
      }
      caixa[forma] = valor;
    });

WorkflowJson renomearCaixa(WorkflowJson w, String de, String para) {
  if (de == para) return w;
  if (!_slug.hasMatch(para)) {
    throw const ErroDeWorkflow('O id precisa começar por letra e ter só letras minúsculas, números e hífen.');
  }
  if (para == 'entrada') throw const ErroDeWorkflow('"entrada" é reservado.');
  if (idsDe(w).contains(para)) throw ErroDeWorkflow('Já existe uma caixa $para.');
  final c = _copia(w);
  String trocarTexto(String texto) =>
      texto.replaceAllMapped(_referencia, (m) => m[1] == de ? m[0]!.replaceFirst(de, para) : m[0]!);
  String trocarCampo(String campo) => campo.startsWith('$de.') ? '$para${campo.substring(de.length)}' : campo;
  void trocarRegra(Object? regra) {
    if (regra is Map<String, dynamic> && regra['campo'] is String) regra['campo'] = trocarCampo(regra['campo'] as String);
  }

  for (final n in nosDe(c)) {
    if (n['id'] == de) n['id'] = para;
    if (n['de'] == de) n['de'] = para;
    for (final campo in camposDeTexto) {
      if (n[campo] is String) n[campo] = trocarTexto(n[campo] as String);
    }
    if (n['regras'] is List) (n['regras'] as List).forEach(trocarRegra);
    trocarRegra(n['enquanto']);
  }
  for (final a in arestasDe(c)) {
    if (a['de'] == de) a['de'] = para;
    if (a['para'] == de) a['para'] = para;
  }
  if (c['inicio'] == de) c['inicio'] = para;
  final layout = c['layout'] as Map<String, dynamic>;
  if (layout.containsKey(de)) layout[para] = layout.remove(de);
  return c;
}

// ── opções da decisão e do board, regras da condição ──────────────

List<String> opcoesDe(Map<String, dynamic> caixa) => [for (final o in (caixa['opcoes'] is List ? caixa['opcoes'] as List : const [])) if (o is String) o];

WorkflowJson _trocarQuando(WorkflowJson c, String id, String antes, String? depois) {
  for (final a in arestasDe(c)) {
    if (a['de'] == id && _quando(a) == antes) {
      if (depois == null) {
        a['_remover'] = true;
      } else {
        a['quando'] = depois;
      }
    }
  }
  c['arestas'] = [for (final a in arestasDe(c)) if (a['_remover'] != true) a];
  return c;
}

WorkflowJson acrescentarOpcao(WorkflowJson w, String id, String opcao) =>
    editarCaixa(w, id, (caixa) => caixa['opcoes'] = [...opcoesDe(caixa), opcao]);

WorkflowJson renomearOpcao(WorkflowJson w, String id, int indice, String nova) {
  final caixa = caixaDe(w, id);
  if (caixa == null) return w;
  final opcoes = opcoesDe(caixa);
  if (indice < 0 || indice >= opcoes.length) return w;
  final antes = opcoes[indice].trim();
  final c = editarCaixa(w, id, (cx) => cx['opcoes'] = [...opcoes]..[indice] = nova);
  final repetida = opcoes.where((o) => o.trim() == antes).length > 1;
  return repetida || nova.trim().isEmpty ? c : _trocarQuando(c, id, antes, nova.trim());
}

WorkflowJson removerOpcao(WorkflowJson w, String id, int indice) {
  final caixa = caixaDe(w, id);
  if (caixa == null) return w;
  final opcoes = opcoesDe(caixa);
  if (indice < 0 || indice >= opcoes.length) return w;
  final antes = opcoes[indice].trim();
  final restantes = [...opcoes]..removeAt(indice);
  final c = editarCaixa(w, id, (cx) {
    if (cx['tipo'] == 'board' && restantes.isEmpty) {
      cx.remove('opcoes');
    } else {
      cx['opcoes'] = restantes;
    }
  });
  return restantes.any((o) => o.trim() == antes) ? c : _trocarQuando(c, id, antes, null);
}

WorkflowJson moverOpcao(WorkflowJson w, String id, int de, int para) => editarCaixa(w, id, (caixa) {
      final opcoes = opcoesDe(caixa);
      if (de < 0 || de >= opcoes.length || para < 0 || para >= opcoes.length) return;
      caixa['opcoes'] = opcoes..insert(para, opcoes.removeAt(de));
    });

List<Map<String, dynamic>> regrasDe(Map<String, dynamic> caixa) =>
    [for (final r in (caixa['regras'] is List ? caixa['regras'] as List : const [])) if (r is Map<String, dynamic>) r];

WorkflowJson acrescentarRegra(WorkflowJson w, String id) => editarCaixa(w, id, (caixa) {
      final usadas = {for (final r in regrasDe(caixa)) _t(r['saida'])};
      caixa['regras'] = [
        ...regrasDe(caixa),
        {'campo': '', 'op': 'igual', 'valor': '', 'saida': idLivre('saida', usadas)},
      ];
    });

WorkflowJson definirRegra(WorkflowJson w, String id, int indice, Map<String, dynamic> regra) {
  final caixa = caixaDe(w, id);
  if (caixa == null) return w;
  final regras = regrasDe(caixa);
  if (indice < 0 || indice >= regras.length) return w;
  final antes = _t(regras[indice]['saida']);
  final depois = _t(regra['saida']);
  final c = editarCaixa(w, id, (cx) => cx['regras'] = [...regras]..[indice] = copiaProfunda(regra));
  final outra = regras.indexed.any((e) => e.$1 != indice && _t(e.$2['saida']) == antes);
  if (antes == depois || antes.isEmpty || outra || depois.isEmpty) return c;
  return _trocarQuando(c, id, antes, depois);
}

WorkflowJson removerRegra(WorkflowJson w, String id, int indice) {
  final caixa = caixaDe(w, id);
  if (caixa == null) return w;
  final regras = regrasDe(caixa);
  if (indice < 0 || indice >= regras.length) return w;
  final antes = _t(regras[indice]['saida']);
  final restantes = [...regras]..removeAt(indice);
  final c = editarCaixa(w, id, (cx) => cx['regras'] = restantes);
  return restantes.any((r) => _t(r['saida']) == antes) ? c : _trocarQuando(c, id, antes, null);
}

WorkflowJson moverRegra(WorkflowJson w, String id, int de, int para) => editarCaixa(w, id, (caixa) {
      final regras = regrasDe(caixa);
      if (de < 0 || de >= regras.length || para < 0 || para >= regras.length) return;
      caixa['regras'] = regras..insert(para, regras.removeAt(de));
    });

// ── ligações ───────────────────────────────────────────────────────

class PontoDeSaida {
  const PontoDeSaida({this.quando, this.varias = false, this.destinos = const []});

  final String? quando;
  final bool varias;
  final List<String> destinos;

  String get rotulo => quando ?? '';
  bool get livre => varias || destinos.isEmpty;
}

List<String?> _quandosDe(Map<String, dynamic> no) {
  final opcoes = <String>{for (final o in opcoesDe(no)) if (o.trim().isNotEmpty) o.trim()}.toList();
  return switch (no['tipo']) {
    'executar' || 'juncao' => const [null],
    'revisar' || 'aprovar' => const ['aprovado'],
    'decisao_humana' => opcoes,
    'condicao' => [
        ...{for (final r in regrasDe(no)) if (_t(r['saida']).isNotEmpty) _t(r['saida'])},
        quandoSenao,
      ],
    'laco' => const ['repetir', 'sair'],
    'espera' => _t(no['prazo']).isNotEmpty ? const ['pronto', 'prazo'] : const ['pronto'],
    'board' => no['opcoes'] is List && opcoes.isNotEmpty ? opcoes : const [null],
    _ => const [],
  };
}

List<PontoDeSaida> pontosDeSaida(WorkflowJson w, String id) {
  final no = caixaDe(w, id);
  if (no == null) return const [];
  final minhas = [for (final a in arestasDe(w)) if (a['de'] == id) a];
  if (no['tipo'] == 'paralelo') {
    return [PontoDeSaida(varias: true, destinos: [for (final a in minhas) _t(a['para'])])];
  }
  return [
    for (final q in _quandosDe(no))
      PontoDeSaida(quando: q, destinos: [for (final a in minhas) if (_quando(a) == q) _t(a['para'])]),
  ];
}

WorkflowJson ligar(WorkflowJson w, String de, String? quando, String para) {
  final origem = caixaDe(w, de);
  final destino = caixaDe(w, para);
  if (origem == null || destino == null || de == para) return w;
  final c = _copia(w);
  final arestas = arestasDe(c);
  if (origem['tipo'] == 'paralelo') {
    if (arestas.any((a) => a['de'] == de && a['para'] == para)) return w;
    arestas.add({'de': de, 'para': para});
  } else {
    arestas.removeWhere((a) => a['de'] == de && _quando(a) == quando);
    arestas.add({'de': de, 'para': para, 'quando': ?quando});
  }
  c['arestas'] = arestas;
  if (destino['tipo'] == 'revisar' || destino['tipo'] == 'aprovar') {
    final executar = origem['tipo'] == 'executar'
        ? de
        : (origem['tipo'] == 'revisar' || origem['tipo'] == 'aprovar') && _t(origem['de']).isNotEmpty
            ? _t(origem['de'])
            : null;
    if (executar != null) caixaDe(c, para)!['de'] = executar;
  }
  return c;
}

WorkflowJson desligar(WorkflowJson w, Aresta aresta) {
  final c = _copia(w);
  c['arestas'] = [
    for (final a in arestasDe(c))
      if (!(a['de'] == aresta.de && a['para'] == aresta.para && _quando(a) == aresta.quando)) a,
  ];
  return c;
}

// ── tipos, saídas e referências ────────────────────────────────────

TipoDeValor? _lerTipo(Object? bruto) {
  if (bruto == 'texto' || bruto == 'numero' || bruto == 'booleano') return TipoDeValor(bruto as String);
  if (bruto is Map && bruto['escolha'] is List) {
    final lista = bruto['escolha'] as List;
    if (lista.length >= 2 && lista.every((x) => x is String && x.trim().isNotEmpty)) {
      return TipoDeValor('escolha', {for (final x in lista) (x as String).trim()}.toList());
    }
  }
  return null;
}

Map<String, TipoDeValor> _lerSaidas(Object? bruto, void Function(String) erro) {
  final saidas = <String, TipoDeValor>{};
  if (bruto is! Map) return saidas;
  for (final MapEntry(:key, :value) in bruto.entries) {
    final nome = key as String;
    if (!_nomeDeCampo.hasMatch(nome)) {
      erro('nome de campo inválido ($nome)');
      continue;
    }
    final tipo = _lerTipo(value);
    if (tipo == null) {
      erro('$nome: tipo inválido (texto, número, sim/não ou escolha com 2 ou mais opções)');
      continue;
    }
    saidas[nome] = tipo;
  }
  return saidas;
}

Object? tipoParaJson(TipoDeValor t) => t.escolha ? {'escolha': t.escolhas} : t.nome;

Map<String, TipoDeValor> entradaDe(WorkflowJson w) => _lerSaidas(w['entrada'], (_) {});

Map<String, TipoDeValor> saidasDeclaradas(Map<String, dynamic> caixa) => _lerSaidas(caixa['saidas'], (_) {});

Map<String, TipoDeValor> saidasDaCaixa(Map<String, dynamic> no) {
  const texto = TipoDeValor.texto();
  final opcoes = <String>{for (final o in opcoesDe(no)) if (o.trim().isNotEmpty) o.trim()}.toList();
  return switch (no['tipo']) {
    'executar' => {'devolutiva': texto, ...saidasDeclaradas(no)..remove('devolutiva')},
    'revisar' || 'aprovar' => {'parecer': texto},
    'decisao_humana' => {'opcao': TipoDeValor('escolha', opcoes), 'comentario': texto},
    'board' => {'sintese': texto, 'decisao': no['opcoes'] is List && opcoes.isNotEmpty ? TipoDeValor('escolha', opcoes) : texto},
    'laco' => {'voltas': const TipoDeValor('numero')},
    'espera' => {'motivo': const TipoDeValor('escolha', ['pronto', 'prazo'])},
    _ => const {},
  };
}

class _Grafo {
  _Grafo(WorkflowJson w) {
    for (final n in nosDe(w)) {
      final id = n['id'];
      if (id is String && _slug.hasMatch(id)) porId[id] = n;
    }
    for (final a in arestasDe(w)) {
      final de = _t(a['de']);
      final para = _t(a['para']);
      (saida[de] ??= []).add(para);
      entram[para] = (entram[para] ?? 0) + 1;
    }
  }

  final porId = <String, Map<String, dynamic>>{};
  final saida = <String, List<String>>{};
  final entram = <String, int>{};

  Set<String> alcancaveis(String de, {String? evitar, Map<String, List<String>>? por}) {
    final vistos = <String>{};
    final pilha = [de];
    while (pilha.isNotEmpty) {
      final atual = pilha.removeLast();
      if (vistos.contains(atual) || atual == evitar) continue;
      vistos.add(atual);
      pilha.addAll((por ?? saida)[atual] ?? const []);
    }
    return vistos;
  }

  bool vemAntes(String ref, String id) => ref != id && alcancaveis(ref).contains(id);
}

List<Map<String, dynamic>> correnteDe(WorkflowJson w, String executar) {
  final porId = {for (final n in nosDe(w)) n['id']: n};
  final arestas = arestasDe(w);
  final cadeia = <Map<String, dynamic>>[];
  var atual = executar;
  for (var i = 0; i < porId.length; i++) {
    final aresta = arestas.where((a) => a['de'] == atual).firstOrNull;
    final prox = aresta == null ? null : porId[aresta['para']];
    if (prox == null || (prox['tipo'] != 'revisar' && prox['tipo'] != 'aprovar') || prox['de'] != executar) break;
    cadeia.add(prox);
    atual = prox['id'] as String;
  }
  return cadeia;
}

class ReferenciaDisponivel {
  const ReferenciaDisponivel({required this.caixa, required this.campo, required this.tipo});

  final String caixa;
  final String campo;
  final TipoDeValor tipo;

  String get campoDaRegra => '$caixa.$campo';
  String get texto => '{{$caixa.$campo}}';
}

List<ReferenciaDisponivel> referenciasDisponiveis(WorkflowJson w, String id) {
  final grafo = _Grafo(w);
  return [
    for (final MapEntry(:key, :value) in entradaDe(w).entries)
      ReferenciaDisponivel(caixa: 'entrada', campo: key, tipo: value),
    for (final n in nosDe(w))
      if (n['id'] is String && grafo.vemAntes(n['id'] as String, id))
        for (final MapEntry(:key, :value) in saidasDaCaixa(n).entries)
          ReferenciaDisponivel(caixa: n['id'] as String, campo: key, tipo: value),
  ];
}

TipoDeValor? tipoDoCampo(WorkflowJson w, String campo) {
  final m = _campoDeRegra.firstMatch(campo.trim());
  if (m == null) return null;
  if (m[1] == 'entrada') return entradaDe(w)[m[2]];
  final no = caixaDe(w, m[1]!);
  return no == null ? null : saidasDaCaixa(no)[m[2]];
}

List<String> opsPara(TipoDeValor? tipo) =>
    tipo == null || tipo.nome == 'numero' ? opsDeRegra : [for (final op in opsDeRegra) if (op != 'maior' && op != 'menor') op];

bool opPedeValor(String op) => op != 'vazio' && op != 'preenchido';

// ── validação (espelho de validarWorkflow em app/src/orquestra/workflow.ts) ──

List<String> membrosDoBoard(EquipeResumo equipe, String? executora) => [
      for (final p in equipe.posicoes)
        if (p.capacidades.contains('board') && p.persona != null && p.persona != executora) p.persona!,
    ];

bool _duracaoValida(String texto) => _duracao.hasMatch(texto);

bool _inteiro(Object? v) => v is int || (v is double && v == v.roundToDouble());

({String campo, String op, Object? valor})? _lerRegra(Object? bruto, void Function(String) erro) {
  if (bruto is! Map) {
    erro('op inválida');
    return null;
  }
  final op = bruto['op'];
  if (op is! String || !opsDeRegra.contains(op)) {
    erro('op inválida (${op ?? 'vazia'})');
    return null;
  }
  final campo = _t(bruto['campo']);
  if (!_campoDeRegra.hasMatch(campo)) {
    erro('campo inválido (${campo.isEmpty ? 'vazio' : campo}); use caixa.saida ou entrada.campo');
    return null;
  }
  final valor = bruto['valor'];
  if (opPedeValor(op) && valor is! String && valor is! num && valor is! bool) {
    erro('"${nomesDeOp[op]}" precisa de valor');
    return null;
  }
  return (campo: campo, op: op, valor: opPedeValor(op) ? valor : null);
}

void _conferirOpcoes(Object? bruto, void Function(String) erro) {
  if (bruto is! List || bruto.length < 2) {
    erro('precisa de 2 ou mais opções');
    return;
  }
  final validas = {for (final o in bruto) if (_t(o).isNotEmpty) _t(o)};
  if (validas.length != bruto.length) erro('opções vazias ou repetidas');
}

ErrosDoWorkflow validarRascunho(WorkflowJson w, EquipeResumo equipe) {
  final erros = <String, List<String>>{};
  void erro(String lugar, String mensagem) => (erros[lugar] ??= []).add(mensagem);
  void doWorkflow(String mensagem) => erro(lugarDoWorkflow, mensagem);

  final idDoWorkflow = w['id'];
  if (idDoWorkflow is! String || !_slug.hasMatch(idDoWorkflow)) doWorkflow('id inválido ($idDoWorkflow)');
  if (_t(w['nome']).isEmpty) doWorkflow('nome obrigatório');
  final entrada = _lerSaidas(w['entrada'], (m) => doWorkflow('entrada: $m'));

  final nos = nosDe(w);
  if (nos.isEmpty) doWorkflow('precisa de caixas');
  final grafo = _Grafo(w);
  final vistos = <String>{};
  final regrasValidas = <String, List<({String campo, String op, Object? valor})>>{};
  final saidasValidas = <String, Map<String, TipoDeValor>>{};

  for (final n in nos) {
    final id = n['id'];
    if (id is! String || !_slug.hasMatch(id)) {
      doWorkflow('caixa com id inválido ($id)');
      continue;
    }
    void aqui(String m) => erro(id, m);
    if (!vistos.add(id) || id == 'entrada') aqui('id repetido ou reservado');
    final tipo = n['tipo'];
    if (!tiposDeCaixa.contains(tipo)) {
      aqui('tipo desconhecido ($tipo)');
      continue;
    }
    if (n.containsKey('prazo') && !_duracaoValida(_t(n['prazo']))) aqui('prazo inválido (use 30m, 2h ou 1d)');
    final regras = <({String campo, String op, Object? valor})>[];
    switch (tipo) {
      case 'executar':
        if (_t(n['instrucao']).isEmpty) aqui('instrução obrigatória');
        if (n.containsKey('saidas')) {
          final saidas = _lerSaidas(n['saidas'], (m) => aqui('saídas: $m'));
          if (saidas.containsKey('devolutiva')) aqui('"devolutiva" é reservada');
          saidasValidas[id] = saidas;
        }
      case 'revisar' || 'aprovar':
        final por = n['por'] is Map ? n['por'] as Map : const {};
        final valido = _t(por['posicao']).isNotEmpty ||
            (tipo == 'revisar' && por['board'] == true) ||
            (tipo == 'aprovar' && por['ueslei'] == true);
        if (!valido) aqui('quem decide é inválido');
      case 'decisao_humana':
        if (_t(n['pergunta']).isEmpty) aqui('pergunta obrigatória');
        _conferirOpcoes(n['opcoes'], aqui);
      case 'condicao':
        final brutas = n['regras'];
        if (brutas is! List || brutas.isEmpty) aqui('precisa de pelo menos uma regra');
        for (final (i, r) in (brutas is List ? brutas : const []).indexed) {
          final saida = r is Map ? _t(r['saida']) : '';
          if (saida.isEmpty || saida == quandoSenao) aqui('regra ${i + 1}: saída obrigatória e diferente de "senao"');
          final regra = _lerRegra(r, (m) => aqui('regra ${i + 1}: $m'));
          if (regra != null) regras.add(regra);
        }
      case 'laco':
        final max = n['maxVoltas'];
        if (!_inteiro(max) || (max as num) < 1 || max > maxVoltasDoLaco) aqui('máximo de voltas obrigatório, de 1 a $maxVoltasDoLaco');
        final regra = _lerRegra(n['enquanto'], (m) => aqui('enquanto: $m'));
        if (regra != null) regras.add(regra);
      case 'espera':
        final formas = formasDeEspera.where(n.containsKey).length;
        if (formas != 1) aqui('use exatamente um de duração, horário e sinal');
        if (n.containsKey('duracao') && !_duracaoValida(_t(n['duracao']))) aqui('duração inválida (use 30m, 2h ou 1d)');
        if (n.containsKey('ate') && !_horario.hasMatch(_t(n['ate']))) aqui('horário inválido (use HH:MM)');
        if (n.containsKey('sinal') && _t(n['sinal']).isEmpty) aqui('sinal vazio');
      case 'board':
        if (_t(n['pauta']).isEmpty) aqui('pauta obrigatória');
        if (n.containsKey('opcoes')) _conferirOpcoes(n['opcoes'], aqui);
    }
    regrasValidas[id] = regras;
  }

  final inicio = _t(w['inicio']);
  if (!grafo.porId.containsKey(inicio)) doWorkflow('início inexistente (${inicio.isEmpty ? 'vazio' : inicio})');
  final arestas = arestasDe(w);
  for (final a in arestas) {
    if (!grafo.porId.containsKey(_t(a['de']))) doWorkflow('ligação de caixa inexistente (${_t(a['de'])})');
    if (!grafo.porId.containsKey(_t(a['para']))) doWorkflow('ligação para caixa inexistente (${_t(a['para'])})');
  }

  for (final MapEntry(key: id, value: n) in grafo.porId.entries) {
    void aqui(String m) => erro(id, m);
    final tipo = n['tipo'];
    if (!tiposDeCaixa.contains(tipo)) continue;
    final minhas = [for (final a in arestas) if (_t(a['de']) == id) a];
    if (tipo == 'paralelo') {
      if (minhas.length < 2) aqui('o paralelo precisa de 2 ou mais ligações');
      if (minhas.any((a) => _quando(a) != null)) aqui('ligações do paralelo não têm "quando"');
    } else {
      final esperadas = _quandosDe(n);
      final usadas = [for (final a in minhas) _quando(a)];
      for (final q in usadas) {
        if (!esperadas.contains(q)) aqui('ligação com "quando" inválido (${q ?? 'vazio'})');
      }
      for (final q in esperadas) {
        final quantas = usadas.where((u) => u == q).length;
        final nome = q == null ? 'de saída' : '"$q"';
        if (quantas == 0) aqui('falta a ligação $nome');
        if (quantas > 1) aqui('ligação $nome repetida');
      }
    }
    if (tipo == 'juncao' && (grafo.entram[id] ?? 0) < 2) aqui('a junção precisa de 2 ou mais ligações entrando');
    if (tipo == 'executar' && equipe.posicao(_t(n['posicao'])) == null) {
      aqui('posição inexistente (${_t(n['posicao']).isEmpty ? 'vazio' : _t(n['posicao'])})');
    }
    if (tipo == 'revisar' || tipo == 'aprovar') {
      final de = grafo.porId[_t(n['de'])];
      if (de == null || de['tipo'] != 'executar') {
        aqui('"de" precisa ser uma caixa executar (${_t(n['de']).isEmpty ? 'vazio' : _t(n['de'])})');
      } else {
        if (!correnteDe(w, de['id'] as String).any((c) => c['id'] == id)) {
          aqui('precisa vir logo depois de ${de['id']} (ou de outra revisão dele)');
        }
        final executora = equipe.posicao(_t(de['posicao']))?.persona;
        final por = n['por'] is Map ? n['por'] as Map : const {};
        final ref = _t(por['posicao']);
        if (ref.isNotEmpty) {
          final alvo = equipe.posicao(ref);
          if (alvo == null) {
            aqui('posição inexistente ($ref)');
          } else if (alvo.persona != null && alvo.persona == executora) {
            aqui('${alvo.personaNome ?? alvo.persona} revisaria o próprio trabalho');
          }
        } else if (tipo == 'revisar' && por['board'] == true && membrosDoBoard(equipe, executora).isEmpty) {
          aqui('o board da equipe não tem membros');
        }
      }
    }
    if (tipo == 'board' && membrosDoBoard(equipe, null).isEmpty) aqui('o board da equipe não tem membros');
  }

  for (final MapEntry(key: id, value: n) in grafo.porId.entries) {
    if (n['tipo'] != 'executar') continue;
    final cadeia = correnteDe(w, id);
    final aprovacoes = cadeia.where((c) => c['tipo'] == 'aprovar').length;
    if (aprovacoes > 1) {
      erro(id, 'só pode haver uma aprovação');
    } else if (aprovacoes == 1 && cadeia.last['tipo'] != 'aprovar') {
      erro(id, 'a aprovação precisa ser a última');
    }
  }

  if (grafo.porId.containsKey(inicio)) {
    final alcancados = grafo.alcancaveis(inicio);
    for (final id in grafo.porId.keys) {
      if (!alcancados.contains(id)) erro(id, 'não é alcançável a partir do início');
    }
  }
  final semLaco = {
    for (final MapEntry(:key, :value) in grafo.saida.entries)
      if (grafo.porId[key]?['tipo'] != 'laco') key: value,
  };
  if (_temCiclo(grafo.porId.keys, semLaco)) doWorkflow('há um ciclo que não passa por um laço');
  for (final laco in grafo.porId.values.where((n) => n['tipo'] == 'laco')) {
    final idDoLaco = laco['id'] as String;
    final repetir = arestas.where((a) => _t(a['de']) == idDoLaco && _quando(a) == 'repetir').firstOrNull;
    if (repetir == null) continue;
    final corpo = grafo
        .alcancaveis(_t(repetir['para']), evitar: idDoLaco)
        .where((id) => grafo.alcancaveis(id).contains(idDoLaco));
    for (final id in corpo) {
      final tipo = grafo.porId[id]?['tipo'];
      if (tipo == 'paralelo' || tipo == 'juncao') erro(id, 'paralelo e junção não podem ficar dentro do laço $idDoLaco');
    }
  }

  Map<String, TipoDeValor> saidasDe(Map<String, dynamic> no) {
    final base = saidasDaCaixa(no);
    if (no['tipo'] != 'executar') return base;
    return {'devolutiva': const TipoDeValor.texto(), ...?saidasValidas[no['id']]};
  }

  for (final MapEntry(key: id, value: n) in grafo.porId.entries) {
    void aqui(String m) => erro(id, m);
    void conferir(String no, String campo, String contexto) {
      if (no == 'entrada') {
        if (!entrada.containsKey(campo)) aqui('$contexto usa entrada.$campo, que não existe');
        return;
      }
      final outro = grafo.porId[no];
      if (outro == null) {
        aqui('$contexto usa a caixa inexistente $no');
      } else if (!saidasDe(outro).containsKey(campo)) {
        aqui('$contexto usa $no.$campo, que não é saída de $no');
      } else if (!grafo.vemAntes(no, id)) {
        aqui('$contexto usa $no, que não vem antes');
      }
    }

    for (final campo in _textosDoTipo(n['tipo'])) {
      for (final m in _referencia.allMatches(_t(n[campo]))) {
        conferir(m[1]!, m[2]!, 'o texto');
      }
    }
    for (final regra in regrasValidas[id] ?? const <({String campo, String op, Object? valor})>[]) {
      final m = _campoDeRegra.firstMatch(regra.campo)!;
      conferir(m[1]!, m[2]!, 'a regra');
      final no = m[1] == 'entrada' ? null : grafo.porId[m[1]];
      final tipo = m[1] == 'entrada' ? entrada[m[2]] : (no == null ? null : saidasDe(no)[m[2]]);
      if (tipo == null) continue;
      if ((regra.op == 'maior' || regra.op == 'menor') && tipo.nome != 'numero') aqui('"${nomesDeOp[regra.op]}" só vale para número');
      if (tipo.nome == 'numero' && regra.valor != null && regra.valor is! num) aqui('o valor precisa ser número');
      if (tipo.nome == 'booleano' && regra.valor != null && regra.valor is! bool) aqui('o valor precisa ser sim ou não');
      if (tipo.escolha && regra.op == 'igual' && !tipo.escolhas.contains('${regra.valor}')) {
        aqui('${regra.valor} não é uma das escolhas de ${regra.campo}');
      }
    }
  }
  return erros;
}

List<String> _textosDoTipo(Object? tipo) => switch (tipo) {
      'executar' => const ['instrucao', 'criterio'],
      'decisao_humana' => const ['pergunta'],
      'board' => const ['pauta'],
      _ => const [],
    };

bool _temCiclo(Iterable<String> ids, Map<String, List<String>> saida) {
  final estado = <String, int>{};
  bool visitar(String id) {
    if (estado[id] == 1) return true;
    if (estado[id] == 2) return false;
    estado[id] = 1;
    for (final prox in saida[id] ?? const <String>[]) {
      if (visitar(prox)) return true;
    }
    estado[id] = 2;
    return false;
  }

  return ids.any(visitar);
}

int contarErros(ErrosDoWorkflow erros) => erros.values.fold(0, (soma, lista) => soma + lista.length);

// ── campos tipados (saídas do executar e entrada do workflow) ──────

typedef CampoTipado = ({String nome, Object? tipo});

const tiposDeCampo = ['texto', 'numero', 'booleano', 'escolha'];

const nomesDeTipoDeCampo = {'texto': 'texto', 'numero': 'número', 'booleano': 'sim/não', 'escolha': 'escolha'};

List<CampoTipado> camposTipados(Object? bruto) => [
      if (bruto is Map)
        for (final MapEntry(:key, :value) in bruto.entries) (nome: key as String, tipo: copiaProfunda(value)),
    ];

String tipoDoCampoTipado(Object? tipo) => tipo is Map ? 'escolha' : (tiposDeCampo.contains(tipo) ? tipo as String : 'texto');

List<String> escolhasDoCampoTipado(Object? tipo) =>
    tipo is Map && tipo['escolha'] is List ? [for (final x in tipo['escolha'] as List) if (x is String) x] : const [];

Object? tipoComEscolhas(String texto) => {
      'escolha': [for (final p in texto.split(',')) if (p.trim().isNotEmpty) p.trim()],
    };

Object? tipoPadrao(String tipo) => tipo == 'escolha'
    ? {
        'escolha': ['opção 1', 'opção 2'],
      }
    : tipo;

String nomeDeCampoLivre(Iterable<String> usados) {
  final ocupados = usados.toSet();
  for (var n = 1;; n++) {
    final nome = n == 1 ? 'campo' : 'campo$n';
    if (!ocupados.contains(nome)) return nome;
  }
}

Map<String, dynamic> _mapaDeCampos(List<CampoTipado> campos) {
  final mapa = <String, dynamic>{};
  for (final c in campos) {
    if (mapa.containsKey(c.nome)) throw ErroDeWorkflow('Já existe um campo ${c.nome}.');
    mapa[c.nome] = copiaProfunda(c.tipo);
  }
  return mapa;
}

WorkflowJson definirSaidas(WorkflowJson w, String id, List<CampoTipado> campos) {
  final mapa = _mapaDeCampos(campos);
  return editarCaixa(w, id, (caixa) {
    if (mapa.isEmpty) {
      caixa.remove('saidas');
    } else {
      caixa['saidas'] = mapa;
    }
  });
}

WorkflowJson definirEntrada(WorkflowJson w, List<CampoTipado> campos) {
  final mapa = _mapaDeCampos(campos);
  return editarWorkflow(w, (c) => c['entrada'] = mapa);
}

// ── geometria do canvas ────────────────────────────────────────────

const raioDoPonto = 6.0;

typedef Curva = ({Ponto p0, Ponto p1, Ponto p2, Ponto p3});

Map<String, List<PontoDeSaida>> pontosDoRascunho(WorkflowJson w) => {for (final id in idsDe(w)) id: pontosDeSaida(w, id)};

Ponto pontoDaSaida(Map<String, Ponto> layout, String id, int indice, int total) {
  final c = cantoDaCaixa(layout, id);
  return (x: c.x + larguraDaCaixa, y: c.y + alturaDaCaixa * (indice + 1) / (total + 1));
}

Ponto origemDaLigacao(Map<String, Ponto> layout, Map<String, List<PontoDeSaida>> pontos, Aresta a) {
  final lista = pontos[a.de] ?? const <PontoDeSaida>[];
  final i = lista.indexWhere((p) => p.varias || p.quando == a.quando);
  if (i >= 0) return pontoDaSaida(layout, a.de, i, lista.length);
  final c = cantoDaCaixa(layout, a.de);
  return (x: c.x + larguraDaCaixa, y: c.y + alturaDaCaixa / 2);
}

Curva curvaDaLigacao(Map<String, Ponto> layout, Ponto origem, String para) {
  final alvo = cantoDaCaixa(layout, para);
  final p3 = (x: alvo.x, y: alvo.y + alturaDaCaixa / 2);
  if (p3.x > origem.x + 20) {
    final meio = (p3.x - origem.x) / 2;
    return (p0: origem, p1: (x: origem.x + meio, y: origem.y), p2: (x: p3.x - meio, y: p3.y), p3: p3);
  }
  final baixo = (origem.y > p3.y ? origem.y : p3.y) + alturaDaCaixa;
  return (p0: origem, p1: (x: origem.x + 80, y: baixo), p2: (x: p3.x - 80, y: baixo), p3: p3);
}

Ponto pontoNaCurva(Curva c, double t) {
  final u = 1 - t;
  final a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t;
  return (
    x: a * c.p0.x + b * c.p1.x + d * c.p2.x + e * c.p3.x,
    y: a * c.p0.y + b * c.p1.y + d * c.p2.y + e * c.p3.y,
  );
}

double _distancia(Ponto p, Ponto a, Ponto b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final tamanho = dx * dx + dy * dy;
  final t = tamanho == 0 ? 0.0 : (((p.x - a.x) * dx + (p.y - a.y) * dy) / tamanho).clamp(0.0, 1.0);
  final x = a.x + t * dx - p.x, y = a.y + t * dy - p.y;
  return x * x + y * y;
}

Aresta? arestaEm(
  List<Aresta> arestas,
  Map<String, Ponto> layout,
  Map<String, List<PontoDeSaida>> pontos,
  double x,
  double y, {
  double tolerancia = 6,
}) {
  final p = (x: x, y: y);
  Aresta? melhor;
  var menor = tolerancia * tolerancia;
  for (final a in arestas) {
    if (!layout.containsKey(a.de) || !layout.containsKey(a.para)) continue;
    final curva = curvaDaLigacao(layout, origemDaLigacao(layout, pontos, a), a.para);
    var anterior = curva.p0;
    for (var i = 1; i <= 24; i++) {
      final atual = pontoNaCurva(curva, i / 24);
      final d = _distancia(p, anterior, atual);
      if (d <= menor) {
        menor = d;
        melhor = a;
      }
      anterior = atual;
    }
  }
  return melhor;
}

({String caixa, int indice})? saidaEm(
  Map<String, Ponto> layout,
  Map<String, List<PontoDeSaida>> pontos,
  double x,
  double y, {
  double raio = raioDoPonto + 4,
}) {
  for (final MapEntry(key: id, value: lista) in pontos.entries) {
    if (!layout.containsKey(id)) continue;
    for (var i = 0; i < lista.length; i++) {
      final c = pontoDaSaida(layout, id, i, lista.length);
      if ((c.x - x) * (c.x - x) + (c.y - y) * (c.y - y) <= raio * raio) return (caixa: id, indice: i);
    }
  }
  return null;
}

// ── desfazer ───────────────────────────────────────────────────────

class Historico<T> {
  Historico(this.atual);

  static const limite = 100;

  T atual;
  final _antes = <T>[];
  final _depois = <T>[];

  bool get podeDesfazer => _antes.isNotEmpty;
  bool get podeRefazer => _depois.isNotEmpty;

  void fazer(T novo) {
    _antes.add(atual);
    if (_antes.length > limite) _antes.removeAt(0);
    _depois.clear();
    atual = novo;
  }

  bool desfazer() {
    if (_antes.isEmpty) return false;
    _depois.add(atual);
    atual = _antes.removeLast();
    return true;
  }

  bool refazer() {
    if (_depois.isEmpty) return false;
    _antes.add(atual);
    atual = _depois.removeLast();
    return true;
  }
}
