import 'dart:convert';
import 'dart:io';

import 'package:control_tower/nucleo/avisos.dart';
import 'package:control_tower/nucleo/baloes.dart';
import 'package:control_tower/nucleo/enderecos.dart';
import 'package:control_tower/nucleo/formato.dart';
import 'package:control_tower/nucleo/modelos.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/nucleo/organograma.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:flutter_test/flutter_test.dart';

const _execucao = {
  'id': 5,
  'tarefa': 3,
  'posicao': 'executor',
  'persona': 'alfred',
  'gatilho': 'atribuicao',
  'status': 'concluida',
  'modelo': 'haiku',
  'inicio': '2026-11-04T10:00:00Z',
  'fim': '2026-11-04T10:01:05Z',
  'custoUSD': 0.03,
};

const _tarefa = {
  'id': 3,
  'equipe': 'casa',
  'posicao': 'executor',
  'titulo': 'Backup',
  'descricao': '',
  'porque': 'não perder dados',
  'pai': null,
  'status': 'em_andamento',
  'dono': 'ueslei',
  'criadaPor': 'ueslei',
  'criadaEm': '2026-10-07T10:00:00Z',
  'atualizadaEm': '2026-10-07T10:05:00Z',
  'dependeDe': [1],
};

const _meta = {'id': '2026-09-30-poe-abc', 'perfil': 'poe', 'titulo': 't', 'criadaEm': '2026-09-30T10:00:00Z'};

final _fixturasEntrada = <String, Map<String, Object?>>{
  'atalhos': {
    'lista': [
      {'rotulo': 'r', 'texto': 't'},
    ],
  },
  'aviso': {'texto': 'oi'},
  'board-sintese': {'texto': 's', 'ata': 'board/minutes/x.md'},
  'board-status': {'texto': 'colhendo'},
  'chunk': {'conversaId': 'c', 'perfil': 'poe', 'texto': 'pe'},
  'comando': {'comando': 'ls'},
  'conversa': {
    'meta': _meta,
    'mensagens': [
      {
        'role': 'user',
        'texto': 'oi',
        'ts': '2026-09-30T10:00:00Z',
        'perfil': 'poe',
        'anexos': [
          {'id': 'a1', 'nome': 'f.png', 'tipo': 'imagem', 'mime': 'image/png', 'bytes': 10, 'arquivo': 'x'},
        ],
      },
    ],
  },
  'conversas': {
    'lista': [_meta],
  },
  'criada': {'meta': _meta},
  'decisao': {'id': 'd1', 'conteudo': '# x'},
  'decisoes': {
    'lista': [
      {'id': 'd1', 'date': '2026-09-30', 'title': 'T', 'status': 'aceita', 'tags': ['a'], 'projeto': 'p'},
    ],
  },
  'equipes': {
    'lista': [
      {
        'id': 'casa',
        'nome': 'Casa',
        'posicoes': [
          {'id': 'executor', 'titulo': 'executor de tarefas', 'persona': 'alfred', 'personaNome': 'Alfred'},
          {'id': 'vaga', 'titulo': 'revisora', 'persona': null, 'personaNome': null},
        ],
      },
    ],
  },
  'erro': {'mensagem': 'falhou'},
  'execucao': {
    'execucao': _execucao,
    'eventos': [
      {'id': 1, 'execucao': 5, 'tipo': 'texto', 'conteudo': 'rodando', 'em': '2026-11-04T10:00:05Z'},
    ],
  },
  'execucao-evento': {
    'execucaoId': 5,
    'tarefaId': 3,
    'evento': {'id': 2, 'execucao': 5, 'tipo': 'comando', 'conteudo': 'rodou: ls', 'em': '2026-11-04T10:00:06Z'},
  },
  'excluida': {'id': 'c'},
  'fim': {'conversaId': 'c'},
  'permissao': {'id': 'p1', 'comando': 'git status'},
  'orquestra': {'pausadoTudo': true},
  'auditoria': {
    'lista': [
      {'id': 1, 'em': '2026-11-04T12:00:00Z', 'quem': 'ueslei', 'acao': 'pausou', 'alvo': 'tudo', 'detalhe': ''},
    ],
  },
  'personas': {
    'lista': [
      {'id': 'vera', 'nome': 'Vera', 'inicial': 'V', 'cor': '#112233', 'titulo': 'revisora', 'conversa': true, 'executor': false, 'excluivel': true, 'modelo': null, 'gerandoPerfil': true},
    ],
  },
  'permissao-resolvida': {'id': 'p1', 'como': 'aprovado'},
  'tarefa': {
    'tarefa': _tarefa,
    'registros': [
      {'id': 1, 'tarefa': 3, 'tipo': 'status', 'autor': 'ueslei', 'texto': 'criou em a fazer', 'em': '2026-10-07T10:00:00Z'},
      {'id': 2, 'tarefa': 3, 'tipo': 'comentario', 'autor': 'ueslei', 'texto': 'à noite', 'em': '2026-10-07T10:01:00Z'},
      {'id': 3, 'tarefa': 3, 'tipo': 'entrega', 'autor': 'alfred', 'texto': 'feito', 'em': '2026-10-07T10:02:00Z'},
    ],
    'execucoes': [_execucao],
    'custoUSD': 0.03,
    'pedida': true,
  },
  'tarefas': {
    'lista': [
      _tarefa,
      {
        ..._tarefa,
        'id': 4,
        'status': 'em_revisao',
        'politica': [
          {'tipo': 'revisao', 'por': {'posicao': 'revisora'}},
          {'tipo': 'aprovacao', 'por': {'ueslei': true}},
        ],
        'etapa': 1,
        'retorno': null,
        'voltas': 2,
        'comQuem': 'com você',
      },
    ],
  },
};

