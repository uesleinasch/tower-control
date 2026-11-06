import 'dart:convert';
import 'dart:io';

import 'package:control_tower/nucleo/avisos.dart';
import 'package:control_tower/nucleo/baloes.dart';
import 'package:control_tower/nucleo/enderecos.dart';
import 'package:control_tower/nucleo/espelho.dart';
import 'package:control_tower/nucleo/formato.dart';
import 'package:control_tower/nucleo/importacao.dart';
import 'package:control_tower/nucleo/modelos.dart';
import 'package:control_tower/nucleo/protocolo.dart';
import 'package:control_tower/nucleo/organograma.dart';
import 'package:control_tower/nucleo/painel.dart';
import 'package:control_tower/nucleo/rotinas.dart';
import 'package:control_tower/nucleo/skills.dart';
import 'package:control_tower/nucleo/tarefas.dart';
import 'package:control_tower/nucleo/workflows.dart';
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

const _disparo = {
  'id': 7,
  'equipe': 'casa',
  'rotina': 'plano-do-dia',
  'origem': 'cron',
  'horario': '2026-11-06T11:30:00.000Z',
  'em': '2026-11-06T11:30:05.000Z',
  'resultado': 'criada',
  'motivo': '',
  'tarefa': 12,
};

const _retrato = {
  'em': '2026-11-05T09:00:00.000Z',
  'pausadoTudo': true,
  'atencao': [
    {
      'tipo': 'comando',
      'titulo': 'Alfred quer rodar um comando',
      'detalhe': 'git push',
      'desde': '2026-11-05T08:50:00.000Z',
      'acoes': ['aprovar', 'negar'],
      'tarefaId': 12,
      'permissaoId': 'p9',
      'persona': 'alfred',
      'equipe': 'casa',
    },
    {
      'tipo': 'aprovacao',
      'titulo': '#13 Plano do dia',
      'detalhe': 'entrega pronta',
      'desde': '2026-11-05T08:00:00.000Z',
      'acoes': ['aprovar', 'pedir-mudanca'],
      'tarefaId': 13,
    },
  ],
  'agora': {
    'rodando': [
      {
        'execucao': 40,
        'tarefaId': 14,
        'titulo': 'Revisar backup',
        'equipe': 'casa',
        'persona': 'Nati',
        'papel': 'revisa',
        'inicio': '2026-11-05T08:58:00.000Z',
        'ultimoEvento': {'tipo': 'ferramenta', 'conteudo': 'Read docs/x.md', 'em': '2026-11-05T08:59:00.000Z'},
      },
    ],
    'naFila': [
      {'execucao': 41, 'tarefaId': 15, 'titulo': 'Relatório', 'persona': 'Alfred', 'motivo': 'tudo pausado', 'desde': '2026-11-05T08:30:00.000Z'},
    ],
  },
  'personas': [
    {'id': 'nati', 'nome': 'Nati', 'cor': '#9a6ee8', 'estado': 'rodando', 'tarefaId': 14, 'gastoMesUSD': 4.5, 'limiteUSD': 5, 'tokensMes': 1000, 'limiteTokens': null, 'abertas': 3},
  ],
  'tarefas': {
    'casa': {'a_fazer': 2, 'em_revisao': 1},
    'codigo': {'concluida': 4},
  },
  'gasto': {'mes': '2026-11', 'tarefasUSD': 1.25, 'totalUSD': 3.5, 'tokensTarefas': 120000, 'tokensTotal': 400000},
  'proximasRotinas': [
    {'equipe': 'casa', 'id': 'plano-do-dia', 'nome': 'Plano do dia', 'proximo': '2026-11-06T11:30:00.000Z'},
  ],
  'atividade': [
    {'em': '2026-11-05T08:59:00.000Z', 'tipo': 'entrega', 'quem': 'nati', 'texto': 'feito', 'tarefaId': 14, 'equipe': 'casa'},
    {'em': '2026-11-05T08:00:00.000Z', 'tipo': 'auditoria', 'quem': 'ueslei', 'texto': 'pausou tudo'},
    {'em': '2026-11-05T07:30:00.000Z', 'tipo': 'disparo', 'quem': 'Plano do dia', 'texto': 'criou a #13', 'tarefaId': 13},
  ],
};

const _mudancaComPlano = {
  'id': 'mudanca-com-plano',
  'nome': 'Mudança com plano',
  'versao': 3,
  'entrada': {'pedido': 'texto'},
  'inicio': 'plano',
  'nos': [
    {
      'id': 'plano',
      'tipo': 'executar',
      'posicao': 'conselho-nati',
      'instrucao': 'Escreva um plano para: {{entrada.pedido}}',
      'criterio': 'Passos numerados e os riscos.',
      'saidas': {
        'plano': 'texto',
        'risco': {'escolha': ['baixo', 'alto']},
      },
    },
    {
      'id': 'risco',
      'tipo': 'condicao',
      'regras': [
        {'campo': 'plano.risco', 'op': 'igual', 'valor': 'alto', 'saida': 'alto'},
      ],
    },
    {'id': 'ok', 'tipo': 'decisao_humana', 'pergunta': 'Risco alto. Seguir?', 'opcoes': ['seguir', 'parar']},
    {'id': 'frente', 'tipo': 'paralelo'},
    {'id': 'executa', 'tipo': 'executar', 'posicao': 'executor', 'instrucao': 'Execute: {{plano.plano}}'},
    {'id': 'revisa', 'tipo': 'revisar', 'de': 'executa', 'por': {'posicao': 'conselho-nati'}},
    {'id': 'nota', 'tipo': 'executar', 'posicao': 'conselho-pami', 'instrucao': 'Escreva a nota de mudança de: {{plano.plano}}'},
    {'id': 'junta', 'tipo': 'juncao'},
    {'id': 'fim', 'tipo': 'fim'},
    {'id': 'parou', 'tipo': 'fim', 'resultado': 'cancelado pelo Ueslei'},
  ],
  'arestas': [
    {'de': 'plano', 'para': 'risco'},
    {'de': 'risco', 'para': 'ok', 'quando': 'alto'},
    {'de': 'risco', 'para': 'frente', 'quando': 'senao'},
    {'de': 'ok', 'para': 'frente', 'quando': 'seguir'},
    {'de': 'ok', 'para': 'parou', 'quando': 'parar'},
    {'de': 'frente', 'para': 'executa'},
    {'de': 'frente', 'para': 'nota'},
    {'de': 'executa', 'para': 'revisa'},
    {'de': 'revisa', 'para': 'junta', 'quando': 'aprovado'},
    {'de': 'nota', 'para': 'junta'},
    {'de': 'junta', 'para': 'fim'},
  ],
  'layout': {},
};

Map<String, Object?> _ficha(int id, String no, String status, {int? veioDe, int? tarefa, Map<String, Object?> saidas = const {}}) => {
      'id': id,
      'fluxo': 9,
      'no': no,
      'status': status,
      'tarefa': tarefa,
      'veioDe': veioDe,
      'chegadas': <String>[],
      'saidas': saidas,
      'acordaEm': null,
      'prazoEm': null,
      'avisada': false,
      'criadaEm': '2026-11-05T09:00:00.000Z',
      'concluidaEm': status == 'esperando' ? null : '2026-11-05T09:10:00.000Z',
    };

