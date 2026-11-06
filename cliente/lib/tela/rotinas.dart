import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../conexao/http.dart';
import '../estado/rotinas.dart';
import '../estado/sala.dart';
import '../nucleo/enderecos.dart';
import '../nucleo/formato.dart';
import '../nucleo/rotinas.dart';
import '../nucleo/tarefas.dart';
import 'comum.dart' show copiar;
import 'tema.dart';

const _larguraDoEditor = 420.0;

class PainelDeRotinas extends StatelessWidget {
  const PainelDeRotinas({super.key, required this.sala, required this.equipe, required this.editar, required this.largo});

  final Sala sala;
  final EquipeResumo equipe;
  final bool editar;
  final bool largo;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([sala.rotinas, sala.workflows]),
        builder: (context, _) {
          final estado = sala.rotinas;
          final lista = _ListaDeRotinas(sala: sala, equipe: equipe, editar: editar);
          final editando = editar && estado.rascunho != null && estado.equipeDoRascunho == equipe.id;
          if (!editando) return lista;
          final editor = _EditorDeRotina(
            key: ValueKey('${equipe.id}/${estado.nova ? '+' : estado.rascunho!.id}'),
            sala: sala,
            equipe: equipe,
          );
          if (!largo) return editor;
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: lista),
            const VerticalDivider(width: 1),
            SizedBox(width: _larguraDoEditor, child: editor),
          ]);
        },
      );
}

class _ListaDeRotinas extends StatelessWidget {
  const _ListaDeRotinas({required this.sala, required this.equipe, required this.editar});

  final Sala sala;
  final EquipeResumo equipe;
  final bool editar;

  @override
  Widget build(BuildContext context) {
    final estado = sala.rotinas;
    final cores = Theme.of(context).colorScheme;
    final daEquipe = estado.daEquipe(equipe.id);
    final sistema = equipe.id == 'casa' ? estado.doSistema : const <Rotina>[];
    final equipeSalva = sala.equipes.equipes.any((e) => e.id == equipe.id);
    final rotulo = TextStyle(color: cores.onSurfaceVariant, fontSize: 11, letterSpacing: 1);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
      Row(children: [
        Expanded(child: Text('ROTINAS · ${equipe.nome.toUpperCase()}', style: rotulo)),
        IconButton(tooltip: 'Recarregar', icon: const Icon(Symbols.refresh), onPressed: estado.carregar),
        if (editar)
          FilledButton.tonalIcon(
            onPressed: equipeSalva && !estado.salvando ? () => estado.novaRotina(equipe) : null,
            icon: const Icon(Symbols.add),
            label: const Text('Nova rotina'),
          ),
      ]),
      if (editar && !equipeSalva)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Salve a equipe antes de criar rotinas.', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
        ),
      if (!estado.carregada)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (daEquipe.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            editar ? 'Nenhuma rotina nesta equipe.' : 'Nenhuma rotina nesta equipe. Rotinas se criam no desktop.',
            style: TextStyle(color: cores.onSurfaceVariant),
          ),
        ),
      for (final r in daEquipe)
        _CartaoDaRotina(
          sala: sala,
          equipe: equipe,
          rotina: r,
          editar: editar,
          selecionada: estado.rascunho?.id == r.id && estado.equipeDoRascunho == equipe.id && !estado.nova,
        ),
      if (sistema.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 4), child: Text('SISTEMA', style: rotulo)),
        for (final r in sistema) _CartaoDaRotina(sala: sala, equipe: equipe, rotina: r, editar: false, selecionada: false),
      ],
    ]);
  }
}

class _CartaoDaRotina extends StatelessWidget {
  const _CartaoDaRotina({
    required this.sala,
    required this.equipe,
    required this.rotina,
    required this.editar,
    required this.selecionada,
  });

  final Sala sala;
  final EquipeResumo equipe;
  final Rotina rotina;
  final bool editar;
  final bool selecionada;

  void _abrirTarefa(int id) {
    sala.tarefas.escolherEquipe(equipe.id);
    sala.abrirTarefa(id);
  }

