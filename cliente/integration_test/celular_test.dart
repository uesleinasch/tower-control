import 'dart:math';

import 'package:control_tower/estado/chat.dart';
import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/sistema/servico_avisos.dart';
import 'package:control_tower/tela/chat.dart';
import 'package:control_tower/tela/conversas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'apoio/acoes.dart' show aberta, cancelarAbertas, fichasDe, fluxoNoServidor, fluxosNoServidor, salvarWorkflow, tarefaNoServidor, workflowsNoServidor;
import 'apoio/ambiente.dart';
import 'apoio/app.dart' show aparecer, aparecerNoPainel, aprovarNoPainel, botao, digitar, salaDe, tocar;
import 'apoio/celular.dart';
import 'apoio/esperas.dart';
import 'apoio/falsos.dart';

const _prazoDoModelo = Duration(seconds: 60);
const _prazoDaEntrega = Duration(seconds: 90);

String _naPasta(String nome) => '${ambiente.dados}/../$nome';

Finder get _cartaoDePermissao => find.text('Alfred quer rodar um comando');

Future<void> _abrirNova(WidgetTester t, String nome) async {
  final sala = salaDe(t);
  await tocar(t, find.widgetWithText(FloatingActionButton, 'Nova'), descricao: 'o botão Nova da lista');
  await tocar(
    t,
    find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(ListTile, nome)),
    descricao: '$nome na folha de nova conversa',
  );
  await esperarAte(
    t,
    () => sala.tela == Tela.chat && sala.chat.conversaId == null && sala.chat.perfil != null,
    descricao: 'a conversa nova com $nome na tela',
  );
  expect(find.byType(ListaConversas), findsNothing, reason: 'o celular mostra uma tela por vez');
}

Future<String> _enviar(WidgetTester t, String texto) async {
  final sala = salaDe(t);
  await digitar(t, find.descendant(of: find.byType(TelaChat), matching: find.byType(TextField)), texto);
  await tocar(t, find.byTooltip('Enviar'));
  await esperarAte(t, () => sala.chat.conversaId != null, descricao: 'a conversa criada no servidor');
  return sala.chat.conversaId!;
}

List<String> _baloes(Sala sala) => [for (final b in sala.chat.itens.whereType<BalaoPerfil>()) b.texto];

Future<void> _esperarFimDoTurno(WidgetTester t, String ultimoBalao) async {
  final sala = salaDe(t);
  await esperarAte(
    t,
    () => !sala.chat.emCurso && _baloes(sala).contains(ultimoBalao),
    descricao: 'o balão "$ultimoBalao" no fim do turno',
    prazo: _prazoDoModelo,
  );
}

Future<Map<String, dynamic>> _conversaNoServidor(Conexao c, String id) =>
    c.pedir({'tipo': 'abrir', 'conversaId': id}, 'conversa', filtro: (m) => m['meta']['id'] == id);

({String texto, bool erro}) _resultado(Map pedido) {
  final mensagens = ((pedido['corpo'] as Map)['messages'] as List).cast<Map>();
  final blocos = (mensagens.lastWhere((m) => m['role'] != 'system')['content'] as List).cast<Map>();
  final r = blocos.lastWhere((b) => b['type'] == 'tool_result');
  final conteudo = r['content'];
  final texto = conteudo is String
      ? conteudo
      : [for (final b in (conteudo as List).cast<Map>()) if (b['type'] == 'text') '${b['text']}'].join('\n');
  return (texto: texto.replaceAll(RegExp(r'<system-reminder>[\s\S]*?</system-reminder>'), '').trim(), erro: r['is_error'] == true);
}

Future<List<({String texto, bool erro})>> _resultadosDoBash(String cena) async => [
  for (final p in await pedidos(cena))
    if (p['resultadoDe'] == 'Bash' && deQuem(p, '# Alfred')) _resultado(p),
];

Map<String, Object?> _bash(String nome, String mensagem, String comando, {bool depoisDoBash = false}) => {
  'nome': nome,
  'quando': {'sistema': '# Alfred', 'mensagem': mensagem, 'resultadoDe': ?(depoisDoBash ? 'Bash' : null)},
  'responde': [
    {
      'ferramenta': 'Bash',
      'entrada': {'command': comando, 'description': nome},
    },
  ],
};

Map<String, Object?> _textoDepoisDoBash(String nome, String mensagem, String texto) => {
  'nome': nome,
  'quando': {'sistema': '# Alfred', 'mensagem': mensagem, 'resultadoDe': 'Bash'},
  'responde': [
    {'texto': texto},
  ],
};

