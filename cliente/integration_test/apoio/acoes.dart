import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ambiente.dart';
import 'esperas.dart';
import 'falsos.dart';

String dados(String relativo) => '${ambiente.dados}/$relativo';

bool aberta(Map t) => t['status'] != 'concluida' && t['status'] != 'cancelada';

Future<List<Map>> tarefasNoServidor(Conexao c) async =>
    ((await c.pedir({'tipo': 'tarefas'}, 'tarefas'))['lista'] as List).cast<Map>();

Future<void> cancelarAbertas(Conexao c) async {
  for (final t in (await tarefasNoServidor(c)).where(aberta)) {
    await c.pedir(
      {'tipo': 'tarefa-status', 'id': t['id'], 'status': 'cancelada'},
      'tarefa',
      filtro: (m) => m['tarefa']['id'] == t['id'] && m['tarefa']['status'] == 'cancelada',
    );
  }
}

Future<Map<String, dynamic>> tarefaNoServidor(Conexao c, int id) =>
    c.pedir({'tipo': 'tarefa', 'id': id}, 'tarefa', filtro: (m) => m['pedida'] == true && m['tarefa']['id'] == id);

Future<void> pausarAlfred(Conexao c) => c.pedir(
  {'tipo': 'pausar', 'alvo': 'alfred'},
  'personas',
  filtro: (m) => (m['lista'] as List).any((p) => p['id'] == 'alfred' && p['pausa'] != null),
);

Future<void> retomarAlfred(Conexao c) => c.pedir(
  {'tipo': 'retomar', 'alvo': 'alfred'},
  'personas',
  filtro: (m) => (m['lista'] as List).any((p) => p['id'] == 'alfred' && p['pausa'] == null),
);

Future<Map<String, dynamic>> workflowsNoServidor(Conexao c) => c.pedir({'tipo': 'workflows'}, 'workflows');

Future<List<Map>> fluxosNoServidor(Conexao c) async => ((await workflowsNoServidor(c))['fluxos'] as List).cast<Map>();

Future<Map> fluxoNoServidor(Conexao c, int id) async =>
    (await fluxosNoServidor(c)).firstWhere((f) => f['id'] == id, orElse: () => throw StateError('o fluxo #$id sumiu'));

List<Map> fichasDe(Map fluxo) => (fluxo['fichas'] as List).cast<Map>();

Future<void> salvarWorkflow(Conexao c, Map<String, Object?> workflow) => c.pedir(
  {'tipo': 'workflow-salvar', 'equipe': 'casa', 'workflow': workflow},
  'workflows',
  filtro: (m) => (m['definicoes'] as List).any(
    (d) => d['equipe'] == 'casa' && d['id'] == workflow['id'] && d['versao'] == (workflow['versao'] as int) + 1,
  ),
);

int versaoNoDisco(String workflow) {
  final arquivo = File(dados('equipes/casa/workflows/$workflow.json'));
  return arquivo.existsSync() ? (jsonDecode(arquivo.readAsStringSync())['versao'] as int) : 0;
}

Future<void> cancelarFluxosDe(Conexao c, String id) async {
  for (final f in await fluxosNoServidor(c)) {
    if (f['workflow'] != id || (f['status'] != 'rodando' && f['status'] != 'esperando')) continue;
    await c.pedir(
      {'tipo': 'workflow-cancelar', 'execucao': f['id']},
      'workflows',
      filtro: (m) => (m['fluxos'] as List).any((x) => x['id'] == f['id'] && x['status'] == 'cancelado'),
    );
  }
}

Future<void> excluirWorkflow(Conexao c, String id) async {
  await cancelarFluxosDe(c, id);
  if (!File(dados('equipes/casa/workflows/$id.json')).existsSync()) return;
  await c.pedir(
    {'tipo': 'workflow-excluir', 'equipe': 'casa', 'id': id},
    'workflows',
    filtro: (m) => !(m['definicoes'] as List).any((d) => d['equipe'] == 'casa' && d['id'] == id),
  );
  await esperarSumir(dados('equipes/casa/workflows/$id.json'));
}

Future<Object?> _doTickTask(String caminho, {bool post = false}) async {
  final uri = Uri.parse('${ambiente.ticktask}$caminho');
  final resposta = post ? await http.post(uri) : await http.get(uri);
  if (resposta.statusCode != 200) throw StateError('$caminho no TickTask falso respondeu ${resposta.statusCode}: ${resposta.body}');
  return jsonDecode(utf8.decode(resposta.bodyBytes));
}

Future<List<Map>> tarefasNoTickTask() async => ((await _doTickTask('/_controle/tarefas')) as List).cast<Map>();

Future<void> finalizarNoTickTask(int id) => _doTickTask('/_controle/finalizar/$id', post: true);
