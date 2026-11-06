import 'dart:convert';
import 'dart:io';

import 'package:control_tower/nucleo/importacao.dart';
import 'package:control_tower/sistema/arquivos.dart' as arquivos;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/acoes.dart';
import '../apoio/ambiente.dart';
import '../apoio/app.dart';
import '../apoio/esperas.dart';
import '../apoio/falsos.dart';

const _prazoDaEntrega = Duration(seconds: 90);

const _equipeDoEspelho = {
  'id': 'espelho',
  'nome': 'Espelho',
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

Future<int> _criarNoEspelho(Conexao c, String titulo) async {
  final criada = await c.pedir(
    {
      'tipo': 'tarefa-criar',
      'tarefa': {'equipe': 'espelho', 'posicao': 'execucao', 'titulo': titulo, 'porque': ''},
    },
    'tarefa',
    filtro: (m) => m['tarefa']['titulo'] == titulo,
  );
  return criada['tarefa']['id'] as int;
}

Future<Map> _noTickTask(WidgetTester t, int tarefa, {String? status, String? nota}) async {
  final nome = '[CT] #$tarefa espera sua aprovação';
  late Map achada;
  await esperarAteAssincrono(t, () async {
    final iguais = (await tarefasNoTickTask()).where((x) => x['name'] == nome).toList();
    if (iguais.length > 1) throw StateError('$nome subiu ${iguais.length} vezes');
    if (iguais.isEmpty) return false;
    achada = iguais.single;
    return (status == null || achada['status'] == status) && (nota == null || '${achada['notas']}'.contains(nota));
  }, descricao: '"$nome"${status == null ? '' : ' $status'}${nota == null ? '' : ' com a nota "$nota"'} no TickTask falso', prazo: _prazoDaEntrega);
  return achada;
}

void cenaDoEspelho() {
  testWidgets('cena 11: espelho sobe o item, finalizar lá age aqui e resolver aqui finaliza lá', (t) async {
    await roteiro('espelho', [
      {
        'nome': 'primeira-entrega',
        'quando': {'mensagem': 'Conferir o espelho, primeira'},
        'responde': [
          {'texto': 'primeira conferida'},
        ],
      },
      {
        'nome': 'segunda-entrega',
        'quando': {'mensagem': 'Conferir o espelho, segunda'},
        'responde': [
          {'texto': 'segunda conferida'},
        ],
      },
    ]);
    final c = await ws();
    addTearDown(() async {
      await c.pedir(
        {
          'tipo': 'espelho-salvar',
          'config': {'ativo': false, 'projeto': 'Control Tower', 'tag': 'control-tower'},
        },
        'espelho',
        filtro: (m) => m['config']['ativo'] == false,
      );
      await cancelarAbertas(c);
      if (File(dados('equipes/espelho/equipe.json')).existsSync()) {
        await c.pedir(
          {'tipo': 'equipe-excluir', 'id': 'espelho'},
          'equipes',
          filtro: (m) => !(m['lista'] as List).any((e) => e['id'] == 'espelho'),
        );
      }
      await c.fechar();
    });
    await subirDesktop(t, ambiente);
    await c.pedir(
      {'tipo': 'equipe-salvar', 'equipe': _equipeDoEspelho},
      'equipes',
      filtro: (m) => (m['lista'] as List).any((e) => e['id'] == 'espelho'),
    );

    await irPara(t, 'Configuração');
    await tocar(t, find.widgetWithText(SwitchListTile, 'Espelhar no TickTask'));
    await digitar(t, campoRotulado('Projeto do TickTask'), 'Control Tower teste');
    await digitar(t, campoRotulado('Tag'), 'ct-teste');
    await tocar(t, botao('Salvar'));
    final config = await esperarJson(
      dados('ticktask.json'),
      ate: (j) => j['tag'] == 'ct-teste',
      descricao: 'o espelho configurado',
    );
    expect(config, allOf(
      containsPair('ativo', true),
      containsPair('projeto', 'Control Tower teste'),
      containsPair('tag', 'ct-teste'),
    ));
    expect(config['tipos'] as List, contains('aprovacao'));

    final primeira = await _criarNoEspelho(c, 'Conferir o espelho, primeira');
    final la = await _noTickTask(t, primeira);
    expect(la['status'], 'proximas');
    expect((await tarefaNoServidor(c, primeira))['tarefa']['status'], 'em_revisao');
    await finalizarNoTickTask(la['id'] as int);
    await tocar(t, botao('Sincronizar agora'));
    await esperarAteAssincrono(
      t,
      () async => (await tarefaNoServidor(c, primeira))['tarefa']['status'] == 'concluida',
      descricao: '#$primeira concluída pelo TickTask',
    );
    final registros = ((await tarefaNoServidor(c, primeira))['registros'] as List).cast<Map>();
    expect(registros.where((r) => r['tipo'] == 'aprovado').map((r) => r['autor']), ['ueslei']);
    final auditoria = 'aprovar via TickTask · tarefa:$primeira';
    await c.pedir(
      {'tipo': 'painel', 'ativo': true},
      'painel',
      filtro: (m) => (m['retrato']['atividade'] as List).any((a) => '${a['texto']}'.contains(auditoria)),
    );
    c.mandar({'tipo': 'painel', 'ativo': false});

    final segunda = await _criarNoEspelho(c, 'Conferir o espelho, segunda');
    final segundaLa = await _noTickTask(t, segunda);
    expect(segundaLa['status'], 'proximas');
    await irPara(t, 'Painel');
    await aparecerNoPainel(t, find.textContaining(auditoria), descricao: 'a auditoria "via TickTask" no painel');
    await aprovarNoPainel(t, segunda);
    await esperarAteAssincrono(
      t,
      () async => (await tarefaNoServidor(c, segunda))['tarefa']['status'] == 'concluida',
      descricao: '#$segunda concluída pela tela',
    );
    final finalizada = await _noTickTask(t, segunda, status: 'finalizada', nota: 'Resolvido no control-tower');
    expect(finalizada['id'], segundaLa['id']);
  });
}

void cenaDosModelos() {
  testWidgets('cena 12: exportar e importar como nova, resolvendo a colisão', (t) async {
    await roteiro('modelos', []);
    final c = await ws();
    final salvarOriginal = arquivos.salvarArquivo;
    final escolherOriginal = arquivos.escolherArquivos;
    String? exportado;
    arquivos.salvarArquivo = ({required nome, required bytes}) async {
      final destino = '${Directory(ambiente.dados).parent.path}/$nome';
      await File(destino).writeAsBytes(bytes);
      exportado = destino;
      return destino;
    };
    arquivos.escolherArquivos = ({extensoes}) async {
      final caminho = exportado;
      return caminho == null ? null : [(nome: caminho.split('/').last, caminho: caminho)];
    };
    addTearDown(() async {
      arquivos.salvarArquivo = salvarOriginal;
      arquivos.escolherArquivos = escolherOriginal;
      if (File(dados('equipes/casa-2/equipe.json')).existsSync()) {
        await c.pedir(
          {'tipo': 'equipe-excluir', 'id': 'casa-2'},
          'equipes',
          filtro: (m) => !(m['lista'] as List).any((e) => e['id'] == 'casa-2'),
        );
      }
      final casa = lerJson(dados('equipes/casa/equipe.json'));
      final posicoes = (casa['posicoes'] as List).cast<Map>();
      if (posicoes.any((p) => p['id'] == 'conselho-natalia')) {
        await c.pedir(
          {
            'tipo': 'equipe-salvar',
            'equipe': {
              ...casa,
              'posicoes': [for (final p in posicoes) if (p['id'] != 'conselho-natalia') p],
              'layout': {...(casa['layout'] as Map? ?? {})}..remove('conselho-natalia'),
            },
          },
          'equipes',
          filtro: (m) => (m['lista'] as List).any(
            (e) => e['id'] == 'casa' && !(e['posicoes'] as List).any((p) => p['id'] == 'conselho-natalia'),
          ),
        );
      }
      if (Directory(dados('profiles/natalia')).existsSync()) {
        await c.pedir(
          {'tipo': 'persona-excluir', 'id': 'natalia', 'confirmacao': 'Natália'},
          'personas',
          filtro: (m) => !(m['lista'] as List).any((p) => p['id'] == 'natalia'),
        );
      }
      await c.fechar();
    });
    await subirDesktop(t, ambiente);
    final sala = salaDe(t);
    await escolherEquipe(t, 'casa', 'Casa');
    await tocar(t, find.byTooltip('Exportar como modelo…'));
    await tocar(t, botao('Exportar…'));
    await esperarAte(t, () => exportado != null, descricao: 'o modelo exportado pelo salvarArquivo');
    final modelo = jsonDecode(File(exportado!).readAsStringSync()) as Map<String, dynamic>;
    expect(modelo['formato'], 'control-tower/modelo');
    expect(jsonEncode(modelo), contains('"conselho-nati"'));

    await tocar(t, botao('Importar modelo…'));
    await aparecer(t, find.text('PERSONAS'), descricao: 'a prévia da importação');
    final importacao = sala.importacao;
    await esperarAte(t, () => importacao.previa != null && !importacao.pendente, descricao: 'a prévia pronta');
    expect(importacao.escolhas.equipeId ?? importacao.previa!.escolhas.equipeId, 'casa-2');
    final linhaDaNati = find.ancestor(of: find.text('Nati'), matching: find.byType(Wrap)).first;
    await tocar(t, find.descendant(of: linhaDaNati, matching: find.byType(DropdownButton<OpcaoDePersona>)));
    await tocar(t, find.text(rotulosDeOpcaoDePersona[OpcaoDePersona.criarComNome]!).last);
    await digitar(t, campoRotulado('Nome da persona nova'), 'Natália');
    await esperarAte(t, () {
      if (importacao.escolhas.personas['nati']?.nome == 'Natália' && !importacao.pendente && importacao.podeImportar) return true;
      throw StateError('erros da prévia: ${importacao.previa?.erros}');
    }, descricao: 'a prévia com a Natália e sem erros');
    await tocar(t, botao('Importar'));

    final equipe = await esperarJson(
      dados('equipes/casa-2/equipe.json'),
      ate: (e) => e['id'] == 'casa-2',
      descricao: 'a equipe casa-2',
    );
    final posicoes = {for (final p in (equipe['posicoes'] as List).cast<Map>()) p['id']: p};
    expect(posicoes['conselho-nati']?['persona'], 'natalia');
    expect(posicoes['conselho-poe']?['persona'], 'poe');
    expect(posicoes['executor']?['persona'], 'alfred');
    await esperarJson(dados('profiles/natalia/persona.json'), ate: (p) => p['nome'] == 'Natália', descricao: 'a persona Natália');
    final casa = await esperarJson(
      dados('equipes/casa/equipe.json'),
      ate: (e) => (e['posicoes'] as List).any((p) => p['id'] == 'conselho-natalia'),
      descricao: 'a posição conselho-natalia na Casa',
    );
    final daCasa = {for (final p in (casa['posicoes'] as List).cast<Map>()) p['id']: p};
    expect(daCasa['conselho-nati']?['persona'], 'nati');
    expect(daCasa['conselho-natalia'], containsPair('persona', 'natalia'));
    expect(daCasa['conselho-natalia']?['capacidades'], isNot(contains('board')));

    await esperarAte(t, () => sala.equipes.atual?.id == 'casa-2', descricao: 'o organograma da equipe nova');
    await aparecer(t, cartaoDaPosicao('conselho-nati'));
    await aparecer(
      t,
      find.descendant(of: cartaoDaPosicao('conselho-nati'), matching: find.textContaining('Natália')),
      descricao: 'a Natália no cartão da posição',
    );
  });
}