  @override
  Widget build(BuildContext context) {
    final estado = sala.rotinas;
    final cores = Theme.of(context).colorScheme;
    final r = rotina;
    final pequeno = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    final posicao = r.sistema ? null : equipe.posicao(r.posicao);
    final ultimo = r.ultimoDisparo;
    return Card(
      color: selecionada ? cores.secondaryContainer : null,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: editar && !r.sistema ? () => estado.editar(r) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(r.nome.isEmpty ? r.id : r.nome, style: const TextStyle(fontWeight: FontWeight.w600))),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(r.sistema ? 'sistema' : r.ativa ? 'ativa' : 'inativa', style: const TextStyle(fontSize: 11)),
              ),
            ]),
            Text(
              [
                if (r.iniciaWorkflow)
                  'inicia ${sala.workflows.nomeDoWorkflow(equipe.id, r.workflow)}'
                else if (posicao != null)
                  posicao.rotulo
                else if (!r.sistema)
                  '${r.posicao} (sumiu)',
                descricaoDoGatilho(r),
              ].join(' · '),
              style: pequeno,
            ),
            Text('próximo: ${r.proximo == null ? '—' : horarioCurto(r.proximo!)}', style: pequeno),
            if (ultimo != null)
              Text(
                'último: ${quando(ultimo.em)} · ${ultimo.resumo}',
                style: TextStyle(color: corDoEstado(context, ultimo.resultado), fontSize: 12),
              )
            else
              Text('nunca disparou', style: pequeno),
            if (!r.sistema)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 8, runSpacing: 4, children: [
                  OutlinedButton.icon(
                    onPressed: () => estado.disparar(r),
                    icon: const Icon(Symbols.play_arrow, size: 18),
                    label: const Text('Disparar agora'),
                  ),
                  TextButton.icon(
                    onPressed: () => estado.alternarAtiva(r),
                    icon: Icon(r.ativa ? Symbols.pause_circle : Symbols.play_circle, size: 18),
                    label: Text(r.ativa ? 'Desativar' : 'Ativar'),
                  ),
                ]),
              ),
            if (r.disparos.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Últimos disparos (${r.disparos.length})', style: pequeno),
                  children: [
                    for (final d in r.disparos)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        title: Text('${horarioCurto(d.em)} · ${d.resumo}',
                            style: TextStyle(color: corDoEstado(context, d.resultado), fontSize: 12)),
                        onTap: d.tarefa == null ? null : () => _abrirTarefa(d.tarefa!),
                      ),
                  ],
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _EditorDeRotina extends StatefulWidget {
  const _EditorDeRotina({super.key, required this.sala, required this.equipe});

  final Sala sala;
  final EquipeResumo equipe;

  @override
  State<_EditorDeRotina> createState() => _EditorDeRotinaState();
}

class _EditorDeRotinaState extends State<_EditorDeRotina> {
  EstadoRotinas get estado => widget.sala.rotinas;
  Rotina get r => estado.rascunho!;

  late final _nome = TextEditingController(text: r.nome);
  late final _titulo = TextEditingController(text: r.titulo);
  late final _descricao = TextEditingController(text: r.descricao);
  late final _porque = TextEditingController(text: r.porque);
  late final _cron = TextEditingController(text: r.cron);
  final _hora = TextEditingController(text: '08:30');
  final _horas = TextEditingController(text: '4');
  var _dia = 1;
  String? _endereco;

  @override
  void initState() {
    super.initState();
    _resolverEndereco();
  }

  Future<void> _resolverEndereco() async {
    final local = widget.sala.canal.endereco;
    if (local == null) return;
    final resposta = await sondar(local);
    final lan = resposta == null ? const <String>[] : enderecosDaResposta(resposta);
    if (mounted) setState(() => _endereco = lan.firstOrNull ?? local);
  }

  @override
  void dispose() {
    for (final c in [_nome, _titulo, _descricao, _porque, _cron, _hora, _horas]) {
      c.dispose();
    }
    super.dispose();
  }

  void _usarCron(String cron) {
    _cron.text = cron;
    estado.mudar((x) => x.copiar(cron: cron));
  }

  void _atalho(String Function(int hora, int minuto) montar) {
    final hm = lerHoraMinuto(_hora.text);
    if (hm == null) return;
    _usarCron(montar(hm.hora, hm.minuto));
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text('Excluir a rotina ${r.nome}?'),
        content: const Text('Os disparos já feitos ficam no histórico. As tarefas criadas por ela continuam.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(contexto).colorScheme.error),
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) estado.excluir();
  }

