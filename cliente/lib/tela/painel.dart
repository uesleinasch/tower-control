import 'package:flutter/material.dart';

import '../estado/sala.dart';
import '../nucleo/modelos.dart';
import '../nucleo/painel.dart';
import '../nucleo/rotinas.dart' show horarioCurto;
import '../nucleo/tarefas.dart';
import 'comum.dart';
import 'equipes.dart' show BarraDePausa, pedirTexto, quandoCurto;
import 'tarefas.dart' show corDoStatus;

class TelaPainel extends StatelessWidget {
  const TelaPainel({super.key, required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: cores.surface,
          child: SafeArea(
            bottom: false,
            child: ListTile(
              leading: const Avatar(cor: Color(Perfil.corPainel), inicial: 'P', tamanho: 32),
              title: const Text('Painel'),
              subtitle: Text(
                'o que precisa de você e o que está rodando',
                style: TextStyle(color: cores.onSurfaceVariant),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        BarraDePausa(estado: sala.equipes),
        Expanded(
          child: ListenableBuilder(
            listenable: sala.painel,
            builder: (context, _) {
              final retrato = sala.painel.retrato;
              if (retrato == null) return const Center(child: CircularProgressIndicator());
              final agora = DateTime.now();
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  _PrecisaDeVoce(sala: sala, retrato: retrato, agora: agora),
                  _Agora(sala: sala, retrato: retrato, agora: agora),
                  _Personas(sala: sala, retrato: retrato),
                  _Tarefas(sala: sala, retrato: retrato),
                  _ProximasRotinas(sala: sala, retrato: retrato),
                  _Atividade(sala: sala, retrato: retrato),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.vazio, required this.filhos, this.acima = const []});

  final String titulo;
  final String vazio;
  final List<Widget> filhos;
  final List<Widget> acima;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text(
            titulo.toUpperCase(),
            style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11, letterSpacing: 1),
          ),
        ),
        ...acima,
        if (filhos.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(vazio, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 13)),
          )
        else
          ...filhos,
      ],
    );
  }
}

String _juntar(Iterable<String?> partes) => partes.whereType<String>().where((p) => p.isNotEmpty).join(' · ');

class _PrecisaDeVoce extends StatelessWidget {
  const _PrecisaDeVoce({required this.sala, required this.retrato, required this.agora});

  final Sala sala;
  final Retrato retrato;
  final DateTime agora;

  Future<void> _agir(BuildContext context, ItemDeAtencao item, String acao) async {
    if (acao != 'pedir-mudanca') {
      sala.agirNoPainel(item, acao);
      return;
    }
    final texto = await pedirTexto(
      context,
      titulo: item.tarefaId == null ? 'Pedir mudança' : 'Pedir mudança em #${item.tarefaId}',
      rotulo: 'O que mudar e por quê',
      acao: 'Pedir mudança',
      multilinha: true,
    );
    if (texto != null) sala.agirNoPainel(item, acao, texto: texto);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return _Secao(
      titulo: 'Precisa de você (${retrato.atencao.length})',
      vazio: 'Nada esperando você.',
      filhos: [
        for (final item in retrato.atencao)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    _juntar([
                      rotulosDeAtencao[item.tipo] ?? item.tipo,
                      if (item.persona case final p?) nomeDeQuem(p, retrato),
                      haQuanto(item.desde, agora),
                    ]),
                    style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
                  ),
                  if (item.detalhe.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      item.detalhe,
                      style: TextStyle(fontSize: 13, fontFamily: item.tipo == 'comando' ? 'monospace' : null),
                    ),
                  ],
                  if (item.acoes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (i, acao) in item.acoes.indexed)
                          if (i == 0 && acao != 'abrir')
                            FilledButton(
                              onPressed: () => _agir(context, item, acao),
                              child: Text(rotulosDeAcao[acao] ?? acao),
                            )
                          else
                            OutlinedButton(
                              onPressed: () => _agir(context, item, acao),
                              child: Text(rotulosDeAcao[acao] ?? acao),
                            ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Agora extends StatelessWidget {
  const _Agora({required this.sala, required this.retrato, required this.agora});

  final Sala sala;
  final Retrato retrato;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final secundario = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    return _Secao(
      titulo: 'Agora',
      vazio: 'Nada rodando nem na fila.',
      filhos: [
        for (final e in retrato.rodando)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(Icons.play_circle_outline, color: corDoStatus('em_andamento')),
            title: Text('#${e.tarefaId} ${e.titulo}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _juntar([e.persona ?? 'board', rotulosDePapel[e.papel] ?? e.papel, haQuanto(e.inicio, agora)]),
                  style: secundario,
                ),
                if (e.ultimoEvento case final ev?)
                  Text(
                    _juntar([ev.tipo == 'texto' ? null : ev.tipo, ev.conteudo]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: secundario.copyWith(fontFamily: ev.tipo == 'texto' ? null : 'monospace'),
                  ),
              ],
            ),
            onTap: () => sala.abrirTarefa(e.tarefaId),
          ),
        for (final e in retrato.naFila)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(Icons.schedule, color: cores.onSurfaceVariant),
            title: Text('#${e.tarefaId} ${e.titulo}'),
            subtitle: Text(_juntar([e.persona, e.motivo]), style: secundario),
            onTap: () => sala.abrirTarefa(e.tarefaId),
          ),
      ],
    );
  }
}

