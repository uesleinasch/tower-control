import 'dart:convert';
import 'dart:io';

import 'package:control_tower/nucleo/editor_de_workflow.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/nucleo/workflows.dart';
import 'package:flutter_test/flutter_test.dart';

final _casos = jsonDecode(File('../docs/workflows-casos.json').readAsStringSync()) as Map<String, dynamic>;

EquipeResumo _equipe(String id) {
  final j = (_casos['equipes'] as Map<String, dynamic>)[id] as Map<String, dynamic>;
  return EquipeResumo.deJson(j);
}

WorkflowJson _base(String nome) => copiaProfunda((_casos['bases'] as Map<String, dynamic>)[nome]) as WorkflowJson;

WorkflowJson _aplicar(WorkflowJson alvo, List<dynamic> mudancas) {
  ({dynamic pai, Object chave}) ate(String caminho) {
    final passos = [for (final p in caminho.split('.')) int.tryParse(p) ?? p];
    dynamic atual = alvo;
    for (final p in passos.sublist(0, passos.length - 1)) {
      atual = atual[p];
    }
    return (pai: atual, chave: passos.last);
  }

  for (final m in mudancas.cast<Map<String, dynamic>>()) {
    if (m['definir'] is String) {
      final (:pai, :chave) = ate(m['definir'] as String);
      pai[chave] = copiaProfunda(m['valor']);
    } else if (m['acrescentar'] is String) {
      final (:pai, :chave) = ate(m['acrescentar'] as String);
      (pai[chave] as List).add(copiaProfunda(m['valor']));
    } else if (m['remover'] is String) {
      final (:pai, :chave) = ate(m['remover'] as String);
      if (pai is List) {
        pai.removeAt(chave as int);
      } else {
        (pai as Map).remove(chave);
      }
    }
  }
  return alvo;
}

Map<String, dynamic> _normalizado(WorkflowJson w) {
  String chave(Object? v) => jsonEncode(v);
  final c = copiaProfunda(w) as WorkflowJson;
  c.remove('layout');
  c.remove('versao');
  c['nos'] = [...nosDe(c)]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  c['arestas'] = [...arestasDe(c)]..sort((a, b) => chave(a).compareTo(chave(b)));
  return c;
}

