import 'package:material_ui/material_ui.dart';

import '../estado/sala.dart';
import '../estado/tarefas.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/protocolo.dart';
import '../nucleo/tarefas.dart';
import '../nucleo/workflows.dart';
import 'chat.dart';
import 'comum.dart';
import 'equipes.dart';
import 'tema.dart';

class TelaTarefas extends StatelessWidget {
  const TelaTarefas({super.key, required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([sala.tarefas, sala.rotinas, sala.workflows]),
        builder: (context, _) {
          final aberta = sala.tarefas.aberta;
          return aberta == null
              ? _Lista(sala: sala)
              : _Detalhe(sala: sala, aberta: aberta);
        },
      );
}

class _Status extends StatelessWidget {
  const _Status(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final cor = corDoEstado(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
      child: Text(nomesDeStatus[status] ?? status, style: TextStyle(color: cor, fontSize: 12)),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) {
    final estado = sala.tarefas;
    final cores = Theme.of(context).colorScheme;
    final grupos = agruparPorStatus(estado.daEquipe);
    return Column(children: [
      Material(
        color: cores.surface,
        child: SafeArea(
          bottom: false,
          child: ListTile(
            leading: const Avatar(cor: Color(Perfil.corTarefas), inicial: 'T', tamanho: 32),
            title: Text('Tarefas — ${estado.nomeDaEquipe}'),
            subtitle: Text('o que as personas têm a fazer', style: TextStyle(color: cores.onSurfaceVariant)),
            trailing: IconButton(tooltip: 'Recarregar', icon: const Icon(Icons.refresh), onPressed: estado.carregar),
          ),
        ),
      ),
      const Divider(height: 1),
      BarraDePausa(estado: sala.equipes),
      Expanded(
        child: !estado.carregada
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (estado.equipes.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: DropdownButton<String>(
                        value: estado.equipes.any((e) => e.id == estado.equipe) ? estado.equipe : null,
                        isExpanded: true,
                        items: [for (final e in estado.equipes) DropdownMenuItem(value: e.id, child: Text(e.nome))],
                        onChanged: (id) => id == null ? null : estado.escolherEquipe(id),
                      ),
                    ),
                  _NovaTarefa(sala: sala),
                  if (estado.daEquipe.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                          child: Text('Nenhuma tarefa ainda.', style: TextStyle(color: cores.onSurfaceVariant))),
                    ),
                  for (final grupo in grupos) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        '${(nomesDeStatus[grupo.status] ?? grupo.status).toUpperCase()} · ${grupo.tarefas.length}',
                        style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11, letterSpacing: 1),
                      ),
                    ),
                    for (final t in grupo.tarefas)
                      ListTile(
                        title: Text('#${t.id} ${t.titulo}'),
                        subtitle: Text(
                          [
                            estado.rotuloDaPosicao(t.posicao),
                            if (t.status == 'em_revisao' && t.comQuem != null) t.comQuem!,
                            quando(t.atualizadaEm),
                            if (t.rodando) '● rodando',
                          ].join(' · '),
                          style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
                        ),
                        trailing: _Status(t.status),
                        onTap: () => estado.abrir(t.id),
                      ),
                  ],
                ],
              ),
      ),
    ]);
  }
}

class _NovaTarefa extends StatefulWidget {
  const _NovaTarefa({required this.sala});

  final Sala sala;

  @override
  State<_NovaTarefa> createState() => _NovaTarefaState();
}

class _NovaTarefaState extends State<_NovaTarefa> {
  final _titulo = TextEditingController();
  final _porque = TextEditingController();
  String? _posicao;

  @override
  void dispose() {
    _titulo.dispose();
    _porque.dispose();
    super.dispose();
  }

  void _criar() {
    final estado = widget.sala.tarefas;
    final posicao = _posicao ?? estado.posicoes.firstOrNull?.id;
    final titulo = _titulo.text.trim();
    if (posicao == null || titulo.isEmpty) return;
    estado.criar(posicao: posicao, titulo: titulo, porque: _porque.text);
    _titulo.clear();
    _porque.clear();
  }

