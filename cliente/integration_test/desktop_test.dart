import 'dart:convert';
import 'dart:io';

import 'package:control_tower/estado/equipes.dart';
import 'package:control_tower/nucleo/modelos.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'apoio/acoes.dart';
import 'apoio/ambiente.dart';
import 'apoio/app.dart';
import 'apoio/esperas.dart';
import 'apoio/falsos.dart';
import 'cenas/conjuntas.dart';
import 'cenas/espelho_e_modelos.dart';
import 'cenas/workflows.dart';

Future<void> excluirRotinaSeExiste(Conexao c, String id) async {
  if (!File(dados('equipes/casa/rotinas/$id.json')).existsSync()) return;
  await c.pedir({'tipo': 'rotina-excluir', 'equipe': 'casa', 'id': id}, 'rotinas');
  await esperarSumir(dados('equipes/casa/rotinas/$id.json'));
}

const nomeDaRotina = 'Revisão semanal de ação';
const idDaRotina = 'revisao-semanal-de-acao';
const tituloDaRotina = 'Conferir pendências e decisões ({data})';
const descricaoDaRotina = 'Olhar o painel, responder às decisões\ne fechar o que já está pronto: ç, ã, é, ô.';
const porqueDaRotina = 'Sem revisão, a fila cresce e ninguém percebe.';
const cronDaRotina = '0 9 * * 1';

const rotinaEsperada = {
  'id': idDaRotina,
  'nome': nomeDaRotina,
  'ativa': true,
  'posicao': 'executor',
  'tarefa': {'titulo': tituloDaRotina, 'descricao': descricaoDaRotina, 'porque': porqueDaRotina},
  'concorrencia': 'pular',
  'perdidos': 'um',
  'cron': cronDaRotina,
  'webhook': true,
};

String? rotinaGravadaComServidorQuieto;

Future<Conexao> prepararRotinas() async {
  final c = await ws();
  await pausarAlfred(c);
  addTearDown(() async {
    await excluirRotinaSeExiste(c, idDaRotina);
    await excluirRotinaSeExiste(c, 'ruido');
    await excluirRotinaSeExiste(c, 'disparavel');
    await cancelarAbertas(c);
    await retomarAlfred(c);
    await c.fechar();
  });
  return c;
}

Future<void> preencherRotina(WidgetTester t, {Future<void> Function()? ruido}) async {
  await escolherEquipe(t, 'casa', 'Casa');
  await verAba(t, AbaDaEquipe.rotinas);
  await tocar(t, botao('Nova rotina'));
  await aparecer(t, campoRotulado('Nome'));
  final campos = [
    ('Nome', nomeDaRotina),
    ('Título', tituloDaRotina),
    ('Descrição', descricaoDaRotina),
    ('Por quê', porqueDaRotina),
    ('Cron (minuto hora dia mês dia-da-semana)', cronDaRotina),
  ];
  for (final (rotulo, texto) in campos) {
    await digitarNoTeclado(t, campoRotulado(rotulo), texto, noMeio: ruido);
    await ruido?.call();
  }
  await tocar(t, find.widgetWithText(CheckboxListTile, 'Webhook'));
  await ruido?.call();
  await tocar(t, botao('Salvar').last);
}