void main() {
  final casa = _equipe('casa');

  group('validação espelhada', () {
    for (final caso in (_casos['casos'] as List).cast<Map<String, dynamic>>()) {
      test(caso['nome'], () {
        final w = _aplicar(_base(caso['base'] as String), (caso['mudar'] as List?) ?? const []);
        final erros = validarRascunho(w, _equipe((caso['equipe'] as String?) ?? 'casa'));
        final esperados = (caso['erros'] as List).cast<String>();
        if (esperados.isEmpty) expect(erros, isEmpty);
        for (final lugar in esperados) {
          expect(erros.keys, contains(lugar), reason: 'erros: $erros');
        }
      });
    }
  });

  test('montar o exemplo só com operações do núcleo', () {
    var w = novoWorkflow('Mudança com plano', const []);
    expect(w['id'], 'mudanca-com-plano');
    w = editarWorkflow(w, (c) => c['entrada'] = {'pedido': 'texto'});
    w = renomearCaixa(w, 'executar', 'plano');
    w = definirCampo(w, 'plano', 'posicao', 'conselho-nati');
    w = definirCampo(w, 'plano', 'instrucao', 'Escreva um plano para: {{entrada.pedido}}');
    w = definirCampo(w, 'plano', 'criterio', 'Passos numerados e os riscos.');
    w = definirCampo(w, 'plano', 'saidas', {
      'plano': 'texto',
      'risco': {
        'escolha': ['baixo', 'alto'],
      },
    });

    var criado = criarDepois(w, 'plano', null, 'condicao');
    w = renomearCaixa(criado.workflow, criado.id, 'risco');
    expect(referenciasDisponiveis(w, 'risco').map((r) => r.campoDaRegra), containsAll(['entrada.pedido', 'plano.risco']));
    expect(opsPara(tipoDoCampo(w, 'plano.risco')), isNot(contains('maior')));
    w = definirRegra(w, 'risco', 0, {'campo': 'plano.risco', 'op': 'igual', 'valor': 'alto', 'saida': 'alto'});

    criado = criarDepois(w, 'risco', 'alto', 'decisao_humana');
    w = renomearCaixa(criado.workflow, criado.id, 'ok');
    w = definirCampo(w, 'ok', 'pergunta', 'Risco alto. Seguir?');
    w = renomearOpcao(w, 'ok', 0, 'seguir');
    w = renomearOpcao(w, 'ok', 1, 'parar');

    criado = criarDepois(w, 'ok', 'seguir', 'paralelo');
    w = renomearCaixa(criado.workflow, criado.id, 'frente');
    w = ligar(w, 'risco', 'senao', 'frente');

    criado = criarDepois(w, 'frente', null, 'executar');
    w = renomearCaixa(criado.workflow, criado.id, 'executa');
    w = definirCampo(w, 'executa', 'posicao', 'executor');
    w = definirCampo(w, 'executa', 'instrucao', 'Execute: {{plano.plano}}');

    criado = criarDepois(w, 'executa', null, 'revisar');
    w = renomearCaixa(criado.workflow, criado.id, 'revisa');
    expect(caixaDe(w, 'revisa')!['de'], 'executa');
    w = definirCampo(w, 'revisa', 'por', {'posicao': 'conselho-nati'});

    criado = criarDepois(w, 'frente', null, 'executar');
    w = renomearCaixa(criado.workflow, criado.id, 'nota');
    w = definirCampo(w, 'nota', 'posicao', 'conselho-pami');
    w = definirCampo(w, 'nota', 'instrucao', 'Escreva a nota de mudança de: {{plano.plano}}');
    expect(referenciasDisponiveis(w, 'nota').map((r) => r.caixa), isNot(contains('executa')));

    criado = criarDepois(w, 'revisa', 'aprovado', 'juncao');
    w = renomearCaixa(criado.workflow, criado.id, 'junta');
    w = ligar(w, 'nota', null, 'junta');
    final fim = arestasDe(w).firstWhere((a) => a['de'] == 'plano');
    expect(fim['para'], 'risco');
    w = ligar(w, 'junta', null, 'fim');

    criado = criarDepois(w, 'ok', 'parar', 'fim');
    w = renomearCaixa(criado.workflow, criado.id, 'parou');
    w = definirCampo(w, 'parou', 'resultado', 'cancelado pelo Ueslei');

    expect(validarRascunho(w, casa), isEmpty);
    expect(_normalizado(w), _normalizado(_base('exemplo')));
    expect((w['layout'] as Map).keys, containsAll(idsDe(w)));
  });

  test('renomear troca o id em ligações, início, layout, de, regras e referências', () {
    var w = comLayoutCompleto(_base('exemplo'));
    w = renomearCaixa(w, 'plano', 'planejar');
    expect(w['inicio'], 'planejar');
    expect((w['layout'] as Map).containsKey('planejar'), isTrue);
    expect(arestasDe(w).first['de'], 'planejar');
    expect(regrasDe(caixaDe(w, 'risco')!).first['campo'], 'planejar.risco');
    expect(caixaDe(w, 'executa')!['instrucao'], 'Execute: {{planejar.plano}}');
    w = renomearCaixa(w, 'executa', 'fazer');
    expect(caixaDe(w, 'revisa')!['de'], 'fazer');
    expect(validarRascunho(w, casa), isEmpty);
    expect(() => renomearCaixa(w, 'fazer', 'nota'), throwsA(isA<ErroDeWorkflow>()));
    expect(() => renomearCaixa(w, 'fazer', 'Fazer'), throwsA(isA<ErroDeWorkflow>()));
    expect(() => renomearCaixa(w, 'fazer', 'entrada'), throwsA(isA<ErroDeWorkflow>()));
  });

  test('pontos de saída de cada tipo', () {
    final w = _base('exemplo');
    expect(pontosDeSaida(w, 'plano').map((p) => p.quando), [null]);
    expect(pontosDeSaida(w, 'risco').map((p) => p.quando), ['alto', 'senao']);
    expect(pontosDeSaida(w, 'ok').map((p) => '${p.quando}>${p.destinos.join(',')}'), ['seguir>frente', 'parar>parou']);
    expect(pontosDeSaida(w, 'frente').single.varias, isTrue);
    expect(pontosDeSaida(w, 'frente').single.destinos, ['executa', 'nota']);
    expect(pontosDeSaida(w, 'revisa').map((p) => p.quando), ['aprovado']);
    expect(pontosDeSaida(w, 'fim'), isEmpty);
    expect(pontosDeSaida(_base('laco'), 'volta').map((p) => p.quando), ['repetir', 'sair']);
    var e = criarCaixa(w, 'espera', (x: 0, y: 0));
    expect(pontosDeSaida(e.workflow, e.id).map((p) => p.quando), ['pronto']);
    final comPrazo = definirCampo(e.workflow, e.id, 'prazo', '1d');
    expect(pontosDeSaida(comPrazo, e.id).map((p) => p.quando), ['pronto', 'prazo']);
    e = criarCaixa(w, 'board', (x: 0, y: 0));
    expect(pontosDeSaida(e.workflow, e.id).map((p) => p.quando), [null]);
    expect(pontosDeSaida(acrescentarOpcao(acrescentarOpcao(e.workflow, e.id, 'a'), e.id, 'b'), e.id).map((p) => p.quando), ['a', 'b']);
  });

  test('ligar troca o destino da saída, o paralelo acumula e desligar remove', () {
    var w = _base('exemplo');
    w = ligar(w, 'ok', 'parar', 'fim');
    expect(pontosDeSaida(w, 'ok').last.destinos, ['fim']);
    expect(arestasDe(w).where((a) => a['de'] == 'ok').length, 2);
    w = ligar(w, 'frente', null, 'fim');
    expect(pontosDeSaida(w, 'frente').single.destinos, ['executa', 'nota', 'fim']);
    expect(ligar(w, 'frente', null, 'fim'), same(w));
    expect(ligar(w, 'plano', null, 'plano'), same(w));
    w = desligar(w, const Aresta(de: 'frente', para: 'fim'));
    expect(pontosDeSaida(w, 'frente').single.destinos, ['executa', 'nota']);
    w = desligar(w, const Aresta(de: 'ok', para: 'fim', quando: 'parar'));
    expect(pontosDeSaida(w, 'ok').last.livre, isTrue);
  });

  test('revisão depois de revisão herda o de', () {
    var w = _base('exemplo');
    final criado = criarDepois(w, 'revisa', 'aprovado', 'aprovar');
    w = criado.workflow;
    expect(caixaDe(w, criado.id)!['de'], 'executa');
    expect(correnteDe(w, 'executa').map((c) => c['id']), ['revisa', criado.id]);
  });

  test('renomear e remover opção e regra levam as ligações junto', () {
    var w = _base('exemplo');
    w = renomearOpcao(w, 'ok', 1, 'abortar');
    expect(arestasDe(w).any((a) => a['de'] == 'ok' && a['quando'] == 'abortar'), isTrue);
    w = removerOpcao(w, 'ok', 1);
    expect(arestasDe(w).where((a) => a['de'] == 'ok').map((a) => a['quando']), ['seguir']);
    w = definirRegra(w, 'risco', 0, {'campo': 'plano.risco', 'op': 'igual', 'valor': 'alto', 'saida': 'perigo'});
    expect(arestasDe(w).any((a) => a['de'] == 'risco' && a['quando'] == 'perigo'), isTrue);
    w = acrescentarRegra(w, 'risco');
    expect(regrasDe(caixaDe(w, 'risco')!).last['saida'], 'saida');
    w = removerRegra(w, 'risco', 0);
    expect(arestasDe(w).where((a) => a['de'] == 'risco').map((a) => a['quando']), ['senao']);
  });

  test('remover caixa leva ligações e layout; definirCampo opcional vazio remove a chave', () {
    var w = comLayoutCompleto(_base('exemplo'));
    w = removerCaixa(w, 'nota');
    expect(caixaDe(w, 'nota'), isNull);
    expect(arestasDe(w).any((a) => a['de'] == 'nota' || a['para'] == 'nota'), isFalse);
    expect((w['layout'] as Map).containsKey('nota'), isFalse);
    w = definirCampo(w, 'plano', 'criterio', '  ');
    expect(caixaDe(w, 'plano')!.containsKey('criterio'), isFalse);
    w = definirCampo(w, 'plano', 'instrucao', '');
    expect(caixaDe(w, 'plano')!['instrucao'], '');
    w = removerCaixa(w, 'plano');
    expect(w['inicio'], '');
    expect(validarRascunho(w, casa)[lugarDoWorkflow], contains('início inexistente (vazio)'));
  });

  test('a espera troca de forma sem sobrar a anterior', () {
    final e = criarCaixa(_base('exemplo'), 'espera', (x: 0, y: 0));
    final w = definirEspera(e.workflow, e.id, 'sinal', 'deploy');
    expect(caixaDe(w, e.id), {'id': e.id, 'tipo': 'espera', 'sinal': 'deploy'});
  });

  test('o rascunho preserva o que o editor não conhece e tira o que o servidor acrescenta', () {
    final bruto = _base('exemplo')
      ..['descricao'] = 'à mão'
      ..['equipe'] = 'casa'
      ..['textosEmArquivo'] = {
        'plano': {'instrucao': 'plano.md'},
      };
    (bruto['nos'] as List).first['cor'] = 'azul';
    final w = Workflow.deJson(jsonDecode(jsonEncode(bruto)) as Map<String, dynamic>);
    final r = rascunhoDe(w);
    expect(r['descricao'], 'à mão');
    expect(r.containsKey('equipe'), isFalse);
    expect(r.containsKey('textosEmArquivo'), isFalse);
    expect(caixaDe(definirCampo(r, 'plano', 'instrucao', 'outra'), 'plano')!['cor'], 'azul');
    expect(textosEmArquivoDe(w), {
      'plano': {'instrucao': 'plano.md'},
    });
  });

  test('novo e duplicar', () {
    final w = novoWorkflow('Relatório', ['relatorio']);
    expect(w['id'], 'relatorio-2');
    expect(w['inicio'], 'executar');
    final erros = validarRascunho(w, casa);
    expect(erros.keys, ['executar']);
    final d = duplicarWorkflow(_base('exemplo'), ['mudanca-com-plano']);
    expect(d['nome'], 'Mudança com plano (cópia)');
    expect(d['id'], 'mudanca-com-plano-copia');
    expect(d['versao'], 0);
    expect(() => novoWorkflow('  ', const []), throwsA(isA<ErroDeWorkflow>()));
  });

  test('saídas e entrada tipadas vão e voltam, e nome repetido é recusado', () {
    var w = _base('exemplo');
    final saidas = camposTipados(caixaDe(w, 'plano')!['saidas']);
    expect(saidas.map((c) => '${c.nome}:${tipoDoCampoTipado(c.tipo)}'), ['plano:texto', 'risco:escolha']);
    expect(escolhasDoCampoTipado(saidas.last.tipo), ['baixo', 'alto']);
    w = definirSaidas(w, 'plano', [...saidas, (nome: nomeDeCampoLivre(saidas.map((c) => c.nome)), tipo: tipoPadrao('numero'))]);
    expect(saidasDeclaradas(caixaDe(w, 'plano')!).keys, ['plano', 'risco', 'campo']);
    expect(() => definirSaidas(w, 'plano', [(nome: 'a', tipo: 'texto'), (nome: 'a', tipo: 'numero')]), throwsA(isA<ErroDeWorkflow>()));
    expect(caixaDe(definirSaidas(w, 'plano', const []), 'plano')!.containsKey('saidas'), isFalse);
    w = definirEntrada(w, [(nome: 'pedido', tipo: 'texto'), (nome: 'nivel', tipo: tipoComEscolhas(' a, b ,, c'))]);
    expect(entradaDe(w)['nivel']!.escolhas, ['a', 'b', 'c']);
  });

  test('geometria: pontos na borda direita, linha e ponto sob o cursor', () {
    final w = comLayoutCompleto(_base('exemplo'));
    final layout = layoutDoRascunho(w);
    final pontos = pontosDoRascunho(w);
    final canto = cantoDaCaixa(layout, 'ok');
    final seguir = pontoDaSaida(layout, 'ok', 0, 2);
    final parar = pontoDaSaida(layout, 'ok', 1, 2);
    expect([seguir.x, parar.x], [canto.x + larguraDaCaixa, canto.x + larguraDaCaixa]);
    expect(seguir.y < parar.y, isTrue);
    expect(saidaEm(layout, pontos, parar.x + 2, parar.y - 2), (caixa: 'ok', indice: 1));
    expect(saidaEm(layout, pontos, canto.x + 10, canto.y + 10), isNull);
    final arestas = Workflow.deJson(w).arestas;
    final ligacao = arestas.firstWhere((a) => a.de == 'ok' && a.quando == 'parar');
    final meio = pontoNaCurva(curvaDaLigacao(layout, origemDaLigacao(layout, pontos, ligacao), ligacao.para), 0.5);
    final achada = arestaEm(arestas, layout, pontos, meio.x, meio.y + 2);
    expect([achada?.de, achada?.para, achada?.quando], ['ok', 'parou', 'parar']);
    expect(arestaEm(arestas, layout, pontos, -500, -500), isNull);
  });

  test('desfazer e refazer', () {
    final h = Historico<int>(0);
    h.fazer(1);
    h.fazer(2);
    expect(h.desfazer(), isTrue);
    expect(h.atual, 1);
    expect(h.refazer(), isTrue);
    expect(h.atual, 2);
    h.desfazer();
    h.fazer(5);
    expect(h.podeRefazer, isFalse);
    expect(h.atual, 5);
  });

  test('ligar sem arrastar: destinos de cada saída e ligações que saem', () {
    final w = _base('exemplo');
    final ok = pontosDeSaida(w, 'ok');
    expect(destinosDaSaida(w, 'ok', ok.first), isNot(contains('ok')));
    expect(destinosDaSaida(w, 'ok', ok.first), isNot(contains('frente')));
    expect(destinosDaSaida(w, 'ok', ok.first), containsAllInOrder(['plano', 'risco', 'parou']));
    final frente = pontosDeSaida(w, 'frente').single;
    expect(destinosDaSaida(w, 'frente', frente), ['plano', 'risco', 'ok', 'revisa', 'junta', 'fim', 'parou']);
    expect(destinosDaSaida(w, 'nada', frente), isEmpty);
    final novo = ligar(w, 'ok', 'seguir', destinosDaSaida(w, 'ok', ok.first).first);
    expect(pontosDeSaida(novo, 'ok').first.destinos, ['plano']);

    expect(ligacoesQueSaem(w, 'ok').map((a) => '${a.para}/${a.quando}'), ['frente/seguir', 'parou/parar']);
    expect(ligacoesQueSaem(w, 'fim'), isEmpty);
    final sem = desligar(w, ligacoesQueSaem(w, 'ok').last);
    expect(pontosDeSaida(sem, 'ok').last.livre, isTrue);
  });

  test('deslocar a caixa pelo teclado parte do layout calculado', () {
    final w = _base('exemplo');
    final antes = layoutDoRascunho(w)['risco']!;
    final depois = deslocarCaixa(w, 'risco', 20, -20);
    expect(layoutDoRascunho(depois)['risco'], (x: antes.x + 20, y: antes.y - 20));
    expect(layoutDoRascunho(depois)['plano'], layoutDoRascunho(w)['plano']);
    expect(() => deslocarCaixa(w, 'nada', 20, 0), throwsA(isA<ErroDeWorkflow>()));
  });

  test('vistaComCaixa só desloca a vista quando a caixa sai da tela', () {
    final layout = {'a': (x: 0.0, y: 0.0), 'b': (x: 900.0, y: 0.0)};
    const v = (dx: 0.0, dy: 0.0, escala: 1.0);
    expect(vistaComCaixa(v, layout, 'a', 800, 600), v);
    final longe = vistaComCaixa(v, layout, 'b', 800, 600);
    final canto = cantoDaCaixa(layout, 'b');
    expect(canto.x + larguraDaCaixa + longe.dx, 800 - 24);
    expect(longe.dy, 0);
    expect(vistaComCaixa(v, layout, 'nada', 800, 600), v);
  });

  test('o estado do fluxo esperando aparece como na fila', () {
    expect(estadoDoFluxo('esperando'), 'na_fila');
    expect(estadoDoFluxo('rodando'), 'rodando');
    expect(estadoDoFluxo('concluido'), 'concluido');
  });
}
