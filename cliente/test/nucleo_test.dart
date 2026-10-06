import 'dart:convert';
import 'dart:io';

import 'package:control_tower/nucleo/avisos.dart';
import 'package:control_tower/nucleo/baloes.dart';
import 'package:control_tower/nucleo/enderecos.dart';
import 'package:control_tower/nucleo/formato.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:flutter_test/flutter_test.dart';

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
  'erro': {'mensagem': 'falhou'},
  'excluida': {'id': 'c'},
  'fim': {'conversaId': 'c'},
  'permissao': {'id': 'p1', 'comando': 'git status'},
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
    });
  });
}