Future<Map<String, dynamic>> rotinaNoDisco() async {
  final texto = await esperarArquivo(dados('equipes/casa/rotinas/$idDaRotina.json'));
  return jsonDecode(texto) as Map<String, dynamic>;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  tearDown(conferirSemRegra);

  testWidgets('desktop: sobe sem bandeja, conecta no servidor de teste e lista as personas', (t) async {
    await subirDesktop(t, ambiente);
    await tocar(t, find.text('Nova conversa'));
    await aparecer(t, find.text('Nati'), descricao: 'a Nati na lista de personas');
    expect(salaDe(t).canal.endereco, '127.0.0.1:${ambiente.porta}');
  });

  testWidgets('cena 3: persona e equipe criadas pelo organograma ficam no disco', (t) async {
    await roteiro('organograma', [
      {
        'nome': 'perfil-gerado',
        'quando': {'sistema': 'Você escreve o profile.md de uma persona'},
        'responde': [
          {'texto': '# Vera\n\nVocê é a Vera, auditora do Ueslei. Confere números e pergunta pela fonte.'},
        ],
        'fundo': true,
      },
      {
        'nome': 'vera-responde',
        'quando': {'sistema': '# Vera', 'mensagem': 'oi, Vera'},
        'responde': [
          {'texto': 'oi, Ueslei. Pode mandar os números.'},
        ],
      },
    ]);
    final c = await ws();
    addTearDown(() async {
      final equipe = File(dados('equipes/teste/equipe.json'));
      if (equipe.existsSync()) await c.pedir({'tipo': 'equipe-excluir', 'id': 'teste'}, 'equipes');
      await c.fechar();
    });
    await subirDesktop(t, ambiente);
    await escolherEquipe(t, 'casa', 'Casa');
    await verAba(t, AbaDaEquipe.organograma);

    await tocar(t, botao('Nova'));
    await digitar(t, campoRotulado('Nome'), 'Vera');
    await digitar(t, campoRotulado('Papel curto (aparece na lista)'), 'auditora');
    await digitar(
      t,
      campoRotulado('Quem é, que papel tem com você e qual é o jeito dela'),
      'Auditora que confere números e pergunta pela fonte.',
    );
    await tocar(t, botao('Criar'));
    await esperarArquivo(dados('profiles/vera/persona.json'));
    await esperarArquivo(dados('profiles/vera/profile.md'), contendo: 'Confere números e pergunta pela fonte.');
    await esperarAte(
      t,
      () => Perfil.todos.any((p) => p.chave == 'vera' && !p.gerandoPerfil),
      descricao: 'a Vera com o perfil gerado',
    );

    await tocar(t, find.text('Nova conversa'));
    await tocar(t, find.widgetWithText(ListTile, 'Vera').last);
    await digitar(
      t,
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Mensagem para Vera…'),
      'oi, Vera',
    );
    await tocar(t, find.byTooltip('Enviar'));
    await aparecer(t, find.textContaining('oi, Ueslei. Pode mandar os números.', findRichText: true));
    final conversa = salaDe(t).chat.conversaId!;
    await esperarArquivo(dados('conversations/$conversa.jsonl'), contendo: 'Pode mandar os números.');

    await irPara(t, 'Equipes');
    await tocar(t, botao('Nova equipe'));
    await digitar(t, campoRotulado('Nome da equipe'), 'Teste');
    await tocar(t, botao('Criar equipe'));
    await esperarAte(t, () => salaDe(t).equipes.atual?.id == 'teste', descricao: 'a equipe Teste em edição');

    for (final (titulo, persona) in [('auditoria', 'Vera'), ('execução', 'Alfred')]) {
      await tocar(t, botao('Posição'));
      await digitar(t, campoRotulado('Título (ex.: revisora)'), titulo);
      await tocar(t, botao('Criar posição'));
      await escolherNoSeletor(t, seletorRotulado('Persona'), persona);
      await tocar(t, find.byTooltip('Fechar'));
    }
    await aparecer(t, cartaoDaPosicao('execucao'));

    final execucao = t.getRect(cartaoDaPosicao('execucao'));
    final escala = execucao.width / 220;
    await arrastar(t, execucao.center, execucao.center + Offset(-100 * escala, 0));
    final execucaoMovida = t.getRect(cartaoDaPosicao('execucao'));
    expect(execucaoMovida.center.dx, lessThan(execucao.center.dx - 50 * escala));
    final auditoria = t.getRect(cartaoDaPosicao('auditoria'));
    await arrastar(t, auditoria.center, execucaoMovida.center + Offset(0, 180 * escala));
    final auditoriaMovida = t.getRect(cartaoDaPosicao('auditoria'));
    expect(auditoriaMovida.center.dy, greaterThan(auditoria.center.dy + 100 * escala));
    final alca = Offset(execucaoMovida.center.dx, execucaoMovida.bottom + 6 * escala);
    await arrastar(t, alca, auditoriaMovida.center);
    await esperarAte(
      t,
      () => salaDe(t).equipes.atual?.posicao('auditoria')?.respondeA == 'execucao',
      descricao: 'a auditoria respondendo à execução no rascunho',
    );

    await tocar(t, botao('Salvar'));
    final equipe = jsonDecode(await esperarArquivo(dados('equipes/teste/equipe.json'))) as Map<String, dynamic>;
    final posicoes = {for (final p in (equipe['posicoes'] as List).cast<Map>()) p['id']: p};
    expect(equipe['nome'], 'Teste');
    expect(posicoes['auditoria']?['persona'], 'vera');
    expect(posicoes['execucao']?['persona'], 'alfred');
    expect(posicoes['auditoria']?['respondeA'], 'execucao');
    expect(posicoes['execucao']?['respondeA'], isNull);
    final layout = equipe['layout'] as Map;
    expect(
      (layout['auditoria']['y'] as num) > (layout['execucao']['y'] as num),
      isTrue,
      reason: 'a auditoria foi arrastada para baixo da execução: $layout',
    );
    await esperarAteAssincrono(t, () async {
      final ultimo = await gitDosDados(['log', '-1', '--format=%s']);
      if (!ultimo.contains('equipe Teste')) throw StateError('o último commit é "${ultimo.trim()}"');
      return true;
    }, descricao: 'o commit da equipe Teste no git dos dados');

    await esperarAte(t, () => !salaDe(t).equipes.alterada, descricao: 'a equipe salva');
    Finder painelDePersonas() => find.text('Clique num cartão para editar a posição.');
    await rolarAte(t, find.byTooltip('Excluir Vera'), dentroDe: painelDePersonas());
    await tocar(t, find.byTooltip('Excluir Vera'));
    await digitar(t, campoRotulado('Digite Vera para confirmar'), 'Vero');
    await tocar(t, botao('Excluir persona'));
    await aparecer(t, find.textContaining('digite o nome exato da persona'), descricao: 'a recusa do nome errado');
    expect(Directory(dados('profiles/vera')).existsSync(), isTrue);

    await rolarAte(t, find.byTooltip('Excluir Vera'), dentroDe: painelDePersonas());
    await tocar(t, find.byTooltip('Excluir Vera'));
    await digitar(t, campoRotulado('Digite Vera para confirmar'), 'Vera');
    await tocar(t, botao('Excluir persona'));
    await esperarSumir(dados('profiles/vera'));
    await esperarAte(t, () => !Perfil.todos.any((p) => p.chave == 'vera'), descricao: 'a Vera sair do elenco');

    await tocar(t, find.widgetWithText(ListTile, 'oi, Vera'), descricao: 'a conversa com a Vera na lista');
    await esperarAte(t, () => salaDe(t).chat.conversaId == conversa, descricao: 'a conversa da Vera aberta');
    await aparecer(t, find.textContaining('oi, Ueslei. Pode mandar os números.', findRichText: true));
    await aparecer(t, find.textContaining('Só leitura'));
    expect(find.byTooltip('Enviar'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Mensagem para')),
      findsNothing,
    );
  });

  testWidgets('cena 7: editor de rotinas guarda exatamente o que foi digitado, com o servidor quieto', (t) async {
    await roteiro('rotinas-quieto', []);
    await prepararRotinas();
    await subirDesktop(t, ambiente);
    await preencherRotina(t);
    expect(await rotinaNoDisco(), rotinaEsperada);
    rotinaGravadaComServidorQuieto = File(dados('equipes/casa/rotinas/$idDaRotina.json')).readAsStringSync();
  });

  testWidgets('cena 7: e com o servidor publicando enquanto se digita', (t) async {
    await roteiro('rotinas-publicando', [
      {
        'nome': 'nati-antes-das-rotinas',
        'quando': {'sistema': '# Nati', 'mensagem': 'vou mexer nas rotinas'},
        'responde': [
          {'texto': 'pode ir'},
        ],
      },
    ]);
    final c = await prepararRotinas();
    await c.pedir({
      'tipo': 'rotina-salvar',
      'equipe': 'casa',
      'rotina': {
        'id': 'ruido',
        'nome': 'Ruído',
        'ativa': true,
        'posicao': 'executor',
        'tarefa': {'titulo': 'ruído da rotina'},
        'concorrencia': 'enfileirar',
        'perdidos': 'um',
      },
    }, 'rotinas');
    await subirDesktop(t, ambiente);
    final sala = salaDe(t);
    await tocar(t, find.text('Nova conversa'));
    await tocar(t, find.widgetWithText(ListTile, 'Nati').last);
    await digitar(
      t,
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Mensagem para Nati…'),
      'vou mexer nas rotinas',
    );
    await tocar(t, find.byTooltip('Enviar'));
    await aparecer(t, find.textContaining('pode ir', findRichText: true));
    var vezes = 0;
    Future<void> ruido() async {
      vezes++;
      final titulo = 'ruído $vezes';
      await c.pedir(
        {
          'tipo': 'tarefa-criar',
          'tarefa': {'equipe': 'casa', 'posicao': 'executor', 'titulo': titulo, 'porque': ''},
        },
        'tarefa',
        filtro: (m) => m['tarefa']['titulo'] == titulo,
      );
      final listaAntes = sala.rotinas.lista;
      c.mandar({'tipo': 'rotina-disparar', 'equipe': 'casa', 'id': 'ruido'});
      await esperarAte(
        t,
        () => !identical(sala.rotinas.lista, listaAntes),
        descricao: 'o disparo do ruído chegar ao app',
      );
      sala.canal
        ..pausar()
        ..iniciar();
      await esperarAte(t, () => sala.canal.conectado, descricao: 'o app reconectar');
    }

    await preencherRotina(t, ruido: ruido);
    expect(vezes, greaterThanOrEqualTo(10));
    expect(await rotinaNoDisco(), rotinaEsperada);
    final gravada = File(dados('equipes/casa/rotinas/$idDaRotina.json')).readAsStringSync();
    if (rotinaGravadaComServidorQuieto != null) expect(gravada, rotinaGravadaComServidorQuieto);
  });

  testWidgets('cena 7: disparo manual e pelo webhook criam a tarefa', (t) async {
    await roteiro('rotinas-disparo', []);
    final c = await prepararRotinas();
    await c.pedir({
      'tipo': 'rotina-salvar',
      'equipe': 'casa',
      'rotina': {
        'id': 'disparavel',
        'nome': 'Disparável',
        'ativa': true,
        'posicao': 'executor',
        'tarefa': {'titulo': 'tarefa da rotina disparável'},
        'webhook': true,
        'concorrencia': 'pular',
        'perdidos': 'um',
      },
    }, 'rotinas');
    await subirDesktop(t, ambiente);
    await escolherEquipe(t, 'casa', 'Casa');
    await verAba(t, AbaDaEquipe.rotinas);
    final cartao = find.ancestor(of: find.text('Disparável'), matching: find.byType(Card));
    await aparecer(t, cartao);

    final manual = c.esperar('tarefa', filtro: (m) => m['tarefa']['titulo'] == 'tarefa da rotina disparável');
    await tocar(t, find.descendant(of: cartao, matching: find.text('Disparar agora')));
    final primeira = (await manual)['tarefa'] as Map;
    expect(primeira['criadaPor'], 'rotina:casa/disparavel');
    await c.pedir(
      {'tipo': 'tarefa-status', 'id': primeira['id'], 'status': 'cancelada'},
      'tarefa',
      filtro: (m) => m['tarefa']['id'] == primeira['id'] && m['tarefa']['status'] == 'cancelada',
    );

    await tocar(t, find.descendant(of: cartao, matching: find.text('Disparável')));
    final rotuloDoToken = find.text('Token (cabeçalho X-Token ou ?token=)');
    await aparecer(t, rotuloDoToken);
    final token = t
        .widget<SelectableText>(
          find.descendant(
            of: find.ancestor(of: rotuloDoToken, matching: find.byType(Column)).first,
            matching: find.byType(SelectableText),
          ),
        )
        .data!;
    final pelaRede = c.esperar(
      'tarefa',
      filtro: (m) => m['tarefa']['titulo'] == 'tarefa da rotina disparável' && m['tarefa']['id'] != primeira['id'],
    );
    final resposta = await http.post(
      Uri.parse('${ambiente.servidor}/rotinas/casa/disparavel'),
      headers: {'X-Token': token},
      body: 'veio de fora',
    );
    expect(resposta.statusCode, 202, reason: resposta.body);
    final segunda = (await pelaRede)['tarefa'] as Map;
    expect(segunda['id'], isNot(primeira['id']));

    await tocar(t, find.descendant(of: cartao, matching: find.textContaining('Últimos disparos')));
    await aparecer(t, find.textContaining('manual · criou a tarefa · #${primeira['id']}'));
    await aparecer(t, find.textContaining('webhook · criou a tarefa · #${segunda['id']}'));
    expect(find.descendant(of: cartao, matching: find.textContaining('Últimos disparos (2)')), findsOneWidget);
  });

  testWidgets('cena 10: skill criada e anexada chega à persona e abre', (t) async {
    const corpo = '# Checklist\n\n- conferir os testes\n- conferir o diff antes de entregar';
    await roteiro('skills', [
      {
        'nome': 'nati-abre-a-skill',
        'quando': {'sistema': '# Nati', 'mensagem': 'confere a entrega pela checklist'},
        'responde': [
          {
            'ferramenta': 'Skill',
            'entrada': {'skill': 'ct-casa:checklist'},
          },
        ],
      },
      {
        'nome': 'nati-depois-da-skill',
        'quando': {'sistema': '# Nati', 'resultadoDe': 'Skill'},
        'responde': [
          {'texto': 'conferi pela checklist'},
        ],
      },
    ]);
    final c = await ws();
    addTearDown(() async {
      final persona = lerJson(dados('profiles/nati/persona.json'));
      if ((persona['skills'] as List?)?.contains('checklist') ?? false) {
        await c.pedir({
          'tipo': 'persona-salvar',
          'persona': {'id': 'nati', 'skills': <String>[]},
        }, 'personas');
      }
      if (Directory(dados('skills/checklist')).existsSync()) {
        await c.pedir({'tipo': 'skill-excluir', 'dono': 'casa', 'id': 'checklist'}, 'skills');
      }
      await c.fechar();
    });
    await subirDesktop(t, ambiente);
    await escolherEquipe(t, 'casa', 'Casa');

    await verAba(t, AbaDaEquipe.skills);
    await tocar(t, botao('Nova skill'));
    await tocar(t, find.text('Na biblioteca da Casa'));
    await digitar(t, campoRotulado('Id'), 'checklist');
    await digitar(t, campoRotulado('Descrição'), 'Lista de conferência antes de entregar um trabalho.');
    await digitar(t, campoRotulado('Corpo (Markdown)'), corpo);
    await tocar(t, botao('Salvar').last);
    await esperarArquivo(dados('skills/checklist/SKILL.md'), contendo: '- conferir o diff antes de entregar');

    await verAba(t, AbaDaEquipe.organograma);
    final linhaDaNati = find.ancestor(of: find.byTooltip('Pausar Nati'), matching: find.byType(Row)).first;
    await tocar(t, find.descendant(of: linhaDaNati, matching: find.byTooltip('Anexar skill da Casa')));
    await tocar(t, find.widgetWithText(MenuItemButton, 'checklist'));
    await esperarArquivo(dados('profiles/nati/persona.json'), contendo: 'checklist');

    await tocar(t, find.text('Nova conversa'));
    await tocar(t, find.widgetWithText(ListTile, 'Nati').last);
    await digitar(
      t,
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Mensagem para Nati…'),
      'confere a entrega pela checklist',
    );
    await tocar(t, find.byTooltip('Enviar'));
    await aparecer(t, find.textContaining('conferi pela checklist', findRichText: true));

    final daNati = (await pedidos('skills')).where((p) => deQuem(p, '# Nati')).toList();
    final turno = daNati.firstWhere(
      (p) => '${p['ultimaMensagem']}'.contains('confere a entrega pela checklist') && p['resultadoDe'] == null,
    );
    expect(turno['ferramentas'], contains('Skill'));
    expect(jsonEncode(turno['corpo']), contains('ct-casa:checklist'));
    final depois = daNati.firstWhere((p) => p['resultadoDe'] == 'Skill');
    final mensagens = ((depois['corpo'] as Map)['messages'] as List).cast<Map>();
    final comResultado = mensagens.lastWhere(
      (m) =>
          m['role'] == 'user' && m['content'] is List && (m['content'] as List).any((b) => b['type'] == 'tool_result'),
    );
    final blocos = (comResultado['content'] as List).cast<Map>();
    expect(jsonEncode(blocos.firstWhere((b) => b['type'] == 'tool_result')), contains('ct-casa:checklist'));
    expect(jsonEncode(blocos), contains('- conferir o diff antes de entregar'));
  });

  cenasDeWorkflows();
  cenaDoEspelho();
  cenaDosModelos();
  cenasConjuntas(lado: 'desktop', subir: (t) => subirDesktop(t, ambiente), ir: irPara);
}