Color _corDoEstado(String estado, ColorScheme cores) => switch (estado) {
  'rodando' => corDoStatus('em_andamento'),
  'na_fila' => corDoStatus('a_fazer'),
  'pausada' || 'sem_orcamento' => cores.error,
  _ => cores.onSurfaceVariant,
};

class _Personas extends StatelessWidget {
  const _Personas({required this.sala, required this.retrato});

  final Sala sala;
  final Retrato retrato;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final secundario = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    final gasto = retrato.gasto;
    return _Secao(
      titulo: 'Personas',
      vazio: 'Nenhuma persona.',
      acima: [
        if (gasto.mes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              'Em ${gasto.mes}: tarefas ${dinheiro(gasto.tarefasUSD)} (${formatarTokens(gasto.tokensTarefas)}) '
              'de ${dinheiro(gasto.totalUSD)} (${formatarTokens(gasto.tokensTotal)}) no total',
              style: secundario,
            ),
          ),
      ],
      filhos: [
        if (retrato.personas.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in retrato.personas)
                SizedBox(
                  width: 260,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: p.tarefaId == null ? null : () => sala.abrirTarefa(p.tarefaId!),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Avatar(cor: Color(p.cor), inicial: p.inicial, tamanho: 28),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(p.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                                Text(
                                  rotulosDeEstado[p.estado] ?? p.estado,
                                  style: TextStyle(color: _corDoEstado(p.estado, cores), fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _juntar([
                                if (p.tarefaId != null) 'tarefa #${p.tarefaId}',
                                '${p.abertas} ${p.abertas == 1 ? 'aberta' : 'abertas'}',
                              ]),
                              style: secundario,
                            ),
                            Text(
                              p.limiteUSD == null
                                  ? dinheiro(p.gastoMesUSD)
                                  : '${dinheiro(p.gastoMesUSD)} de ${dinheiro(p.limiteUSD)}',
                              style: secundario,
                            ),
                            Text(
                              p.limiteTokens == null
                                  ? formatarTokens(p.tokensMes)
                                  : '${formatarTokens(p.tokensMes)} de ${formatarTokens(p.limiteTokens!)}',
                              style: secundario,
                            ),
                            if (p.proporcaoDoLimite case final proporcao?) ...[
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: proporcao,
                                color: proporcao >= 1
                                    ? cores.error
                                    : proporcao >= 0.8
                                    ? corDoStatus('em_andamento')
                                    : null,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Tarefas extends StatelessWidget {
  const _Tarefas({required this.sala, required this.retrato});

  final Sala sala;
  final Retrato retrato;

  String _nomeDaEquipe(String id) => sala.tarefas.equipes.where((e) => e.id == id).map((e) => e.nome).firstOrNull ?? id;

  @override
  Widget build(BuildContext context) {
    final estado = sala.painel;
    final equipe = estado.equipe;
    final contagem = contagemPorStatus(retrato.tarefas[equipe] ?? const {});
    return _Secao(
      titulo: 'Tarefas',
      vazio: 'Nenhuma tarefa nesta equipe.',
      acima: [
        if (retrato.tarefas.length > 1)
          DropdownButton<String>(
            value: equipe,
            isExpanded: true,
            items: [for (final id in retrato.tarefas.keys) DropdownMenuItem(value: id, child: Text(_nomeDaEquipe(id)))],
            onChanged: (id) => id == null ? null : estado.escolherEquipe(id),
          ),
      ],
      filhos: [
        if (contagem.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in contagem)
                ActionChip(
                  avatar: CircleAvatar(backgroundColor: corDoStatus(c.status), radius: 6),
                  label: Text('${nomesDeStatus[c.status] ?? c.status} · ${c.quantas}'),
                  onPressed: () => sala.abrirTarefasDaEquipe(equipe),
                ),
            ],
          ),
      ],
    );
  }
}

class _ProximasRotinas extends StatelessWidget {
  const _ProximasRotinas({required this.sala, required this.retrato});

  final Sala sala;
  final Retrato retrato;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return _Secao(
      titulo: 'Próximas rotinas',
      vazio: 'Nenhuma rotina agendada.',
      filhos: [
        for (final r in retrato.proximasRotinas)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(Icons.schedule, color: cores.onSurfaceVariant),
            title: Text(r.nome.isEmpty ? r.id : r.nome),
            subtitle: Text(
              _juntar([r.equipe, if (r.proximo case final p?) horarioCurto(p)]),
              style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
            ),
            onTap: () => sala.abrirEquipe(r.equipe, rotinas: true),
          ),
      ],
    );
  }
}

class _Atividade extends StatelessWidget {
  const _Atividade({required this.sala, required this.retrato});

  final Sala sala;
  final Retrato retrato;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final estado = sala.painel;
    final quens = [
      ...quemNaAtividade(retrato.atividade),
      if (estado.filtroQuem case final q? when !quemNaAtividade(retrato.atividade).contains(q)) q,
    ];
    final tipos = [
      ...tiposNaAtividade(retrato.atividade),
      if (estado.filtroTipo case final t? when !tiposNaAtividade(retrato.atividade).contains(t)) t,
    ];
    final filtrada = estado.atividade;
    return _Secao(
      titulo: 'Atividade',
      vazio: retrato.atividade.isEmpty ? 'Nada registrado ainda.' : 'Nada com esses filtros.',
      acima: [
        if (quens.isNotEmpty || tipos.isNotEmpty)
          Wrap(
            spacing: 12,
            children: [
              DropdownButton<String?>(
                value: estado.filtroQuem,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  for (final q in quens) DropdownMenuItem(value: q, child: Text(nomeDeQuem(q, retrato))),
                ],
                onChanged: (q) => estado.filtrar(quem: q, tipo: estado.filtroTipo),
              ),
              DropdownButton<String?>(
                value: estado.filtroTipo,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos os tipos')),
                  for (final t in tipos) DropdownMenuItem(value: t, child: Text(rotulosDeAtividade[t] ?? t)),
                ],
                onChanged: (t) => estado.filtrar(quem: estado.filtroQuem, tipo: t),
              ),
            ],
          ),
      ],
      filhos: [
        for (final a in filtrada)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(a.texto, maxLines: 3, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              _juntar([
                nomeDeQuem(a.quem, retrato),
                rotulosDeAtividade[a.tipo] ?? a.tipo,
                if (a.tarefaId != null) '#${a.tarefaId}',
                if (a.em case final em?) quandoCurto(em),
              ]),
              style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
            ),
            onTap: a.tarefaId == null ? null : () => sala.abrirTarefa(a.tarefaId!),
          ),
      ],
    );
  }
}
