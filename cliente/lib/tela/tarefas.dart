import 'package:flutter/material.dart';

import '../estado/sala.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/tarefas.dart';
import 'chat.dart';
import 'comum.dart';

class TelaTarefas extends StatelessWidget {
  const TelaTarefas({super.key, required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sala.tarefas,
        builder: (context, _) {
          final aberta = sala.tarefas.aberta;
          return aberta == null
              ? _Lista(sala: sala)
              : _Detalhe(sala: sala, tarefa: aberta.tarefa, registros: aberta.registros);
        },
      );
}

Color corDoStatus(String status) => switch (status) {
      'a_fazer' => const Color(0xFF5B8DEF),
      'em_andamento' => const Color(0xFFE0A458),
      'em_revisao' => const Color(0xFF9A6EE8),
      'bloqueada' => const Color(0xFFE05A5A),
      'concluida' => const Color(0xFF4FAE7C),
      _ => const Color(0xFF8B93A7),
    };

class _Status extends StatelessWidget {
  const _Status(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final cor = corDoStatus(status);
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
    final grupos = agruparPorStatus(estado.lista);
    return Column(children: [
      Material(
        color: cores.surface,
        child: SafeArea(
          bottom: false,
          child: ListTile(
            leading: const Avatar(cor: Color(Perfil.corTarefas), inicial: 'T', tamanho: 32),
            title: const Text('Tarefas — Casa'),
            subtitle: Text('o que as personas têm a fazer', style: TextStyle(color: cores.onSurfaceVariant)),
            trailing: IconButton(tooltip: 'Recarregar', icon: const Icon(Icons.refresh), onPressed: estado.carregar),
          ),
        ),
      ),
      const Divider(),
      Expanded(
        child: !estado.carregada
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _NovaTarefa(sala: sala),
                  if (estado.lista.isEmpty)
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
                          '${estado.rotuloDaPosicao(t.posicao)} · ${quando(t.atualizadaEm)}',
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
  const _Detalhe({required this.sala, required this.tarefa, required this.registros});

  final Sala sala;
  final Tarefa tarefa;
  final List<RegistroDeTarefa> registros;

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

  @override
  Widget build(BuildContext context) {
    final estado = widget.sala.tarefas;
    final t = widget.tarefa;
    final cores = Theme.of(context).colorScheme;
    final ficha = [
      '**${t.titulo}**',
      '${estado.rotuloDaPosicao(t.posicao)}${t.dono != null ? ' · com ${t.dono}' : ''}',
      if (t.porque.isNotEmpty) 'Por quê: ${t.porque}',
      if (t.dependeDe.isNotEmpty) 'Depende de: ${t.dependeDe.map((d) => '#$d').join(', ')}',
      if (t.pai != null) 'Parte da tarefa #${t.pai}',
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
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
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
                  child: r.comentario
                      ? Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${r.autor} · ${quando(r.em)}',
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