  Widget _webhook(BuildContext context, Rotina? salva) {
    final cores = Theme.of(context).colorScheme;
    final pequeno = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    final token = salva?.token;
    final caminho = salva?.url;
    if (!r.webhook) return const SizedBox.shrink();
    if (salva?.webhook != true || token == null || caminho == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('Salve para gerar a URL e o token.', style: pequeno),
      );
    }
    final url = urlDoWebhook(_endereco ?? widget.sala.canal.endereco ?? 'host:7878', caminho);
    Widget linha(String rotulo, String valor) => Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rotulo, style: pequeno),
              SelectableText(valor, style: const TextStyle(fontFamily: familiaMono, fontSize: 12)),
            ]),
          ),
          IconButton(tooltip: 'Copiar', icon: const Icon(Symbols.content_copy, size: 18), onPressed: () => copiar(context, valor)),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      linha('URL (POST)', url),
      linha('Token (cabeçalho X-Token ou ?token=)', token),
      linha('Exemplo', curlDoWebhook(url, token)),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: estado.trocarToken, icon: const Icon(Symbols.autorenew), label: const Text('Trocar token')),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final equipe = widget.equipe;
    final pequeno = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    final rotina = r;
    final salva = estado.salva(equipe.id, rotina.id);
    final definicoes = widget.sala.workflows.definicoes;
    final erros = estado.errosDoRascunho(equipe, workflows: definicoes);
    final possiveis = workflowsParaRotina(definicoes, equipe.id);
    final porWorkflow = rotina.iniciaWorkflow;
    final escolhido = definicoes.where((w) => w.equipe == equipe.id && w.id == rotina.workflow).firstOrNull;
    final proximos = rotina.cron.trim().isEmpty ? const <DateTime>[] : proximosDoCron(rotina.cron, DateTime.now());
    final previa = tituloDaTarefa(rotina.titulo, proximos.firstOrNull ?? DateTime.now());
    final posicaoValida = equipe.posicao(rotina.posicao) != null;
    Widget secao(String texto) =>
        Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text(texto, style: pequeno));

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: Text(estado.nova ? 'Nova rotina' : 'Rotina ${rotina.id}', style: Theme.of(context).textTheme.titleSmall),
        ),
        IconButton(tooltip: 'Fechar', icon: const Icon(Symbols.close), onPressed: estado.fecharEditor),
      ]),
      TextField(
        controller: _nome,
        decoration: InputDecoration(labelText: 'Nome', helperText: 'id: ${rotina.id}${estado.nova ? ' (fixo depois de salvar)' : ''}'),
        onChanged: (v) => estado.mudar((x) => x.copiar(nome: v)),
      ),
      secao('Destino'),
      SegmentedButton<bool>(
        segments: [
          const ButtonSegment(value: false, label: Text('Criar tarefa'), icon: Icon(Symbols.task_alt)),
          ButtonSegment(
            value: true,
            label: const Text('Iniciar workflow'),
            icon: const Icon(Symbols.alt_route),
            enabled: porWorkflow || possiveis.isNotEmpty,
          ),
        ],
        selected: {porWorkflow},
        onSelectionChanged: (v) => estado.mudar((x) => x.copiar(workflow: v.first ? possiveis.first.id : '')),
      ),
      if (!porWorkflow && possiveis.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Nenhum workflow desta equipe pode ser iniciado por rotina (a entrada precisa ser vazia ou só "dados" em texto).',
              style: pequeno),
        ),
      const SizedBox(height: 12),
      if (porWorkflow)
        DropdownButtonFormField<String>(
          initialValue: escolhido?.id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Workflow',
            helperText: escolhido != null && escolhido.entrada.containsKey('dados')
                ? 'o corpo do webhook vai em entrada.dados'
                : null,
          ),
          items: [
            for (final w in [...possiveis, if (escolhido != null && !possiveis.contains(escolhido)) escolhido])
              DropdownMenuItem(value: w.id, child: Text(w.nome, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => v == null ? null : estado.mudar((x) => x.copiar(workflow: v)),
        )
      else ...[
        DropdownButtonFormField<String>(
          initialValue: posicaoValida ? rotina.posicao : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Posição que recebe a tarefa'),
          items: [for (final p in equipe.posicoes) DropdownMenuItem(value: p.id, child: Text(p.rotulo, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => v == null ? null : estado.mudar((x) => x.copiar(posicao: v)),
        ),
        secao('Tarefa'),
        TextField(
          controller: _titulo,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: 'Título',
            helperText: rotina.titulo.trim().isEmpty ? 'aceita {data} e {hora}' : 'prévia: $previa',
            counterText: '',
          ),
          onChanged: (v) => estado.mudar((x) => x.copiar(titulo: v)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descricao,
          minLines: 2,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Descrição'),
          onChanged: (v) => estado.mudar((x) => x.copiar(descricao: v)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _porque,
          decoration: const InputDecoration(labelText: 'Por quê'),
          onChanged: (v) => estado.mudar((x) => x.copiar(porque: v)),
        ),
      ],
      secao('Gatilho'),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 80,
          child: TextField(controller: _hora, decoration: const InputDecoration(labelText: 'às', isDense: true)),
        ),
        ActionChip(label: const Text('todo dia'), onPressed: () => _atalho(cronTodoDia)),
        ActionChip(label: const Text('dias úteis'), onPressed: () => _atalho(cronDiasUteis)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownButton<int>(
          value: _dia,
          items: [for (final (i, d) in diasDaSemana.indexed) DropdownMenuItem(value: i, child: Text(d))],
          onChanged: (v) => setState(() => _dia = v ?? _dia),
        ),
        ActionChip(label: const Text('toda semana neste dia'), onPressed: () => _atalho((h, m) => cronSemanal(_dia, h, m))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 80,
          child: TextField(
            controller: _horas,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'N horas', isDense: true),
          ),
        ),
        ActionChip(
          label: const Text('a cada N horas'),
          onPressed: () {
            final n = int.tryParse(_horas.text.trim());
            if (n != null && n >= 1 && n <= 23) _usarCron(cronACadaHoras(n));
          },
        ),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _cron,
        style: const TextStyle(fontFamily: familiaMono),
        decoration: const InputDecoration(
          labelText: 'Cron (minuto hora dia mês dia-da-semana)',
          helperText: 'vazio: sem horário (só webhook ou manual)',
        ),
        onChanged: (v) => estado.mudar((x) => x.copiar(cron: v)),
      ),
      if (proximos.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('próximos: ${proximos.map(horarioCurto).join(' · ')}', style: pequeno),
      ],
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: rotina.webhook,
        title: const Text('Webhook'),
        subtitle: const Text('aceita disparo por POST de fora'),
        onChanged: (v) => estado.mudar((x) => x.copiar(webhook: v)),
      ),
      if (webhookArriscado(rotina, equipe))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Atenção: esta posição roda comandos no automático. O texto do webhook vem de fora '
            'e entra na tarefa como dado; comando sensível ainda pede aprovação.',
            style: const TextStyle(color: Color(0xFFE0A458), fontSize: 12),
          ),
        ),
      _webhook(context, salva),
      secao('Política'),
      DropdownButtonFormField<String>(
        initialValue: concorrencias.containsKey(rotina.concorrencia) ? rotina.concorrencia : 'pular',
        isExpanded: true,
        decoration: InputDecoration(
          labelText: porWorkflow ? 'Com o workflow anterior ainda aberto' : 'Com a tarefa anterior ainda aberta',
        ),
        items: [for (final MapEntry(:key, :value) in concorrencias.entries) DropdownMenuItem(value: key, child: Text(value))],
        onChanged: (v) => v == null ? null : estado.mudar((x) => x.copiar(concorrencia: v)),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: perdidosDaRotina.containsKey(rotina.perdidos) ? rotina.perdidos : 'um',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Horário perdido (servidor desligado)'),
        items: [for (final MapEntry(:key, :value) in perdidosDaRotina.entries) DropdownMenuItem(value: key, child: Text(value))],
        onChanged: (v) => v == null ? null : estado.mudar((x) => x.copiar(perdidos: v)),
      ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: rotina.ativa,
        title: const Text('Ativa'),
        onChanged: (v) => estado.mudar((x) => x.copiar(ativa: v)),
      ),
      for (final erro in erros)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(erro, style: TextStyle(color: cores.error, fontSize: 12)),
        ),
      if (estado.erro != null && erros.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(estado.erro!, style: TextStyle(color: cores.error, fontSize: 12)),
        ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: erros.isEmpty && !estado.salvando ? () => estado.salvar(equipe, workflows: definicoes) : null,
          icon: const Icon(Symbols.save),
          label: Text(estado.salvando ? 'Salvando…' : 'Salvar'),
        ),
        if (!estado.nova)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cores.error),
            onPressed: estado.salvando ? null : _excluir,
            icon: const Icon(Symbols.delete),
            label: const Text('Excluir'),
          ),
      ]),
    ]);
  }
}
