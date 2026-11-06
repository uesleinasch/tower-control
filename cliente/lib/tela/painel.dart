import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../conexao/canal.dart' show EstadoConexao;
import '../estado/sala.dart';
import '../nucleo/design.dart';
import '../nucleo/modelos.dart';
import '../nucleo/painel.dart';
import '../nucleo/rotinas.dart' show horarioCurto;
import '../nucleo/tarefas.dart';
import '../nucleo/workflows.dart' show nomesDeCaixa;
import 'comum.dart';
import 'equipes.dart' show BarraDePausa, pedirTexto, quandoCurto;
import 'workflows.dart' show cancelarFluxo;
import 'tema.dart';

const _numeros = [FontFeature.tabularFigures()];

class TelaPainel extends StatelessWidget {
  const TelaPainel({super.key, required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, limites) {
        final classe = ClasseDeJanela.de(limites.maxWidth);
        final margem = classe.margemLateral;
        final colunas = colunasDoPainel(classe);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cabecalho(margem: margem),
            BarraDePausa(estado: sala.equipes),
            const Divider(height: 1),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([sala.painel, sala.workflows]),
                builder: (context, _) {
                  final retrato = sala.painel.retrato;
                  if (retrato == null) {
                    return _Esqueleto(
                      colunas: colunas,
                      margem: margem,
                      semConexao: sala.canal.estado != EstadoConexao.conectado,
                    );
                  }
                  final agora = DateTime.now();
                  return ListView(
                    padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, margem, Espacos.esp5),
                    children: [
                      _PrecisaDeVoce(sala: sala, retrato: retrato, agora: agora, colunas: colunas),
                      const SizedBox(height: Espacos.esp5),
                      _Grade(colunas: colunas, filhos: [
                        _Agora(sala: sala, retrato: retrato, agora: agora),
                        _Workflows(sala: sala, retrato: retrato, agora: agora),
                        _Gasto(retrato: retrato),
                        _Personas(sala: sala, retrato: retrato),
                        _Tarefas(sala: sala, retrato: retrato),
                        _ProximasRotinas(sala: sala, retrato: retrato),
                        _Atividade(sala: sala, retrato: retrato),
                      ]),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      });
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.margem});

  final double margem;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      color: tema.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, margem, Espacos.esp3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Painel', style: tema.textTheme.titleLarge),
              Text(
                'O que precisa de você e o que está rodando',
                style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Grade extends StatelessWidget {
  const _Grade({required this.colunas, required this.filhos, this.espaco = Espacos.esp4});

  final int colunas;
  final List<Widget> filhos;
  final double espaco;

  @override
  Widget build(BuildContext context) {
    Widget coluna(List<Widget> itens) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, item) in itens.indexed) ...[
              if (i > 0) SizedBox(height: espaco),
              item,
            ],
          ],
        );
    if (colunas == 1) return coluna(filhos);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, itens) in emColunas(filhos, colunas).indexed) ...[
          if (i > 0) SizedBox(width: espaco),
          Expanded(child: coluna(itens)),
        ],
      ],
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({
    required this.titulo,
    required this.icone,
    required this.filhos,
    required this.vazio,
    this.acaoDoVazio,
    this.acima = const [],
    this.contagem,
  });

  final String titulo;
  final IconData icone;
  final List<Widget> filhos;
  final String vazio;
  final Widget? acaoDoVazio;
  final List<Widget> acima;
  final int? contagem;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icone, size: 20, color: cores.onSurfaceVariant),
              const SizedBox(width: Espacos.esp2),
              Expanded(child: Text(titulo, style: tema.textTheme.titleMedium)),
              if (contagem case final n?)
                Text('$n', style: tema.textTheme.headlineSmall?.copyWith(fontFeatures: _numeros)),
            ]),
            const SizedBox(height: Espacos.esp3),
            ...acima,
            if (filhos.isEmpty)
              _Vazio(texto: vazio, acao: acaoDoVazio)
            else
              ...filhos,
          ],
        ),
      ),
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio({required this.texto, this.acao});

  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espacos.esp2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Symbols.inbox, size: 20, color: cor),
            const SizedBox(width: Espacos.esp2),
            Expanded(child: Text(texto, style: tema.textTheme.bodyMedium?.copyWith(color: cor))),
          ]),
          if (acao != null) ...[const SizedBox(height: Espacos.esp2), acao!],
        ],
      ),
    );
  }
}