String _gravar(String arquivo) => 'echo ${arquivo.split('/').last.split('.').first} > ${_naPasta(arquivo)} && cat ${_naPasta(arquivo)}';

Future<void> _respostaNoChat(WidgetTester t, {required String cena, required String arquivo, required bool permitir}) async {
  final mensagem = 'grave $arquivo pelo celular';
  final comando = _gravar(arquivo);
  await roteiro(cena, [
    _textoDepoisDoBash('alfred-conclui', mensagem, permitir ? 'gravei' : 'não gravei'),
    _bash('alfred-pede', mensagem, comando),
  ]);
  await subirCelular(t, ambiente);
  final sala = salaDe(t);
  final escuta = EscutaDoApp(sala);
  addTearDown(escuta.parar);
  addTearDown(() => negarPendentes(escuta));

  await _abrirNova(t, 'Alfred');
  await _enviar(t, mensagem);
  await aparecer(t, _cartaoDePermissao, descricao: 'o pedido de aprovação no chat do celular', prazo: _prazoDoModelo);
  final pedido = escuta.pedidos.single;
  expect(pedido.comando, comando);
  expect(pedido.tarefaId, isNull);
  expect(find.text(comando), findsOneWidget);

  await tocar(t, find.widgetWithText(permitir ? FilledButton : TextButton, permitir ? 'Permitir' : 'Negar'));
  await esperarAte(
    t,
    () => escuta.resolvida(pedido.id) != null,
    descricao: 'o permissao-resolvida do servidor',
    prazo: const Duration(seconds: 15),
  );
  expect(escuta.resolvida(pedido.id)!.como, permitir ? 'aprovado' : 'negado');
  await _esperarFimDoTurno(t, permitir ? 'gravei' : 'não gravei');

  final resultados = await _resultadosDoBash(cena);
  expect(resultados, hasLength(1));
  if (permitir) {
    expect(resultados.single.erro, isFalse, reason: resultados.single.texto);
    expect(resultados.single.texto.trim(), arquivo.split('.').first);
  } else {
    expect(resultados.single.erro, isTrue, reason: 'o falso recebeu: ${resultados.single.texto}');
  }
}

const _equipeDoCelular = {
  'id': 'celular',
  'nome': 'Celular',
  'posicoes': [
    {
      'id': 'execucao',
      'titulo': 'execução',
      'persona': 'alfred',
      'respondeA': null,
      'capacidades': ['arquivos'],
      'aprovacao': 'sempre',
      'politica': [
        {
          'tipo': 'aprovacao',
          'por': {'ueslei': true},
        },
      ],
    },
  ],
  'layout': <String, Object?>{},
};

Future<void> _excluirEquipe(Conexao c, String id) async {
  final lista = ((await c.pedir({'tipo': 'equipes'}, 'equipes'))['lista'] as List).cast<Map>();
  if (!lista.any((e) => e['id'] == id)) return;
  await c.pedir(
    {'tipo': 'equipe-excluir', 'id': id},
    'equipes',
    filtro: (m) => !(m['lista'] as List).any((e) => e['id'] == id),
  );
}

const _workflowDaDecisao = 'decisao-celular';
const _nomeDaDecisao = 'Decisão no celular';

Future<void> _excluirWorkflow(Conexao c, String id) async {
  for (final f in await fluxosNoServidor(c)) {
    if (f['workflow'] != id || (f['status'] != 'rodando' && f['status'] != 'esperando')) continue;
    await c.pedir(
      {'tipo': 'workflow-cancelar', 'execucao': f['id']},
      'workflows',
      filtro: (m) => (m['fluxos'] as List).any((x) => x['id'] == f['id'] && x['status'] == 'cancelado'),
    );
  }
  final definicoes = ((await workflowsNoServidor(c))['definicoes'] as List).cast<Map>();
  if (!definicoes.any((d) => d['equipe'] == 'casa' && d['id'] == id)) return;
  await c.pedir(
    {'tipo': 'workflow-excluir', 'equipe': 'casa', 'id': id},
    'workflows',
    filtro: (m) => !(m['definicoes'] as List).any((d) => d['equipe'] == 'casa' && d['id'] == id),
  );
}

Map? _ficha(Map fluxo, String no) => fichasDe(fluxo).where((f) => f['no'] == no).lastOrNull;

