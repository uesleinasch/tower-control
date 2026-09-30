import 'dart:convert';

import 'package:control_tower/estado/areas.dart';
import 'package:control_tower/estado/chat.dart';
import 'package:control_tower/nucleo/modelos.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:flutter_test/flutter_test.dart';

const _meta = MetaConversa(id: 'c1', perfil: 'poe', titulo: 'oi', criadaEm: null);

void main() {
  late List<Map<String, dynamic>> enviados;
  var online = true;
  bool enviar(Saida s) {
    if (!online) return false;
    enviados.add(jsonDecode(s.codificar()) as Map<String, dynamic>);
    return true;
  }

  setUp(() {
    enviados = [];
    online = true;
  });

  group('EstadoChat', () {
    test('primeiro envio manda nova; depois de criada, mensagem', () {
      final chat = EstadoChat(enviar)..novaConversa('alfred', foco: 'ticktask');
      expect(chat.enviar('registre x'), isTrue);
      expect(enviados.last['tipo'], 'nova');
      expect(enviados.last['foco'], 'ticktask');
      chat
        ..tratar(const Criada(MetaConversa(id: 'c1', perfil: 'alfred', titulo: 'registre x', criadaEm: null)))
        ..tratar(const Fim('c1'));
      expect(chat.enviar('mais'), isTrue);
      expect(enviados.last['tipo'], 'mensagem');
      expect(enviados.last['conversaId'], 'c1');
    });

    test('não envia em curso, vazio ou desconectado', () {
      final chat = EstadoChat(enviar)..novaConversa('poe');
      expect(chat.enviar('   '), isFalse);
      online = false;
      expect(chat.enviar('oi'), isFalse);
      expect(chat.itens.whereType<DoUsuario>(), isEmpty);
      online = true;
      expect(chat.enviar('oi'), isTrue);
      expect(chat.enviar('de novo'), isFalse);
    });

    test('streaming vira balões no fim e ignora pedaço de outra conversa', () {
      final chat = EstadoChat(enviar)..tratar(const ConversaAberta(_meta, []));
      chat
        ..enviar('pergunta')
        ..tratar(const Pedaco('c1', 'poe', 'um\n---\ndo'))
        ..tratar(const Pedaco('outra', 'nati', 'intruso'))
        ..tratar(const Pedaco('c1', 'poe', 'is'));
      expect(chat.emStreaming.fechados, ['um']);
      expect(chat.emStreaming.aberto, 'dois');
      chat.tratar(const Fim('c1'));
      final baloes = chat.itens.whereType<BalaoPerfil>().toList();
      expect(baloes.map((b) => b.texto), ['um', 'dois']);
      expect(baloes.first.primeiro, isTrue);
      expect(chat.emCurso, isFalse);
    });

    test('permissão responde uma vez e cai para conexaoCaiu na reconexão', () {
      final chat = EstadoChat(enviar)..tratar(const ConversaAberta(_meta, []));
      chat
        ..tratar(const PedidoDePermissao('p1', 'ls'))
        ..tratar(const PedidoDePermissao('p2', 'rm x'));
      final p1 = chat.itens[0] as Permissao;
      final p2 = chat.itens[1] as Permissao;
      chat
        ..responderPermissao(p1, permitido: true)
        ..responderPermissao(p1, permitido: false);
      expect(p1.situacao, SituacaoPermissao.permitido);
      expect(enviados.where((m) => m['tipo'] == 'permissao-resposta'), hasLength(1));
      chat.conexaoRestabelecida();
      expect(p2.situacao, SituacaoPermissao.conexaoCaiu);
      expect(enviados.last, {'tipo': 'abrir', 'conversaId': 'c1'});
    });

    test('reabrir a mesma conversa preserva citação e anexos do compositor', () {
      const anexo = Anexo(id: 'a1', nome: 'f.png', tipo: TipoAnexo.imagem, mime: 'image/png', bytes: 1);
      final chat = EstadoChat(enviar)
        ..tratar(const ConversaAberta(_meta, []))
        ..definirCitacao('trecho')
        ..adicionarAnexo(anexo)
        ..tratar(const ConversaAberta(_meta, []));
      expect(chat.citacao, 'trecho');
      expect(chat.anexos.single.id, 'a1');
      chat.tratar(const ConversaAberta(
          MetaConversa(id: 'c2', perfil: 'nati', titulo: 'x', criadaEm: null), []));
      expect(chat.citacao, isNull);
      expect(chat.anexos, isEmpty);
    });

    test('conversa aberta reconstrói balões da resposta gravada', () {
      final chat = EstadoChat(enviar)
        ..tratar(const ConversaAberta(_meta, [
          Mensagem(doUsuario: true, texto: 'q', ts: null, perfil: 'poe'),
          Mensagem(doUsuario: false, texto: 'a\n---\nb', ts: null, perfil: 'poe'),
        ]));
      expect(chat.itens, hasLength(3));
      expect(chat.titulo, 'Poe — oi');
    });
  });

  group('EstadoBoard', () {
    test('convoca, recebe status e síntese', () {
      final board = EstadoBoard(enviar);
      expect(board.convocar('pauta', contexto: '  '), isTrue);
      expect(enviados.last.containsKey('contexto'), isFalse);
      expect(board.convocar('outra'), isFalse);
      board.tratar(const BoardSintese('síntese', 'board/minutes/a.md'));
      expect(board.emCurso, isFalse);
      expect(board.itens.last, isA<Sintese>());
    });
  });

  group('EstadoDecisoes', () {
    test('filtra por título, projeto e tag', () {
      final d = EstadoDecisoes(enviar)
        ..tratar(const Decisoes([
          Decisao(id: '1', data: '', titulo: 'Usar Bun', status: 'aceita', tags: ['runtime'], projeto: 'tower'),
          Decisao(id: '2', data: '', titulo: 'Outra', status: 'proposta', tags: ['ux'], projeto: 'casa'),
        ]));
      expect(d.filtradas, hasLength(2));
      d.filtrar('RUNTIME');
      expect(d.filtradas.single.id, '1');
      d.filtrar('casa');
      expect(d.filtradas.single.id, '2');
    });
  });
}