IconData _iconeDoEstado(String? estado) => switch (estado) {
      'ocioso' => Symbols.radio_button_unchecked,
      'pausada' => Symbols.pause_circle,
      'sem_orcamento' => Symbols.money_off,
      _ => switch (papelDoEstado(estado)) {
          PapelDeEstado.neutro => Symbols.inventory_2,
          PapelDeEstado.fila => Symbols.schedule,
          PapelDeEstado.andamento => Symbols.play_circle,
          PapelDeEstado.revisao => Symbols.rate_review,
          PapelDeEstado.aviso => Symbols.block,
          PapelDeEstado.sucesso => Symbols.check_circle,
          PapelDeEstado.cancelado => Symbols.cancel,
          PapelDeEstado.erro => Symbols.error,
        },
    };

class _RotuloDeEstado extends StatelessWidget {
  const _RotuloDeEstado({required this.estado, required this.rotulo});

  final String estado;
  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final cor = corDoEstado(context, estado);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_iconeDoEstado(estado), size: 16, color: cor),
        const SizedBox(width: Espacos.esp1),
        Flexible(child: Text(rotulo, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cor))),
      ],
    );
  }
}

String _juntar(Iterable<String?> partes) => partes.whereType<String>().where((p) => p.isNotEmpty).join(' · ');

IconData _iconeDaAtencao(String tipo) => switch (tipo) {
      'comando' => Symbols.terminal,
      'aprovacao' => Symbols.verified_user,
      'decisao' => Symbols.fact_check,
      'plano' => Symbols.rate_review,
      'entrega' => Symbols.inventory,
      'sinal' => Symbols.flag,
      'bloqueada' => Symbols.block,
      'atrasada' => Symbols.alarm,
      'backlog' => Symbols.inventory_2,
      'orcamento' => Symbols.savings,
      'rotina' => Symbols.event_repeat,
      'vaga' => Symbols.person_off,
      _ => Symbols.priority_high,
    };

class _PrecisaDeVoce extends StatelessWidget {
  const _PrecisaDeVoce({required this.sala, required this.retrato, required this.agora, required this.colunas});

  final Sala sala;
  final Retrato retrato;
  final DateTime agora;
  final int colunas;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final itens = retrato.atencao;
    final cabecalho = Semantics(
      header: true,
      label: 'Precisa de você: ${itens.length}',
      excludeSemantics: true,
      child: Row(children: [
        Icon(Symbols.notifications_active, color: itens.isEmpty ? cores.onSurfaceVariant : cores.tertiary),
        const SizedBox(width: Espacos.esp2),
        Expanded(child: Text('Precisa de você', style: tema.textTheme.titleMedium)),
        Text('${itens.length}', style: tema.textTheme.headlineSmall?.copyWith(fontFeatures: _numeros)),
      ]),
    );
    if (itens.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Espacos.esp4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cabecalho,
            const SizedBox(height: Espacos.esp2),
            Row(children: [
              Icon(Symbols.check_circle, size: 20, color: CoresSemanticas.de(context).sucesso.cor),
              const SizedBox(width: Espacos.esp2),
              Expanded(
                child: Text(
                  'Nada esperando você.',
                  style: tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant),
                ),
              ),
            ]),
          ]),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cabecalho,
        const SizedBox(height: Espacos.esp3),
        _Grade(
          colunas: colunas,
          espaco: Espacos.esp3,
          filhos: [
            for (final item in itens) _PedidoDeAtencao(sala: sala, retrato: retrato, item: item, agora: agora),
          ],
        ),
      ],
    );
  }
}

class _PedidoDeAtencao extends StatelessWidget {
  const _PedidoDeAtencao({required this.sala, required this.retrato, required this.item, required this.agora});

