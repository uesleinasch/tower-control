import 'organograma.dart';
import 'tarefas.dart';
import 'workflows.dart';

class ErroDeCron implements Exception {
  const ErroDeCron(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

class Cron {
  const Cron({
    required this.minutos,
    required this.horas,
    required this.dias,
    required this.meses,
    required this.semana,
    required this.diaRestrito,
    required this.semanaRestrita,
  });

  final Set<int> minutos;
  final Set<int> horas;
  final Set<int> dias;
  final Set<int> meses;
  final Set<int> semana;
  final bool diaRestrito;
  final bool semanaRestrita;
}

typedef _Campo = ({String nome, int min, int max});

const List<_Campo> _campos = [
  (nome: 'minuto', min: 0, max: 59),
  (nome: 'hora', min: 0, max: 23),
  (nome: 'dia do mês', min: 1, max: 31),
  (nome: 'mês', min: 1, max: 12),
  (nome: 'dia da semana', min: 0, max: 7),
];

final _numero = RegExp(r'^\d+$');

int _inteiro(String texto, _Campo campo) {
  if (!_numero.hasMatch(texto)) throw ErroDeCron('${campo.nome}: "$texto" não é número');
  final n = int.parse(texto);
  if (n < campo.min || n > campo.max) throw ErroDeCron('${campo.nome}: $n fora de ${campo.min}–${campo.max}');
  return n;
}

Set<int> _lerCampo(String texto, _Campo campo) {
  final valores = <int>{};
  for (final parte in texto.split(',')) {
    final pedacos = parte.split('/');
    final faixa = pedacos.first;
    if (faixa.isEmpty || pedacos.length > 2) throw ErroDeCron('${campo.nome}: "$parte" inválido');
    final passoTexto = pedacos.length == 2 ? pedacos[1] : null;
    final passo = passoTexto == null ? 1 : _inteiro(passoTexto, (nome: campo.nome, min: 1, max: campo.max + 1));
    int de;
    int ate;
    if (faixa == '*') {
      de = campo.min;
      ate = campo.max;
    } else if (faixa.contains('-')) {
      final limites = faixa.split('-');
      de = _inteiro(limites[0], campo);
      ate = _inteiro(limites[1], campo);
      if (de > ate) throw ErroDeCron('${campo.nome}: faixa $faixa invertida');
    } else {
      de = _inteiro(faixa, campo);
      ate = passoTexto == null ? de : campo.max;
    }
    for (var v = de; v <= ate; v += passo) {
      valores.add(campo.nome == 'dia da semana' && v == 7 ? 0 : v);
    }
  }
  return valores;
}

Cron lerCron(String expressao) {
  final partes = expressao.trim().split(RegExp(r'\s+'));
  if (partes.length != 5) throw const ErroDeCron('use 5 campos: minuto hora dia-do-mês mês dia-da-semana');
  final campos = [for (var i = 0; i < 5; i++) _lerCampo(partes[i], _campos[i])];
  return Cron(
    minutos: campos[0],
    horas: campos[1],
    dias: campos[2],
    meses: campos[3],
    semana: campos[4],
    diaRestrito: partes[2] != '*',
    semanaRestrita: partes[4] != '*',
  );
}

String? erroDoCron(String expressao) {
  try {
    lerCron(expressao);
    return null;
  } on ErroDeCron catch (e) {
    return e.mensagem;
  }
}

bool _diaCasa(Cron cron, DateTime d) {
  final dia = cron.dias.contains(d.day);
  final semana = cron.semana.contains(d.weekday % 7);
  if (cron.diaRestrito && cron.semanaRestrita) return dia || semana;
  return dia && semana;
}

const _limiteDePassos = 200000;

DateTime? proximoHorario(Cron cron, DateTime depois) {
  final l = depois.toLocal();
  var d = DateTime(l.year, l.month, l.day, l.hour, l.minute + 1);
  for (var passos = 0; passos < _limiteDePassos; passos++) {
    if (!cron.meses.contains(d.month)) {
      d = DateTime(d.year, d.month + 1, 1);
    } else if (!_diaCasa(cron, d)) {
      d = DateTime(d.year, d.month, d.day + 1);
    } else if (!cron.horas.contains(d.hour)) {
      d = DateTime(d.year, d.month, d.day, d.hour + 1);
    } else if (!cron.minutos.contains(d.minute)) {
      d = DateTime(d.year, d.month, d.day, d.hour, d.minute + 1);
    } else {
      return d;
    }
  }
  return null;
}

List<DateTime> proximosHorarios(Cron cron, DateTime depois, int quantos) {
  final saida = <DateTime>[];
  var atual = depois;
  while (saida.length < quantos) {
    final proximo = proximoHorario(cron, atual);
    if (proximo == null) break;
    saida.add(proximo);
    atual = proximo;
  }
  return saida;
}

int menorIntervaloEmMinutos(Cron cron) {
  final horarios = [for (final h in cron.horas) for (final m in cron.minutos) h * 60 + m]..sort();
  if (horarios.length < 2) return 24 * 60;
  var menor = 24 * 60 - horarios.last + horarios.first;
  for (var i = 1; i < horarios.length; i++) {
    final diferenca = horarios[i] - horarios[i - 1];
    if (diferenca < menor) menor = diferenca;
  }
  return menor;
}

const intervaloMinimoEmMinutos = 15;
const concorrencias = {
  'pular': 'pular (não cria se a anterior está aberta)',
  'enfileirar': 'enfileirar (a nova espera a anterior)',
  'substituir': 'substituir (cancela a anterior)',
};
const perdidosDaRotina = {
  'um': 'dispara uma vez ao voltar',
  'ignorar': 'ignora os horários perdidos',
};
const nomesDeOrigem = {'cron': 'horário', 'webhook': 'webhook', 'manual': 'manual'};
const nomesDeResultado = {'criada': 'criou a tarefa', 'pulada': 'pulou', 'falhou': 'falhou'};

DateTime? _data(Object? bruto) => bruto is String ? DateTime.tryParse(bruto)?.toLocal() : null;

class Disparo {
  const Disparo({
    required this.id,
    required this.equipe,
    required this.rotina,
    required this.origem,
    this.horario,
    required this.em,
    required this.resultado,
    this.motivo = '',
    this.tarefa,
  });

  final int id;
  final String equipe;
  final String rotina;
  final String origem;
  final DateTime? horario;
  final DateTime em;
  final String resultado;
  final String motivo;
  final int? tarefa;

  String get resumo => [
        nomesDeOrigem[origem] ?? origem,
        if (resultado != 'criada' || tarefa != null || motivo.isEmpty) nomesDeResultado[resultado] ?? resultado,
        if (tarefa != null) '#$tarefa',
        if (motivo.isNotEmpty) motivo,
      ].join(' · ');

  factory Disparo.deJson(Map<String, dynamic> j) => Disparo(
        id: (j['id'] as num?)?.toInt() ?? 0,
        equipe: j['equipe'] as String? ?? '',
        rotina: j['rotina'] as String? ?? '',
        origem: j['origem'] as String? ?? 'manual',
        horario: _data(j['horario']),
        em: _data(j['em']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        resultado: j['resultado'] as String? ?? 'falhou',
        motivo: j['motivo'] as String? ?? '',
        tarefa: (j['tarefa'] as num?)?.toInt(),
      );
}

class Rotina {
  const Rotina({
    required this.id,
    required this.nome,
    this.ativa = true,
    this.posicao = '',
    this.titulo = '',
    this.descricao = '',
    this.porque = '',
    this.workflow = '',
    this.cron = '',
    this.webhook = false,
    this.concorrencia = 'pular',
    this.perdidos = 'um',
    this.equipe,
    this.sistema = false,
    this.proximo,
    this.ultimoDisparo,
    this.disparos = const [],
    this.token,
    this.url,
  });

  final String id;
  final String nome;
  final bool ativa;
  final String posicao;
  final String titulo;
  final String descricao;
  final String porque;
  final String workflow;
  final String cron;
  final bool webhook;
  final String concorrencia;
  final String perdidos;
  final String? equipe;
  final bool sistema;
  final DateTime? proximo;
  final Disparo? ultimoDisparo;
  final List<Disparo> disparos;
  final String? token;
  final String? url;

  Rotina copiar({
    String? id,
    String? nome,
    bool? ativa,
    String? posicao,
    String? titulo,
    String? descricao,
    String? porque,
    String? workflow,
    String? cron,
    bool? webhook,
    String? concorrencia,
    String? perdidos,
  }) =>
      Rotina(
        id: id ?? this.id,
        nome: nome ?? this.nome,
        ativa: ativa ?? this.ativa,
        posicao: posicao ?? this.posicao,
        titulo: titulo ?? this.titulo,
        descricao: descricao ?? this.descricao,
        porque: porque ?? this.porque,
        workflow: workflow ?? this.workflow,
        cron: cron ?? this.cron,
        webhook: webhook ?? this.webhook,
        concorrencia: concorrencia ?? this.concorrencia,
        perdidos: perdidos ?? this.perdidos,
        equipe: equipe,
        sistema: sistema,
        proximo: proximo,
        ultimoDisparo: ultimoDisparo,
        disparos: disparos,
        token: token,
        url: url,
      );

  bool get iniciaWorkflow => workflow.isNotEmpty;

  Map<String, Object?> paraJson() => {
        'id': id,
        'nome': nome.trim(),
        'ativa': ativa,
        if (iniciaWorkflow)
          'workflow': workflow
        else ...{
          'posicao': posicao,
          'tarefa': {
            'titulo': titulo.trim(),
            if (descricao.trim().isNotEmpty) 'descricao': descricao.trim(),
            if (porque.trim().isNotEmpty) 'porque': porque.trim(),
          },
        },
        if (cron.trim().isNotEmpty) 'cron': cron.trim(),
        if (webhook) 'webhook': true,
        'concorrencia': concorrencia,
        'perdidos': perdidos,
      };

  factory Rotina.deJson(Map<String, dynamic> j) {
    final tarefa = j['tarefa'] is Map ? j['tarefa'] as Map : const {};
    String texto(Object? v) => v is String ? v : '';
    return Rotina(
      id: texto(j['id']),
      nome: texto(j['nome']),
      ativa: j['ativa'] != false,
      posicao: texto(j['posicao']),
      titulo: texto(tarefa['titulo']),
      descricao: texto(tarefa['descricao']),
      porque: texto(tarefa['porque']),
      workflow: texto(j['workflow']),
      cron: texto(j['cron']),
      webhook: j['webhook'] == true,
      concorrencia: j['concorrencia'] is String ? j['concorrencia'] as String : 'pular',
      perdidos: j['perdidos'] is String ? j['perdidos'] as String : 'um',
      equipe: j['equipe'] is String ? j['equipe'] as String : null,
      sistema: j['sistema'] == true,
      proximo: _data(j['proximo']),
      ultimoDisparo: j['ultimoDisparo'] is Map<String, dynamic> ? Disparo.deJson(j['ultimoDisparo'] as Map<String, dynamic>) : null,
      disparos: [
        for (final d in (j['disparos'] is List ? j['disparos'] as List : const []).whereType<Map<String, dynamic>>())
          Disparo.deJson(d),
      ],
      token: j['token'] is String ? j['token'] as String : null,
      url: j['url'] is String ? j['url'] as String : null,
    );
  }
}

final _slugDaRotina = RegExp(r'^[a-z][a-z0-9-]{0,47}$');

List<Workflow> workflowsParaRotina(List<Workflow> workflows, String equipe) =>
    [for (final w in workflows) if (w.equipe == equipe && aceitaRotina(w)) w];

enum CampoDaRotina { id, nome, workflow, titulo, posicao, concorrencia, perdidos, cron }

String? erroDoCronDaRotina(String expressao) {
  final cron = expressao.trim();
  if (cron.isEmpty) return null;
  try {
    if (menorIntervaloEmMinutos(lerCron(cron)) < intervaloMinimoEmMinutos) {
      return 'o cron dispara com menos de $intervaloMinimoEmMinutos minutos de intervalo';
    }
    return null;
  } on ErroDeCron catch (e) {
    return 'cron inválido (${e.mensagem})';
  }
}

Map<CampoDaRotina, String> errosDosCamposDaRotina(Rotina r, EquipeResumo equipe, {List<Workflow> workflows = const []}) {
  if (!_slugDaRotina.hasMatch(r.id)) return {CampoDaRotina.id: 'id inválido (${r.id})'};
  final erros = <CampoDaRotina, String>{};
  if (r.nome.trim().isEmpty) erros[CampoDaRotina.nome] = 'nome obrigatório';
  if (r.iniciaWorkflow) {
    final w = workflows.where((w) => w.equipe == equipe.id && w.id == r.workflow).firstOrNull;
    if (w == null) {
      erros[CampoDaRotina.workflow] = 'workflow inexistente (${r.workflow})';
    } else if (!aceitaRotina(w)) {
      erros[CampoDaRotina.workflow] = 'o workflow ${r.workflow} pede entrada que a rotina não dá (só "dados" em texto)';
    }
  } else {
    if (r.titulo.trim().isEmpty) erros[CampoDaRotina.titulo] = 'título da tarefa obrigatório';
    final posicao = r.posicao.trim();
    if (equipe.posicao(posicao) == null) erros[CampoDaRotina.posicao] = 'posição inexistente ($posicao)';
  }
  if (!concorrencias.containsKey(r.concorrencia)) erros[CampoDaRotina.concorrencia] = 'concorrência inválida';
  if (!perdidosDaRotina.containsKey(r.perdidos)) erros[CampoDaRotina.perdidos] = 'perdidos inválido';
  if (erroDoCronDaRotina(r.cron) case final cron?) erros[CampoDaRotina.cron] = cron;
  return erros;
}

List<String> errosDaRotina(Rotina r, EquipeResumo equipe, {List<Workflow> workflows = const []}) {
  final erros = errosDosCamposDaRotina(r, equipe, workflows: workflows);
  if (erros[CampoDaRotina.id] case final id?) return ['rotina: $id'];
  return [for (final e in erros.values) 'rotina ${r.id}: $e'];
}

String _dois(int n) => n.toString().padLeft(2, '0');

String tituloDaTarefa(String modelo, DateTime quando) => modelo
    .replaceAll('{data}', '${_dois(quando.day)}/${_dois(quando.month)}')
    .replaceAll('{hora}', '${_dois(quando.hour)}:${_dois(quando.minute)}');

String previaDoCron(String expressao, DateTime agora) {
  final proximos = proximosDoCron(expressao, agora);
  return proximos.isEmpty ? '' : 'Próximas: ${proximos.map(horarioCurto).join(' · ')}';
}

List<DateTime> proximosDoCron(String expressao, DateTime agora, [int quantos = 3]) {
  try {
    return proximosHorarios(lerCron(expressao), agora, quantos);
  } on ErroDeCron {
    return const [];
  }
}

({String equipe, String id})? rotinaDoAutor(String? criadaPor) {
  const prefixo = 'rotina:';
  if (criadaPor == null || !criadaPor.startsWith(prefixo)) return null;
  final resto = criadaPor.substring(prefixo.length);
  final barra = resto.indexOf('/');
  if (barra < 0) return (equipe: '', id: resto);
  return (equipe: resto.substring(0, barra), id: resto.substring(barra + 1));
}

String idDaNovaRotina(String nome, Iterable<String> usados) =>
    idLivre(nome.trim().isEmpty ? 'rotina' : slugDe(nome), usados);

bool webhookArriscado(Rotina r, EquipeResumo equipe) {
  if (!r.webhook) return false;
  if (r.iniciaWorkflow) return false;
  final p = equipe.posicao(r.posicao);
  return p != null && p.capacidades.contains('comandos') && p.aprovacao == 'auto';
}

String urlDoWebhook(String endereco, String caminho) => 'http://$endereco$caminho';

String curlDoWebhook(String url, String token) =>
    "curl -X POST -H 'X-Token: $token' --data 'texto do disparo' $url";

const diasDaSemana = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];

String cronTodoDia(int hora, int minuto) => '$minuto $hora * * *';

String cronDiasUteis(int hora, int minuto) => '$minuto $hora * * 1-5';

String cronSemanal(int dia, int hora, int minuto) => '$minuto $hora * * $dia';

String cronACadaHoras(int horas) => horas <= 1 ? '0 * * * *' : '0 */$horas * * *';

String descricaoDoGatilho(Rotina r) {
  final partes = [
    if (r.cron.trim().isNotEmpty) r.cron.trim(),
    if (r.webhook) 'webhook',
  ];
  return partes.isEmpty ? 'só manual' : partes.join(' · ');
}

const _diasCurtos = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];

String horarioCurto(DateTime d) {
  final l = d.toLocal();
  return '${_diasCurtos[l.weekday % 7]} ${_dois(l.day)}/${_dois(l.month)} ${_dois(l.hour)}:${_dois(l.minute)}';
}

final _horaMinuto = RegExp(r'^(\d{1,2})(?::(\d{2}))?$');

({int hora, int minuto})? lerHoraMinuto(String texto) {
  final m = _horaMinuto.firstMatch(texto.trim());
  if (m == null) return null;
  final hora = int.parse(m.group(1)!);
  final minuto = int.parse(m.group(2) ?? '0');
  if (hora > 23 || minuto > 59) return null;
  return (hora: hora, minuto: minuto);
}