  @override
  Widget build(BuildContext context) {
    final posicoes = widget.sala.tarefas.posicoes;
    final escolhida = posicoes.any((p) => p.id == _posicao) ? _posicao : posicoes.firstOrNull?.id;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            initialValue: escolhida,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Posição'),
            items: [for (final p in posicoes) DropdownMenuItem(value: p.id, child: Text(p.rotulo))],
            onChanged: (valor) => setState(() => _posicao = valor),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titulo,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'O que precisa ser feito', counterText: ''),
            onSubmitted: (_) => _criar(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _porque,
            decoration: const InputDecoration(labelText: 'Por quê (o objetivo que a persona recebe junto)'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(onPressed: _criar, child: const Text('Criar tarefa')),
          ),
        ]),
      ),
    );
  }
}

class _Detalhe extends StatefulWidget {
  const _Detalhe({required this.sala, required this.aberta});

  final Sala sala;
  final TarefaAberta aberta;

  Tarefa get tarefa => aberta.tarefa;
  List<RegistroDeTarefa> get registros => aberta.registros;

  @override
  State<_Detalhe> createState() => _DetalheState();
}

class _DetalheState extends State<_Detalhe> {
  final _comentario = TextEditingController();

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  void _comentar() {
    widget.sala.tarefas.comentar(widget.tarefa.id, _comentario.text);
    _comentario.clear();
  }

