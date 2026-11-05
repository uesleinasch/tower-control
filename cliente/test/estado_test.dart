import 'dart:convert';

import 'package:control_tower/estado/areas.dart';
import 'package:control_tower/estado/chat.dart';
import 'package:control_tower/estado/presenca.dart';
import 'package:control_tower/estado/equipes.dart';
import 'package:control_tower/estado/rotinas.dart';
import 'package:control_tower/estado/tarefas.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/nucleo/modelos.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/nucleo/rotinas.dart';
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

  group('EstadoEquipes', () {
    const casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [PosicaoResumo(id: 'executor', titulo: 'executor', persona: 'alfred')]);

    test('editar marca rascunho, salvar envia a equipe e a resposta limpa o rascunho', () {
      final estado = EstadoEquipes(enviar)..tratar(const EquipesRecebidas([casa]));
      expect(estado.alterada, isFalse);
      estado.novaPosicao('Revisora');
      expect([estado.alterada, estado.selecionada], [true, 'revisora']);
      estado.salvar();
      expect(enviados.last['tipo'], 'equipe-salvar');
      expect((enviados.last['equipe'] as Map)['posicoes'], hasLength(2));
      estado.tratar(const EquipesRecebidas([casa]));
      expect([estado.alterada, estado.salvando], [false, false]);
    });

    test('pausa geral alterna conforme o estado do servidor', () {
      final estado = EstadoEquipes(enviar)..alternarPausaGeral();
      expect(enviados.last, {'tipo': 'pausar', 'alvo': '*'});
      estado
        ..tratar(const OrquestraRecebida(pausadoTudo: true))
        ..alternarPausaGeral();
      expect(enviados.last, {'tipo': 'retomar', 'alvo': '*'});
    });

    test('erro do servidor mantém o rascunho, e validação local nem envia', () {
      final estado = EstadoEquipes(enviar)
        ..tratar(const EquipesRecebidas([casa]))
        ..novaPosicao('Revisora')
        ..salvar()
        ..tratar(const Erro('posição executor: tem tarefa aberta'));
      expect([estado.alterada, estado.erro], [true, 'posição executor: tem tarefa aberta']);
      final enviadosAntes = enviados.length;
      estado
        ..aplicar((e) => e.copiar(nome: ' '))
        ..salvar();
      expect(enviados.length, enviadosAntes);
      expect(estado.erro, contains('nome obrigatório'));
    });
  });

  group('EstadoTarefas', () {
    final tarefa = Tarefa(id: 3, equipe: 'casa', posicao: 'executor', titulo: 't', status: 'em_andamento', atualizadaEm: DateTime(2026));
    Execucao execucao(int id, String status) =>
        Execucao(id: id, tarefa: 3, gatilho: 'atribuicao', status: status, inicio: DateTime(2026));
    EventoDeExecucao evento(int id) => EventoDeExecucao(id: id, tipo: 'texto', conteudo: 'e$id', em: DateTime(2026));

    test('abrir a tarefa pede o log da última execução, que cresce ao vivo', () {
      final estado = EstadoTarefas(enviar)..tratar(TarefaRecebida(tarefa, const [], execucoes: [execucao(5, 'rodando')], pedida: true));
      expect(enviados.last, {'tipo': 'execucao', 'id': 5});
      estado
        ..tratar(ExecucaoRecebida(execucao(5, 'rodando'), [evento(1)]))
        ..tratar(EventoRecebido(5, 3, evento(2)))
        ..tratar(EventoRecebido(9, 3, evento(3)));
      expect(estado.log!.eventos.map((e) => e.conteudo), ['e1', 'e2']);
      estado.tratar(ExecucaoRecebida(execucao(6, 'rodando'), null));
      expect(estado.aberta!.execucoes.map((e) => e.id), [5, 6]);
      expect(enviados.last, {'tipo': 'execucao', 'id': 6});
    });

    test('permissão de tarefa fica na tarefa, não no chat, e responde uma vez', () {
      final chat = EstadoChat(enviar)..tratar(const ConversaAberta(_meta, []));
      final estado = EstadoTarefas(enviar)..tratar(TarefaRecebida(tarefa, const [], pedida: true));
      const pedido = PedidoDePermissao('p1', 'ls', tarefaId: 3);
      chat.tratar(pedido);
      estado.tratar(pedido);
      expect(chat.itens.whereType<Permissao>(), isEmpty);
      expect(estado.pedidosDaAberta.map((p) => p.comando), ['ls']);
      estado
        ..responder('p1', permitido: true)
        ..responder('p1', permitido: false);
      expect(enviados.where((m) => m['tipo'] == 'permissao-resposta'), hasLength(1));
      estado
        ..tratar(const PedidoDePermissao('p2', 'df', tarefaId: 3))
        ..tratar(const PermissaoResolvida('p2', 'expirado'));
      expect(estado.pedidos, isEmpty);
    });

    test('decidir a etapa do Ueslei manda tarefa-decidir, e mudança sem texto não sai', () {
      final estado = EstadoTarefas(enviar)
        ..aprovarEtapa(3)
        ..aprovarEtapa(3, ' bom ')
        ..pedirMudanca(3, '  ')
        ..pedirMudanca(3, ' faltou o teste ');
      expect(enviados, [
        {'tipo': 'tarefa-decidir', 'id': 3, 'decisao': 'aprovar'},
        {'tipo': 'tarefa-decidir', 'id': 3, 'decisao': 'aprovar', 'texto': 'bom'},
        {'tipo': 'tarefa-decidir', 'id': 3, 'decisao': 'mudanca', 'texto': 'faltou o teste'},
      ]);
      expect(estado.lista, isEmpty);
    });
  });

  group('EstadoRotinas', () {
    const casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [PosicaoResumo(id: 'executor', titulo: 'executor', persona: 'alfred')]);
    const plano = Rotina(id: 'plano-do-dia', nome: 'Plano do dia', posicao: 'executor', titulo: 'Plano {data}', equipe: 'casa');
    const sistema = Rotina(id: 'memoria', nome: 'Agenda da memória', cron: '*/5 * * * *', sistema: true);

    test('lista separa equipe e sistema, e a de sistema não dispara nem ativa', () {
      final estado = EstadoRotinas(enviar)
        ..carregar()
        ..tratar(const RotinasRecebidas([plano, sistema]));
      expect(estado.carregada, isTrue);
      expect(estado.daEquipe('casa').map((r) => r.id), ['plano-do-dia']);
      expect(estado.doSistema.single.id, 'memoria');
      estado
        ..disparar(sistema)
        ..alternarAtiva(sistema)
        ..editar(sistema)
        ..disparar(plano)
        ..alternarAtiva(plano);
      expect(estado.rascunho, isNull);
      expect(enviados, [
        {'tipo': 'rotinas'},
        {'tipo': 'rotina-disparar', 'equipe': 'casa', 'id': 'plano-do-dia'},
        {'tipo': 'rotina-ativar', 'equipe': 'casa', 'id': 'plano-do-dia', 'ativa': false},
      ]);
      expect(estado.criadaPelaRotina('rotina:casa/plano-do-dia'), 'criada pela rotina Plano do dia');
      expect(estado.criadaPelaRotina('rotina:casa/sumiu'), 'criada pela rotina sumiu');
      expect(estado.criadaPelaRotina('ueslei'), isNull);
    });

    test('nova rotina gera o id do nome, não salva com erro e fixa o id depois de salva', () {
      final estado = EstadoRotinas(enviar)..tratar(const RotinasRecebidas([plano]));
      estado.novaRotina(casa);
      expect([estado.nova, estado.rascunho!.posicao], [true, 'executor']);
      estado.mudar((r) => r.copiar(nome: 'Plano do dia'));
      expect(estado.rascunho!.id, 'plano-do-dia-2');
      expect(estado.errosDoRascunho(casa), ['rotina plano-do-dia-2: título da tarefa obrigatório']);
      estado.salvar(casa);
      expect(enviados, isEmpty);
      expect(estado.erro, isNotNull);
      estado
        ..mudar((r) => r.copiar(titulo: 'Plano {data}', cron: '30 8 * * 1-5'))
        ..salvar(casa);
      expect(enviados.single['tipo'], 'rotina-salvar');
      expect((enviados.single['rotina'] as Map)['id'], 'plano-do-dia-2');
      expect(estado.salvando, isTrue);
      estado.tratar(const RotinasRecebidas([plano]));
      expect(estado.salvando, isTrue);
      estado.tratar(RotinasRecebidas([plano, plano.copiar(id: 'plano-do-dia-2')]));
      expect([estado.salvando, estado.nova], [false, false]);
      estado.mudar((r) => r.copiar(nome: 'Outro nome'));
      expect(estado.rascunho!.id, 'plano-do-dia-2');
    });

    test('erro do servidor ao salvar fica no estado; excluir fecha o editor quando some da lista', () {
      final estado = EstadoRotinas(enviar)
        ..tratar(const RotinasRecebidas([plano]))
        ..editar(plano)
        ..salvar(casa);
      estado.tratar(const Erro('rotina plano-do-dia: posição inexistente (x)'));
      expect([estado.salvando, estado.erro], [false, 'rotina plano-do-dia: posição inexistente (x)']);
      estado.excluir();
      expect(enviados.last, {'tipo': 'rotina-excluir', 'equipe': 'casa', 'id': 'plano-do-dia'});
      estado.tratar(const RotinasRecebidas([plano]));
      expect(estado.rascunho, isNotNull);
      estado.tratar(const RotinasRecebidas([]));
      expect([estado.rascunho, estado.salvando], [null, false]);
    });

    test('trocar token só com o webhook salvo', () {
      final estado = EstadoRotinas(enviar)
        ..tratar(const RotinasRecebidas([plano]))
        ..editar(plano)
        ..mudar((r) => r.copiar(webhook: true))
        ..trocarToken();
      expect(enviados, isEmpty);
      estado
        ..tratar(RotinasRecebidas([plano.copiar(webhook: true)]))
        ..trocarToken();
      expect(enviados.single, {'tipo': 'rotina-token', 'equipe': 'casa', 'id': 'plano-do-dia'});
    });
  });

  group('EstadoChat', () {
    test('primeiro envio manda nova; depois de criada, mensagem', () {
      final chat = EstadoChat(enviar)
        ..novaConversa('alfred')
        ..alternarTicktask();
      expect(chat.enviar('registre x'), isTrue);
      expect(enviados.last['tipo'], 'nova');
      expect(enviados.last['foco'], 'ticktask');
      chat
        ..tratar(const Criada(MetaConversa(id: 'c1', perfil: 'alfred', titulo: 'registre x', criadaEm: null)))
        ..tratar(const Fim('c1'));
      expect(chat.enviar('mais'), isTrue);
      expect(enviados.last['tipo'], 'mensagem');
      expect(enviados.last['conversaId'], 'c1');
      expect(enviados.last['foco'], 'ticktask');
    });

    test('TickTask liga e desliga no meio da conversa do Alfred', () {
      final chat = EstadoChat(enviar)
        ..novaConversa('alfred')
        ..tratar(const Criada(MetaConversa(id: 'c1', perfil: 'alfred', titulo: 't', criadaEm: null)))
        ..tratar(const Fim('c1'))
        ..alternarTicktask()
        ..alternarTicktask();
      expect(chat.ticktask, isFalse);
      expect(chat.enviar('ls'), isTrue);
      expect(enviados.last['foco'], '');
    });

    test('conselheiro não manda foco', () {
      final chat = EstadoChat(enviar)
        ..novaConversa('poe')
        ..tratar(const Criada(MetaConversa(id: 'c2', perfil: 'poe', titulo: 't', criadaEm: null)))
        ..tratar(const Fim('c2'));
      expect(chat.enviar('oi'), isTrue);
      expect(enviados.last.containsKey('foco'), isFalse);
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

    test('permissão resolvida por fora (aviso ou prazo) fecha o cartão sem responder de novo', () {
      final chat = EstadoChat(enviar)..tratar(const ConversaAberta(_meta, []));
      chat
        ..tratar(const PedidoDePermissao('p1', 'ls'))
        ..tratar(const PedidoDePermissao('p2', 'rm x'))
        ..tratar(const PedidoDePermissao('p3', 'df'))
        ..tratar(const PermissaoResolvida('p1', 'aprovado'))
        ..tratar(const PermissaoResolvida('p2', 'expirado'))
        ..tratar(const PermissaoResolvida('p3', 'negado'))
        ..tratar(const PermissaoResolvida('outra', 'aprovado'));
      final situacoes = [for (final p in chat.itens.whereType<Permissao>()) p.situacao];
      expect(situacoes, [SituacaoPermissao.permitido, SituacaoPermissao.expirado, SituacaoPermissao.negado]);
      chat.responderPermissao(chat.itens.first as Permissao, permitido: false);
      expect(enviados.where((m) => m['tipo'] == 'permissao-resposta'), isEmpty);
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

  group('Presenca', () {
    List<Object?> visiveis() => [for (final e in enviados) e['conversaId']];

    test('informa a conversa na tela só em primeiro plano e sem repetir', () {
      final p = Presenca(enviar)
        ..definirNaTela('c1')
        ..definirNaTela('c1')
        ..definirPrimeiroPlano(false)
        ..definirPrimeiroPlano(true)
        ..definirNaTela(null);
      expect(enviados.every((e) => e['tipo'] == 'visivel'), isTrue);
      expect(visiveis(), ['c1', null, 'c1', null]);
      expect(p.visivel, isNull);
    });

    test('sem conexão tenta de novo na próxima mudança e repete tudo ao reconectar', () {
      online = false;
      final p = Presenca(enviar)..definirNaTela('c1');
      expect(enviados, isEmpty);
      online = true;
      p
        ..definirNaTela('c1')
        ..reconectou();
      expect(visiveis(), ['c1', 'c1']);
    });
  });
}
