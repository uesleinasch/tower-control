import 'dart:convert';
import 'dart:io';

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
}