  final Sala sala;
  final Retrato retrato;
  final ItemDeAtencao item;
  final DateTime agora;

  Future<void> _agir(BuildContext context, String acao) async {
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

  Widget _botao(BuildContext context, String acao, int indice) {
    final rotulo = Text(rotulosDeAcao[acao] ?? acao);
    void agir() => _agir(context, acao);
    return switch (enfaseDaAcao(acao, indice: indice, total: item.acoes.length)) {
      EnfaseDaAcao.principal => FilledButton(onPressed: agir, child: rotulo),
      EnfaseDaAcao.secundaria => OutlinedButton(onPressed: agir, child: rotulo),
      EnfaseDaAcao.baixa => TextButton(onPressed: agir, child: rotulo),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final faixa = tema.textTheme.labelMedium?.copyWith(color: cores.onTertiaryContainer);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: cores.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacos.esp4, vertical: Espacos.esp2),
              child: Row(children: [
                Icon(_iconeDaAtencao(item.tipo), size: 16, color: cores.onTertiaryContainer),
                const SizedBox(width: Espacos.esp2),
                Expanded(
                  child: Text(
                    _juntar([
                      rotulosDeAtencao[item.tipo] ?? item.tipo,
                      if (item.persona case final p?) nomeDeQuem(p, retrato),
                    ]),
                    style: faixa,
                  ),
                ),
                Text(haQuanto(item.desde, agora), style: faixa?.copyWith(fontFeatures: _numeros)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Espacos.esp4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.titulo, style: tema.textTheme.titleSmall),
                if (item.detalhe.isNotEmpty) ...[
                  const SizedBox(height: Espacos.esp2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
                    child: SelectableText(
                      item.detalhe,
                      style: tema.textTheme.bodyMedium?.copyWith(
                        fontFamily: item.tipo == 'comando' ? familiaMono : null,
                      ),
                    ),
                  ),
                ],
                if (item.tipo == 'decisao')
                  _Decisao(key: ValueKey('decisao-${item.fluxo}-${item.ficha}'), sala: sala, item: item)
                else if (item.acoes.isNotEmpty) ...[
                  const SizedBox(height: Espacos.esp3),
                  Wrap(
                    spacing: Espacos.esp2,
                    runSpacing: Espacos.esp2,
                    children: [for (final (i, acao) in item.acoes.indexed) _botao(context, acao, i)],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Decisao extends StatefulWidget {
  const _Decisao({super.key, required this.sala, required this.item});

  final Sala sala;
  final ItemDeAtencao item;

  @override
  State<_Decisao> createState() => _DecisaoState();
}

class _DecisaoState extends State<_Decisao> {
  final _comentario = TextEditingController();

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Espacos.esp3),
        TextField(
          controller: _comentario,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Comentário (opcional)'),
        ),
        const SizedBox(height: Espacos.esp3),
        Wrap(
          spacing: Espacos.esp2,
          runSpacing: Espacos.esp2,
          children: [
            for (final (i, opcao) in item.opcoes.indexed)
              if (i == 0)
                FilledButton(
                  onPressed: () => widget.sala.agirNoPainel(item, 'decidir', opcao: opcao, texto: _comentario.text),
                  child: Text(opcao),
                )
              else
                OutlinedButton(
                  onPressed: () => widget.sala.agirNoPainel(item, 'decidir', opcao: opcao, texto: _comentario.text),
                  child: Text(opcao),
                ),
            if (item.fluxo case final fluxo?)
              TextButton(
                onPressed: () => widget.sala.abrirFluxo(fluxo, equipe: item.equipe),
                child: const Text('Ver workflow'),
              ),
          ],
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
    final tema = Theme.of(context);
    final secundario = tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant);
    Widget linha({
      required String estado,
      required int tarefaId,
      required String titulo,
      required List<Widget> detalhes,
    }) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_iconeDoEstado(estado), color: corDoEstado(context, estado)),
          title: Text('#$tarefaId $titulo'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rotulosDeEstado[estado] ?? estado,
                style: tema.textTheme.labelMedium?.copyWith(color: corDoEstado(context, estado)),
              ),
              ...detalhes,
            ],
          ),
          onTap: () => sala.abrirTarefa(tarefaId),
        );
    return _Cartao(
      titulo: 'Agora',
      icone: Symbols.play_circle,
      contagem: retrato.rodando.length + retrato.naFila.length,
      vazio: 'Nada rodando nem na fila.',
      acaoDoVazio: TextButton(onPressed: () => sala.ir(Tela.tarefas), child: const Text('Ver tarefas')),
      filhos: [
        for (final e in retrato.rodando)
          linha(estado: 'rodando', tarefaId: e.tarefaId, titulo: e.titulo, detalhes: [
            Text(
              _juntar([e.persona ?? 'board', rotulosDePapel[e.papel] ?? e.papel, haQuanto(e.inicio, agora)]),
              style: secundario,
            ),
            if (e.ultimoEvento case final ev?)
              Text(
                _juntar([ev.tipo == 'texto' ? null : ev.tipo, ev.conteudo]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: secundario?.copyWith(fontFamily: ev.tipo == 'texto' ? null : familiaMono),
              ),
          ]),
        for (final e in retrato.naFila)
          linha(estado: 'na_fila', tarefaId: e.tarefaId, titulo: e.titulo, detalhes: [
            Text(_juntar([e.persona, e.motivo]), style: secundario),
          ]),
      ],
    );
  }
}

class _Workflows extends StatelessWidget {
  const _Workflows({required this.sala, required this.retrato, required this.agora});

  final Sala sala;
  final Retrato retrato;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    return _Cartao(
      titulo: 'Workflows',
      icone: Symbols.schema,
      contagem: retrato.workflows.length,
      vazio: 'Nenhum workflow rodando.',
      acaoDoVazio: TextButton(onPressed: () => sala.abrirWorkflows(null), child: const Text('Ver workflows')),
      filhos: [
        for (final (i, f) in retrato.workflows.indexed) ...[
          if (i > 0) const Divider(height: Espacos.esp5),
          Text(f.nome, style: tema.textTheme.titleSmall),
          const SizedBox(height: Espacos.esp1),
          Wrap(
            spacing: Espacos.esp2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              f.ativas.isEmpty
                  ? const _RotuloDeEstado(estado: 'na_fila', rotulo: 'na fila')
                  : const _RotuloDeEstado(estado: 'rodando', rotulo: 'rodando'),
              Text(_juntar(['#${f.fluxo}', f.equipe, haQuanto(f.desde, agora)]), style: secundario),
            ],
          ),
          const SizedBox(height: Espacos.esp1),
          Text(
            f.ativas.isEmpty
                ? 'esperando o anterior'
                : 'em: ${f.ativas.map((a) => '${a.titulo} (${nomesDeCaixa[a.tipo] ?? a.tipo}${a.tarefaId == null ? '' : ' #${a.tarefaId}'})').join(', ')}',
            style: secundario,
          ),
          Wrap(
            spacing: Espacos.esp2,
            children: [
              TextButton.icon(
                onPressed: () => sala.abrirFluxo(f.fluxo, equipe: f.equipe),
                icon: const Icon(Symbols.schema, size: 20),
                label: const Text('Ver workflow'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: cores.error),
                onPressed: () => cancelarFluxo(context, sala.workflows, f.fluxo, f.nome),
                icon: const Icon(Symbols.cancel, size: 20),
                label: const Text('Cancelar workflow'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Gasto extends StatelessWidget {
  const _Gasto({required this.retrato});

  final Retrato retrato;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final secundario = tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant, fontFeatures: _numeros);
    final gasto = retrato.gasto;
    Widget linha(String rotulo, double usd, int tokens) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacos.esp1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rotulo, style: tema.textTheme.bodyMedium),
                    Text(formatarTokens(tokens), style: secundario),
                  ],
                ),
              ),
              Text(dinheiro(usd), style: tema.textTheme.headlineSmall?.copyWith(fontFeatures: _numeros)),
            ],
          ),
        );
    return _Cartao(
      titulo: gasto.mes.isEmpty ? 'Gasto do mês' : 'Gasto de ${gasto.mes}',
      icone: Symbols.savings,
      vazio: 'Nenhum gasto registrado neste mês.',
      filhos: [
        if (gasto.mes.isNotEmpty) ...[
          linha('Tarefas', gasto.tarefasUSD, gasto.tokensTarefas),
          linha('Total', gasto.totalUSD, gasto.tokensTotal),
        ],
      ],
    );
  }
}