final _saidas = <Saida>[
  const Listar(),
  const Nova(perfil: 'poe', texto: 'oi'),
  const EnviarMensagem(conversaId: 'c', texto: 'oi'),
  const RespostaDePermissao('p1', permitido: true),
  const Excluir('c'),
  const Abrir('c'),
  const ConvocarBoard('pauta'),
  const PedirDecisoes(),
  const PedirDecisao('d1'),
  const Visivel('c'),
  const PedirEquipes(),
  const PedirTarefas(equipe: 'casa'),
  const PedirTarefa(3),
  const CriarTarefa(equipe: 'casa', posicao: 'executor', titulo: 't'),
  const MudarStatusTarefa(3, 'concluida'),
  const ComentarTarefa(3, 'oi'),
  const PedirExecucao(5),
  const PedirPersonas(),
  const CriarPersona(nome: 'Vera', base: 'revisora'),
  const ExcluirPersona('vera', 'Vera'),
  const SalvarEquipe(EquipeResumo(id: 'codigo', nome: 'Código', posicoes: [])),
  const ExcluirEquipe('codigo'),
  const SalvarOrcamento('alfred', usd: 5, tokens: 2000000),
  const Pausar('*'),
  const Retomar('alfred'),
  const AprovarPlano(3),
  const PedirAuditoria(),
  const DecidirTarefa.aprovar(3),
];

