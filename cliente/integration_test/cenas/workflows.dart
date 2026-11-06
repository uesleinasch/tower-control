import 'dart:convert';
import 'dart:math';

import 'package:control_tower/estado/equipes.dart';
import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/nucleo/editor_de_workflow.dart';
import 'package:control_tower/tela/workflows.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/acoes.dart';
import '../apoio/ambiente.dart';
import '../apoio/app.dart';
import '../apoio/esperas.dart';
import '../apoio/falsos.dart';
import '../apoio/grafo.dart';

const _instrucaoDoExecutor = 'Classifique a prioridade da demanda: {{entrada.dados}}';
const _instrucaoDaNati = 'Nati, analise a demanda: {{entrada.dados}}';
const _instrucaoDoPoe = 'Poe, analise a demanda: {{entrada.dados}}';
const _prazoDoFluxo = Duration(seconds: 90);

const _caixasDaTriagem = <String, Map<String, Object?>>{
  'executar': {
    'id': 'executar',
    'tipo': 'executar',
    'titulo': 'Classificar',
    'posicao': 'executor',
    'instrucao': _instrucaoDoExecutor,
    'saidas': {
      'prioridade': {
        'escolha': ['alta', 'baixa'],
      },
    },
  },
  'condicao': {
    'id': 'condicao',
    'tipo': 'condicao',
    'regras': [
      {'campo': 'executar.prioridade', 'op': 'igual', 'valor': 'alta', 'saida': 'alta'},
    ],
  },
  'paralelo': {'id': 'paralelo', 'tipo': 'paralelo'},
  'fim-baixa': {'id': 'fim-baixa', 'tipo': 'fim'},
  'executar-2': {
    'id': 'executar-2',
    'tipo': 'executar',
    'titulo': 'Análise da Nati',
    'posicao': 'conselho-nati',
    'instrucao': _instrucaoDaNati,
  },
  'executar-3': {
    'id': 'executar-3',
    'tipo': 'executar',
    'titulo': 'Análise do Poe',
    'posicao': 'conselho-poe',
    'instrucao': _instrucaoDoPoe,
  },
  'aprovar': {
    'id': 'aprovar',
    'tipo': 'aprovar',
    'de': 'executar-2',
    'por': {'ueslei': true},
  },
  'aprovar-2': {
    'id': 'aprovar-2',
    'tipo': 'aprovar',
    'de': 'executar-3',
    'por': {'ueslei': true},
  },
  'juncao': {'id': 'juncao', 'tipo': 'juncao'},
  'decisao': {
    'id': 'decisao',
    'tipo': 'decisao_humana',
    'pergunta': 'seguir?',
    'opcoes': ['seguir', 'parar'],
  },
  'fim': {'id': 'fim', 'tipo': 'fim'},
};

const _arestasDaTriagem = [
  {'de': 'executar', 'para': 'condicao'},
  {'de': 'condicao', 'para': 'paralelo', 'quando': 'alta'},
  {'de': 'condicao', 'para': 'fim-baixa', 'quando': 'senao'},
  {'de': 'paralelo', 'para': 'executar-2'},
  {'de': 'paralelo', 'para': 'executar-3'},
  {'de': 'executar-2', 'para': 'aprovar'},
  {'de': 'executar-3', 'para': 'aprovar-2'},
  {'de': 'aprovar', 'para': 'juncao', 'quando': 'aprovado'},
  {'de': 'aprovar-2', 'para': 'juncao', 'quando': 'aprovado'},
  {'de': 'juncao', 'para': 'decisao'},
  {'de': 'decisao', 'para': 'fim', 'quando': 'seguir'},
  {'de': 'decisao', 'para': 'fim', 'quando': 'parar'},
];

Map<String, Object?> _triagemSemeada() => {
  'id': 'triagem',
  'nome': 'Triagem',
  'versao': 0,
  'entrada': {'dados': 'texto'},
  'inicio': 'executar',
  'nos': _caixasDaTriagem.values.toList(),
  'arestas': _arestasDaTriagem,
  'layout': <String, Object?>{},
};

