import 'dart:convert';

import 'package:control_tower/estado/areas.dart';
import 'package:control_tower/estado/chat.dart';
import 'package:control_tower/estado/editor_de_workflow.dart';
import 'package:control_tower/estado/espelho.dart';
import 'package:control_tower/estado/importacao.dart';
import 'package:control_tower/estado/presenca.dart';
import 'package:control_tower/estado/equipes.dart';
import 'package:control_tower/estado/painel.dart';
import 'package:control_tower/estado/rotinas.dart';
import 'package:control_tower/estado/skills.dart';
import 'package:control_tower/estado/tarefas.dart';
import 'package:control_tower/estado/workflows.dart';
import 'package:control_tower/nucleo/editor_de_workflow.dart';
import 'package:control_tower/nucleo/espelho.dart';
import 'package:control_tower/nucleo/importacao.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/nucleo/modelos.dart';
import 'package:control_tower/nucleo/painel.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/nucleo/rotinas.dart';
import 'package:control_tower/nucleo/skills.dart';
import 'package:control_tower/nucleo/workflows.dart';
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

  group('EstadoSkills', () {
    const relatorio = Skill(dono: 'casa', id: 'relatorio-semanal', descricao: 'relatório da semana', corpo: '# passos');

    test('nova skill vai com nova: true, e a lista com o conteúdo enviado tira do rascunho', () {
      final e = EstadoSkills(enviar)
        ..tratar(const SkillsRecebidas([relatorio]))
        ..nova('poe');
      expect([e.rascunho?.nova, e.podeSalvar], [true, false]);
      e
        ..mudar(id: 'revisar-texto')
        ..mudar(descricao: ' revisa o texto ')
        ..mudar(corpo: 'passo a passo\n')
        ..salvar();
      expect(enviados.last, {
        'tipo': 'skill-salvar',
        'dono': 'poe',
        'skill': {'id': 'revisar-texto', 'descricao': 'revisa o texto', 'corpo': 'passo a passo\n'},
        'nova': true,
      });
      expect([e.salvando, e.podeSalvar], [true, false]);
      e.tratar(const SkillsRecebidas([relatorio]));
      expect([e.salvando, e.rascunho?.id], [true, 'revisar-texto']);
      e.tratar(const SkillsRecebidas([
        relatorio,
        Skill(dono: 'poe', id: 'revisar-texto', descricao: 'revisa o texto', corpo: 'passo a passo'),
      ]));
      expect([e.salvando, e.rascunho, e.erro], [false, null, null]);
    });

    test('editar manda nova: false e o erro do servidor mantém o rascunho', () {
      final e = EstadoSkills(enviar)
        ..tratar(const SkillsRecebidas([relatorio]))
        ..editar(relatorio)
        ..mudar(id: 'outro', corpo: '# outros passos')
        ..salvar();
      expect(enviados.last['nova'], false);
      expect((enviados.last['skill'] as Map)['id'], 'relatorio-semanal');
      e.tratar(const Erro('skill relatorio-semanal: não existe'));
      expect([e.salvando, e.erro, e.rascunho?.corpo], [false, 'skill relatorio-semanal: não existe', '# outros passos']);
    });

    test('rascunho inválido nem envia, e id repetido no mesmo dono é recusado', () {
      final e = EstadoSkills(enviar)
        ..tratar(const SkillsRecebidas([relatorio]))
        ..nova('casa')
        ..mudar(id: 'relatorio-semanal', descricao: 'd', corpo: 'c')
        ..salvar();
      expect(enviados, isEmpty);
      expect(e.erro, contains('já existe'));
      e.descartar();
      expect([e.rascunho, e.erro], [null, null]);
    });

    test('excluir espera a lista sem a skill, e a recusa vira erro', () {
      final e = EstadoSkills(enviar)
        ..tratar(const SkillsRecebidas([relatorio]))
        ..excluir(relatorio);
      expect(enviados.last, {'tipo': 'skill-excluir', 'dono': 'casa', 'id': 'relatorio-semanal'});
      e.tratar(const Erro('a skill relatorio-semanal está anexada a Poe'));
      expect([e.salvando, e.erro], [false, 'a skill relatorio-semanal está anexada a Poe']);
      e
        ..editar(relatorio)
        ..excluir(relatorio)
        ..tratar(const SkillsRecebidas([]));
      expect([e.salvando, e.rascunho, e.lista], [false, null, isEmpty]);
    });

    test('anexar e tirar na persona mandam persona-salvar com a lista inteira', () {
      final antes = Perfil.todos;
      addTearDown(() => Perfil.registrar(antes));
      Perfil.registrar(const [Perfil('poe', 'Poe', 'P', 0, 'o amigo', skills: ['a'])]);
      EstadoSkills(enviar)
        ..anexarNaPersona('poe', 'relatorio-semanal')
        ..anexarNaPersona('poe', 'a')
        ..tirarDaPersona('poe', 'a');
      expect(enviados.map((m) => m['persona']), [
        {'id': 'poe', 'skills': ['a', 'relatorio-semanal']},
        {'id': 'poe', 'skills': ['a']},
        {'id': 'poe', 'skills': []},
      ]);
    });

    test('anexo na posição entra no rascunho do organograma e vai pelo equipe-salvar', () {
      const casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [PosicaoResumo(id: 'executor', titulo: 'executor', persona: 'alfred')]);
      final equipes = EstadoEquipes(enviar)
        ..tratar(const EquipesRecebidas([casa]))
        ..aplicar((e) => anexarSkillNaPosicao(e, 'executor', 'relatorio-semanal'));
      expect(equipes.alterada, isTrue);
      equipes.salvar();
      final posicoes = (enviados.last['equipe'] as Map)['posicoes'] as List;
      expect((posicoes.single as Map)['skills'], ['relatorio-semanal']);
    });
  });

  group('EstadoEspelho', () {
    const salva = ConfigDoEspelho(ativo: false, projeto: 'Control Tower', tag: 'control-tower', tipos: ['aprovacao']);
    const estado = EstadoDoEspelho(conectado: true, abertos: 2);

    test('abrir a tela pede o estado, e reconectar só pede de novo com a tela aberta', () {
      final e = EstadoEspelho(enviar)..reconectou();
      expect(enviados, isEmpty);
      e.definirAberto(true);
      expect(enviados.map((m) => m['tipo']), ['espelho']);
      e
        ..reconectou()
        ..definirAberto(false)
        ..reconectou();
      expect(enviados.map((m) => m['tipo']), ['espelho', 'espelho']);
    });

    test('salvar manda espelho-salvar com a config, e a config igual à enviada tira do rascunho', () {
      final e = EstadoEspelho(enviar)..tratar(const EspelhoRecebido(salva, estado));
      expect([e.alterado, e.podeSalvar], [false, false]);
      e
        ..mudar(ativo: true, projeto: 'Casa ')
        ..marcarTipo('vaga', true)
        ..salvar();
      expect(enviados.last, {
        'tipo': 'espelho-salvar',
        'config': {'ativo': true, 'projeto': 'Casa', 'tag': 'control-tower', 'tipos': ['aprovacao', 'vaga']},
      });
      expect([e.salvando, e.podeSalvar], [true, false]);
      e.tratar(const EspelhoRecebido(salva, EstadoDoEspelho(abertos: 5)));
      expect([e.salvando, e.rascunho?.projeto, e.estado.abertos], [true, 'Casa ', 5]);
      e.tratar(const EspelhoRecebido(
          ConfigDoEspelho(ativo: true, projeto: 'Casa', tag: 'control-tower', tipos: ['aprovacao', 'vaga']), estado));
      expect([e.salvando, e.rascunho, e.erro, e.config?.ativo], [false, null, null, true]);
    });

    test('o erro do servidor mantém o rascunho, e descartar volta para a config salva', () {
      final e = EstadoEspelho(enviar)
        ..tratar(const EspelhoRecebido(salva, estado))
        ..mudar(projeto: 'Inexistente')
        ..salvar();
      e.tratar(const Erro('espelho: projeto do TickTask obrigatório'));
      expect([e.salvando, e.erro, e.rascunho?.projeto, e.vista.projeto],
          [false, 'espelho: projeto do TickTask obrigatório', 'Inexistente', 'Inexistente']);
      e.descartar();
      expect([e.rascunho, e.erro, e.vista.projeto], [null, null, 'Control Tower']);
    });

    test('rascunho inválido nem envia', () {
      final e = EstadoEspelho(enviar)
        ..tratar(const EspelhoRecebido(salva, estado))
        ..mudar(tag: '  ')
        ..salvar();
      expect(enviados, isEmpty);
      expect([e.podeSalvar, e.erro], [false, 'a tag é obrigatória']);
    });

    test('sincronizar manda espelho-sincronizar e espera o próximo espelho', () {
      final e = EstadoEspelho(enviar)
        ..tratar(const EspelhoRecebido(salva, estado))
        ..sincronizar();
      expect(enviados.last, {'tipo': 'espelho-sincronizar'});
      expect(e.sincronizando, isTrue);
      e.sincronizar();
      expect(enviados, hasLength(1));
      e.tratar(const EspelhoRecebido(salva, EstadoDoEspelho(conectado: true, abertos: 3, pendentes: 1)));
      expect([e.sincronizando, e.resumo], [false, 'desligado']);
    });
  });

  group('EstadoImportacao', () {
    PreviaDoModeloRecebida previa(Map<String, Object?> escolhas, {List<String> erros = const []}) =>
        PreviaDoModeloRecebida(PreviaDoModelo.deJson({
          'resumo': {'tipo': 'equipe', 'nome': 'Work', 'posicoes': 1},
          'personasDoModelo': [
            {'id': 'eva', 'nome': 'Eva', 'traz': true},
          ],
          'escolhas': escolhas,
          'erros': erros,
        }));
    const padrao = {
      'equipe': {'id': 'work-2', 'nome': 'Work 2'},
      'personas': {
        'eva': {'acao': 'criar'},
      },
    };
    const daqui = ['poe', 'alfred'];

    test('abrir pede a prévia sem escolhas e adota as do servidor', () {
      final e = EstadoImportacao(enviar)..abrir('{"m":1}', arquivo: 'work.json');
      expect(enviados, [
        {'tipo': 'modelo-previa', 'conteudo': '{"m":1}'},
      ]);
      expect([e.aberta, e.pendente, e.podeImportar], [true, true, false]);
      e.tratar(previa(padrao));
      expect([e.pendente, e.podeImportar, e.escolhas.equipeId], [false, true, 'work-2']);
    });

    test('só uma prévia por vez: a mudança feita no meio sai depois, com as escolhas mais novas', () {
      final e = EstadoImportacao(enviar)..abrir('{}');
      e.tratar(previa(padrao));
      e.mudar(e.escolhas.comOpcaoDePersona('eva', OpcaoDePersona.vaga, nomeNoModelo: 'Eva', personasDaqui: daqui));
      e.mudar(e.escolhas.comOpcaoDePersona('eva', OpcaoDePersona.outra, nomeNoModelo: 'Eva', personasDaqui: daqui));
      expect(enviados, hasLength(2));
      expect([e.pendente, e.podeImportar], [true, false]);
      e.tratar(previa({...padrao, 'personas': {'eva': {'acao': 'vaga'}}}));
      expect(enviados, hasLength(3));
      expect(((enviados.last['escolhas'] as Map)['personas'] as Map)['eva'], {'acao': 'usar', 'persona': 'poe'});
      expect(e.escolhas.personas['eva']!.persona, 'poe');
      expect(e.pendente, isTrue);
      e.tratar(previa({...padrao, 'personas': {'eva': {'acao': 'usar', 'persona': 'poe'}}}));
      expect([e.pendente, e.podeImportar, e.previa!.escolhas.personas['eva']!.persona], [false, true, 'poe']);
    });

    test('prévia sem pedido em voo é ignorada, e a de um arquivo anterior é descartada', () {
      final e = EstadoImportacao(enviar)..tratar(previa(padrao));
      expect(e.previa, isNull);
      e.abrir('{"velho":1}');
      e.abrir('{"novo":1}');
      expect(enviados, hasLength(1));
      e.tratar(previa(padrao));
      expect(e.previa, isNull);
      expect(enviados.last, {'tipo': 'modelo-previa', 'conteudo': '{"novo":1}'});
      e.tratar(previa(padrao));
      expect(e.previa, isNotNull);
    });

    test('campo de texto espera o fim da digitação para pedir a prévia', () async {
      final e = EstadoImportacao(enviar, espera: const Duration(milliseconds: 20))..abrir('{}');
      e.tratar(previa(padrao));
      e
        ..mudar(e.escolhas.comEquipe(id: 'w'), digitando: true)
        ..mudar(e.escolhas.comEquipe(id: 'wo'), digitando: true)
        ..mudar(e.escolhas.comEquipe(id: 'wor'), digitando: true);
      expect([enviados.length, e.pendente], [1, true]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(enviados, hasLength(2));
      expect((enviados.last['escolhas'] as Map)['equipe'], {'id': 'wor', 'nome': 'Work 2'});
      expect(e.escolhas.equipeId, 'wor');
    });

    test('com erro na prévia não importa; sem erro manda modelo-importar com as escolhas', () {
      final e = EstadoImportacao(enviar, espera: Duration.zero)..abrir('{}', destino: 'casa');
      e.tratar(previa(padrao, erros: ['equipe: id inválido']));
      e.importar();
      expect(enviados, hasLength(1));
      e.mudar(e.escolhas.comEquipe(id: 'work-3'));
      e.tratar(previa({...padrao, 'equipe': {'id': 'work-3', 'nome': 'Work 2'}}));
      e.importar();
      expect(enviados.last, {
        'tipo': 'modelo-importar',
        'conteudo': '{}',
        'destino': 'casa',
        'escolhas': {
          'equipe': {'id': 'work-3', 'nome': 'Work 2'},
          'personas': {
            'eva': {'acao': 'criar'},
          },
        },
      });
      expect([e.importando, e.ocupado, e.podeImportar], [true, true, false]);
      e.tratar(const ModeloImportado('work-3'));
      expect([e.importando, e.importado?.equipe], [false, 'work-3']);
    });

    test('erro do servidor na importação volta para a tela', () {
      final e = EstadoImportacao(enviar)..abrir('{}');
      e
        ..tratar(previa(padrao))
        ..importar()
        ..tratar(const Erro('já existe a pasta equipes/work-2'));
      expect([e.importando, e.erro, e.podeImportar], [false, 'já existe a pasta equipes/work-2', true]);
    });

    test('reconectar repede a prévia e solta a importação presa', () {
      final e = EstadoImportacao(enviar)..abrir('{}');
      e.reconectou();
      expect(enviados, hasLength(2));
      e
        ..tratar(previa(padrao))
        ..importar();
      expect(enviados, hasLength(3));
      e.reconectou();
      expect([e.importando, e.erro != null, enviados.last['tipo']], [false, true, 'modelo-previa']);
      e.fechar();
      expect([e.aberta, e.previa], [false, null]);
    });

    test('exportar devolve o modelo recebido ou falha com o erro do servidor', () async {
      final e = EstadoImportacao(enviar);
      final pedido = e.exportar('work', personas: false);
      expect(enviados.last, {'tipo': 'modelo-exportar', 'equipe': 'work', 'personas': false, 'rotinas': true});
      expect(e.ocupado, isTrue);
      await expectLater(e.exportar('work'), throwsA(isA<FalhaDeExportacao>()));
      e.tratar(const ModeloRecebido('work.ctmodelo.json', '{}'));
      expect((await pedido).nome, 'work.ctmodelo.json');
      expect(e.exportando, isFalse);
      final falha = e.exportar('casa', workflow: 'revisao');
      expect(enviados.last, {'tipo': 'modelo-exportar', 'equipe': 'casa', 'workflow': 'revisao'});
      e.tratar(const Erro('o workflow revisao não existe na equipe Casa'));
      await expectLater(falha, throwsA(predicate((f) => '$f' == 'o workflow revisao não existe na equipe Casa')));
      online = false;
      await expectLater(e.exportar('work'), throwsA(isA<FalhaDeExportacao>()));
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

  group('EstadoPainel', () {
    List<Object?> assinaturas() => [for (final e in enviados) if (e['tipo'] == 'painel') e['ativo']];

    test('assina ao entrar, desassina ao sair e não repete', () {
      EstadoPainel(enviar)
        ..definirAberto(false)
        ..definirAberto(true)
        ..definirAberto(true)
        ..definirAberto(false)
        ..definirAberto(false);
      expect(assinaturas(), [true, false]);
    });

    test('reconectar com o painel aberto assina de novo; fechado, não manda nada', () {
      final p = EstadoPainel(enviar)..reconectou();
      expect(assinaturas(), isEmpty);
      p
        ..definirAberto(true)
        ..reconectou();
      expect(assinaturas(), [true, true]);
      p
        ..definirAberto(false)
        ..reconectou();
      expect(assinaturas(), [true, true, false]);
    });

    test('sem conexão ao entrar, a assinatura sai quando reconecta', () {
      online = false;
      final p = EstadoPainel(enviar)..definirAberto(true);
      expect(enviados, isEmpty);
      online = true;
      p.reconectou();
      expect(assinaturas(), [true]);
    });

    test('retrato chega, filtros aplicam no cliente e ação manda a mensagem', () {
      final p = EstadoPainel(enviar);
      var avisos = 0;
      p
        ..addListener(() => avisos++)
        ..tratar(const PainelRecebido(Retrato(atividade: [
          ItemDeAtividade(tipo: 'entrega', quem: 'nati', texto: 'a'),
          ItemDeAtividade(tipo: 'comentario', quem: 'ueslei', texto: 'b'),
        ])));
      expect([avisos, p.atividade.length], [1, 2]);
      p.filtrar(quem: 'ueslei');
      expect(p.atividade.map((a) => a.texto), ['b']);
      p.filtrar(quem: 'ueslei', tipo: 'entrega');
      expect(p.atividade, isEmpty);
      expect(p.agir(const ItemDeAtencao(tipo: 'entrega', tarefaId: 9), 'concluir'), isA<MandarSaida>());
      expect(enviados.last, {'tipo': 'tarefa-status', 'id': 9, 'status': 'concluida'});
      final antes = enviados.length;
      expect(p.agir(const ItemDeAtencao(tipo: 'entrega', tarefaId: 9), 'abrir'), isA<IrParaTarefa>());
      expect(enviados.length, antes);
    });

    test('retrato do painel atualiza a pausa geral de Equipes', () {
      final e = EstadoEquipes(enviar)..tratar(const PainelRecebido(Retrato(pausadoTudo: true)));
      expect(e.pausadoTudo, isTrue);
    });
  });

  group('EstadoWorkflows', () {
    const pedido = Workflow(id: 'mudanca', nome: 'Mudança', equipe: 'casa', entrada: {'pedido': TipoDeValor.texto(), 'vezes': TipoDeValor('numero')});
    const livre = Workflow(id: 'livre', nome: 'Livre', equipe: 'casa');
    const outra = Workflow(id: 'x', nome: 'X', equipe: 'codigo');
    const aberto = Fluxo(id: 9, equipe: 'casa', workflow: 'mudanca', definicao: pedido, fichas: [Ficha(id: 1, no: 'a')]);
    const fechado = Fluxo(id: 8, equipe: 'casa', workflow: 'livre', definicao: livre, status: 'concluido');

    test('carrega, separa por equipe e guarda abertos e encerrados', () {
      final estado = EstadoWorkflows(enviar)..carregar();
      expect(enviados.single, {'tipo': 'workflows'});
      estado.tratar(const WorkflowsRecebidos([pedido, livre, outra], [aberto, fechado]));
      expect(estado.carregada, isTrue);
      expect(estado.daEquipe('casa').map((w) => w.id), ['mudanca', 'livre']);
      expect(estado.abertos('casa').map((f) => f.id), [9]);
      expect(estado.abertos('casa', 'livre'), isEmpty);
      expect(estado.encerrados('casa').map((f) => f.id), [8]);
      expect(estado.nomeDoWorkflow('casa', 'livre'), 'Livre');
      expect(estado.nomeDoWorkflow('casa', 'sumiu'), 'sumiu');
    });

    test('iniciar converte a entrada e só manda sem erro', () {
      final estado = EstadoWorkflows(enviar);
      expect(estado.iniciar(pedido, {'pedido': 'oi', 'vezes': 'muitas'}), ['vezes precisa ser um número']);
      expect(enviados, isEmpty);
      expect(estado.iniciar(pedido, {'pedido': ' oi ', 'vezes': '2'}), isEmpty);
      expect(enviados.single, {
        'tipo': 'workflow-iniciar',
        'equipe': 'casa',
        'id': 'mudanca',
        'entrada': {'pedido': 'oi', 'vezes': 2},
      });
    });

    test('decidir, sinalizar e cancelar mandam as mensagens do fluxo', () {
      EstadoWorkflows(enviar)
        ..decidir(9, 3, 'seguir', '  ')
        ..decidir(9, 3, 'parar', 'arriscado')
        ..sinalizar(9, 4)
        ..cancelar(9);
      expect(enviados, [
        {'tipo': 'workflow-decidir', 'execucao': 9, 'ficha': 3, 'opcao': 'seguir'},
        {'tipo': 'workflow-decidir', 'execucao': 9, 'ficha': 3, 'opcao': 'parar', 'comentario': 'arriscado'},
        {'tipo': 'workflow-sinal', 'execucao': 9, 'ficha': 4},
        {'tipo': 'workflow-cancelar', 'execucao': 9},
      ]);
    });

    test('ver um fluxo usa a definição em que ele rodou, e o fluxo pedido antes da lista se completa', () {
      final estado = EstadoWorkflows(enviar)..verFluxo(9, equipe: 'casa');
      expect([estado.vendo?.fluxo, estado.vendo?.workflow, estado.definicaoVista], [9, '', null]);
      estado.tratar(const WorkflowsRecebidos([livre], [aberto]));
      expect(estado.vendo, (equipe: 'casa', workflow: 'mudanca', fluxo: 9));
      expect(estado.definicaoVista?.nome, 'Mudança');
      estado.selecionarCaixa('a');
      expect(estado.caixa, 'a');
      estado.selecionarCaixa('a');
      expect(estado.caixa, isNull);
      estado
        ..selecionarCaixa('a')
        ..verDefinicao(livre);
      expect([estado.vendo?.fluxo, estado.definicaoVista?.id, estado.caixa], [null, 'livre', null]);
      estado.fecharGrafo();
      expect(estado.vendo, isNull);
    });

    test('rotina com workflow salva sem tarefa e valida contra os workflows da equipe', () {
      const casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [PosicaoResumo(id: 'executor', titulo: 'executor')]);
      final rotinas = EstadoRotinas(enviar)..novaRotina(casa);
      rotinas.mudar((r) => r.copiar(nome: 'Semanal', workflow: 'livre'));
      expect(rotinas.errosDoRascunho(casa), ['rotina semanal: workflow inexistente (livre)']);
      expect(rotinas.errosDoRascunho(casa, workflows: [livre]), isEmpty);
      rotinas.salvar(casa, workflows: [livre]);
      expect(enviados.single['rotina'], {
        'id': 'semanal',
        'nome': 'Semanal',
        'ativa': true,
        'workflow': 'livre',
        'concorrencia': 'pular',
        'perdidos': 'um',
      });
    });

    test('decidir pelo painel manda a opção e o comentário', () {
      const item = ItemDeAtencao(tipo: 'decisao', acoes: ['decidir'], fluxo: 9, ficha: 3, opcoes: ['seguir', 'parar']);
      final efeito = EstadoPainel(enviar).agir(item, 'decidir', opcao: 'seguir', texto: 'ok');
      expect(efeito, isA<MandarSaida>());
      expect(enviados.single, {'tipo': 'workflow-decidir', 'execucao': 9, 'ficha': 3, 'opcao': 'seguir', 'comentario': 'ok'});
    });

    test('a aba de workflows da equipe alterna com o organograma e com as rotinas', () {
      final e = EstadoEquipes(enviar)..selecionar('executor');
      e.alternarAba(AbaDaEquipe.workflows);
      expect([e.vendoWorkflows, e.vendoRotinas, e.selecionada], [true, false, null]);
      e.verRotinas(true);
      expect([e.vendoWorkflows, e.vendoRotinas], [false, true]);
      e
        ..alternarAba(AbaDaEquipe.rotinas)
        ..alternarAba(AbaDaEquipe.workflows)
        ..alternarAba(AbaDaEquipe.workflows);
      expect(e.aba, AbaDaEquipe.organograma);
    });
  });

  group('EstadoEditorDeWorkflow', () {
    const casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [PosicaoResumo(id: 'executor', titulo: 'executor', persona: 'alfred')]);
    Workflow relatorio(int versao, [String instrucao = 'faça']) => Workflow.deJson({
          'id': 'relatorio',
          'nome': 'Relatório',
          'versao': versao,
          'equipe': 'casa',
          'descricao': 'escrito à mão',
          'entrada': <String, dynamic>{},
          'inicio': 'executar',
          'nos': [
            {'id': 'executar', 'tipo': 'executar', 'posicao': 'executor', 'instrucao': instrucao},
            {'id': 'fim', 'tipo': 'fim'},
          ],
          'arestas': [
            {'de': 'executar', 'para': 'fim'},
          ],
        });
    String? instrucao(EstadoEditorDeWorkflow e) => caixaDe(e.rascunho!, 'executar')!['instrucao'] as String?;

    test('abrir, editar, desfazer e refazer; digitação no mesmo campo vira um passo só', () {
      final e = EstadoEditorDeWorkflow(enviar)..abrir(relatorio(2), casa);
      expect([e.aberto, e.alterado, e.problemas, e.versaoBase], [true, false, 0, 2]);
      e
        ..aplicar((w) => definirCampo(w, 'executar', 'instrucao', 'o'), grupo: 'instrucao')
        ..aplicar((w) => definirCampo(w, 'executar', 'instrucao', 'ou'), grupo: 'instrucao')
        ..aplicar((w) => definirCampo(w, 'executar', 'instrucao', 'outra'), grupo: 'instrucao');
      expect([e.alterado, instrucao(e)], [true, 'outra']);
      e.desfazer();
      expect([e.alterado, instrucao(e), e.podeRefazer], [false, 'faça', true]);
      e.refazer();
      expect(instrucao(e), 'outra');
      final id = e.criar('fim', (x: 500, y: 0));
      expect(e.selecionada, id);
      e.desfazer();
      expect(e.selecionada, isNull);
      expect(e.renomear('executar', 'Fazer'), isNotNull);
      expect(e.renomear('executar', 'fazer'), isNull);
      expect(caixaDe(e.rascunho!, 'fazer'), isNotNull);
    });

    test('salvar manda o rascunho com a versão em que abriu e o layout completo', () {
      final e = EstadoEditorDeWorkflow(enviar)
        ..abrir(relatorio(2), casa)
        ..aplicar((w) => definirCampo(w, 'executar', 'instrucao', 'outra'))
        ..salvar();
      expect(e.salvando, isTrue);
      final w = enviados.single['workflow'] as Map<String, dynamic>;
      expect([enviados.single['tipo'], enviados.single['equipe'], w['versao'], w['descricao']], ['workflow-salvar', 'casa', 2, 'escrito à mão']);
      expect((w['layout'] as Map).keys, containsAll(['executar', 'fim']));
      expect(w.containsKey('equipe'), isFalse);
    });

    test('sai do rascunho só quando chega a versão nova', () {
      final e = EstadoEditorDeWorkflow(enviar)
        ..abrir(relatorio(2), casa)
        ..aplicar((w) => definirCampo(w, 'executar', 'instrucao', 'outra'))
        ..salvar()
        ..tratar(WorkflowsRecebidos([relatorio(2)], const []));
      expect([e.salvando, e.alterado], [true, true]);
      e.tratar(WorkflowsRecebidos([relatorio(3, 'outra')], const []));
      expect([e.aberto, e.salvando, e.alterado, e.versaoBase, instrucao(e), e.podeDesfazer], [true, false, false, 3, 'outra', false]);
    });

    test('erro do servidor mantém o rascunho aberto com a mensagem', () {
      final e = EstadoEditorDeWorkflow(enviar)
        ..abrir(relatorio(2), casa)
        ..aplicar((w) => definirCampo(w, 'executar', 'instrucao', 'outra'))
        ..salvar()
        ..tratar(const Erro('o workflow relatorio mudou desde que você abriu'));
      expect([e.aberto, e.salvando, e.alterado, instrucao(e)], [true, false, true, 'outra']);
      expect(e.erro, contains('mudou desde'));
    });

    test('com erro de validação não salva', () {
      final e = EstadoEditorDeWorkflow(enviar)
        ..abrir(relatorio(2), casa)
        ..aplicar((w) => definirCampo(w, 'executar', 'instrucao', ''));
      expect(e.erros.keys, ['executar']);
      expect(e.podeSalvar, isFalse);
      e.salvar();
      expect(enviados, isEmpty);
      expect([e.salvando, e.erro], [false, 'Corrija o problema antes de salvar.']);
    });

    test('novo, duplicar e excluir', () {
      final e = EstadoEditorDeWorkflow(enviar);
      expect(e.criarNovo(' ', casa, const []), isNotNull);
      expect(e.criarNovo('Relatório', casa, ['relatorio']), isNull);
      expect([e.id, e.novo, e.alterado], ['relatorio-2', true, true]);
      e.excluir();
      expect([e.aberto, enviados], [false, isEmpty]);
      e.duplicar(relatorio(2), casa, ['relatorio']);
      expect([e.id, e.rascunho!['nome'], e.versaoBase], ['relatorio-copia', 'Relatório (cópia)', 0]);
      e
        ..abrir(relatorio(2), casa)
        ..excluir();
      expect(enviados.single, {'tipo': 'workflow-excluir', 'equipe': 'casa', 'id': 'relatorio'});
      e.tratar(WorkflowsRecebidos([relatorio(2)], const []));
      expect(e.aberto, isTrue);
      e.tratar(const WorkflowsRecebidos([], []));
      expect(e.aberto, isFalse);
    });

    test('iniciar pelo editor sobrepõe o fluxo novo da mesma versão', () {
      final def = relatorio(2);
      Fluxo fluxo(int id) => Fluxo(id: id, equipe: 'casa', workflow: 'relatorio', versao: 2, definicao: def);
      final e = EstadoEditorDeWorkflow(enviar)
        ..abrir(def, casa)
        ..aguardarFluxoNovo([9])
        ..tratar(WorkflowsRecebidos([def], [fluxo(9)]));
      expect(e.sobreposto, isNull);
      e.tratar(WorkflowsRecebidos([def], [fluxo(9), fluxo(10)]));
      expect(e.sobreposto, 10);
      e.aplicar((w) => definirCampo(w, 'executar', 'titulo', 'Fazer'));
      expect(e.sobreposto, isNull);
    });
  });
}