  Future<void> _pedirMudanca() async {
    final texto = await pedirTexto(
      context,
      titulo: 'Pedir mudança em #${widget.tarefa.id}',
      rotulo: 'O que mudar e por quê',
      acao: 'Pedir mudança',
      multilinha: true,
    );
    if (texto != null) widget.sala.tarefas.pedirMudanca(widget.tarefa.id, texto);
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.sala.tarefas;
    final t = widget.tarefa;
    final cores = Theme.of(context).colorScheme;
    final ficha = [
      '**${t.titulo}**',
      '${estado.rotuloDaPosicao(t.posicao)}${t.rodando ? ' · rodando agora' : ''} · custo ${dinheiro(widget.aberta.custoUSD)}',
      if (t.porque.isNotEmpty) 'Por quê: ${t.porque}',
      if (t.dependeDe.isNotEmpty) 'Depende de: ${t.dependeDe.map((d) => '#$d').join(', ')}',
      if (t.pai != null) 'Parte da tarefa #${t.pai}',
      ?widget.sala.rotinas.criadaPelaRotina(t.criadaPor),
      if (t.fluxo != null) descricaoDaCaixaDaTarefa(t, widget.sala.workflows.fluxos),
      if (t.descricao.isNotEmpty) t.descricao,
    ].join('\n\n');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) estado.fecharDetalhe();
      },
      child: Column(children: [
        Material(
          color: cores.surface,
          child: SafeArea(
            bottom: false,
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: estado.fecharDetalhe),
              Expanded(child: Text('#${t.id}', overflow: TextOverflow.ellipsis)),
              Padding(padding: const EdgeInsets.only(right: 12), child: _Status(t.status)),
            ]),
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SelectionArea(child: TextoMarkdown(ficha)),
              if (t.fluxo case final fluxo?)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => widget.sala.abrirFluxo(fluxo, equipe: t.equipe),
                    icon: const Icon(Icons.alt_route, size: 18),
                    label: const Text('Ver o workflow'),
                  ),
                ),
              if (t.politica.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Trilha(
                  trilha: trilhaDaTarefa(
                    t,
                    estado.equipes.where((e) => e.id == t.equipe).firstOrNull,
                    (id) => Perfil.porChave(id).nome,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (t.esperaDecisaoDoUeslei) ...[
                  FilledButton.icon(
                    onPressed: () => estado.aprovarEtapa(t.id),
                    icon: const Icon(Icons.check),
                    label: const Text('Aprovar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pedirMudanca,
                    icon: const Icon(Icons.undo),
                    label: const Text('Pedir mudança'),
                  ),
                ],
                if (t.status == 'em_revisao' && planoPendente(widget.registros))
                  FilledButton.icon(
                    onPressed: () => estado.aprovarPlano(t.id),
                    icon: const Icon(Icons.check),
                    label: const Text('Aprovar plano'),
                  ),
                for (final para in t.proximosStatus)
                  OutlinedButton(
                    onPressed: () => estado.mudarStatus(t.id, para),
                    child: Text('→ ${nomesDeStatus[para] ?? para}'),
                  ),
              ]),
              const SizedBox(height: 16),
              for (final r in widget.registros)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: r.comentario || r.destacado
                      ? Card(
                          margin: EdgeInsets.zero,
                          shape: r.destacado
                              ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: corDoEstado(
                                      context,
                                      switch (r.tipo) {
                                        'entrega' || 'plano' || 'aprovado' || 'mudanca' => r.tipo,
                                        _ => 'bloqueada',
                                      },
                                    ),
                                  ),
                                )
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                  '${r.autor}${switch (r.tipo) {
                                    'entrega' => ' entregou',
                                    'ajuda' => ' pediu ajuda',
                                    'plano' => ' propôs um plano',
                                    'aprovado' => ' aprovou',
                                    'mudanca' => ' pediu mudança',
                                    _ => '',
                                  }} · ${quando(r.em)}',
                                  style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
                              const SizedBox(height: 4),
                              SelectableText(r.texto),
                            ]),
                          ),
                        )
                      : Text('${r.autor}: ${r.texto} · ${quando(r.em)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
                ),
              for (final pedido in estado.pedidosDaAberta) _PedidoDeComando(pedido: pedido, estado: estado),
              if (widget.aberta.execucoes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('EXECUÇÕES · ${widget.aberta.execucoes.length}',
                    style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11, letterSpacing: 1)),
                for (final e in widget.aberta.execucoes.reversed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    selected: estado.log?.execucaoId == e.id,
                    title: Text('${e.id} · ${nomesDeExecucao[e.status] ?? e.status}'),
                    subtitle: Text(
                      [
                        e.persona,
                        nomesDeGatilho[e.gatilho] ?? e.gatilho,
                        if (e.duracao(DateTime.now()) case final d?) duracaoCurta(d),
                        if (e.custoUSD != null) dinheiro(e.custoUSD),
                        e.erro,
                      ].whereType<String>().join(' · '),
                      style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
                    ),
                    onTap: e.comecou ? () => estado.abrirLog(e.id) : null,
                  ),
              ],
              if (estado.log case final log?) ...[
                const SizedBox(height: 12),
                Text('LOG DA EXECUÇÃO ${log.execucaoId}',
                    style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11, letterSpacing: 1)),
                if (log.eventos.isEmpty)
                  Text('Sem eventos ainda.', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
                for (final ev in log.eventos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: SelectableText(
                      '${quando(ev.em)}  ${ev.conteudo}',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: ev.tipo == 'texto' ? null : familiaMono,
                        color: switch (ev.tipo) {
                          'texto' => cores.onSurface,
                          'erro' => cores.error,
                          _ => cores.onSurfaceVariant,
                        },
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _comentario,
                  minLines: 1,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'Comentar na tarefa…'),
                  onSubmitted: (_) => _comentar(),
                ),
              ),
              IconButton(tooltip: 'Comentar', icon: const Icon(Icons.send), onPressed: _comentar),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PedidoDeComando extends StatelessWidget {
  const _PedidoDeComando({required this.pedido, required this.estado});

  final PedidoDePermissao pedido;
  final EstadoTarefas estado;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Comando pedindo aprovação'),
            const SizedBox(height: 6),
            SelectableText(pedido.comando, style: const TextStyle(fontFamily: familiaMono)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton(onPressed: () => estado.responder(pedido.id, permitido: true), child: const Text('Permitir')),
              OutlinedButton(onPressed: () => estado.responder(pedido.id, permitido: false), child: const Text('Negar')),
            ]),
          ]),
        ),
      );
}

class _Trilha extends StatelessWidget {
  const _Trilha({required this.trilha});

  final List<PassoDaTrilha> trilha;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final destaque = corDoEstado(context, 'em_revisao');
    return Text.rich(
      TextSpan(children: [
        for (final (i, passo) in trilha.indexed) ...[
          if (i > 0) TextSpan(text: '  →  ', style: TextStyle(color: cores.onSurfaceVariant)),
          TextSpan(
            text: passo.estado == 'passada' ? '✓ ${passo.rotulo}' : passo.rotulo,
            style: switch (passo.estado) {
              'atual' => TextStyle(color: destaque, fontWeight: FontWeight.w600),
              'passada' => TextStyle(color: cores.onSurfaceVariant),
              _ => TextStyle(color: cores.onSurface),
            },
          ),
        ],
      ]),
      style: const TextStyle(fontSize: 13),
    );
  }
}