class _Personas extends StatelessWidget {
  const _Personas({required this.sala, required this.retrato});

  final Sala sala;
  final Retrato retrato;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros);
    final aviso = CoresSemanticas.de(context).aviso.cor;
    return _Cartao(
      titulo: 'Personas',
      icone: Symbols.person,
      vazio: 'Nenhuma persona.',
      acaoDoVazio: TextButton(onPressed: () => sala.ir(Tela.equipes), child: const Text('Ver equipes')),
      filhos: [
        for (final (i, p) in retrato.personas.indexed) ...[
          if (i > 0) const Divider(height: Espacos.esp3),
          InkWell(
            borderRadius: BorderRadius.circular(Raios.sm),
            onTap: p.tarefaId == null ? null : () => sala.abrirTarefa(p.tarefaId!),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Espacos.esp2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Avatar(cor: Color(p.cor), inicial: p.inicial, tamanho: 28),
                    const SizedBox(width: Espacos.esp2),
                    Expanded(child: Text(p.nome, style: tema.textTheme.titleSmall)),
                    _RotuloDeEstado(estado: p.estado, rotulo: rotulosDeEstado[p.estado] ?? p.estado),
                  ]),
                  const SizedBox(height: Espacos.esp1),
                  Row(children: [
                    Expanded(
                      child: Text(
                        _juntar([
                          if (p.tarefaId != null) 'tarefa #${p.tarefaId}',
                          '${p.abertas} ${p.abertas == 1 ? 'aberta' : 'abertas'}',
                        ]),
                        style: secundario,
                      ),
                    ),
                    Text(
                      p.limiteUSD == null
                          ? dinheiro(p.gastoMesUSD)
                          : '${dinheiro(p.gastoMesUSD)} de ${dinheiro(p.limiteUSD)}',
                      style: secundario,
                    ),
                  ]),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      p.limiteTokens == null
                          ? formatarTokens(p.tokensMes)
                          : '${formatarTokens(p.tokensMes)} de ${formatarTokens(p.limiteTokens!)}',
                      style: secundario,
                    ),
                  ),
                  if (p.proporcaoDoLimite case final proporcao?) ...[
                    const SizedBox(height: Espacos.esp1),
                    LinearProgressIndicator(
                      value: proporcao,
                      semanticsLabel: 'Orçamento do mês de ${p.nome}',
                      semanticsValue: '${(proporcao * 100).round()}%',
                      color: proporcao >= 1
                          ? cores.error
                          : proporcao >= 0.8
                              ? aviso
                              : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
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
    final tema = Theme.of(context);
    final estado = sala.painel;
    final equipe = estado.equipe;
    final contagem = contagemPorStatus(retrato.tarefas[equipe] ?? const {});
    return _Cartao(
      titulo: 'Tarefas',
      icone: Symbols.task_alt,
      vazio: 'Nenhuma tarefa nesta equipe.',
      acaoDoVazio: TextButton(onPressed: () => sala.abrirTarefasDaEquipe(equipe), child: const Text('Ver tarefas')),
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
        for (final c in contagem)
          InkWell(
            borderRadius: BorderRadius.circular(Raios.sm),
            onTap: () => sala.abrirTarefasDaEquipe(equipe),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Espacos.esp1),
              child: Row(children: [
                Expanded(child: _RotuloDeEstado(estado: c.status, rotulo: nomesDeStatus[c.status] ?? c.status)),
                Text('${c.quantas}', style: tema.textTheme.headlineSmall?.copyWith(fontFeatures: _numeros)),
              ]),
            ),
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
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    return _Cartao(
      titulo: 'Próximas rotinas',
      icone: Symbols.event_repeat,
      vazio: 'Nenhuma rotina agendada.',
      acaoDoVazio: TextButton(
        onPressed: () => sala.abrirEquipe(null, rotinas: true),
        child: const Text('Ver rotinas'),
      ),
      filhos: [
        for (final r in retrato.proximasRotinas)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Symbols.event_repeat, size: 20, color: cores.onSurfaceVariant),
            title: Text(r.nome.isEmpty ? r.id : r.nome),
            subtitle: Text(r.equipe, style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant)),
            trailing: r.proximo == null
                ? null
                : Text(horarioCurto(r.proximo!), style: tema.textTheme.bodySmall?.copyWith(fontFeatures: _numeros)),
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
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final estado = sala.painel;
    final quens = [
      ...quemNaAtividade(retrato.atividade),
      if (estado.filtroQuem case final q? when !quemNaAtividade(retrato.atividade).contains(q)) q,
    ];
    final tipos = [
      ...tiposNaAtividade(retrato.atividade),
      if (estado.filtroTipo case final t? when !tiposNaAtividade(retrato.atividade).contains(t)) t,
    ];
    final filtrando = estado.filtroQuem != null || estado.filtroTipo != null;
    return _Cartao(
      titulo: 'Atividade',
      icone: Symbols.history,
      vazio: retrato.atividade.isEmpty ? 'Nada registrado ainda.' : 'Nada com esses filtros.',
      acaoDoVazio: filtrando
          ? TextButton(onPressed: () => estado.filtrar(quem: null, tipo: null), child: const Text('Limpar filtros'))
          : null,
      acima: [
        if (quens.isNotEmpty || tipos.isNotEmpty)
          Wrap(
            spacing: Espacos.esp3,
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
        for (final a in estado.atividade)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(a.texto, maxLines: 3, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              _juntar([
                nomeDeQuem(a.quem, retrato),
                rotulosDeAtividade[a.tipo] ?? a.tipo,
                if (a.tarefaId != null) '#${a.tarefaId}',
                if (a.em case final em?) quandoCurto(em),
              ]),
              style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros),
            ),
            onTap: a.tarefaId == null ? null : () => sala.abrirTarefa(a.tarefaId!),
          ),
      ],
    );
  }
}