void main() {
  final protocolo =
      jsonDecode(File('../docs/protocolo.json').readAsStringSync()) as Map<String, dynamic>;

  group('contrato do protocolo', () {
    test('todo tipo servidor→cliente tem fixtura e decodifica para um tipo conhecido', () {
      final tipos = (protocolo['servidor→cliente'] as List).cast<String>();
      expect(_fixturasEntrada.keys.toSet(), tipos.toSet());
      for (final tipo in tipos) {
        final entrada = Entrada.decodificar(jsonEncode({'tipo': tipo, ..._fixturasEntrada[tipo]!}));
        expect(entrada, isNot(isA<Desconhecida>()), reason: tipo);
      }
    });

    test('toda saída do codec é um tipo cliente→servidor e cobre a lista', () {
      final tipos = (protocolo['cliente→servidor'] as List).cast<String>();
      expect(_saidas.map((s) => s.tipo).toSet(), tipos.toSet());
    });
  });

  group('tarefas', () {
    test('tarefa decodifica com registros, dependências e marca de pedida', () {
      final e = Entrada.decodificar(jsonEncode({'tipo': 'tarefa', ..._fixturasEntrada['tarefa']!})) as TarefaRecebida;
      expect(e.tarefa.id, 3);
      expect(e.tarefa.dependeDe, [1]);
      expect(e.tarefa.proximosStatus, contains('em_revisao'));
      expect(e.registros.map((r) => r.comentario), [false, true, false]);
      expect(e.registros.map((r) => r.destacado), [false, false, true]);
      expect(e.execucoes.single.duracao(DateTime.now()), const Duration(seconds: 65));
      expect(e.custoUSD, 0.03);
      expect(dinheiro(0.03), r'US$ 0.030');
      expect(e.pedida, isTrue);
    });

    test('posição vaga e ocupada têm rótulos diferentes', () {
      final e = Entrada.decodificar(jsonEncode({'tipo': 'equipes', ..._fixturasEntrada['equipes']!})) as EquipesRecebidas;
      expect(e.lista.single.posicoes.map((p) => p.rotulo), ['Alfred · executor de tarefas', 'revisora (vaga)']);
    });

    test('agrupa por status na ordem de trabalho e substitui tarefa atualizada', () {
      Tarefa t(int id, String status) => Tarefa(
          id: id, equipe: 'casa', posicao: 'p', titulo: '$id', status: status, atualizadaEm: DateTime(2026));
      final grupos = agruparPorStatus([t(1, 'concluida'), t(2, 'a_fazer'), t(3, 'em_andamento'), t(4, 'a_fazer')]);
      expect(grupos.map((g) => g.status), ['em_andamento', 'a_fazer', 'concluida']);
      expect(grupos[1].tarefas.map((x) => x.id), [2, 4]);
      final lista = comTarefa([t(1, 'a_fazer'), t(2, 'a_fazer')], t(2, 'concluida'));
      expect(lista.map((x) => x.status), ['a_fazer', 'concluida']);
      expect(comTarefa(lista, t(9, 'backlog')).first.id, 9);
    });

    test('criar tarefa vai com a equipe e a posição dentro de "tarefa"', () {
      final json = jsonDecode(const CriarTarefa(equipe: 'casa', posicao: 'executor', titulo: 't').codificar()) as Map;
      expect(json['tipo'], 'tarefa-criar');
      expect(json['tarefa'], {'equipe': 'casa', 'posicao': 'executor', 'titulo': 't', 'porque': ''});
    });

    test('política, etapa e com quem chegam na tarefa, com padrão seguro para servidor antigo', () {
      final e = Entrada.decodificar(jsonEncode({'tipo': 'tarefas', ..._fixturasEntrada['tarefas']!})) as TarefasRecebidas;
      final [antiga, nova] = e.lista;
      expect([antiga.politica, antiga.etapa, antiga.retorno, antiga.voltas, antiga.comQuem], [isEmpty, null, null, 0, null]);
      expect(antiga.esperaDecisaoDoUeslei, isFalse);
      expect(nova.politica, [const EtapaDePolitica.revisaoPor('revisora'), const EtapaDePolitica.aprovacaoDoUeslei()]);
      expect([nova.etapa, nova.voltas, nova.comQuem], [1, 2, 'com você']);
      expect(nova.esperaDecisaoDoUeslei, isTrue);
      expect(nova.proximosStatus, contains('bloqueada'));
      final bruta = (_fixturasEntrada['tarefas']!['lista'] as List)[1] as Map<String, dynamic>;
      expect(Tarefa.deJson({...bruta, 'etapa': 0}).esperaDecisaoDoUeslei, isFalse);
      expect(Tarefa.deJson({...bruta, 'status': 'em_andamento'}).esperaDecisaoDoUeslei, isFalse);
      expect(Tarefa.deJson({...bruta, 'etapa': 7}).etapaAtual, isNull);
    });

    test('registros de aprovação e de mudança ficam destacados', () {
      RegistroDeTarefa r(String tipo) => RegistroDeTarefa(tipo: tipo, autor: 'nati', texto: 't', em: DateTime(2026));
      expect(['aprovado', 'mudanca', 'status', 'comentario'].map((t) => r(t).destacado), [true, true, false, false]);
    });

    test('tarefa-decidir leva a decisão, e o texto só quando há', () {
      expect(jsonDecode(const DecidirTarefa.aprovar(3).codificar()), {'tipo': 'tarefa-decidir', 'id': 3, 'decisao': 'aprovar'});
      expect(jsonDecode(const DecidirTarefa.aprovar(3, texto: 'ok').codificar()),
          {'tipo': 'tarefa-decidir', 'id': 3, 'decisao': 'aprovar', 'texto': 'ok'});
      expect(jsonDecode(const DecidirTarefa.mudanca(3, 'refaz').codificar()),
          {'tipo': 'tarefa-decidir', 'id': 3, 'decisao': 'mudanca', 'texto': 'refaz'});
    });

    test('trilha marca a etapa atual e as passadas, e resolve os nomes', () {
      const casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [
        PosicaoResumo(id: 'executor', titulo: 'executor', persona: 'alfred', personaNome: 'Alfred'),
        PosicaoResumo(id: 'revisora', titulo: 'revisora', persona: 'nati'),
        PosicaoResumo(id: 'vaga', titulo: 'auditora'),
      ]);
      String nome(String id) => id == 'nati' ? 'Nati' : id;
      Tarefa t(String status, {int? etapa, int? retorno}) => Tarefa(
            id: 1,
            equipe: 'casa',
            posicao: 'executor',
            titulo: 't',
            status: status,
            atualizadaEm: DateTime(2026),
            etapa: etapa,
            retorno: retorno,
            politica: const [
              EtapaDePolitica.revisaoPor('revisora'),
              EtapaDePolitica.revisaoDoBoard(),
              EtapaDePolitica.revisaoPor('vaga'),
              EtapaDePolitica.aprovacaoDoUeslei(),
            ],
          );
      List<String> estados(Tarefa x) => trilhaDaTarefa(x, casa, nome).map((p) => p.estado).toList();
      expect(trilhaDaTarefa(t('em_revisao', etapa: 1), casa, nome).map((p) => p.rotulo),
          ['Alfred executa', 'Nati revisa', 'board revisa', 'auditora revisa', 'Ueslei aprova']);
      expect(estados(t('em_revisao', etapa: 1)), ['passada', 'passada', 'atual', 'futura', 'futura']);
      expect(estados(t('em_andamento')), ['atual', 'futura', 'futura', 'futura', 'futura']);
      expect(estados(t('em_andamento', retorno: 2)), ['atual', 'passada', 'passada', 'futura', 'futura']);
      expect(estados(t('concluida')), everyElement('passada'));
      expect(trilhaDaTarefa(Tarefa(id: 2, equipe: 'casa', posicao: 'executor', titulo: 't', status: 'a_fazer', atualizadaEm: DateTime(2026)), casa, nome),
          isEmpty);
      expect(rotuloDaEtapa(const EtapaDePolitica.aprovacaoDoUeslei(), casa, nome), 'aprovação do Ueslei');
      expect(rotuloDaEtapa(const EtapaDePolitica.revisaoPor('revisora'), casa, nome), 'revisão de Nati');
      expect(rotuloDaEtapa(const EtapaDePolitica(tipo: 'aprovacao', board: true), casa, nome), 'etapa inválida');
    });

    test('transições espelham as do servidor', () {
      final servidor = File('../app/src/orquestra/tarefa.ts').readAsStringSync();
      for (final MapEntry(key: de, value: paras) in transicoesDeTarefa.entries) {
        expect(servidor, contains('$de: [${paras.map((p) => '"$p"').join(', ')}]'), reason: de);
      }
    });
  });

  group('codec', () {
    test('conversa traz mensagens com anexos', () {
      final e = Entrada.decodificar(jsonEncode({'tipo': 'conversa', ..._fixturasEntrada['conversa']!}));
      final aberta = e as ConversaAberta;
      expect(aberta.meta.perfil, 'poe');
      expect(aberta.mensagens.single.doUsuario, isTrue);
      expect(aberta.mensagens.single.anexos.single.nome, 'f.png');
    });

    test('tipo desconhecido e JSON quebrado não lançam', () {
      expect(Entrada.decodificar('{"tipo":"novidade"}'), isA<Desconhecida>());
      expect(Entrada.decodificar('não é json'), isA<Desconhecida>());
    });

    test('saída omite campos nulos', () {
      final json = jsonDecode(const Nova(perfil: 'alfred', texto: 'x', foco: 'ticktask').codificar()) as Map;
      expect(json['tipo'], 'nova');
      expect(json['foco'], 'ticktask');
      expect(json.containsKey('citacao'), isFalse);
    });
  });

  group('balões', () {
    test('divide pela linha --- e descarta vazios', () {
      expect(dividirBaloes('um\n---\ndois\n  ----  \ntrês\n---\n\n'), ['um', 'dois', 'três']);
    });

    test('em curso separa fechados do aberto', () {
      final r = baloesEmCurso('um\n---\ndo');
      expect(r.fechados, ['um']);
      expect(r.aberto, 'do');
    });

    test('citação longa é cortada em 180', () {
      expect(cortarCitacao('a' * 200), '${'a' * 180}…');
    });
  });

  group('formato', () {
    test('bytes', () {
      expect(formatarBytes(500), '500 B');
      expect(formatarBytes(2048), '2 kB');
      expect(formatarBytes(1536 * 1024), '1,5 MB');
      expect(formatarBytes(2 * 1024 * 1024), '2 MB');
    });

    test('mime pelo nome', () {
      expect(mimePorNome('Foto.JPG'), 'image/jpeg');
      expect(mimePorNome('a.pdf'), 'application/pdf');
      expect(mimePorNome('log.txt'), 'text/plain');
      expect(mimePorNome('pacote.zip'), 'application/octet-stream');
      expect(mimePorNome('semextensao'), 'application/octet-stream');
    });

    test('quando', () {
      final agora = DateTime(2026, 9, 30, 15);
      expect(quando(DateTime(2026, 9, 30, 9, 5), agora: agora), '09:05');
      expect(quando(DateTime(2026, 9, 29, 9), agora: agora), 'ontem');
      expect(quando(DateTime(2026, 8, 3), agora: agora), '3/ago');
    });
  });

  group('endereços', () {
    test('normaliza esquema, caminho e porta ausente', () {
      expect(normalizarEndereco('ws://10.0.0.2:7878/ws'), '10.0.0.2:7878');
      expect(normalizarEndereco('100.1.2.3'), '100.1.2.3:7878');
      expect(normalizarEndereco('host com espaço'), isNull);
    });

    test('pareamento aceita lista JSON e ignora lixo', () {
      expect(enderecosDoPareamento('["ws://a:1/ws","a:1","b"]'), ['a:1', 'b:7878']);
      expect(enderecosDoPareamento('{}'), isEmpty);
      expect(enderecosDoPareamento('xx'), isEmpty);
    });

    test('renovar põe os endereços novos na frente sem repetir', () {
      final r = renovar(['velho:7878', '10.0.0.2:7878'], {'lan': '10.0.0.2', 'tailscale': '100.1.1.1', 'porta': 7878});
      expect(r, ['10.0.0.2:7878', '100.1.1.1:7878', 'velho:7878']);
    });

    test('disputar fica com o primeiro que responde', () async {
      final r = await disputar(['lento', 'rapido', 'morto'], (e) async {
        if (e == 'morto') throw const SocketException('x');
        await Future<void>.delayed(Duration(milliseconds: e == 'lento' ? 50 : 1));
        return {'porta': 7878, 'e': e};
      });
      expect(r!.endereco, 'rapido');
    });

    test('disputar devolve null quando todos falham', () async {
      expect(await disputar(['a', 'b'], (e) async => e == 'a' ? null : throw Exception()), isNull);
      expect(await disputar([], (e) async => {}), isNull);
    });
  });

  group('avisos', () {
    final agora = DateTime.utc(2026, 10, 6, 12);
    Notificacao aviso(String tipo, List<String> acoes, {DateTime? criadoEm, DateTime? expiraEm, String? conversaId}) =>
        lerLinha(jsonEncode({
          'id': 'a1',
          'seq': 7,
          'tipo': tipo,
          'titulo': 't',
          'corpo': 'c',
          'alvo': {'conversaId': ?conversaId, 'tarefaId': 3},
          'acoes': acoes,
          'criadoEm': (criadoEm ?? agora).toIso8601String(),
          'expiraEm': ?expiraEm?.toIso8601String(),
        })) as Notificacao;

    test('linha NDJSON vira aviso, resolução ou nada', () {
      final n = aviso('lembrete', ['concluir', 'adiar']);
      expect([n.seq, n.tarefaId, n.acoes], [7, 3, ['concluir', 'adiar']]);
      final r = lerLinha('{"tipo":"resolvido","id":"a1","seq":8,"como":"lido","em":"x","aparelho":"desktop"}');
      expect(r, isA<Resolucao>());
      expect([(r as Resolucao).como, r.aparelho, r.seq], ['lido', 'desktop', 8]);
      expect(lerLinha('{}'), isNull);
      expect(lerLinha(''), isNull);
      expect(lerLinha('lixo'), isNull);
      expect(lerLinha('{"tipo":"resolvido","id":"a1"}'), isNull);
    });

    test('carga da notificação ida e volta', () {
      final n = aviso('resposta', ['responder'], conversaId: '2026-10-06-poe-abc');
      final volta = Notificacao.daCarga(n.paraCarga())!;
      expect([volta.id, volta.tipo, volta.conversaId, volta.acoes], [n.id, 'resposta', '2026-10-06-poe-abc', ['responder']]);
      expect(Notificacao.daCarga('não é json'), isNull);
      expect(Notificacao.daCarga(null), isNull);
    });

    test('tipo decide o canal', () {
      expect(
        [for (final t in ['aprovacao', 'lembrete', 'atrasada', 'resumo', 'resposta']) canalDe(t)],
        [Canal.aprovacoes, Canal.lembretes, Canal.lembretes, Canal.resumo, Canal.respostas],
      );
    });

    test('botões seguem as ações do aviso; sem campo de texto, responder abre a conversa', () {
      List<String> ids(Notificacao n, {bool texto = true}) =>
          [for (final b in botoesDe(n, campoDeTexto: texto, agora: agora)) b.id];
      expect(ids(aviso('aprovacao', ['aprovar', 'negar'])), ['aprovar', 'negar']);
      expect(ids(aviso('lembrete', ['concluir', 'adiar'])), ['concluir', 'adiar-1h', 'adiar-amanha']);
      expect(ids(aviso('resumo', [])), isEmpty);
      final resposta = aviso('resposta', ['responder']);
      expect(botoesDe(resposta, campoDeTexto: true, agora: agora).single.comTexto, isTrue);
      expect(ids(resposta, texto: false), [abrirConversa]);
    });

    test('aprovação vencida fica sem botões e diz que expirou', () {
      final vencida = aviso('aprovacao', ['aprovar', 'negar'], expiraEm: agora);
      expect(botoesDe(vencida, campoDeTexto: true, agora: agora), isEmpty);
      expect(corpoDe(vencida, agora), contains('Expirou'));
      final viva = aviso('aprovacao', ['aprovar', 'negar'], expiraEm: agora.add(const Duration(seconds: 1)));
      expect(corpoDe(viva, agora), 'c');
    });

    test('botão vira o corpo do POST', () {
      expect(pedidoDoBotao('aprovar', aparelho: 'celular'), {'aparelho': 'celular', 'acao': 'aprovar'});
      expect(pedidoDoBotao('adiar-amanha', aparelho: 'celular'),
          {'aparelho': 'celular', 'acao': 'adiar', 'adiarPara': 'amanha'});
      expect(pedidoDoBotao('responder', texto: ' ok ', aparelho: 'celular'),
          {'aparelho': 'celular', 'acao': 'responder', 'texto': 'ok'});
      expect(pedidoDoBotao('responder', texto: '  ', aparelho: 'celular'), isNull);
      expect(pedidoDoBotao(abrirConversa, aparelho: 'celular'), isNull);
    });

    test('resultado da ação em texto curto', () {
      expect(textoDoResultado(200, {'como': 'aprovado'}), 'Aprovado');
      expect(textoDoResultado(409, {'como': 'negado', 'aparelho': 'desktop'}), 'Já resolvido no desktop: Negado');
      expect(textoDoResultado(404, {}), 'Este aviso não existe mais');
      expect(textoDoResultado(503, {'erro': 'O TickTask está fechado'}), 'O TickTask está fechado');
    });

    test('backlog antigo chega sem som e o muito antigo é ignorado', () {
      expect(alertaDe(aviso('resposta', [], criadoEm: agora.subtract(const Duration(seconds: 30))), agora), Alerta.tocar);
      expect(alertaDe(aviso('resposta', [], criadoEm: agora.subtract(const Duration(minutes: 5))), agora), Alerta.silencioso);
      expect(alertaDe(aviso('resposta', [], criadoEm: agora.subtract(const Duration(hours: 25))), agora), Alerta.ignorar);
    });

    test('id da notificação é estável e positivo', () {
      expect(idDaNotificacao('abc'), idDaNotificacao('abc'));
      expect(idDaNotificacao('abc'), isNot(idDaNotificacao('abd')));
      expect(idDaNotificacao('9b6f3c1e-0000-4000-8000-000000000000'), greaterThanOrEqualTo(0));
    });

    test('toque leva à conversa ou ao Alfred no TickTask', () {
      expect((destinoDe(aviso('resposta', [], conversaId: 'c1')) as AbrirConversa).conversaId, 'c1');
      expect(destinoDe(aviso('lembrete', [])), isA<NovaComAlfredNoTickTask>());
      expect(destinoDe(aviso('resumo', [])), isA<NovaComAlfredNoTickTask>());
      expect((destinoDe(aviso('tarefa', [])) as AbrirTarefa).tarefaId, 3);
      expect((destinoDe(aviso('aprovacao', ['aprovar', 'negar'])) as AbrirTarefa).tarefaId, 3);
    });

    test('permissão de tarefa traz o id da tarefa', () {
      final e = Entrada.decodificar('{"tipo":"permissao","id":"p1","comando":"ls","tarefaId":3}') as PedidoDePermissao;
      expect(e.tarefaId, 3);
    });
  });

  group('organograma', () {
    EquipeResumo codigo() => EquipeResumo.deJson({
          'id': 'codigo',
          'nome': 'Código',
          'posicoes': [
            {'id': 'tech-lead', 'titulo': 'tech lead', 'persona': 'nati', 'capacidades': ['arquivos']},
            {'id': 'executor', 'titulo': 'executor', 'persona': 'alfred', 'respondeA': 'tech-lead', 'capacidades': ['arquivos', 'comandos']},
            {'id': 'revisora', 'titulo': 'revisora', 'persona': null, 'respondeA': 'executor', 'capacidades': ['arquivos']},
          ],
          'layout': {
            'tech-lead': {'x': 0, 'y': 0},
            'executor': {'x': 0, 'y': 160},
            'revisora': {'x': 280, 'y': 320},
          },
        });

    test('ligar recusa ciclo e auto-ligação, e soltar responde ao Ueslei', () {
      final e = codigo();
      expect(() => ligar(e, 'tech-lead', 'revisora'), throwsA(isA<ErroDeOrganograma>()));
      expect(() => ligar(e, 'executor', 'executor'), throwsA(isA<ErroDeOrganograma>()));
      expect(ligar(e, 'revisora', 'tech-lead').posicao('revisora')!.respondeA, 'tech-lead');
      expect(soltar(e, 'executor').posicao('executor')!.respondeA, isNull);
    });

    test('remover posição religa as subordinadas ao chefe dela e tira do layout', () {
      final e = removerPosicao(codigo(), 'executor');
      expect(e.posicao('revisora')!.respondeA, 'tech-lead');
      expect(e.layout.containsKey('executor'), isFalse);
    });

    test('adicionar posição gera id único a partir do título', () {
      final r1 = adicionarPosicao(codigo(), 'Revisora');
      expect(r1.id, 'revisora-2');
      expect(r1.equipe.ponto('revisora-2'), (x: 560.0, y: 0.0));
      expect(adicionarPosicao(codigo(), 'Ação rápida').id, 'acao-rapida');
      expect(slugDe('42 coisas'), 'p-42-coisas');
    });

    test('mover não deixa coordenada negativa', () {
      expect(mover(codigo(), 'executor', -10, 40.4).ponto('executor'), (x: 0.0, y: 40.0));
    });

    test('a alça liga pelo ponto em que foi solta', () {
      final e = codigo();
      final revisora = cantoDoCartao(e, 'revisora');
      expect((alvoEm(e, revisora.x + 5, revisora.y + 5) as NaPosicao).id, 'revisora');
      expect(alvoEm(e, -50, -50), isNull);
      expect(ligarPelaAlca(e, 'tech-lead', const NaPosicao('revisora')).posicao('revisora')!.respondeA, 'tech-lead');
      expect(ligarPelaAlca(e, 'executor', null), same(e));
      expect(ligarPelaAlca(e, 'executor', const NaPosicao('executor')), same(e));
    });

    test('caixa solta ligada desce para baixo do chefe sem cair em cima de outro cartão', () {
      final solta = adicionarPosicao(codigo(), 'Analista');
      expect(solta.equipe.posicao(solta.id)!.respondeA, isNull);
      final ligada = ligarAbaixo(solta.equipe, solta.id, 'tech-lead');
      expect(ligada.posicao(solta.id)!.respondeA, 'tech-lead');
      expect(ligada.ponto(solta.id).y, 160);
      expect(ligada.ponto(solta.id).x, isNot(ligada.ponto('executor').x));
      final sub = adicionarSubordinada(codigo(), 'revisora', 'Estagiária');
      expect([sub.id, sub.equipe.posicao(sub.id)!.respondeA, sub.equipe.ponto(sub.id).y], ['estagiaria', 'revisora', 480.0]);
    });

    test('clique perto da linha acha a ligação; longe dela, nada', () {
      final e = codigo();
      final caminho = caminhoDaLigacao(e, 'executor');
      expect(caminho, hasLength(4));
      expect(ligacaoEm(e, caminho[0].x + 3, (caminho[0].y + caminho[1].y) / 2), 'executor');
      expect(ligacaoEm(e, caminho[0].x + 40, (caminho[0].y + caminho[1].y) / 2), isNull);
      expect(caminhoDaLigacao(e, 'tech-lead'), isEmpty);
    });

    test('chefes possíveis excluem a própria posição e quem formaria ciclo', () {
      expect(chefesPossiveis(codigo(), 'executor').map((p) => p.id), ['tech-lead']);
      expect(chefesPossiveis(codigo(), 'tech-lead').map((p) => p.id), isEmpty);
    });

    test('organizar põe cada nível numa linha e os filhos sob o pai, sem sobrepor', () {
      final e = organizar(ligar(soltar(codigo(), 'revisora'), 'revisora', 'tech-lead'));
      expect(e.ponto('tech-lead'), (x: 140.0, y: 0.0));
      expect(e.ponto('executor'), (x: 0.0, y: 160.0));
      expect(e.ponto('revisora'), (x: 280.0, y: 160.0));
      final soltas = organizar(adicionarPosicao(e, 'Outra').equipe);
      expect(soltas.ponto('outra'), (x: 560.0, y: 0.0));
    });

    test('valida com as mesmas regras do servidor e vai e volta em JSON', () {
      final e = codigo();
      expect(validarOrganograma(e, {'nati', 'alfred'}), isEmpty);
      expect(validarOrganograma(e, {'nati'}), contains('posição executor: persona desconhecida (alfred)'));
      final dupla = editarPosicao(e, 'revisora', (p) => p.copiar(persona: () => 'nati'));
      expect(validarOrganograma(dupla, {'nati', 'alfred'}), contains('persona nati: ocupa mais de uma posição na mesma equipe'));
      final json = jsonDecode(jsonEncode(e.paraJson())) as Map<String, dynamic>;
      expect(EquipeResumo.deJson(json).paraJson(), e.paraJson());
      expect((json['posicoes'] as List).first, isNot(contains('personaNome')));
    });

    test('política vai e volta em JSON e some quando vazia', () {
      final e = adicionarEtapa(
        adicionarEtapa(codigo(), 'executor', const EtapaDePolitica.aprovacaoDoUeslei()),
        'executor',
        const EtapaDePolitica.revisaoPor('tech-lead'),
      );
      final json = jsonDecode(jsonEncode(e.paraJson())) as Map<String, dynamic>;
      expect((json['posicoes'] as List)[1]['politica'], [
        {'tipo': 'revisao', 'por': {'posicao': 'tech-lead'}},
        {'tipo': 'aprovacao', 'por': {'ueslei': true}},
      ]);
      expect(EquipeResumo.deJson(json).paraJson(), e.paraJson());
      expect((json['posicoes'] as List)[0], isNot(contains('politica')));
      final board = adicionarEtapa(e, 'executor', const EtapaDePolitica.revisaoDoBoard());
      expect(board.posicao('executor')!.politica.map((x) => x.paraJson()['por']), [
        {'posicao': 'tech-lead'},
        {'board': true},
        {'ueslei': true},
      ]);
      final movida = moverEtapa(board, 'executor', 0, 1);
      expect(movida.posicao('executor')!.politica.first, const EtapaDePolitica.revisaoDoBoard());
      expect(moverEtapa(board, 'executor', 0, -1).posicao('executor')!.politica, board.posicao('executor')!.politica);
      expect(removerEtapa(movida, 'executor', 2).posicao('executor')!.politica, hasLength(2));
    });

    group('validação da política', () {
      EquipeResumo comPolitica(List<EtapaDePolitica> politica, {EquipeResumo? base}) =>
          editarPosicao(base ?? codigo(), 'executor', (p) => p.copiar(politica: politica));
      List<String> erros(EquipeResumo e) => validarOrganograma(e, {'nati', 'alfred'});

      test('política válida não tem erro', () {
        final e = comPolitica(const [EtapaDePolitica.revisaoPor('tech-lead'), EtapaDePolitica.aprovacaoDoUeslei()]);
        expect(erros(e), isEmpty);
      });

      test('quem decide inválido', () {
        for (final etapa in const [
          EtapaDePolitica(tipo: 'consulta', posicao: 'tech-lead'),
          EtapaDePolitica(tipo: 'aprovacao', board: true),
          EtapaDePolitica(tipo: 'revisao', ueslei: true),
          EtapaDePolitica(tipo: 'revisao'),
        ]) {
          expect(erros(comPolitica([const EtapaDePolitica.revisaoPor('tech-lead'), etapa])),
              ['posição executor: etapa 2: quem decide é inválido'],
              reason: etapa.paraJson().toString());
        }
        final bruta = EtapaDePolitica.deJson({'tipo': 'revisao', 'por': 'ninguém'});
        expect(bruta.valida, isFalse);
      });

      test('só uma aprovação, e sempre no fim', () {
        expect(
          erros(comPolitica(const [EtapaDePolitica.aprovacaoPor('tech-lead'), EtapaDePolitica.aprovacaoDoUeslei()])),
          contains('posição executor: só pode haver uma aprovação'),
        );
        expect(
          erros(comPolitica(const [EtapaDePolitica.aprovacaoDoUeslei(), EtapaDePolitica.revisaoPor('tech-lead')])),
          contains('posição executor: a aprovação precisa ser a última etapa'),
        );
      });

      test('posição inexistente, a própria posição e a mesma persona', () {
        expect(erros(comPolitica(const [EtapaDePolitica.revisaoPor('fantasma')])),
            ['posição executor: etapa 1: posição inexistente (fantasma)']);
        expect(erros(comPolitica(const [EtapaDePolitica.revisaoPor('executor')])),
            ['posição executor: etapa 1: não pode revisar a própria posição']);
        final mesma = EquipeResumo(id: 'x', nome: 'X', posicoes: [
          const PosicaoResumo(id: 'executor', titulo: 'e', persona: 'alfred', politica: [EtapaDePolitica.aprovacaoPor('outra')]),
          const PosicaoResumo(id: 'outra', titulo: 'o', persona: 'alfred'),
        ]);
        expect(errosDaPolitica(mesma, mesma.posicao('executor')!), ['posição executor: etapa 1: alfred revisaria o próprio trabalho']);
        expect(erros(comPolitica(const [EtapaDePolitica.revisaoPor('revisora')])), isEmpty);
      });

      test('board precisa de membro com persona que não seja a executora', () {
        const etapa = [EtapaDePolitica.revisaoDoBoard()];
        expect(erros(comPolitica(etapa)), ['posição executor: etapa 1: o board da equipe não tem membros']);
        final soAExecutora = editarPosicao(comPolitica(etapa), 'executor', (p) => p.copiar(capacidades: [...p.capacidades, 'board']));
        expect(erros(soAExecutora), ['posição executor: etapa 1: o board da equipe não tem membros']);
        final vaga = editarPosicao(comPolitica(etapa), 'revisora', (p) => p.copiar(capacidades: ['board']));
        expect(erros(vaga), ['posição executor: etapa 1: o board da equipe não tem membros']);
        final comMembro = editarPosicao(comPolitica(etapa), 'tech-lead', (p) => p.copiar(capacidades: ['board']));
        expect(erros(comMembro), isEmpty);
      });
    });

    test('zoom mantém fixo o ponto sob o cursor, e ajustar cabe tudo na tela', () {
      const v = (dx: 10.0, dy: 20.0, escala: 1.0);
      final antes = paraMundo(v, 300, 200);
      final z = zoomEm(v, 300, 200, 2);
      final depois = paraMundo(z, 300, 200);
      expect([depois.x, depois.y], [antes.x, antes.y]);
      expect(zoomEm(v, 0, 0, 99).escala, escalaMaxima);
      expect(zoomEm(v, 0, 0, 0.01).escala, escalaMinima);
      expect(deslocarVista(v, 5, -5), (dx: 15.0, dy: 15.0, escala: 1.0));
      final e = codigo();
      final ajuste = ajustarVista(e, 400, 300);
      expect(ajuste.escala, lessThan(1));
      for (final p in e.posicoes) {
        final c = cantoDoCartao(e, p.id);
        final x = c.x * ajuste.escala + ajuste.dx;
        final y = c.y * ajuste.escala + ajuste.dy;
        expect(x >= 0 && x + larguraDoCartao * ajuste.escala <= 400, isTrue, reason: p.id);
        expect(y >= 0 && y + alturaDoCartao * ajuste.escala <= 300, isTrue, reason: p.id);
      }
      expect(ajustarVista(e, 4000, 3000).escala, 1);
    });

    test('a alça é achada pelo círculo abaixo do cartão', () {
      final e = codigo();
      final c = cantoDoCartao(e, 'executor');
      expect(alcaEm(e, c.x + larguraDoCartao / 2, c.y + alturaDoCartao + 5), 'executor');
      expect(alcaEm(e, c.x + 5, c.y + 5), isNull);
    });

    test('orçamento, pausa e plano chegam no modelo e voltam no JSON', () {
      final p = Perfil.deJson({
        'id': 'alfred', 'nome': 'Alfred', 'cor': '#a9b0bf', 'orcamentoMensalUSD': 5, 'gastoMesUSD': 4.5,
        'gastoTotalMesUSD': 6, 'pausa': {'motivo': 'orcamento'},
      });
      expect([p.orcamentoMensalUSD, p.gastoMesUSD, p.pausa, p.proporcaoDoOrcamento], [5.0, 4.5, 'orcamento', 0.9]);
      expect(Perfil.deJson({'id': 'x', 'nome': 'X'}).proporcaoDoOrcamento, isNull);
      final posicao = codigo().posicao('executor')!.copiar(aprovarPlano: true, delegaDireto: true);
      expect(posicao.paraJson(), containsPair('aprovarPlano', true));
      expect(PosicaoResumo.deJson(posicao.paraJson().cast<String, dynamic>()).delegaDireto, isTrue);
      expect(codigo().posicao('executor')!.paraJson().containsKey('aprovarPlano'), isFalse);
      RegistroDeTarefa r(String tipo) => RegistroDeTarefa(tipo: tipo, autor: 'a', texto: 't', em: DateTime(2026));
      expect(planoPendente([r('plano')]), isTrue);
      expect(planoPendente([r('plano'), r('plano-aprovado')]), isFalse);
      expect(planoPendente([r('entrega')]), isFalse);
      expect(r('plano').destacado, isTrue);
      final json = jsonDecode(const SalvarOrcamento('alfred', usd: null, tokens: 500000).codificar()) as Map;
      expect(json['persona'], {'id': 'alfred', 'orcamentoMensalUSD': null, 'orcamentoMensalTokens': 500000});
      final tokens = Perfil.deJson({'id': 'x', 'nome': 'X', 'orcamentoMensalUSD': 10, 'gastoMesUSD': 1, 'orcamentoMensalTokens': 1000, 'tokensMes': 900});
      expect(tokens.proporcaoDoOrcamento, 0.9);
      expect(formatarTokens(1250000), '1,3 mi tokens');
      expect(formatarTokens(45400), '45 mil tokens');
    });

    test('personas do servidor substituem o registro fixo', () {
      final original = Perfil.todos;
      try {
        final e = Entrada.decodificar(jsonEncode({'tipo': 'personas', ..._fixturasEntrada['personas']!})) as PersonasRecebidas;
        Perfil.registrar(e.lista);
        final vera = Perfil.porChave('vera');
        expect([vera.nome, vera.cor, vera.papel, vera.gerandoPerfil], ['Vera', 0xFF112233, 'revisora', true]);
        expect(Perfil.porChave('poe').inicial, '?');
      } finally {
        Perfil.registrar(original);
      }
    });
  });
}