final _fluxo = <String, Object?>{
  'id': 9,
  'equipe': 'casa',
  'workflow': 'mudanca-com-plano',
  'versao': 3,
  'definicao': _mudancaComPlano,
  'entrada': {'pedido': 'trocar o disco'},
  'status': 'rodando',
  'resultado': null,
  'criadoPor': 'ueslei',
  'depoisDe': null,
  'criadoEm': '2026-11-05T09:00:00.000Z',
  'atualizadoEm': '2026-11-05T09:10:00.000Z',
  'erro': null,
  'fichas': [
    _ficha(1, 'plano', 'concluida', tarefa: 20, saidas: {'devolutiva': 'feito', 'plano': '1. backup\n2. troca', 'risco': 'alto'}),
    _ficha(2, 'risco', 'concluida', veioDe: 1),
    _ficha(3, 'ok', 'concluida', veioDe: 2, saidas: {'opcao': 'seguir', 'comentario': ''}),
    _ficha(4, 'frente', 'concluida', veioDe: 3),
    _ficha(5, 'executa', 'esperando', veioDe: 4, tarefa: 21),
    _ficha(6, 'nota', 'concluida', veioDe: 4, tarefa: 22, saidas: {'devolutiva': 'nota pronta'}),
    _ficha(7, 'junta', 'esperando', veioDe: 6),
  ],
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
          {'id': 'executor', 'titulo': 'executor de tarefas', 'persona': 'alfred', 'personaNome': 'Alfred', 'skills': ['relatorio-semanal']},
          {'id': 'vaga', 'titulo': 'revisora', 'persona': null, 'personaNome': null},
        ],
      },
    ],
  },
  'erro': {'mensagem': 'falhou'},
  'espelho': {
    'config': {'ativo': true, 'projeto': 'Control Tower', 'tag': 'control-tower', 'tipos': ['aprovacao', 'decisao']},
    'estado': {'conectado': true, 'ultimaVolta': '2026-11-05T13:04:00.000Z', 'erro': null, 'abertos': 3, 'pendentes': 1},
  },
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
  'painel': {'retrato': _retrato},
  'personas': {
    'lista': [
      {'id': 'vera', 'nome': 'Vera', 'inicial': 'V', 'cor': '#112233', 'titulo': 'revisora', 'conversa': true, 'executor': false, 'excluivel': true, 'modelo': null, 'gerandoPerfil': true, 'skills': ['relatorio-semanal']},
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
  'skills': {
    'lista': [
      {
        'dono': 'casa',
        'id': 'relatorio-semanal',
        'descricao': 'Como escrever o relatório da semana',
        'corpo': '# Relatório\n\n1. junte as tarefas',
        'arquivos': ['modelo.md'],
        'usadaPor': {
          'personas': ['vera'],
          'posicoes': ['casa/executor'],
        },
      },
      {
        'dono': 'vera',
        'id': 'revisar-texto',
        'descricao': '',
        'corpo': '',
        'arquivos': [],
        'erro': 'a descrição é obrigatória',
        'usadaPor': {'personas': [], 'posicoes': []},
      },
    ],
  },
  'rotinas': {
    'lista': [
      {
        'id': 'plano-do-dia',
        'nome': 'Plano do dia',
        'ativa': true,
        'posicao': 'executor',
        'tarefa': {'titulo': 'Plano do dia {data}', 'porque': 'organizar o dia'},
        'cron': '30 8 * * 1-5',
        'webhook': true,
        'concorrencia': 'pular',
        'perdidos': 'um',
        'equipe': 'casa',
        'proximo': '2026-11-09T11:30:00.000Z',
        'ultimoDisparo': _disparo,
        'disparos': [_disparo],
        'token': 'abc123',
        'url': '/rotinas/casa/plano-do-dia',
      },
      {'id': 'memoria', 'nome': 'Agenda da memória', 'cron': '*/5 * * * *', 'equipe': null, 'sistema': true, 'proximo': null, 'ultimoDisparo': null, 'disparos': []},
    ],
  },
  'workflows': {
    'definicoes': [
      {..._mudancaComPlano, 'equipe': 'casa'},
    ],
    'fluxos': [_fluxo],
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
  'modelo': {'nome': 'work.ctmodelo.json', 'conteudo': '{"formato":"control-tower/modelo"}'},
  'modelo-previa': _previaDeEquipe,
  'modelo-importado': {'equipe': 'work-2'},
};

const _previaDeEquipe = <String, Object?>{
  'resumo': {
    'tipo': 'equipe',
    'nome': 'Work',
    'exportadoEm': '2026-11-05T12:00:00.000Z',
    'posicoes': 3,
    'personas': 2,
    'workflows': 1,
    'rotinas': 1,
    'skills': 2,
  },
  'personasDoModelo': [
    {'id': 'nati', 'nome': 'Nati', 'traz': true},
    {'id': 'eva', 'nome': 'Eva', 'traz': true},
    {'id': 'zed', 'nome': 'zed', 'traz': false},
  ],
  'posicoesDoModelo': [],
  'entra': ['equipe Work 2 (work-2) com 3 posições'],
  'escolhas': {
    'equipe': {'id': 'work-2', 'nome': 'Work 2'},
    'personas': {
      'nati': {'acao': 'usar', 'persona': 'nati'},
      'eva': {'acao': 'criar'},
      'zed': {'acao': 'vaga'},
    },
    'skills': {
      'relatorio': {'acao': 'usar'},
    },
  },
  'avisos': ['a skill relatorio daqui é diferente da do modelo; fica a daqui'],
  'erros': [],
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
  const SalvarDadosDaPersona('alfred', nome: 'Alfred', modelo: 'sonnet'),
  const Pausar('*'),
  const Retomar('alfred'),
  const AprovarPlano(3),
  const AssinarPainel(ativo: true),
  const DecidirTarefa.aprovar(3),
  const PedirRotinas(),
  const DispararRotina('casa', 'plano-do-dia'),
  const AtivarRotina('casa', 'plano-do-dia', ativa: false),
  const SalvarRotina('casa', Rotina(id: 'plano-do-dia', nome: 'Plano do dia', posicao: 'executor', titulo: 't')),
  const ExcluirRotina('casa', 'plano-do-dia'),
  const TrocarTokenDaRotina('casa', 'plano-do-dia'),
  const PedirWorkflows(),
  const IniciarWorkflow('casa', 'mudanca-com-plano', {'pedido': 'x'}),
  const DecidirWorkflow(9, 3, 'seguir'),
  const SinalizarWorkflow(9, 4),
  const CancelarWorkflow(9),
  const SalvarWorkflow('casa', _mudancaComPlano),
  const ExcluirWorkflow('casa', 'mudanca-com-plano'),
  const PedirSkills(),
  const SalvarSkill(RascunhoDeSkill(dono: 'casa', id: 'relatorio-semanal', descricao: 'd', corpo: 'c')),
  const ExcluirSkill('casa', 'relatorio-semanal'),
  const SalvarSkillsDaPersona('poe', ['relatorio-semanal']),
  const PedirEspelho(),
  const SalvarEspelho(ConfigDoEspelho()),
  const SincronizarEspelho(),
  const ExportarModelo('casa'),
  const PedirPreviaDoModelo('{}'),
  const ImportarModelo('{}', escolhas: EscolhasDoModelo()),
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

  group('rotinas', () {
    const casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [
      PosicaoResumo(id: 'executor', titulo: 'executor', persona: 'alfred', capacidades: ['comandos'], aprovacao: 'auto'),
      PosicaoResumo(id: 'revisora', titulo: 'revisora', capacidades: ['comandos']),
    ]);
    const plano = Rotina(id: 'plano-do-dia', nome: 'Plano do dia', posicao: 'executor', titulo: 'Plano do dia {data}', cron: '30 8 * * 1-5');
    String? erroDe(String cron) {
      try {
        lerCron(cron);
        return null;
      } on ErroDeCron catch (e) {
        return e.mensagem;
      }
    }

    test('rotinas decodificam com disparos, token e a de sistema; padrões seguros', () {
      final e = Entrada.decodificar(jsonEncode({'tipo': 'rotinas', ..._fixturasEntrada['rotinas']!})) as RotinasRecebidas;
      final [r, sistema] = e.lista;
      expect([r.id, r.nome, r.titulo, r.porque, r.descricao, r.cron, r.webhook, r.token, r.url],
          ['plano-do-dia', 'Plano do dia', 'Plano do dia {data}', 'organizar o dia', '', '30 8 * * 1-5', true, 'abc123', '/rotinas/casa/plano-do-dia']);
      expect(r.proximo!.isAtSameMomentAs(DateTime.utc(2026, 11, 9, 11, 30)), isTrue);
      expect(r.proximo!.isUtc, isFalse);
      expect([r.ultimoDisparo!.tarefa, r.ultimoDisparo!.origem, r.disparos.single.resultado], [12, 'cron', 'criada']);
      expect(r.ultimoDisparo!.resumo, 'horário · criou a tarefa · #12');
      expect([sistema.sistema, sistema.equipe, sistema.ativa, sistema.concorrencia, sistema.perdidos, sistema.ultimoDisparo],
          [true, null, true, 'pular', 'um', null]);
      final vazia = Rotina.deJson(const {});
      expect([vazia.ativa, vazia.concorrencia, vazia.perdidos, vazia.webhook, vazia.disparos], [true, 'pular', 'um', false, isEmpty]);
    });

    test('rotina-salvar leva a definição sem campos vazios', () {
      final json = jsonDecode(SalvarRotina('casa', plano.copiar(porque: '  ', descricao: ' ler a agenda ')).codificar()) as Map;
      expect(json, {
        'tipo': 'rotina-salvar',
        'equipe': 'casa',
        'rotina': {
          'id': 'plano-do-dia',
          'nome': 'Plano do dia',
          'ativa': true,
          'posicao': 'executor',
          'tarefa': {'titulo': 'Plano do dia {data}', 'descricao': 'ler a agenda'},
          'cron': '30 8 * * 1-5',
          'concorrencia': 'pular',
          'perdidos': 'um',
        },
      });
      expect((jsonDecode(SalvarRotina('casa', plano.copiar(cron: '', webhook: true)).codificar())['rotina'] as Map)['webhook'], true);
      expect(jsonDecode(const AtivarRotina('casa', 'x', ativa: false).codificar()),
          {'tipo': 'rotina-ativar', 'equipe': 'casa', 'id': 'x', 'ativa': false});
    });

    test('cron de dias úteis: sábado aponta para segunda 08:30', () {
      final cron = lerCron('30 8 * * 1-5');
      final sabado = DateTime(2026, 11, 7, 10, 0);
      expect(sabado.weekday, DateTime.saturday);
      expect(proximoHorario(cron, sabado), DateTime(2026, 11, 9, 8, 30));
      expect(proximosHorarios(cron, sabado, 3), [DateTime(2026, 11, 9, 8, 30), DateTime(2026, 11, 10, 8, 30), DateTime(2026, 11, 11, 8, 30)]);
      expect(proximoHorario(cron, DateTime(2026, 11, 9, 8, 30, 20)), DateTime(2026, 11, 10, 8, 30));
    });

    test('dia do mês e dia da semana restritos juntos valem como "ou"; 7 é domingo', () {
      final ou = lerCron('0 0 31 * 1');
      expect(proximosHorarios(ou, DateTime(2026, 10, 29, 12), 3),
          [DateTime(2026, 10, 31), DateTime(2026, 11, 2), DateTime(2026, 11, 9)]);
      expect(proximoHorario(lerCron('0 9 * * 7'), DateTime(2026, 11, 7, 10)), DateTime(2026, 11, 8, 9));
      expect(lerCron('0 9 * * 7').semana, {0});
      expect(proximoHorario(lerCron('0 0 1 1 *'), DateTime(2026, 11, 5)), DateTime(2027, 1, 1));
    });

    test('listas, faixas e passos', () {
      expect(lerCron('*/20 * * * *').minutos, {0, 20, 40});
      expect(lerCron('10-30/10 * * * *').minutos, {10, 20, 30});
      expect(lerCron('50/5 * * * *').minutos, {50, 55});
      expect(lerCron('0,15,45 * * * *').minutos, {0, 15, 45});
      expect(lerCron('0 * * * 5-7').semana, {5, 6, 0});
    });

    test('erros do cron com as mensagens do servidor', () {
      expect(erroDe('61 * * * *'), 'minuto: 61 fora de 0–59');
      expect(erroDe('* * *'), 'use 5 campos: minuto hora dia-do-mês mês dia-da-semana');
      expect(erroDe('5-1 * * * *'), 'minuto: faixa 5-1 invertida');
      expect(erroDe('a * * * *'), 'minuto: "a" não é número');
      expect(erroDe('0 24 * * *'), 'hora: 24 fora de 0–23');
      expect(erroDe('0 0 0 * *'), 'dia do mês: 0 fora de 1–31');
      expect(erroDe('0 0 * JAN *'), 'mês: "JAN" não é número');
      expect(erroDe('1/2/3 * * * *'), 'minuto: "1/2/3" inválido');
      expect(erroDe('0 0 * * 8'), 'dia da semana: 8 fora de 0–7');
      expect(erroDe('*/0 * * * *'), 'minuto: 0 fora de 1–60');
    });

    test('intervalo mínimo conta a virada do dia', () {
      expect(menorIntervaloEmMinutos(lerCron('*/20 * * * *')), 20);
      expect(menorIntervaloEmMinutos(lerCron('*/10 * * * *')), 10);
      expect(menorIntervaloEmMinutos(lerCron('0,50 * * * *')), 10);
      expect(menorIntervaloEmMinutos(lerCron('55 23 * * *')), 1440);
      expect(menorIntervaloEmMinutos(lerCron('0 8,20 * * *')), 720);
    });

    test('validação espelha a do servidor', () {
      expect(errosDaRotina(plano, casa), isEmpty);
      expect(errosDaRotina(plano.copiar(cron: '*/20 * * * *'), casa), isEmpty);
      expect(errosDaRotina(plano.copiar(cron: '55 23 * * *'), casa), isEmpty);
      expect(errosDaRotina(plano.copiar(cron: ''), casa), isEmpty);
      expect(errosDaRotina(plano.copiar(cron: '*/10 * * * *'), casa),
          ['rotina plano-do-dia: o cron dispara com menos de 15 minutos de intervalo']);
      expect(errosDaRotina(plano.copiar(cron: '0,50 * * * *'), casa),
          ['rotina plano-do-dia: o cron dispara com menos de 15 minutos de intervalo']);
      expect(errosDaRotina(plano.copiar(cron: '61 * * * *'), casa),
          ['rotina plano-do-dia: cron inválido (minuto: 61 fora de 0–59)']);
      expect(errosDaRotina(plano.copiar(id: 'Plano'), casa), ['rotina: id inválido (Plano)']);
      expect(errosDaRotina(plano.copiar(nome: ' ', titulo: '', posicao: 'sumiu', concorrencia: 'x', perdidos: 'y'), casa), [
        'rotina plano-do-dia: nome obrigatório',
        'rotina plano-do-dia: título da tarefa obrigatório',
        'rotina plano-do-dia: posição inexistente (sumiu)',
        'rotina plano-do-dia: concorrência inválida',
        'rotina plano-do-dia: perdidos inválido',
      ]);
    });

    test('título, autor, id novo, atalhos e aviso do webhook', () {
      expect(tituloDaTarefa('Plano do dia {data} às {hora}', DateTime(2026, 11, 5, 8, 30)), 'Plano do dia 05/11 às 08:30');
      expect(rotinaDoAutor('rotina:casa/plano-do-dia'), (equipe: 'casa', id: 'plano-do-dia'));
      expect(rotinaDoAutor('ueslei'), isNull);
      expect(rotinaDoAutor(null), isNull);
      expect(idDaNovaRotina('Plano do Dia', ['plano-do-dia']), 'plano-do-dia-2');
      expect(idDaNovaRotina('', const []), 'rotina');
      expect([cronTodoDia(8, 30), cronDiasUteis(8, 30), cronSemanal(1, 9, 0), cronACadaHoras(4), cronACadaHoras(1)],
          ['30 8 * * *', '30 8 * * 1-5', '0 9 * * 1', '0 */4 * * *', '0 * * * *']);
      expect(lerHoraMinuto('8:30'), (hora: 8, minuto: 30));
      expect(lerHoraMinuto('9'), (hora: 9, minuto: 0));
      expect(lerHoraMinuto('24:00'), isNull);
      expect(horarioCurto(DateTime(2026, 11, 9, 8, 30)), 'seg 09/11 08:30');
      expect(webhookArriscado(plano.copiar(webhook: true), casa), isTrue);
      expect(webhookArriscado(plano, casa), isFalse);
      expect(webhookArriscado(plano.copiar(webhook: true, posicao: 'revisora'), casa), isFalse);
      expect(urlDoWebhook('192.168.0.5:7878', '/rotinas/casa/x'), 'http://192.168.0.5:7878/rotinas/casa/x');
      expect(descricaoDoGatilho(plano.copiar(cron: '', webhook: false)), 'só manual');
    });

    test('tarefa traz criadaPor', () {
      expect(Tarefa.deJson({..._tarefa, 'criadaPor': 'rotina:casa/plano-do-dia'}).criadaPor, 'rotina:casa/plano-do-dia');
    });

    test('erros presos ao campo e prévia do cron', () {
      expect(errosDosCamposDaRotina(plano, casa), isEmpty);
      expect(errosDosCamposDaRotina(plano.copiar(nome: '', titulo: ' ', posicao: 'sumiu', cron: '*/5 * * * *'), casa), {
        CampoDaRotina.nome: 'nome obrigatório',
        CampoDaRotina.titulo: 'título da tarefa obrigatório',
        CampoDaRotina.posicao: 'posição inexistente (sumiu)',
        CampoDaRotina.cron: 'o cron dispara com menos de 15 minutos de intervalo',
      });
      expect(errosDosCamposDaRotina(plano.copiar(id: 'X'), casa), {CampoDaRotina.id: 'id inválido (X)'});
      expect(erroDoCronDaRotina(''), isNull);
      expect(erroDoCronDaRotina('0 9 * * 1'), isNull);
      expect(erroDoCronDaRotina('0 9 * *'), 'cron inválido (use 5 campos: minuto hora dia-do-mês mês dia-da-semana)');
      final sabado = DateTime(2026, 11, 7, 10);
      expect(previaDoCron('30 8 * * 1-5', sabado), 'Próximas: seg 09/11 08:30 · ter 10/11 08:30 · qua 11/11 08:30');
      expect(previaDoCron('', sabado), '');
      expect(previaDoCron('0 9 * *', sabado), '');
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

    test('equipe nova não tem personas, e adicionar uma persona cria a posição ocupada por ela', () {
      const nova = EquipeResumo(id: 'nova', nome: 'Nova', posicoes: []);
      final vazia = personasDaEquipe(nova, ['poe', 'nati']);
      expect(vazia.naEquipe, isEmpty);
      expect(vazia.disponiveis, ['poe', 'nati']);

      final r = adicionarPersona(nova, 'nati', 'conselheira');
      expect(r.equipe.posicao(r.id)!.persona, 'nati');
      expect(r.equipe.posicao(r.id)!.titulo, 'conselheira');
      expect(r.equipe.posicao(r.id)!.respondeA, isNull);
      final depois = personasDaEquipe(r.equipe, ['poe', 'nati']);
      expect(depois.naEquipe, {'nati': ['conselheira']});
      expect(depois.disponiveis, ['poe']);
    });

    test('remover persona tira todas as posições dela e religa as subordinadas', () {
      final dupla = adicionarPersona(codigo(), 'nati', 'revisora técnica').equipe;
      final sem = removerPersona(dupla, 'nati');
      expect(sem.posicoes.where((p) => p.persona == 'nati'), isEmpty);
      expect(sem.posicao('executor')!.respondeA, isNull);
      expect(sem.posicao('revisora')!.respondeA, 'executor');
      expect(removerPersona(codigo(), 'poe').posicoes.length, 3);
    });

    test('equipes da persona juntam as posições de todas as equipes', () {
      final pesquisa = adicionarPersona(const EquipeResumo(id: 'pesquisa', nome: 'Pesquisa', posicoes: []), 'nati', 'revisora').equipe;
      final equipes = [adicionarPersona(codigo(), 'nati', 'arquiteta').equipe, pesquisa];
      final daNati = equipesDaPersona(equipes, 'nati');
      expect([for (final x in daNati) x.equipe.id], ['codigo', 'pesquisa']);
      expect(daNati.first.posicoes, ['tech lead', 'arquiteta']);
      expect(contarPosicoes(equipes, 'nati'), 3);
      expect(contarPosicoes(equipes, 'poe'), 0);
      expect(equipesDaPersona(equipes, 'poe'), isEmpty);
    });

    test('rodando vem da tarefa rodando: executora fora de etapa, revisora na etapa', () {
      Tarefa tarefa(String posicao, {bool rodando = true, int? etapa, String status = 'em_andamento'}) => Tarefa(
            id: 1,
            equipe: 'codigo',
            posicao: posicao,
            titulo: 't',
            status: status,
            atualizadaEm: DateTime(2026),
            rodando: rodando,
            etapa: etapa,
            politica: const [EtapaDePolitica.revisaoPor('tech-lead')],
          );
      expect(personasRodando([tarefa('executor')], [codigo()]), {'alfred'});
      expect(personasRodando([tarefa('executor', rodando: false)], [codigo()]), isEmpty);
      expect(personasRodando([tarefa('executor', etapa: 0, status: 'em_revisao')], [codigo()]), {'nati'});
      expect(personasRodando([tarefa('revisora')], [codigo()]), isEmpty);
      expect(personasRodando([tarefa('executor')], const []), isEmpty);
    });

    test('título ao entrar usa o papel ou o nome, e a lista de nomes junta com "e"', () {
      expect(tituloAoEntrar(const Perfil('vera', 'Vera', 'V', 0, '  auditora ')), 'auditora');
      expect(tituloAoEntrar(const Perfil('vera', 'Vera', 'V', 0, '')), 'Vera');
      expect(juntarComE(const []), '');
      expect(juntarComE(const ['Nati']), 'Nati');
      expect(juntarComE(const ['Nati', 'Alfred']), 'Nati e Alfred');
      expect(juntarComE(const ['Poe', 'Nati', 'Alfred']), 'Poe, Nati e Alfred');
    });

    test('salvar dados da persona manda nome e modelo, e a cor só quando muda', () {
      final semCor = jsonDecode(const SalvarDadosDaPersona('poe', nome: 'Poe', modelo: null).codificar()) as Map;
      expect(semCor['tipo'], 'persona-salvar');
      expect(semCor['persona'], {'id': 'poe', 'nome': 'Poe', 'modelo': null});
      final comCor = jsonDecode(
        const SalvarDadosDaPersona('poe', nome: 'Poe', modelo: 'opus', cor: '#4fae7c', mudarCor: true).codificar(),
      ) as Map;
      expect(comCor['persona'], {'id': 'poe', 'nome': 'Poe', 'modelo': 'opus', 'cor': '#4fae7c'});
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

    test('deslocar move o cartão em passos e para no zero', () {
      final e = deslocar(codigo(), 'revisora', passoDeMover, -passoDeMover);
      expect(e.ponto('revisora'), (x: 280 + passoDeMover, y: 320 - passoDeMover));
      expect(deslocar(codigo(), 'tech-lead', -passoDeMover, -passoDeMover).ponto('tech-lead'), (x: 0, y: 0));
      expect(() => deslocar(codigo(), 'nada', passoDeMover, 0), throwsA(isA<ErroDeOrganograma>()));
    });

    test('vistaComCartao só desloca a vista quando o cartão sai da tela', () {
      final e = codigo();
      const v = (dx: 100.0, dy: 100.0, escala: 1.0);
      expect(vistaComCartao(v, e, 'tech-lead', 800, 600), v);
      final aDireita = vistaComCartao(v, e, 'revisora', 400, 600);
      final canto = cantoDoCartao(e, 'revisora');
      expect(canto.x + larguraDoCartao + aDireita.dx, 400 - 24);
      expect(aDireita.dy, 100);
      final abaixo = vistaComCartao(v, e, 'revisora', 800, 300);
      expect(canto.y + alturaDoCartao + abaixo.dy, 300 - 24);
      final aEsquerda = vistaComCartao((dx: -500.0, dy: 0.0, escala: 1.0), e, 'tech-lead', 800, 600);
      expect(cantoDoCartao(e, 'tech-lead').x + aEsquerda.dx, 24);
      expect(vistaComCartao(v, e, 'nada', 800, 600), v);
    });

    test('estado da pausa da persona segue o mapa de estados', () {
      expect(estadoDaPausa(null), isNull);
      expect(estadoDaPausa('ueslei'), 'pausada');
      expect(estadoDaPausa('tudo'), 'pausada');
      expect(estadoDaPausa('orcamento'), 'sem_orcamento');
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

  group('painel', () {
    Retrato decodificar(Object? retrato) =>
        (Entrada.decodificar(jsonEncode({'tipo': 'painel', 'retrato': retrato})) as PainelRecebido).retrato;

    test('retrato completo decodifica todas as seções', () {
      final r = decodificar(_retrato);
      expect([r.pausadoTudo, r.em], [true, DateTime.utc(2026, 11, 5, 9)]);
      expect(r.atencao.map((a) => [a.tipo, a.acoes, a.tarefaId, a.permissaoId, a.persona]), [
        ['comando', ['aprovar', 'negar'], 12, 'p9', 'alfred'],
        ['aprovacao', ['aprovar', 'pedir-mudanca'], 13, null, null],
      ]);
      final viva = r.rodando.single;
      expect([viva.execucao, viva.tarefaId, viva.persona, viva.papel], [40, 14, 'Nati', 'revisa']);
      expect([viva.ultimoEvento?.tipo, viva.ultimoEvento?.conteudo], ['ferramenta', 'Read docs/x.md']);
      expect([r.naFila.single.motivo, r.naFila.single.persona], ['tudo pausado', 'Alfred']);
      final nati = r.personas.single;
      expect(
        [nati.cor, nati.estado, nati.tarefaId, nati.limiteUSD, nati.limiteTokens, nati.abertas, nati.proporcaoDoLimite],
        [0xFF9A6EE8, 'rodando', 14, 5.0, null, 3, 0.9],
      );
      expect(r.tarefas, {
        'casa': {'a_fazer': 2, 'em_revisao': 1},
        'codigo': {'concluida': 4},
      });
      expect([r.gasto.mes, r.gasto.tarefasUSD, r.gasto.tokensTotal], ['2026-11', 1.25, 400000]);
      expect(r.proximasRotinas.single.proximo, DateTime.utc(2026, 11, 6, 11, 30));
      expect(r.atividade.map((a) => a.tipo), ['entrega', 'auditoria', 'disparo']);
    });

    test('campos ausentes ou com tipo errado caem em padrões seguros', () {
      for (final vazio in [null, <String, Object?>{}, 'lixo']) {
        final r = decodificar(vazio);
        expect(
          [r.em, r.pausadoTudo, r.atencao, r.rodando, r.naFila, r.personas, r.tarefas, r.proximasRotinas, r.atividade],
          [null, false, isEmpty, isEmpty, isEmpty, isEmpty, isEmpty, isEmpty, isEmpty],
        );
        expect([r.gasto.mes, r.gasto.totalUSD, r.gasto.tokensTarefas], ['', 0, 0]);
      }
      final r = decodificar({
        'agora': {
          'rodando': [<String, Object?>{}],
          'naFila': [<String, Object?>{}],
        },
        'atencao': [
          {'acoes': ['abrir', 3]},
        ],
        'personas': [
          {'id': 'vera'},
        ],
        'tarefas': {
          'casa': {'a_fazer': 'dois', 'backlog': 1},
          'ruim': 3,
        },
        'proximasRotinas': [<String, Object?>{}],
        'atividade': [<String, Object?>{}, 'nada'],
      });
      final viva = r.rodando.single;
      expect(
        [viva.execucao, viva.tarefaId, viva.titulo, viva.persona, viva.papel, viva.inicio, viva.ultimoEvento],
        [0, 0, '', null, 'executa', null, null],
      );
      final espera = r.naFila.single;
      expect([espera.tarefaId, espera.persona, espera.motivo, espera.desde], [0, null, '', null]);
      final item = r.atencao.single;
      expect(
        [item.tipo, item.titulo, item.detalhe, item.desde, item.acoes, item.tarefaId, item.permissaoId],
        ['', '', '', null, ['abrir'], null, null],
      );
      final vera = r.personas.single;
      expect(
        [vera.nome, vera.cor, vera.estado, vera.tarefaId, vera.gastoMesUSD, vera.limiteUSD, vera.tokensMes, vera.abertas],
        ['vera', 0xFF8B93A7, 'ocioso', null, 0, null, 0, 0],
      );
      expect(vera.proporcaoDoLimite, isNull);
      expect(r.tarefas, {
        'casa': {'backlog': 1},
        'ruim': <String, int>{},
      });
      expect([r.proximasRotinas.single.nome, r.proximasRotinas.single.proximo], ['', null]);
      expect(r.atividade.single.em, isNull);
    });

    test('cada ação vira a mensagem que as telas já mandam', () {
      Map<String, Object?>? mensagem(ItemDeAtencao item, String acao, {String? texto}) =>
          switch (efeitoDaAcao(item, acao, texto: texto)) {
            MandarSaida(:final saida) => jsonDecode(saida.codificar()) as Map<String, Object?>,
            _ => null,
          };
      const comando = ItemDeAtencao(tipo: 'comando', permissaoId: 'p9', tarefaId: 12);
      const aprovacao = ItemDeAtencao(tipo: 'aprovacao', tarefaId: 13);
      const plano = ItemDeAtencao(tipo: 'plano', tarefaId: 14);
      const entrega = ItemDeAtencao(tipo: 'entrega', tarefaId: 15);
      const backlog = ItemDeAtencao(tipo: 'backlog', tarefaId: 16);
      expect(mensagem(comando, 'aprovar'), {'tipo': 'permissao-resposta', 'id': 'p9', 'permitido': true});
      expect(mensagem(comando, 'negar'), {'tipo': 'permissao-resposta', 'id': 'p9', 'permitido': false});
      expect(mensagem(aprovacao, 'aprovar'), {'tipo': 'tarefa-decidir', 'id': 13, 'decisao': 'aprovar'});
      expect(
        mensagem(aprovacao, 'pedir-mudanca', texto: '  refaz o resumo  '),
        {'tipo': 'tarefa-decidir', 'id': 13, 'decisao': 'mudanca', 'texto': 'refaz o resumo'},
      );
      expect(efeitoDaAcao(aprovacao, 'pedir-mudanca'), isNull);
      expect(efeitoDaAcao(aprovacao, 'pedir-mudanca', texto: '   '), isNull);
      expect(mensagem(plano, 'aprovar-plano'), {'tipo': 'tarefa-aprovar-plano', 'id': 14});
      expect(mensagem(entrega, 'concluir'), {'tipo': 'tarefa-status', 'id': 15, 'status': 'concluida'});
      expect(mensagem(backlog, 'liberar'), {'tipo': 'tarefa-status', 'id': 16, 'status': 'a_fazer'});
      expect(efeitoDaAcao(const ItemDeAtencao(tipo: 'comando'), 'aprovar'), isNull);
      expect(efeitoDaAcao(const ItemDeAtencao(tipo: 'entrega'), 'concluir'), isNull);
      expect(efeitoDaAcao(entrega, 'desconhecida'), isNull);
    });

    test('abrir navega sem mandar mensagem', () {
      EfeitoDaAcao? abrir(ItemDeAtencao item) => efeitoDaAcao(item, 'abrir');
      expect((abrir(const ItemDeAtencao(tipo: 'bloqueada', tarefaId: 7)) as IrParaTarefa).id, 7);
      expect((abrir(const ItemDeAtencao(tipo: 'vaga', tarefaId: 8, equipe: 'codigo')) as IrParaTarefa).id, 8);
      expect((abrir(const ItemDeAtencao(tipo: 'orcamento', persona: 'nati', equipe: 'casa')) as IrParaEquipe).equipe, 'casa');
      expect((abrir(const ItemDeAtencao(tipo: 'vaga', equipe: 'codigo')) as IrParaEquipe).equipe, 'codigo');
      expect((abrir(const ItemDeAtencao(tipo: 'rotina', equipe: 'casa', rotina: 'p')) as IrParaRotinas).equipe, 'casa');
      expect(abrir(const ItemDeAtencao(tipo: 'bloqueada')), isNull);
    });

    test('filtros da atividade por persona e por tipo', () {
      final r = decodificar(_retrato);
      expect(filtrarAtividade(r.atividade).length, 3);
      expect(filtrarAtividade(r.atividade, quem: 'nati').map((a) => a.texto), ['feito']);
      expect(filtrarAtividade(r.atividade, tipo: 'auditoria').map((a) => a.quem), ['ueslei']);
      expect(filtrarAtividade(r.atividade, quem: 'nati', tipo: 'auditoria'), isEmpty);
      expect(quemNaAtividade(r.atividade), ['nati', 'ueslei', 'Plano do dia']);
      expect(tiposNaAtividade(r.atividade), ['entrega', 'auditoria', 'disparo']);
      expect([for (final q in quemNaAtividade(r.atividade)) nomeDeQuem(q, r)], ['Nati', 'Ueslei', 'Plano do dia']);
    });

    test('equipe das tarefas, contagem por status e tempo relativo', () {
      final r = decodificar(_retrato);
      expect([equipeDasTarefas(r, null), equipeDasTarefas(r, 'codigo'), equipeDasTarefas(r, 'sumiu')],
          ['casa', 'codigo', 'casa']);
      expect(contagemPorStatus(r.tarefas['casa']!).map((c) => c.status), ['em_revisao', 'a_fazer']);
      final agora = DateTime.utc(2026, 11, 5, 9);
      expect(haQuanto(agora.subtract(const Duration(seconds: 20)), agora), 'agora');
      expect(haQuanto(agora.subtract(const Duration(minutes: 12)), agora), 'há 12 min');
      expect(haQuanto(agora.subtract(const Duration(hours: 3)), agora), 'há 3 h');
      expect(haQuanto(agora.subtract(const Duration(days: 2)), agora), 'há 2 d');
      expect(haQuanto(null, agora), '');
    });
  });

  group('workflows', () {
    WorkflowsRecebidos recebidos() =>
        Entrada.decodificar(jsonEncode({'tipo': 'workflows', ..._fixturasEntrada['workflows']!})) as WorkflowsRecebidos;

    test('decodifica definições e fluxos com as fichas', () {
      final e = recebidos();
      final w = e.definicoes.single;
      expect([w.id, w.nome, w.versao, w.equipe, w.inicio], ['mudanca-com-plano', 'Mudança com plano', 3, 'casa', 'plano']);
      expect(w.entrada, {'pedido': const TipoDeValor.texto()});
      expect(w.nos, hasLength(10));
      expect(w.caixa('ok')!.opcoes, ['seguir', 'parar']);
      expect(w.caixa('plano')!.detalhe, 'conselho-nati');
      expect(w.caixa('ok')!.nomeDoTipo, 'decisão humana');
      expect(w.arestas[1].quando, 'alto');
      final f = e.fluxos.single;
      expect([f.id, f.aberto, f.nome, f.workflow, f.entrada['pedido']], [9, true, 'Mudança com plano', 'mudanca-com-plano', 'trocar o disco']);
      expect(f.fichas, hasLength(7));
      expect(f.ficha(5)!.tarefa, 21);
      expect(f.ficha(1)!.saidas['risco'], 'alto');
      expect(f.ficha(7)!.esperando, isTrue);
    });

    test('campos ausentes caem em padrões seguros', () {
      final vazia = Entrada.decodificar('{"tipo":"workflows"}') as WorkflowsRecebidos;
      expect([vazia.definicoes, vazia.fluxos], [isEmpty, isEmpty]);
      final w = Workflow.deJson({
        'id': 'x',
        'entrada': {
          'a': 'estranho',
          'b': {'escolha': []},
          'c': {
            'escolha': ['s', 'n'],
          },
          'd': 'numero',
          'e': 'booleano',
        },
        'nos': [
          {'tipo': 'fim'},
          'lixo',
          {'id': 'f', 'tipo': 'fim'},
        ],
        'arestas': [
          {'de': 'f'},
        ],
        'layout': {
          'f': {'x': 1},
        },
      });
      expect([w.nome, w.versao, w.equipe, w.inicio], ['x', 0, '', '']);
      expect(w.entrada.values.map((t) => t.nome), ['texto', 'texto', 'escolha', 'numero', 'booleano']);
      expect(w.entrada['c']!.escolhas, ['s', 'n']);
      expect(w.nos.map((n) => n.id), ['f']);
      expect([w.arestas.single.para, w.arestas.single.quando], ['', null]);
      expect(w.layout, isEmpty);
      final f = Fluxo.deJson({'id': 2});
      expect([f.status, f.aberto, f.fichas, f.erro, f.definicao.nos], ['rodando', true, isEmpty, null, isEmpty]);
      final ficha = Ficha.deJson({
        'id': 1,
        'no': 'a',
        'saidas': {
          'x': [1],
          'y': 2,
          'z': true,
        },
      });
      expect([ficha.status, ficha.tarefa, ficha.saidas], ['esperando', null, {'y': 2, 'z': true}]);
      expect(Tarefa.deJson({..._tarefa, 'fluxo': 9, 'ficha': 5}).ficha, 5);
      expect(Tarefa.deJson(_tarefa).fluxo, isNull);
    });

    test('layout calculado do exemplo da spec: nível pelo maior caminho, empilhado na ordem das caixas', () {
      final w = recebidos().definicoes.single;
      expect(layoutCalculado(w), {
        'plano': (x: 0.0, y: 0.0),
        'risco': (x: 260.0, y: 0.0),
        'ok': (x: 520.0, y: 0.0),
        'frente': (x: 780.0, y: 0.0),
        'executa': (x: 1040.0, y: 0.0),
        'revisa': (x: 1300.0, y: 0.0),
        'nota': (x: 1040.0, y: 120.0),
        'junta': (x: 1560.0, y: 0.0),
        'fim': (x: 1820.0, y: 0.0),
        'parou': (x: 780.0, y: 120.0),
      });
      final comLayout = Workflow.deJson({
        ..._mudancaComPlano,
        'layout': {
          'plano': {'x': 5, 'y': 7},
        },
      });
      final layout = layoutDoGrafo(comLayout);
      expect([layout['plano'], layout['risco']], [(x: 5.0, y: 7.0), (x: 260.0, y: 0.0)]);
      expect(caixaEm(layout, 260 + margemDoGrafo + 10, margemDoGrafo + 10), 'risco');
      expect(caixaEm(layout, -50, -50), isNull);
    });

    test('a volta do laço não empurra o nível, e caixa inalcançável vai para um nível extra', () {
      final w = Workflow.deJson({
        'id': 'l',
        'inicio': 'a',
        'nos': [
          {'id': 'solta', 'tipo': 'fim'},
          {'id': 'a', 'tipo': 'executar'},
          {'id': 'volta', 'tipo': 'laco'},
          {'id': 'fim', 'tipo': 'fim'},
        ],
        'arestas': [
          {'de': 'a', 'para': 'volta'},
          {'de': 'volta', 'para': 'a', 'quando': 'repetir'},
          {'de': 'volta', 'para': 'fim', 'quando': 'sair'},
        ],
      });
      expect(layoutCalculado(w), {
        'solta': (x: 780.0, y: 0.0),
        'a': (x: 0.0, y: 0.0),
        'volta': (x: 260.0, y: 0.0),
        'fim': (x: 520.0, y: 0.0),
      });
      expect(caixasEmOrdem(w).map((c) => c.id), ['a', 'volta', 'fim', 'solta']);
    });

    test('ordem do caminho: esperando no topo, depois por criação, com o resumo das saídas', () {
      final f = recebidos().fluxos.single;
      final passos = ordemDoCaminho(f);
      expect(passos.map((p) => p.ficha), [5, 7, 1, 2, 3, 4, 6]);
      expect(passos.map((p) => p.destacado), [true, true, false, false, false, false, false]);
      expect([passos.first.no, passos.first.tipo, passos.first.tarefa], ['executa', 'executar', 21]);
      expect(passos[2].resumo, 'devolutiva: feito · plano: 1. backup 2. troca · risco: alto');
      expect(resumoDasSaidas({'x': 'a' * 100, 'ok': false}, limite: 3), 'x: aaa… · ok: não');
      expect(estadoDasCaixas(f), containsPair('executa', 'esperando'));
      expect(estadoDasCaixas(f)['plano'], 'concluida');
      expect(estadoDasCaixas(f).containsKey('revisa'), isFalse);
      expect(arestasPercorridas(f), {'plano>risco', 'risco>ok', 'ok>frente', 'frente>executa', 'frente>nota', 'nota>junta'});
    });

    test('formulário de entrada converte cada tipo e aponta o que falta', () {
      const entrada = {
        'pedido': TipoDeValor.texto(),
        'vezes': TipoDeValor('numero'),
        'urgente': TipoDeValor('booleano'),
        'risco': TipoDeValor('escolha', ['baixo', 'alto']),
      };
      final ok = converterEntrada(entrada, {'pedido': '  trocar o disco ', 'vezes': '3,5', 'urgente': true, 'risco': 'alto'});
      expect(ok.erros, isEmpty);
      expect(ok.valores, {'pedido': 'trocar o disco', 'vezes': 3.5, 'urgente': true, 'risco': 'alto'});
      expect(converterEntrada(entrada, {'vezes': '4', 'risco': 'baixo'}).valores, {'pedido': '', 'vezes': 4, 'urgente': false, 'risco': 'baixo'});
      expect(converterEntrada(entrada, {'vezes': '4', 'risco': 'baixo'}).valores['vezes'], isA<int>());
      final ruim = converterEntrada(entrada, {'vezes': 'três', 'risco': 'médio'});
      expect(ruim.erros, ['vezes precisa ser um número', 'risco: escolha uma das opções']);
      expect(jsonDecode(IniciarWorkflow('casa', 'w', ok.valores).codificar()), {
        'tipo': 'workflow-iniciar',
        'equipe': 'casa',
        'id': 'w',
        'entrada': {'pedido': 'trocar o disco', 'vezes': 3.5, 'urgente': true, 'risco': 'alto'},
      });
    });

    test('rotina pode iniciar workflow com entrada vazia ou só dados em texto', () {
      const casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [PosicaoResumo(id: 'executor', titulo: 'executor')]);
      const livre = Workflow(id: 'livre', nome: 'Livre', equipe: 'casa');
      const comDados = Workflow(id: 'dados', nome: 'Dados', equipe: 'casa', entrada: {'dados': TipoDeValor.texto()});
      final comPedido = recebidos().definicoes.single;
      expect([aceitaRotina(livre), aceitaRotina(comDados), aceitaRotina(comPedido)], [true, true, false]);
      expect(workflowsParaRotina([livre, comDados, comPedido], 'casa').map((w) => w.id), ['livre', 'dados']);
      const r = Rotina(id: 'r', nome: 'R', workflow: 'livre');
      expect(errosDaRotina(r, casa, workflows: [livre]), isEmpty);
      expect(errosDaRotina(r, casa), ['rotina r: workflow inexistente (livre)']);
      expect(errosDaRotina(r.copiar(workflow: 'mudanca-com-plano'), casa, workflows: [comPedido]), [
        'rotina r: o workflow mudanca-com-plano pede entrada que a rotina não dá (só "dados" em texto)',
      ]);
      expect(r.paraJson(), {'id': 'r', 'nome': 'R', 'ativa': true, 'workflow': 'livre', 'concorrencia': 'pular', 'perdidos': 'um'});
      expect(r.copiar(workflow: '', titulo: 't').paraJson()['tarefa'], {'titulo': 't'});
      expect(Rotina.deJson({'id': 'r', 'nome': 'R', 'workflow': 'livre'}).iniciaWorkflow, isTrue);
      expect(Rotina.deJson({'id': 'r', 'nome': 'R'}).workflow, '');
      final disparo = Disparo.deJson({..._disparo, 'tarefa': null, 'motivo': 'iniciou o workflow (execução #9)'});
      expect(disparo.resumo, 'horário · iniciou o workflow (execução #9)');
    });

    test('tarefa de fluxo diz a caixa e o workflow', () {
      final f = recebidos().fluxos.single;
      Tarefa t(int? fluxo, int? ficha) => Tarefa.deJson({..._tarefa, 'fluxo': fluxo, 'ficha': ficha});
      expect(descricaoDaCaixaDaTarefa(t(9, 5), [f]), 'caixa executa do workflow Mudança com plano');
      expect(descricaoDaCaixaDaTarefa(t(9, 99), [f]), 'parte do workflow Mudança com plano');
      expect(descricaoDaCaixaDaTarefa(t(8, 1), [f]), 'parte do workflow #8');
      expect(descricaoDaCaixaDaTarefa(t(null, null), [f]), '');
    });

    test('retrato traz os workflows e os itens novos de atenção', () {
      final retrato = Retrato.deJson({
        'workflows': [
          {
            'fluxo': 9,
            'equipe': 'casa',
            'workflow': 'mudanca-com-plano',
            'nome': 'Mudança com plano',
            'desde': '2026-11-05T09:00:00.000Z',
            'ativas': [
              {'ficha': 5, 'no': 'executa', 'titulo': 'executa', 'tipo': 'executar', 'tarefaId': 21},
              {'ficha': 7, 'no': 'junta'},
            ],
          },
          {'fluxo': 10},
        ],
        'atencao': [
          {'tipo': 'decisao', 'acoes': ['decidir'], 'fluxo': 9, 'ficha': 3, 'opcoes': ['seguir', 'parar', 3]},
        ],
      });
      final f = retrato.workflows.first;
      expect([f.fluxo, f.nome, f.ativas.length, f.ativas.first.tarefaId], [9, 'Mudança com plano', 2, 21]);
      expect([f.ativas.last.titulo, f.ativas.last.tipo, f.ativas.last.tarefaId], ['junta', '', null]);
      expect([retrato.workflows.last.nome, retrato.workflows.last.ativas], ['', isEmpty]);
      final item = retrato.atencao.single;
      expect([item.fluxo, item.ficha, item.opcoes], [9, 3, ['seguir', 'parar']]);
      expect(const Retrato().workflows, isEmpty);
    });

    test('ações decidir, sinalizar e abrir dos itens de workflow', () {
      const decisao = ItemDeAtencao(tipo: 'decisao', acoes: ['decidir'], fluxo: 9, ficha: 3, opcoes: ['seguir', 'parar'], equipe: 'casa');
      Map<String, dynamic>? saida(EfeitoDaAcao? e) =>
          e is MandarSaida ? jsonDecode(e.saida.codificar()) as Map<String, dynamic> : null;
      expect(saida(efeitoDaAcao(decisao, 'decidir', opcao: 'seguir', texto: '  vai  ')), {
        'tipo': 'workflow-decidir',
        'execucao': 9,
        'ficha': 3,
        'opcao': 'seguir',
        'comentario': 'vai',
      });
      expect(saida(efeitoDaAcao(decisao, 'decidir', opcao: 'parar', texto: ' ')),
          {'tipo': 'workflow-decidir', 'execucao': 9, 'ficha': 3, 'opcao': 'parar'});
      expect(efeitoDaAcao(decisao, 'decidir', opcao: 'talvez'), isNull);
      expect(efeitoDaAcao(decisao, 'decidir'), isNull);
      const sinal = ItemDeAtencao(tipo: 'sinal', acoes: ['sinalizar'], fluxo: 9, ficha: 4);
      expect(saida(efeitoDaAcao(sinal, 'sinalizar')), {'tipo': 'workflow-sinal', 'execucao': 9, 'ficha': 4});
      expect(efeitoDaAcao(const ItemDeAtencao(tipo: 'sinal', fluxo: 9), 'sinalizar'), isNull);
      const atrasada = ItemDeAtencao(tipo: 'atrasada', acoes: ['abrir'], fluxo: 9, ficha: 5, equipe: 'casa');
      final irFluxo = efeitoDaAcao(atrasada, 'abrir');
      expect(irFluxo, isA<IrParaFluxo>());
      expect([(irFluxo as IrParaFluxo).fluxo, irFluxo.equipe], [9, 'casa']);
      const comTarefa = ItemDeAtencao(tipo: 'atrasada', acoes: ['abrir'], fluxo: 9, ficha: 5, tarefaId: 21);
      expect((efeitoDaAcao(comTarefa, 'abrir') as IrParaTarefa).id, 21);
      expect(rotulosDeAcao['sinalizar'], 'Sinalizar');
      expect([rotulosDeAtencao['decisao'], rotulosDeAtencao['sinal'], rotulosDeAtencao['atrasada']], ['decisão', 'sinal', 'atrasada']);
    });
  });

  group('skills', () {
    test('skills decodifica dono, arquivos, erro e quem usa', () {
      final e = Entrada.decodificar(jsonEncode({'tipo': 'skills', ..._fixturasEntrada['skills']!})) as SkillsRecebidas;
      final [relatorio, revisar] = e.lista;
      expect([relatorio.daCasa, relatorio.valida, relatorio.arquivos], [true, true, ['modelo.md']]);
      expect([relatorio.usadaPor.personas, relatorio.usadaPor.posicoes], [['vera'], ['casa/executor']]);
      expect([revisar.dono, revisar.valida, revisar.erro, revisar.usadaPor.vazio], ['vera', false, 'a descrição é obrigatória', true]);
      expect(agruparSkills(e.lista).map((g) => (g.dono, g.skills.length)), [('casa', 1), ('vera', 1)]);
      expect(agruparSkills(const []).map((g) => g.dono), ['casa']);
      expect(
        descreverUso(relatorio.usadaPor, nomeDaPersona: (p) => p.toUpperCase(), nomeDaPosicao: (p) => 'pos $p'),
        'VERA, pos casa/executor',
      );
      expect(descreverUso(revisar.usadaPor, nomeDaPersona: (p) => p), 'ninguém usa');
    });

    test('skills da posição e da persona vão e voltam pelo JSON', () {
      final equipes = Entrada.decodificar(jsonEncode({'tipo': 'equipes', ..._fixturasEntrada['equipes']!})) as EquipesRecebidas;
      final [executor, vaga] = equipes.lista.single.posicoes;
      expect([executor.skills, vaga.skills], [['relatorio-semanal'], isEmpty]);
      expect(executor.paraJson()['skills'], ['relatorio-semanal']);
      expect(vaga.paraJson().containsKey('skills'), isFalse);
      expect(PosicaoResumo.deJson(executor.paraJson().cast<String, dynamic>()).skills, ['relatorio-semanal']);
      expect(executor.copiar(titulo: 'x').skills, ['relatorio-semanal']);

      final personas = Entrada.decodificar(jsonEncode({'tipo': 'personas', ..._fixturasEntrada['personas']!})) as PersonasRecebidas;
      expect(personas.lista.single.skills, ['relatorio-semanal']);
      expect(Perfil.deJson(const {'id': 'x'}).skills, isEmpty);
      expect(jsonDecode(SalvarSkillsDaPersona('vera', personas.lista.single.skills).codificar()), {
        'tipo': 'persona-salvar',
        'persona': {'id': 'vera', 'skills': ['relatorio-semanal']},
      });
      expect((jsonDecode(const SalvarSkillsDaPersona('vera', []).codificar()) as Map)['persona'], {'id': 'vera', 'skills': []});
    });

    test('salvar e excluir skill levam o dono, o rascunho limpo e a marca de nova', () {
      const r = RascunhoDeSkill(dono: 'poe', id: ' revisar-texto ', descricao: ' revisa ', corpo: 'passo a passo');
      expect(jsonDecode(const SalvarSkill(r).codificar()), {
        'tipo': 'skill-salvar',
        'dono': 'poe',
        'skill': {'id': 'revisar-texto', 'descricao': 'revisa', 'corpo': 'passo a passo'},
        'nova': true,
      });
      final existente = RascunhoDeSkill.de(const Skill(dono: 'casa', id: 'x', descricao: 'd', corpo: 'c'));
      expect((jsonDecode(SalvarSkill(existente).codificar()) as Map)['nova'], false);
      expect(existente.copiar(id: 'outro').id, 'x');
      expect(jsonDecode(const ExcluirSkill('casa', 'x').codificar()), {'tipo': 'skill-excluir', 'dono': 'casa', 'id': 'x'});
    });

    test('validação do rascunho segue a do servidor', () {
      List<String> erros(RascunhoDeSkill r, [List<Skill> existentes = const []]) => errosDoRascunho(r, existentes: existentes);
      const ok = RascunhoDeSkill(dono: 'casa', id: 'relatorio-semanal', descricao: 'quando pedir o relatório', corpo: '# passos');
      expect(erros(ok), isEmpty);
      for (final id in ['', 'Relatorio', '1relatorio', 'relatório', 'com espaco x', 'a' * 65]) {
        expect(erros(ok.copiar(id: id)), [contains('id inválido')], reason: id);
      }
      expect(erros(ok.copiar(id: 'a' * 64)), isEmpty);
      expect(erros(ok.copiar(id: 'a-1-b')), isEmpty);
      expect(erros(ok.copiar(descricao: '   ')), ['a descrição é obrigatória']);
      expect(erros(ok.copiar(descricao: 'x' * limiteDaDescricao)), isEmpty);
      expect(erros(ok.copiar(descricao: 'x' * (limiteDaDescricao + 1))), ['a descrição passa de 1024 caracteres']);
      expect(erros(ok.copiar(corpo: '\n  \n')), ['o corpo da skill está vazio']);
      expect(erros(ok.copiar(corpo: 'x' * (limiteDoCorpo + 1))), ['o corpo da skill passa de 100 mil caracteres']);
      const mesma = Skill(dono: 'casa', id: 'relatorio-semanal');
      expect(erros(ok, [mesma]), [contains('já existe')]);
      expect(erros(ok.copiar(dono: 'poe'), [mesma]), isEmpty);
      expect(erros(RascunhoDeSkill.de(const Skill(dono: 'casa', id: 'relatorio-semanal', descricao: 'd', corpo: 'c')), [mesma]),
          isEmpty);
    });

    test('anexar e tirar skill de persona e de posição, sem repetir', () {
      expect(comSkill(['a'], 'b'), ['a', 'b']);
      expect(comSkill(['a', 'b'], 'a'), ['a', 'b']);
      expect(semSkill(['a', 'b'], 'a'), ['b']);
      expect(semSkill(['a'], 'z'), ['a']);
      const casa = EquipeResumo(id: 'casa', nome: 'Casa', posicoes: [PosicaoResumo(id: 'executor', titulo: 'executor')]);
      final com = anexarSkillNaPosicao(anexarSkillNaPosicao(casa, 'executor', 'a'), 'executor', 'a');
      expect(com.posicao('executor')!.skills, ['a']);
      expect(tirarSkillDaPosicao(com, 'executor', 'a').posicao('executor')!.skills, isEmpty);
      const biblioteca = [
        Skill(dono: 'casa', id: 'a', descricao: 'da casa'),
        Skill(dono: 'casa', id: 'b', descricao: 'quebrada', erro: 'sem descrição'),
        Skill(dono: 'casa', id: 'c', descricao: 'outra'),
        Skill(dono: 'poe', id: 'propria', descricao: 'só do poe'),
      ];
      expect(anexaveis(biblioteca, ['a']).map((s) => s.id), ['c']);
    });

    test('descrição das skills: próprias primeiro, anexadas depois, sumidas e inválidas marcadas', () {
      const biblioteca = [
        Skill(dono: 'casa', id: 'a', descricao: 'da casa'),
        Skill(dono: 'casa', id: 'b', descricao: 'quebrada', erro: 'sem name'),
        Skill(dono: 'poe', id: 'propria', descricao: 'só do poe'),
        Skill(dono: 'nati', id: 'dela', descricao: 'da nati'),
      ];
      const poe = Perfil('poe', 'Poe', 'P', 0, 'o amigo', skills: ['a', 'b', 'sumiu']);
      final daPersona = skillsDaPersona(biblioteca, poe);
      expect(daPersona.map((s) => s.rotulo), ['propria', 'a', 'b (inválida)', 'sumiu (inválida)']);
      expect(daPersona.map((s) => s.propria), [true, false, false, false]);
      expect(daPersona.map((s) => s.descricao).take(2), ['só do poe', 'da casa']);
      const posicao = PosicaoResumo(id: 'executor', titulo: 'executor', skills: ['a']);
      expect(skillsDaPosicao(biblioteca, posicao).map((s) => (s.id, s.descricao, s.propria)), [('a', 'da casa', false)]);
    });

    test('erros do rascunho presos ao campo, um por campo', () {
      const ok = RascunhoDeSkill(dono: 'casa', id: 'relatorio', descricao: 'quando pedir', corpo: '# passos');
      expect(errosDosCamposDaSkill(ok), isEmpty);
      expect(errosDosCamposDaSkill(ok.copiar(id: 'Relatorio', descricao: ' ', corpo: '')), {
        CampoDaSkill.id: 'id inválido (letras minúsculas, números e hífen, começando por letra)',
        CampoDaSkill.descricao: 'a descrição é obrigatória',
        CampoDaSkill.corpo: 'o corpo da skill está vazio',
      });
      expect(errosDosCamposDaSkill(ok, existentes: const [Skill(dono: 'casa', id: 'relatorio')]),
          {CampoDaSkill.id: 'já existe a skill relatorio em Casa'});
    });
  });
  group('espelho', () {
    test('espelho decodifica a config e o estado, com a volta em hora local', () {
      final e = Entrada.decodificar(jsonEncode({'tipo': 'espelho', ..._fixturasEntrada['espelho']!})) as EspelhoRecebido;
      expect([e.config.ativo, e.config.projeto, e.config.tag, e.config.tipos], [true, 'Control Tower', 'control-tower', ['aprovacao', 'decisao']]);
      expect([e.estado.conectado, e.estado.erro, e.estado.abertos, e.estado.pendentes], [true, null, 3, 1]);
      expect(e.estado.ultimaVolta, DateTime.utc(2026, 11, 5, 13, 4).toLocal());
      expect(e.estado.ultimaVolta!.isUtc, isFalse);
      final vazio = Entrada.decodificar('{"tipo":"espelho"}') as EspelhoRecebido;
      expect([vazio.config.ativo, vazio.config.tipos, vazio.estado.ultimaVolta, vazio.estado.abertos], [false, isEmpty, null, 0]);
    });

    test('as saídas do espelho: pedir, salvar com a config aparada e na ordem, sincronizar', () {
      expect(jsonDecode(const PedirEspelho().codificar()), {'tipo': 'espelho'});
      expect(jsonDecode(const SincronizarEspelho().codificar()), {'tipo': 'espelho-sincronizar'});
      const config = ConfigDoEspelho(ativo: true, projeto: ' Casa ', tag: 'ct ', tipos: ['vaga', 'aprovacao']);
      expect(jsonDecode(const SalvarEspelho(config).codificar()), {
        'tipo': 'espelho-salvar',
        'config': {'ativo': true, 'projeto': 'Casa', 'tag': 'ct', 'tipos': ['aprovacao', 'vaga']},
      });
    });

    test('os tipos seguem a ordem do servidor, e marcar e desmarcar mantém essa ordem', () {
      expect(tiposDoEspelho, ['aprovacao', 'plano', 'entrega', 'decisao', 'sinal', 'bloqueada', 'backlog', 'atrasada', 'orcamento', 'rotina', 'vaga']);
      expect(rotulosDoEspelho['orcamento'], 'orçamento estourado');
      const c = ConfigDoEspelho(tipos: ['decisao']);
      expect(c.comTipo('vaga', true).comTipo('aprovacao', true).tipos, ['aprovacao', 'decisao', 'vaga']);
      expect(c.comTipo('decisao', false).tipos, isEmpty);
      expect(c.comTipo('decisao', true).tipos, ['decisao']);
    });

    test('validação: projeto e tag obrigatórios e só tipos conhecidos', () {
      expect(errosDaConfigDoEspelho(const ConfigDoEspelho()), isEmpty);
      expect(errosDaConfigDoEspelho(const ConfigDoEspelho(projeto: '  ', tag: '', tipos: ['aprovacao', 'qualquer'])), [
        'o projeto do TickTask é obrigatório',
        'a tag é obrigatória',
        'tipo desconhecido (qualquer)',
      ]);
    });

    test('mesmaQue compara a config aparada e sem olhar a ordem dos tipos', () {
      const a = ConfigDoEspelho(ativo: true, projeto: 'Casa', tag: 'ct', tipos: ['aprovacao', 'vaga']);
      expect(a.mesmaQue(const ConfigDoEspelho(ativo: true, projeto: 'Casa ', tag: ' ct', tipos: ['vaga', 'aprovacao'])), isTrue);
      expect(a.mesmaQue(a.copiar(ativo: false)), isFalse);
      expect(a.mesmaQue(a.comTipo('plano', true)), isFalse);
      expect(a.mesmaQue(null), isFalse);
    });

    test('texto do estado: conectado com contagens, fora do ar com o erro, desligado', () {
      const ligado = ConfigDoEspelho(ativo: true);
      expect(resumoDoEspelho(ligado, const EstadoDoEspelho(conectado: true, abertos: 3, pendentes: 1)), 'conectado · 3 no TickTask · 1 esperando');
      expect(resumoDoEspelho(ligado, const EstadoDoEspelho(conectado: true, abertos: 2)), 'conectado · 2 no TickTask');
      expect(resumoDoEspelho(ligado, const EstadoDoEspelho(erro: 'TickTask fora do ar')), 'fora do ar: TickTask fora do ar');
      expect(resumoDoEspelho(ligado, const EstadoDoEspelho()), 'esperando a primeira volta');
      expect(resumoDoEspelho(const ConfigDoEspelho(), const EstadoDoEspelho(conectado: true, abertos: 3)), 'desligado');
    });

    test('última volta: hora quando é hoje, dia e hora quando não é', () {
      final agora = DateTime(2026, 11, 5, 18);
      expect(ultimaVoltaDoEspelho(const EstadoDoEspelho(), agora: agora), 'nenhuma volta ainda');
      expect(ultimaVoltaDoEspelho(EstadoDoEspelho(ultimaVolta: DateTime(2026, 11, 5, 9, 7)), agora: agora), 'última volta às 09:07');
      expect(ultimaVoltaDoEspelho(EstadoDoEspelho(ultimaVolta: DateTime(2026, 11, 4, 22, 30)), agora: agora), 'última volta ontem, às 22:30');
      expect(ultimaVoltaDoEspelho(EstadoDoEspelho(ultimaVolta: DateTime(2026, 11, 1, 8)), agora: agora), 'última volta 1/nov, às 08:00');
    });
  });
  group('importação de modelos', () {
    test('modelo e modelo-importado decodificam', () {
      final m = Entrada.decodificar(jsonEncode({'tipo': 'modelo', ..._fixturasEntrada['modelo']!})) as ModeloRecebido;
      expect([m.nome, m.conteudo], ['work.ctmodelo.json', '{"formato":"control-tower/modelo"}']);
      final i = Entrada.decodificar('{"tipo":"modelo-importado","equipe":"casa","workflow":"revisao-2"}') as ModeloImportado;
      expect([i.equipe, i.workflow], ['casa', 'revisao-2']);
      expect((Entrada.decodificar('{"tipo":"modelo-importado","equipe":"work-2"}') as ModeloImportado).workflow, isNull);
    });

    test('a prévia lê resumo, personas, escolhas, avisos e erros', () {
      final p = (Entrada.decodificar(jsonEncode({'tipo': 'modelo-previa', ..._previaDeEquipe})) as PreviaDoModeloRecebida).previa;
      expect([p.valida, p.deWorkflow, p.podeImportar], [true, false, true]);
      expect(p.resumo!.contagem, '3 posições · 2 personas · 1 workflow · 1 rotina · 2 skills');
      expect([for (final x in p.personas) '${x.id}:${x.traz}'], ['nati:true', 'eva:true', 'zed:false']);
      expect([p.escolhas.equipeId, p.escolhas.equipeNome], ['work-2', 'Work 2']);
      expect([for (final MapEntry(:key, :value) in p.escolhas.personas.entries) '$key:${value.opcao(key).name}'],
          ['nati:daqui', 'eva:criar', 'zed:vaga']);
      expect(p.skillsEmColisao, ['relatorio']);
      expect(p.entra, ['equipe Work 2 (work-2) com 3 posições']);
      expect(p.avisos, hasLength(1));
      expect(p.escolhas.paraJson(), _previaDeEquipe['escolhas']);
    });

    test('arquivo que não é modelo vem com resumo nulo e não importa', () {
      final p = PreviaDoModelo.deJson({
        'resumo': null,
        'personasDoModelo': [],
        'posicoesDoModelo': [],
        'entra': [],
        'escolhas': {},
        'avisos': [],
        'erros': ['não é um modelo do control-tower'],
      });
      expect([p.valida, p.podeImportar, p.escolhas.vazia], [false, false, true]);
      expect(p.erros, ['não é um modelo do control-tower']);
    });

    test('prévia de workflow lê posições e ligações, inclusive sem ligação', () {
      final p = PreviaDoModelo.deJson({
        'resumo': {'tipo': 'workflow', 'nome': 'Revisão', 'exportadoEm': 'x', 'posicoes': 2, 'personas': 0, 'workflows': 1, 'rotinas': 0, 'skills': 0},
        'posicoesDoModelo': [
          {'id': 'executor', 'titulo': 'executor'},
          {'id': 'revisora', 'titulo': 'revisora'},
        ],
        'escolhas': {
          'posicoes': {'executor': 'executor', 'revisora': null},
          'workflow': {'id': 'revisao-2'},
        },
        'erros': ['posição revisora: escolha uma posição da equipe Casa para ela'],
      });
      expect([p.deWorkflow, p.podeImportar, p.resumo!.exportadoEm, p.resumo!.contagem], [true, false, null, '2 posições']);
      expect(p.posicoes.map((x) => x.titulo), ['executor', 'revisora']);
      expect(p.escolhas.posicoes, {'executor': 'executor', 'revisora': null});
      expect(p.escolhas.paraJson(), {
        'posicoes': {'executor': 'executor', 'revisora': null},
        'workflow': {'id': 'revisao-2'},
      });
    });

    test('as saídas levam o formato do protocolo', () {
      expect(jsonDecode(const ExportarModelo('work', personas: false).codificar()),
          {'tipo': 'modelo-exportar', 'equipe': 'work', 'personas': false, 'rotinas': true});
      expect(jsonDecode(const ExportarModelo.workflow('casa', 'revisao').codificar()),
          {'tipo': 'modelo-exportar', 'equipe': 'casa', 'workflow': 'revisao'});
      expect(jsonDecode(const PedirPreviaDoModelo('{"a":1}').codificar()), {'tipo': 'modelo-previa', 'conteudo': '{"a":1}'});
      const escolhas = EscolhasDoModelo(posicoes: {'revisora': 'revisora'}, workflowId: 'w');
      expect(jsonDecode(const PedirPreviaDoModelo('{}', destino: 'casa', escolhas: escolhas).codificar()), {
        'tipo': 'modelo-previa',
        'conteudo': '{}',
        'destino': 'casa',
        'escolhas': {
          'posicoes': {'revisora': 'revisora'},
          'workflow': {'id': 'w'},
        },
      });
      expect(jsonDecode(const ImportarModelo('{}', escolhas: EscolhasDoModelo()).codificar()),
          {'tipo': 'modelo-importar', 'conteudo': '{}', 'escolhas': {}});
    });

    test('mudar a ação de uma persona', () {
      final base = EscolhasDoModelo.deJson(_previaDeEquipe['escolhas']);
      const daqui = ['nati', 'poe', 'alfred'];
      Map<String, Object?> acao(EscolhasDoModelo e, String id) => e.personas[id]!.paraJson();
      final outra = base.comOpcaoDePersona('nati', OpcaoDePersona.outra, nomeNoModelo: 'Nati', personasDaqui: daqui);
      expect(acao(outra, 'nati'), {'acao': 'usar', 'persona': 'poe'});
      expect(outra.personas['nati']!.opcao('nati'), OpcaoDePersona.outra);
      final alfred = outra.comPersonaDaqui('nati', 'alfred');
      expect(acao(alfred, 'nati'), {'acao': 'usar', 'persona': 'alfred'});
      expect(acao(alfred.comOpcaoDePersona('nati', OpcaoDePersona.outra, nomeNoModelo: 'Nati', personasDaqui: daqui), 'nati'),
          {'acao': 'usar', 'persona': 'alfred'});
      final comNome = base.comOpcaoDePersona('nati', OpcaoDePersona.criarComNome, nomeNoModelo: 'Nati', personasDaqui: daqui);
      expect(acao(comNome, 'nati'), {'acao': 'criar', 'nome': 'Nati'});
      final vazio = comNome.comNomeDePersona('nati', '');
      expect([acao(vazio, 'nati'), vazio.personas['nati']!.opcao('nati')], [
        {'acao': 'criar', 'nome': ''},
        OpcaoDePersona.criarComNome,
      ]);
      expect(acao(vazio.comOpcaoDePersona('nati', OpcaoDePersona.criar, nomeNoModelo: 'Nati', personasDaqui: daqui), 'nati'),
          {'acao': 'criar'});
      expect(acao(base.comOpcaoDePersona('eva', OpcaoDePersona.vaga, nomeNoModelo: 'Eva', personasDaqui: daqui), 'eva'),
          {'acao': 'vaga'});
      expect(acao(base.comOpcaoDePersona('eva', OpcaoDePersona.daqui, nomeNoModelo: 'Eva', personasDaqui: daqui), 'eva'),
          {'acao': 'usar', 'persona': 'eva'});
      expect(acao(base, 'nati'), {'acao': 'usar', 'persona': 'nati'});
    });

    test('mudar skill, posição, equipe e workflow', () {
      final base = EscolhasDoModelo.deJson(_previaDeEquipe['escolhas']);
      final importar = base.comOpcaoDeSkill('relatorio', OpcaoDeSkill.importar);
      expect(importar.skills['relatorio']!.paraJson(), {'acao': 'importar', 'id': 'relatorio-2'});
      final outroId = importar.comIdDeSkill('relatorio', 'relatorio-novo');
      expect(outroId.comOpcaoDeSkill('relatorio', OpcaoDeSkill.importar).skills['relatorio']!.id, 'relatorio-novo');
      expect(outroId.comOpcaoDeSkill('relatorio', OpcaoDeSkill.daqui).skills['relatorio']!.paraJson(), {'acao': 'usar'});
      final equipe = base.comEquipe(id: 'work-3').comEquipe(nome: 'Trabalho');
      expect(equipe.paraJson()['equipe'], {'id': 'work-3', 'nome': 'Trabalho'});
      const w = EscolhasDoModelo(posicoes: {'executor': 'executor', 'revisora': null});
      final ligada = w.comPosicao('revisora', 'executor').comPosicao('executor', '').comWorkflow('revisao-3');
      expect(ligada.paraJson(), {
        'posicoes': {'executor': null, 'revisora': 'executor'},
        'workflow': {'id': 'revisao-3'},
      });
    });

    test('completar com o servidor mantém o que o usuário escolheu e traz o que faltava', () {
      final doServidor = EscolhasDoModelo.deJson({
        'equipe': {'id': 'work-2', 'nome': 'Work 2'},
        'personas': {
          'nati': {'acao': 'usar', 'persona': 'nati'},
          'eva': {'acao': 'criar'},
        },
        'skills': {'outra': {'acao': 'usar'}},
      });
      final local = const EscolhasDoModelo(equipeId: '').comNomeDePersona('eva', '');
      final junta = local.completadaCom(doServidor);
      expect(junta.paraJson(), {
        'equipe': {'id': '', 'nome': 'Work 2'},
        'personas': {
          'nati': {'acao': 'usar', 'persona': 'nati'},
          'eva': {'acao': 'criar', 'nome': ''},
        },
        'skills': {'outra': {'acao': 'usar'}},
      });
      expect(const EscolhasDoModelo().completadaCom(doServidor).paraJson(), doServidor.paraJson());
    });

    test('resumo diz quando foi exportado', () {
      final r = ResumoDoModelo(tipo: 'equipe', nome: 'Work', exportadoEm: DateTime(2026, 11, 5, 9, 7));
      expect(r.exportado(agora: DateTime(2026, 11, 5, 15)), 'exportado hoje, às 09:07');
      expect(r.exportado(agora: DateTime(2026, 11, 8)), 'exportado 5/nov, às 09:07');
    });

    test('erros da prévia ficam presos ao campo pelo prefixo, e o resto fica solto', () {
      final p = PreviaDoModelo.deJson({
        'resumo': {'tipo': 'equipe', 'nome': 'Work'},
        'personasDoModelo': [
          {'id': 'nati', 'nome': 'Nati', 'traz': true},
        ],
        'posicoesDoModelo': [
          {'id': 'executor', 'titulo': 'executor'},
        ],
        'escolhas': {
          'skills': {
            'relatorio': {'acao': 'usar'},
          },
        },
        'erros': [
          'equipe: já existe uma equipe com o id casa',
          'persona Nati: já existe uma persona com o id nati; use a daqui ou escolha outro nome',
          'skill relatorio: o id relatorio já está em uso',
          'skill outra: é usada pela equipe, mas não veio no modelo e não existe aqui',
          'posição executor: escolha uma posição da equipe Casa para ela',
          'persona Nati, skill x: sem descrição',
        ],
      });
      expect(errosDoCampo(p.erros, [prefixoDaEquipe]), ['já existe uma equipe com o id casa']);
      expect(errosDoCampo(p.erros, prefixosDaPersona(p.personas.first)),
          ['já existe uma persona com o id nati; use a daqui ou escolha outro nome']);
      expect(errosDoCampo(p.erros, [prefixoDaSkill('relatorio')]), ['o id relatorio já está em uso']);
      expect(p.errosSoltos, [
        'skill outra: é usada pela equipe, mas não veio no modelo e não existe aqui',
        'posição executor: escolha uma posição da equipe Casa para ela',
        'persona Nati, skill x: sem descrição',
      ]);
    });

    test('id do modelo validado na hora', () {
      expect(erroDeId('casa-2'), isNull);
      expect(erroDeId(''), 'o id é obrigatório');
      for (final id in ['Casa', '2casa', 'casa 2', 'cása']) {
        expect(erroDeId(id), startsWith('id inválido'), reason: id);
      }
      expect(erroDeId('a' * 48), isNull);
      expect(erroDeId('a' * 49), 'id longo demais: no máximo 48 caracteres');
      expect(erroDeId('a' * 64, maximo: 64), isNull);
    });
  });

  test('o nome da Casa vem da equipe casa, com Casa como reserva, e chega aos rótulos das skills', () {
    expect(nomeDaCasaEm(const []), 'Casa');
    expect(nomeDaCasaEm(const [EquipeResumo(id: 'casa', nome: ' ', posicoes: [])]), 'Casa');
    const sala = [EquipeResumo(id: 'codigo', nome: 'Código', posicoes: []), EquipeResumo(id: 'casa', nome: 'Sala', posicoes: [])];
    expect(nomeDaCasaEm(sala), 'Sala');
    expect(rotuloDoDono('casa', casa: nomeDaCasaEm(sala)), 'Sala');
    expect(
      errosDosCamposDaSkill(
        const RascunhoDeSkill(dono: 'casa', id: 'relatorio', descricao: 'd', corpo: 'c'),
        existentes: const [Skill(dono: 'casa', id: 'relatorio')],
        casa: 'Sala',
      )[CampoDaSkill.id],
      'já existe a skill relatorio em Sala',
    );
  });
}