class _Esqueleto extends StatelessWidget {
  const _Esqueleto({required this.colunas, required this.margem, required this.semConexao});

  final int colunas;
  final double margem;
  final bool semConexao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    Widget barra(double fracao, double altura) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fracao,
          child: Container(
            height: altura,
            decoration: BoxDecoration(
              color: cores.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Raios.xs),
            ),
          ),
        );
    Widget cartao(int linhas) => Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Espacos.esp4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                barra(0.4, Espacos.esp4),
                for (var i = 0; i < linhas; i++) ...[
                  const SizedBox(height: Espacos.esp3),
                  barra(i.isEven ? 0.9 : 0.6, Espacos.esp3),
                ],
              ],
            ),
          ),
        );
    return Semantics(
      label: semConexao ? 'Esperando a conexão com o servidor' : 'Carregando o painel',
      child: ExcludeSemantics(
        child: ListView(
          padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, margem, Espacos.esp5),
          children: [
            if (semConexao) ...[
              Row(children: [
                Icon(Symbols.cloud_off, size: 20, color: cores.onSurfaceVariant),
                const SizedBox(width: Espacos.esp2),
                Expanded(
                  child: Text(
                    'Esperando a conexão com o servidor.',
                    style: tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant),
                  ),
                ),
              ]),
              const SizedBox(height: Espacos.esp4),
            ],
            cartao(2),
            const SizedBox(height: Espacos.esp5),
            _Grade(colunas: colunas, filhos: [for (var i = 0; i < 6; i++) cartao(i.isEven ? 3 : 2)]),
          ],
        ),
      ),
    );
  }
}