Map<String, Object?> _semeado(String id, String nome, List<Map<String, Object?>> nos, List<Map<String, Object?>> arestas) => {
  'id': id,
  'nome': nome,
  'versao': 0,
  'entrada': <String, Object?>{},
  'inicio': nos.first['id'],
  'nos': nos,
  'arestas': arestas,
  'layout': <String, Object?>{},
};

Map<String, Object?> _devolve(String nome, String mensagem, Map<String, Object?> valores, {int vezes = 1}) => {
  'nome': nome,
  'quando': {'mensagem': mensagem},
  'responde': [
    {'ferramenta': 'mcp__orquestra__devolver', 'entrada': valores},
  ],
  'vezes': vezes,
};

Map<String, Object?> _terminaDepoisDeDevolver(String nome, String mensagem, String texto, {int vezes = 1}) => {
  'nome': nome,
  'quando': {'mensagem': mensagem, 'resultadoDe': 'devolver'},
  'responde': [
    {'texto': texto},
  ],
  'vezes': vezes,
};

Map<String, Object?> _respondeTexto(String nome, String mensagem, String texto) => {
  'nome': nome,
  'quando': {'mensagem': mensagem},
  'responde': [
    {'texto': texto},
  ],
};

Future<int> _fluxoNovo(WidgetTester t, Conexao c, String workflow, Set<Object?> antes) async {
  late int id;
  await esperarAteAssincrono(t, () async {
    final novos = [
      for (final f in await fluxosNoServidor(c))
        if (f['workflow'] == workflow && !antes.contains(f['id'])) f['id'] as int,
    ];
    if (novos.isEmpty) return false;
    id = novos.reduce(max);
    return true;
  }, descricao: 'o fluxo novo de $workflow no servidor');
  return id;
}

Future<Map> _esperarFluxo(
  WidgetTester t,
  Conexao c,
  int id,
  bool Function(Map fluxo) condicao, {
  required String descricao,
  Duration prazo = _prazoDoFluxo,
}) async {
  late Map fluxo;
  await esperarAteAssincrono(t, () async {
    fluxo = await fluxoNoServidor(c, id);
    if (condicao(fluxo)) return true;
    final caixas = [for (final f in fichasDe(fluxo)) '${f['no']} ${f['status']}'];
    throw StateError('o fluxo #$id está ${fluxo['status']}${fluxo['erro'] == null ? '' : ' (${fluxo['erro']})'}: $caixas');
  }, descricao: descricao, prazo: prazo);
  return fluxo;
}

Map? _ficha(Map fluxo, String no) => fichasDe(fluxo).where((f) => f['no'] == no).lastOrNull;

Future<Set<Object?>> _fluxosAtuais(Conexao c) async => {for (final f in await fluxosNoServidor(c)) f['id']};

Future<void> _iniciarPeloCartao(WidgetTester t, String nome, {String? dados}) async {
  final cartao = find.ancestor(of: find.text(nome), matching: find.byType(Card)).first;
  await tocar(t, find.descendant(of: cartao, matching: botao('Iniciar')), descricao: 'o Iniciar do cartão $nome');
  await aparecer(t, find.text('Iniciar $nome'));
  if (dados != null) await digitar(t, campoRotulado('dados'), dados);
  await tocar(t, botao('Iniciar').last);
  await _esperarSumirDaTela(t, find.text('Iniciar $nome'));
}

Future<void> _esperarSumirDaTela(WidgetTester t, Finder alvo) =>
    esperarAte(t, () => alvo.evaluate().isEmpty, descricao: '${alvo.toString(describeSelf: true)} sumir');

Future<void> _verEncerrado(WidgetTester t, int fluxo, String status) async {
  final linha = find.textContaining('#$fluxo · $status');
  if (linha.evaluate().isEmpty) await tocar(t, find.textContaining('ENCERRADOS ('));
  await aparecer(t, linha, descricao: 'o fluxo #$fluxo $status na lista de encerrados');
}

Future<void> _configurarExecutar(WidgetTester t, {required String posicao, required String titulo, required String instrucao}) async {
  await escolherNoSeletor(t, seletorRotulado('Posição'), posicao);
  await digitar(t, campoRotulado('Título (opcional)'), titulo);
  await digitar(t, campoRotulado('Instrução'), instrucao);
}