Future<Map> _esperarFluxo(WidgetTester t, Conexao c, int id, bool Function(Map f) condicao, {required String descricao}) async {
  late Map fluxo;
  await esperarAteAssincrono(t, () async {
    fluxo = await fluxoNoServidor(c, id);
    if (condicao(fluxo)) return true;
    throw StateError('o fluxo #$id está ${fluxo['status']}: ${[for (final f in fichasDe(fluxo)) '${f['no']} ${f['status']}']}');
  }, descricao: descricao, prazo: _prazoDaEntrega);
  return fluxo;
}

Future<void> _irParaOPainel(WidgetTester t) async {
  await tocar(t, find.descendant(of: find.byType(NavigationBar), matching: find.text('Painel')));
  await esperarAte(t, () => salaDe(t).tela == Tela.painel, descricao: 'o painel na tela');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  tearDown(conferirSemRegra);
  tearDownAll(() => const ServicoDeAvisos().desligar());

  testWidgets('cena 1 (celular): mensagem para a Nati vira balões', (t) async {
    await roteiro('celular-chat', [
      {
        'nome': 'nati-responde',
        'quando': {'sistema': '# Nati', 'mensagem': 'como vai o projeto, pelo celular?'},
        'responde': [
          {'texto': 'um\n\n---\n\ndois'},
        ],
      },
    ]);
    final c = await ws();
    addTearDown(c.fechar);
    await subirCelular(t, ambiente);
    final sala = salaDe(t);
    expect(sala.canal.endereco, endsWith(':${ambiente.porta}'));

    await _abrirNova(t, 'Nati');
    final conversa = await _enviar(t, 'como vai o projeto, pelo celular?');
    await _esperarFimDoTurno(t, 'dois');
    expect(_baloes(sala), ['um', 'dois']);
    expect(find.text('um', findRichText: true), findsWidgets);
    expect(find.text('dois', findRichText: true), findsWidgets);
    expect(find.byType(ListaConversas), findsNothing);

    final gravada = await _conversaNoServidor(c, conversa);
    final resposta = (gravada['mensagens'] as List).cast<Map>().singleWhere((m) => m['role'] == 'assistant');
    expect('${resposta['texto']}'.split(RegExp(r'\n\s*-{3,}\s*\n')), ['um', 'dois']);
  });

  testWidgets('cena 2 (celular): Alfred pede, celular aprova, comando roda', (t) async {
    await _respostaNoChat(t, cena: 'celular-aprovar', arquivo: 'cena2.txt', permitir: true);
  });

  testWidgets('cena 2 (celular): negado não roda', (t) async {
    await _respostaNoChat(t, cena: 'celular-negar', arquivo: 'cena2-negado.txt', permitir: false);
  });

  testWidgets('cena 2 (celular): pelo aviso, com o chat fechado', (t) async {
    const mensagem = 'grave cena2-aviso.txt pelo celular, com o chat fechado';
    final comando = _gravar('cena2-aviso.txt');
    await roteiro('celular-aviso', [
      _textoDepoisDoBash('alfred-conclui', mensagem, 'gravei pelo aviso'),
      _bash('alfred-pede', mensagem, comando),
    ]);
    await subirCelular(t, ambiente);
    final sala = salaDe(t);
    final escuta = EscutaDoApp(sala);
    addTearDown(escuta.parar);
    addTearDown(() => negarPendentes(escuta));
    await esperarAteAssincrono(
      t,
      () => const ServicoDeAvisos().ligado(),
      descricao: 'o serviço de avisos do app de teste escutando o /avisos',
    );

    await _abrirNova(t, 'Alfred');
    final conversa = await _enviar(t, mensagem);
    await tocar(t, find.byIcon(Icons.arrow_back), descricao: 'a seta que fecha o chat');
    await esperarAte(t, () => sala.tela == Tela.conversas, descricao: 'a lista no lugar do chat');

    final (ativa, aviso) = await avisoNaBandeja(
      t,
      (n) => n.tipo == 'aprovacao' && n.conversaId == conversa,
      descricao: 'o aviso de aprovação da conversa na bandeja do celular',
      prazo: _prazoDoModelo,
    );
    expect(aviso.corpo, comando);
    expect(aviso.acoes, containsAll(['aprovar', 'negar']));
    expect(sala.tela, Tela.conversas);

    await tocarNoBotaoDoAviso(t, ativa, 'aprovar');
    await esperarAte(
      t,
      () => escuta.resolvida(aviso.id) != null,
      descricao: 'o permissao-resolvida do servidor depois do toque no aviso',
      prazo: const Duration(seconds: 15),
    );
    expect(escuta.resolvida(aviso.id)!.como, 'aprovado');
    await esperarAteAssincrono(
      t,
      () async => (await _resultadosDoBash('celular-aviso')).isNotEmpty,
      descricao: 'o resultado do comando no modelo falso',
      prazo: _prazoDoModelo,
    );
    final resultado = (await _resultadosDoBash('celular-aviso')).single;
    expect(resultado.erro, isFalse, reason: resultado.texto);
    expect(resultado.texto.trim(), 'cena2-aviso');
    expect(sala.tela, Tela.conversas);
    await esperarAteAssincrono(
      t,
      () async => ((await _conversaNoServidorPorFora(conversa))['mensagens'] as List)
          .cast<Map>()
          .any((m) => m['role'] == 'assistant' && m['texto'] == 'gravei pelo aviso'),
      descricao: 'a resposta final gravada na conversa',
      prazo: _prazoDoModelo,
    );
  });

  testWidgets('cena 2 (celular): no auto, comum passa e sensível pede', (t) async {
    const mensagem = 'grave cena2-auto.txt no auto e apague a pasta x';
    final comum = _gravar('cena2-auto.txt');
    final sensivel = 'rm -rf ${_naPasta('x')}';
    await roteiro('celular-auto', [
      _bash('alfred-pede-o-sensivel', mensagem, sensivel, depoisDoBash: true),
      _textoDepoisDoBash('alfred-conclui', mensagem, 'parei no rm'),
      _bash('alfred-roda-o-comum', mensagem, comum),
    ]);
    final c = await ws();
    addTearDown(c.fechar);
    await subirCelular(t, ambiente);
    final sala = salaDe(t);
    final escuta = EscutaDoApp(sala);
    addTearDown(escuta.parar);
    addTearDown(() => negarPendentes(escuta));

    await _abrirNova(t, 'Alfred');
    await tocar(t, find.widgetWithText(FilterChip, 'auto'));
    await esperarAte(t, () => sala.chat.auto, descricao: 'o modo auto ligado no chat');
    final conversa = await _enviar(t, mensagem);

    await aparecer(t, _cartaoDePermissao, descricao: 'o pedido de aprovação do comando sensível', prazo: _prazoDoModelo);
    expect([for (final p in escuta.pedidos) p.comando], [sensivel]);
    expect([for (final r in sala.chat.itens.whereType<Registro>()) r.comando], [comum]);
    expect(find.text(comum), findsOneWidget);

    await tocar(t, find.widgetWithText(TextButton, 'Negar'));
    final pedido = escuta.pedidos.single;
    await esperarAte(
      t,
      () => escuta.resolvida(pedido.id) != null,
      descricao: 'o permissao-resolvida do servidor',
      prazo: const Duration(seconds: 15),
    );
    expect(escuta.resolvida(pedido.id)!.como, 'negado');
    await _esperarFimDoTurno(t, 'parei no rm');

    final resultados = await _resultadosDoBash('celular-auto');
    expect(resultados, hasLength(2));
    expect(resultados.first.erro, isFalse, reason: resultados.first.texto);
    expect(resultados.first.texto.trim(), 'cena2-auto');
    expect(resultados.last.erro, isTrue, reason: 'o falso recebeu: ${resultados.last.texto}');
    expect((await _conversaNoServidor(c, conversa))['meta']['auto'], isTrue);
  });

  testWidgets('cena 6 (celular): aprovação final do Ueslei pelo celular', (t) async {
    const titulo = 'Conferir pelo celular';
    await roteiro('celular-aprovacao-final', [
      {
        'nome': 'alfred-entrega',
        'quando': {'mensagem': titulo},
        'responde': [
          {'texto': 'conferido'},
        ],
      },
    ]);
    final c = await ws();
    addTearDown(() async {
      await cancelarAbertas(c);
      await _excluirEquipe(c, 'celular');
      await c.fechar();
    });
    await c.pedir(
      {'tipo': 'equipe-salvar', 'equipe': _equipeDoCelular},
      'equipes',
      filtro: (m) => (m['lista'] as List).any((e) => e['id'] == 'celular'),
    );
    final criada = await c.pedir(
      {
        'tipo': 'tarefa-criar',
        'tarefa': {'equipe': 'celular', 'posicao': 'execucao', 'titulo': titulo, 'porque': ''},
      },
      'tarefa',
      filtro: (m) => m['tarefa']['titulo'] == titulo,
    );
    final id = criada['tarefa']['id'] as int;
    await esperarAteAssincrono(
      t,
      () async {
        final tarefa = (await tarefaNoServidor(c, id))['tarefa'] as Map;
        if (tarefa['status'] == 'em_revisao' && tarefa['rodando'] != true) return true;
        throw StateError('#$id está ${tarefa['status']}');
      },
      descricao: '#$id esperando a aprovação do Ueslei',
      prazo: _prazoDaEntrega,
    );

    await subirCelular(t, ambiente);
    await _irParaOPainel(t);
    await aprovarNoPainel(t, id);
    await esperarAteAssincrono(
      t,
      () async => ((await tarefaNoServidor(c, id))['tarefa'] as Map)['status'] == 'concluida',
      descricao: '#$id concluída no servidor',
    );
    final registros = ((await tarefaNoServidor(c, id))['registros'] as List).cast<Map>();
    expect(registros.where((r) => r['tipo'] == 'aprovado').map((r) => r['autor']), ['ueslei']);
    expect(aberta((await tarefaNoServidor(c, id))['tarefa'] as Map), isFalse);
    await esperarAte(
      t,
      () => find.text('#$id espera sua aprovação').evaluate().isEmpty,
      descricao: 'o pedido de aprovação sair do painel do celular',
    );
  });

  testWidgets('cena 9 (celular): decisão humana tomada no celular termina o fluxo', (t) async {
    final c = await ws();
    addTearDown(() async {
      await _excluirWorkflow(c, _workflowDaDecisao);
      await c.fechar();
    });
    await salvarWorkflow(c, {
      'id': _workflowDaDecisao,
      'nome': _nomeDaDecisao,
      'versao': 0,
      'entrada': <String, Object?>{},
      'inicio': 'decisao',
      'nos': [
        {
          'id': 'decisao',
          'tipo': 'decisao_humana',
          'pergunta': 'seguir pelo celular?',
          'opcoes': ['parar', 'seguir'],
        },
        {'id': 'fim', 'tipo': 'fim'},
        {'id': 'fim-parar', 'tipo': 'fim'},
      ],
      'arestas': [
        {'de': 'decisao', 'para': 'fim', 'quando': 'seguir'},
        {'de': 'decisao', 'para': 'fim-parar', 'quando': 'parar'},
      ],
      'layout': <String, Object?>{},
    });
    final antes = {for (final f in await fluxosNoServidor(c)) f['id']};
    c.mandar({'tipo': 'workflow-iniciar', 'equipe': 'casa', 'id': _workflowDaDecisao, 'entrada': <String, Object?>{}});
    late int fluxo;
    await esperarAteAssincrono(t, () async {
      final novos = [
        for (final f in await fluxosNoServidor(c))
          if (f['workflow'] == _workflowDaDecisao && !antes.contains(f['id'])) f['id'] as int,
      ];
      if (novos.isEmpty) return false;
      fluxo = novos.reduce(max);
      return true;
    }, descricao: 'o fluxo novo no servidor');
    await _esperarFluxo(t, c, fluxo, (f) => _ficha(f, 'decisao')?['status'] == 'esperando', descricao: 'o fluxo parado na decisão');

    await subirCelular(t, ambiente);
    await _irParaOPainel(t);
    final pergunta = find.text('$_nomeDaDecisao pergunta');
    await aparecerNoPainel(t, pergunta, descricao: 'a decisão no painel do celular');
    final cartao = find.ancestor(of: pergunta, matching: find.byType(Card)).first;
    await tocar(t, find.descendant(of: cartao, matching: botao('seguir')));

    final concluido = await _esperarFluxo(t, c, fluxo, (f) => f['status'] == 'concluido', descricao: 'o fluxo concluído');
    expect(_ficha(concluido, 'decisao')?['saidas'], containsPair('opcao', 'seguir'));
    expect(_ficha(concluido, 'fim')?['status'], 'concluida');
    expect(_ficha(concluido, 'fim-parar'), isNull);
    await esperarAte(t, () => pergunta.evaluate().isEmpty, descricao: 'a decisão sair do painel do celular');
  });
}

Future<Map<String, dynamic>> _conversaNoServidorPorFora(String id) async {
  final c = await ws();
  try {
    return await _conversaNoServidor(c, id);
  } finally {
    await c.fechar();
  }
}