Future<void> _abrirTarefa(WidgetTester t, int id, String titulo) async {
  await irPara(t, 'Tarefas');
  final linha = find.text('#$id $titulo');
  await aparecer(t, linha, descricao: 'a tarefa #$id na lista');
  await tocar(t, linha);
  await esperarAte(t, () => salaDe(t).tarefas.aberta?.tarefa.id == id, descricao: 'a tarefa #$id aberta');
}

void cenasDeWorkflows() {
  testWidgets('cena 9: workflow montado no editor salva, inicia e segue pelo ramo devolvido', (t) async {
    await roteiro('workflows-alta', [
      _terminaDepoisDeDevolver('executor-termina', 'Classifique a prioridade da demanda', 'classifiquei como alta'),
      _devolve('executor-devolve', 'Classifique a prioridade da demanda', {'prioridade': 'alta'}),
      _respondeTexto('nati-analisa', 'Nati, analise a demanda', 'análise da Nati pronta'),
      _respondeTexto('poe-analisa', 'Poe, analise a demanda', 'análise do Poe pronta'),
    ]);
    final c = await ws();
    Sala? subida;
    addTearDown(() async {
      subida?.editorDeWorkflow.fechar();
      subida?.workflows.fecharGrafo();
      await excluirWorkflow(c, 'triagem');
      await cancelarAbertas(c);
      await c.fechar();
    });
    await excluirWorkflow(c, 'triagem');
    await subirDesktop(t, ambiente);
    final sala = subida = salaDe(t);
    final editor = sala.editorDeWorkflow;
    await escolherEquipe(t, 'casa', 'Casa');
    await verAba(t, AbaDaEquipe.workflows);
    await tocar(t, botao('Novo workflow'));
    await digitar(t, campoRotulado('Nome do workflow'), 'Triagem');
    await tocar(t, botao('Criar'));
    await esperarAte(t, () => editor.aberto && editor.id == 'triagem', descricao: 'o editor com o workflow triagem');
    await aparecer(t, find.byType(CanvasDoGrafo));

    await tocar(t, botao('Acrescentar campo'));
    await digitar(t, campoRotulado('Nome').last, 'dados');
    await esperarAte(
      t,
      () => jsonEncode(rascunhoNaTela(t)['entrada']) == jsonEncode({'dados': 'texto'}),
      descricao: 'a entrada dados no rascunho',
    );

    await selecionarCaixa(t, 'fim');
    await tocar(t, find.byTooltip('Menu da caixa'));
    await tocar(t, find.text('Remover caixa'));
    await esperarAte(t, () => !idsDe(rascunhoNaTela(t)).contains('fim'), descricao: 'a caixa fim removida');

    await selecionarCaixa(t, 'executar');
    await _configurarExecutar(t, posicao: 'Alfred · executor de tarefas', titulo: 'Classificar', instrucao: _instrucaoDoExecutor);
    await tocar(t, botao('Acrescentar campo'));
    await digitar(t, campoRotulado('Nome'), 'prioridade');
    await escolherNoSeletor(t, seletorRotulado('Tipo'), 'escolha');
    await digitar(t, campoRotulado('Valores, separados por vírgula'), 'alta, baixa');

    final condicao = await criarPeloPonto(t, 'executar', null, 'condicao');
    await escolherOpcao(t, seletorRotulado('Campo'), find.textContaining('prioridade ·'));
    await digitar(t, campoRotulado('Saída (vira o ponto de ligação)'), 'alta');
    final paralelo = await criarPeloPonto(t, condicao, 'alta', 'paralelo');
    final fimBaixa = await criarPeloPonto(t, condicao, 'senao', 'fim');
    await digitar(t, campoRotulado('Id'), 'fim-baixa');
    await tocar(t, find.byTooltip('Renomear'));
    await esperarAte(t, () => idsDe(rascunhoNaTela(t)).contains('fim-baixa'), descricao: 'a caixa $fimBaixa virar fim-baixa');

    final a = await criarPeloPonto(t, paralelo, null, 'executar');
    await _configurarExecutar(t, posicao: 'Nati · engenheira sênior', titulo: 'Análise da Nati', instrucao: _instrucaoDaNati);
    final b = await criarPeloPonto(t, paralelo, null, 'executar');
    await _configurarExecutar(t, posicao: 'Poe · o amigo', titulo: 'Análise do Poe', instrucao: _instrucaoDoPoe);
    final aprovarA = await criarPeloPonto(t, a, null, 'aprovar');
    final aprovarB = await criarPeloPonto(t, b, null, 'aprovar');
    final juncao = await criarPeloPonto(t, aprovarA, 'aprovado', 'juncao');
    await ligarArrastando(t, aprovarB, 'aprovado', juncao);
    await esperarAte(
      t,
      () => ligacoesDe(rascunhoNaTela(t)).contains('$aprovarB>$juncao (aprovado)'),
      descricao: 'a ligação de $aprovarB para $juncao',
    );
    final decisao = await criarPeloPonto(t, juncao, null, 'decisao_humana');
    await digitar(t, campoRotulado('Pergunta'), 'seguir?');
    await digitar(t, campoRotulado('Opção 1'), 'seguir');
    await digitar(t, campoRotulado('Opção 2'), 'parar');
    final fim = await criarPeloPonto(t, decisao, 'seguir', 'fim');
    await ligarArrastando(t, decisao, 'parar', fim);

    final esperadas = {
      for (final a in _arestasDaTriagem) '${a['de']}>${a['para']}${a['quando'] == null ? '' : ' (${a['quando']})'}',
    };
    await esperarAte(t, () => ligacoesDe(rascunhoNaTela(t)).containsAll(esperadas), descricao: 'todas as ligações no rascunho');
    expect(ligacoesDe(rascunhoNaTela(t)), esperadas);
    expect(editor.erros, isEmpty);
    expect({for (final n in nosDe(rascunhoNaTela(t))) n['id']: n}, _caixasDaTriagem);

    final valido = rascunhoNaTela(t);
    await ligarArrastando(t, juncao, null, juncao);
    await aparecer(t, find.text('Solte o ponto em cima de outra caixa para ligar.'));
    expect(mesmoWorkflow(rascunhoNaTela(t), valido), isTrue, reason: 'o editor não liga uma caixa a ela mesma');
    await ligarArrastando(t, aprovarB, 'aprovado', decisao);
    const erroDaJuncao = 'a junção precisa de 2 ou mais ligações entrando';
    await esperarAte(t, () {
      if (editor.erros[juncao]?.contains(erroDaJuncao) ?? false) return true;
      throw StateError('erros do rascunho: ${editor.erros}');
    }, descricao: 'o erro "$erroDaJuncao" preso à caixa $juncao');
    expect(ligacoesDe(rascunhoNaTela(t)), contains('$aprovarB>$decisao (aprovado)'));
    expect(t.widget<CanvasDoGrafo>(find.byType(CanvasDoGrafo)).comErro, contains(juncao));
    await selecionarCaixa(t, juncao);
    await aparecer(t, find.text(erroDaJuncao), descricao: 'o erro da junção no painel da caixa');
    expect(t.widget<ButtonStyleButton>(botao('Salvar')).onPressed, isNull, reason: 'o salvar fica desligado com erro');
    await tocar(t, find.byTooltip('Desfazer (Ctrl+Z)'));
    await esperarAte(
      t,
      () => editor.problemas == 0 && mesmoWorkflow(rascunhoNaTela(t), valido),
      descricao: 'o rascunho válido de volta',
    );

    await tocar(t, botao('Salvar'));
    final salvo = await esperarJson(
      dados('equipes/casa/workflows/triagem.json'),
      ate: (w) => w['versao'] == 1,
      descricao: 'a triagem salva na versão 1',
    );
    expect(salvo['entrada'], {'dados': 'texto'});
    expect(salvo['inicio'], 'executar');
    expect({for (final n in (salvo['nos'] as List).cast<Map>()) n['id']: n}, _caixasDaTriagem);
    expect(ligacoesDe(salvo), esperadas);

    final antes = await _fluxosAtuais(c);
    await esperarAte(t, () => !editor.alterado && editor.versaoBase == 1, descricao: 'o editor na versão 1 salva');
    await tocar(t, botao('Iniciar'));
    await aparecer(t, find.text('Iniciar Triagem'));
    await digitar(t, campoRotulado('dados'), 'Demanda urgente do cliente');
    await tocar(t, botao('Iniciar').last);
    final fluxo = await _fluxoNovo(t, c, 'triagem', antes);

    final comAeB = await _esperarFluxo(
      t,
      c,
      fluxo,
      (f) => _ficha(f, a)?['tarefa'] != null && _ficha(f, b)?['tarefa'] != null,
      descricao: 'as tarefas de $a e $b criadas',
    );
    expect(_ficha(comAeB, 'executar')?['saidas'], containsPair('prioridade', 'alta'));
    expect(_ficha(comAeB, 'fim-baixa'), isNull);
    final tarefaA = _ficha(comAeB, a)!['tarefa'] as int;
    final tarefaB = _ficha(comAeB, b)!['tarefa'] as int;

    await irPara(t, 'Painel');
    await aprovarNoPainel(t, tarefaA, prazo: _prazoDoFluxo);
    final depoisDeA = await _esperarFluxo(
      t,
      c,
      fluxo,
      (f) => _ficha(f, aprovarA)?['status'] == 'concluida',
      descricao: 'a aprovação de $a no fluxo',
    );
    expect(_ficha(depoisDeA, juncao)?['status'], 'esperando');
    expect(_ficha(depoisDeA, juncao)?['chegadas'], [aprovarA]);
    expect(_ficha(depoisDeA, decisao), isNull, reason: 'a junção espera as duas entregas');

    await aprovarNoPainel(t, tarefaB, prazo: _prazoDoFluxo);
    final naDecisao = await _esperarFluxo(
      t,
      c,
      fluxo,
      (f) => _ficha(f, decisao)?['status'] == 'esperando',
      descricao: 'o fluxo parado na decisão humana',
    );
    expect(_ficha(naDecisao, juncao)?['status'], 'concluida');
    expect(naDecisao['status'], 'rodando');
    await aparecerNoPainel(t, find.text('Triagem pergunta'), descricao: 'a decisão no painel');

    c.mandar({
      'tipo': 'workflow-decidir',
      'execucao': fluxo,
      'ficha': _ficha(naDecisao, decisao)!['id'],
      'opcao': 'seguir',
      'comentario': 'pode seguir',
    });
    final concluido = await _esperarFluxo(t, c, fluxo, (f) => f['status'] == 'concluido', descricao: 'o fluxo concluído');
    expect(_ficha(concluido, decisao)?['saidas'], containsPair('opcao', 'seguir'));
    expect(_ficha(concluido, fim)?['status'], 'concluida');
    await esperarAte(t, () => find.text('Triagem pergunta').evaluate().isEmpty, descricao: 'a decisão sair do painel');
    await esperarAte(t, () => sala.workflows.fluxo(fluxo)?.status == 'concluido', descricao: 'o fluxo concluído no app');
  });

  testWidgets('cena 9: a outra rodada segue pelo outro ramo', (t) async {
    await roteiro('workflows-baixa', [
      _terminaDepoisDeDevolver('executor-termina', 'Classifique a prioridade da demanda', 'classifiquei como baixa'),
      _devolve('executor-devolve', 'Classifique a prioridade da demanda', {'prioridade': 'baixa'}),
    ]);
    final c = await ws();
    addTearDown(() async {
      await excluirWorkflow(c, 'triagem');
      await cancelarAbertas(c);
      await c.fechar();
    });
    await salvarWorkflow(c, {..._triagemSemeada(), 'versao': versaoNoDisco('triagem')});
    final antes = await _fluxosAtuais(c);
    await subirDesktop(t, ambiente);
    await escolherEquipe(t, 'casa', 'Casa');
    await verAba(t, AbaDaEquipe.workflows);
    await _iniciarPeloCartao(t, 'Triagem', dados: 'Demanda que pode esperar');
    final fluxo = await _fluxoNovo(t, c, 'triagem', antes);
    final concluido = await _esperarFluxo(t, c, fluxo, (f) => f['status'] == 'concluido', descricao: 'o fluxo concluído');
    expect({for (final f in fichasDe(concluido)) f['no']}, {'executar', 'condicao', 'fim-baixa'});
    expect(_ficha(concluido, 'executar')?['saidas'], containsPair('prioridade', 'baixa'));
    final doFluxo = (await tarefasNoServidor(c)).where((x) => x['fluxo'] == fluxo).toList();
    expect(doFluxo.map((x) => x['titulo']), ['Triagem: Classificar']);
    expect((await pedidos('workflows-baixa')).where((p) => '${p['ultimaMensagem']}'.contains('analise a demanda')), isEmpty);
    await _verEncerrado(t, fluxo, 'concluído');
  });

  testWidgets('cena 9: laço para no limite', (t) async {
    await roteiro('workflows-laco', [
      _terminaDepoisDeDevolver('tentar-termina', 'Tente de novo até dar certo', 'ainda não deu', vezes: 2),
      _devolve('tentar-devolve', 'Tente de novo até dar certo', {'ok': false}, vezes: 2),
    ]);
    final c = await ws();
    addTearDown(() async {
      await excluirWorkflow(c, 'repeticao');
      await cancelarAbertas(c);
      await c.fechar();
    });
    await salvarWorkflow(
      c,
      _semeado(
        'repeticao',
        'Repetição',
        [
          {
            'id': 'voltas',
            'tipo': 'laco',
            'maxVoltas': 2,
            'enquanto': {'campo': 'tentar.ok', 'op': 'diferente', 'valor': true},
          },
          {
            'id': 'tentar',
            'tipo': 'executar',
            'posicao': 'executor',
            'instrucao': 'Tente de novo até dar certo.',
            'saidas': {'ok': 'booleano'},
          },
          {'id': 'fim', 'tipo': 'fim', 'resultado': 'saiu pelo limite de voltas'},
        ],
        [
          {'de': 'voltas', 'para': 'tentar', 'quando': 'repetir'},
          {'de': 'tentar', 'para': 'voltas'},
          {'de': 'voltas', 'para': 'fim', 'quando': 'sair'},
        ],
      ),
    );
    final antes = await _fluxosAtuais(c);
    await subirDesktop(t, ambiente);
    await escolherEquipe(t, 'casa', 'Casa');
    await verAba(t, AbaDaEquipe.workflows);
    await _iniciarPeloCartao(t, 'Repetição');
    final fluxo = await _fluxoNovo(t, c, 'repeticao', antes);
    final concluido = await _esperarFluxo(t, c, fluxo, (f) => f['status'] == 'concluido', descricao: 'o fluxo concluído');
    expect(concluido['resultado'], 'saiu pelo limite de voltas');
    final fichas = fichasDe(concluido);
    expect(fichas.where((f) => f['no'] == 'tentar').map((f) => f['saidas']['ok']), [false, false]);
    expect(fichas.where((f) => f['no'] == 'voltas').map((f) => f['saidas']['voltas']), [1, 2, 3]);
    final execucoes = (await pedidos('workflows-laco'))
        .where((p) => '${p['ultimaMensagem']}'.contains('Tente de novo até dar certo') && p['resultadoDe'] == null);
    expect(execucoes, hasLength(2));
    await _verEncerrado(t, fluxo, 'concluído');
  });

  testWidgets('cena 9: cancelar uma tarefa do fluxo cancela o fluxo', (t) async {
    await roteiro('workflows-cancelar', []);
    final c = await ws();
    Sala? sala;
    addTearDown(() async {
      sala?.tarefas.fecharDetalhe();
      sala?.workflows.fecharGrafo();
      await excluirWorkflow(c, 'cancelavel');
      await cancelarAbertas(c);
      await retomarAlfred(c);
      await c.fechar();
    });
    await salvarWorkflow(
      c,
      _semeado(
        'cancelavel',
        'Cancelável',
        [
          {'id': 'esperar', 'tipo': 'executar', 'posicao': 'executor', 'instrucao': 'Espere até alguém cancelar.'},
          {'id': 'fim', 'tipo': 'fim'},
        ],
        [
          {'de': 'esperar', 'para': 'fim'},
        ],
      ),
    );
    await pausarAlfred(c);
    await subirDesktop(t, ambiente);
    sala = salaDe(t);
    final antes = await _fluxosAtuais(c);
    c.mandar({'tipo': 'workflow-iniciar', 'equipe': 'casa', 'id': 'cancelavel', 'entrada': <String, Object?>{}});
    final fluxo = await _fluxoNovo(t, c, 'cancelavel', antes);
    final comTarefa = await _esperarFluxo(t, c, fluxo, (f) => _ficha(f, 'esperar')?['tarefa'] != null, descricao: 'a tarefa da caixa');
    final tarefa = _ficha(comTarefa, 'esperar')!['tarefa'] as int;

    await _abrirTarefa(t, tarefa, 'Cancelável: esperar');
    await tocar(t, find.byTooltip('Mais opções'));
    await tocar(t, find.text('Cancelar tarefa'));
    final cancelado = await _esperarFluxo(t, c, fluxo, (f) => f['status'] == 'cancelado', descricao: 'o fluxo cancelado');
    expect(cancelado['erro'], 'a tarefa #$tarefa foi cancelada');
    expect(_ficha(cancelado, 'esperar')?['status'], 'cancelada');
    expect(_ficha(cancelado, 'fim'), isNull);
    await tocar(t, botao('Ver o workflow'));
    await aparecer(t, find.textContaining('#$fluxo · cancelado'), descricao: 'o fluxo cancelado na tela');
  });

  testWidgets('cena 9: terminar sem devolver é falha', (t) async {
    await roteiro('workflows-sem-devolucao', [
      _respondeTexto('executor-esquece-de-devolver', 'Classifique sem devolver a demanda', 'achei que era alta'),
    ]);
    final c = await ws();
    Sala? sala;
    addTearDown(() async {
      sala?.tarefas.fecharDetalhe();
      await excluirWorkflow(c, 'sem-devolucao');
      await cancelarAbertas(c);
      await c.fechar();
    });
    await subirDesktop(t, ambiente);
    sala = salaDe(t);
    await salvarWorkflow(
      c,
      _semeado(
        'sem-devolucao',
        'Sem devolução',
        [
          {
            'id': 'classificar',
            'tipo': 'executar',
            'posicao': 'executor',
            'instrucao': 'Classifique sem devolver a demanda.',
            'saidas': {
              'prioridade': {
                'escolha': ['alta', 'baixa'],
              },
            },
          },
          {'id': 'fim', 'tipo': 'fim'},
        ],
        [
          {'de': 'classificar', 'para': 'fim'},
        ],
      ),
    );
    final antes = await _fluxosAtuais(c);
    c.mandar({'tipo': 'workflow-iniciar', 'equipe': 'casa', 'id': 'sem-devolucao', 'entrada': <String, Object?>{}});
    final fluxo = await _fluxoNovo(t, c, 'sem-devolucao', antes);
    final comTarefa = await _esperarFluxo(t, c, fluxo, (f) => _ficha(f, 'classificar')?['tarefa'] != null, descricao: 'a tarefa da caixa');
    final tarefa = _ficha(comTarefa, 'classificar')!['tarefa'] as int;

    await _abrirTarefa(t, tarefa, 'Sem devolução: classificar');
    await aparecer(
      t,
      find.textContaining('a caixa terminou sem chamar devolver'),
      descricao: 'a falha SEM_DEVOLUCAO na tela da tarefa',
      prazo: _prazoDoFluxo,
    );
    final detalhe = await tarefaNoServidor(c, tarefa);
    final execucoes = (detalhe['execucoes'] as List).cast<Map>();
    expect(execucoes.where((e) => e['status'] == 'falhou').map((e) => e['erro']), ['a caixa terminou sem chamar devolver']);
    expect(execucoes.where((e) => e['status'] == 'concluida'), isEmpty);
    final rodando = await fluxoNoServidor(c, fluxo);
    expect(rodando['status'], 'rodando');
    expect(_ficha(rodando, 'classificar')?['status'], 'esperando');
    expect(_ficha(rodando, 'fim'), isNull);
    await c.pedir(
      {'tipo': 'tarefa-status', 'id': tarefa, 'status': 'cancelada'},
      'tarefa',
      filtro: (m) => m['tarefa']['id'] == tarefa && m['tarefa']['status'] == 'cancelada',
    );
  });
}
