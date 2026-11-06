import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/sala.dart';
import '../estado/tarefas.dart';
import '../nucleo/design.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/protocolo.dart';
import '../nucleo/tarefas.dart';
import '../nucleo/workflows.dart';
import 'chat.dart';
import 'comum.dart';
import 'equipes.dart';
import 'paineis.dart';
import 'tema.dart';
import 'workflows.dart' show escolherEscopoDoCancelamento, pedidoDaCaixaParada;

const _larguraDaLista = 360.0;
const _numeros = [FontFeature.tabularFigures()];

class TelaTarefas extends StatefulWidget {
  const TelaTarefas({super.key, required this.sala});

  final Sala sala;

  @override
  State<TelaTarefas> createState() => _TelaTarefasState();
}

class _TelaTarefasState extends State<TelaTarefas> {
  final _focoDoTitulo = FocusNode();

  @override
  void dispose() {
    _focoDoTitulo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sala = widget.sala;
    return ListenableBuilder(
      listenable: Listenable.merge([sala.tarefas, sala.rotinas, sala.workflows]),
      builder: (context, _) => LayoutBuilder(builder: (context, limites) {
        final classe = ClasseDeJanela.de(limites.maxWidth);
        final aberta = sala.tarefas.aberta;
        final lista = _Lista(sala: sala, focoDoTitulo: _focoDoTitulo, selecionada: aberta?.tarefa.id);
        if (!classe.comDoisPaineis && aberta != null) {
          return _Detalhe(key: ValueKey(aberta.tarefa.id), sala: sala, aberta: aberta, emPainel: false);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cabecalho(estado: sala.tarefas, margem: classe.margemLateral),
            BarraDePausa(estado: sala.equipes),
            const Divider(height: 1),
            Expanded(
              child: !classe.comDoisPaineis
                  ? lista
                  : LadoALado(
                      painel: 'tarefas',
                      rotulo: 'Largura da lista de tarefas',
                      inicial: _larguraDaLista,
                      lateral: lista,
                      principal: aberta == null
                          ? _NadaSelecionado(estado: sala.tarefas, focoDoTitulo: _focoDoTitulo)
                          : _Detalhe(key: ValueKey(aberta.tarefa.id), sala: sala, aberta: aberta, emPainel: true),
                    ),
            ),
          ],
        );
      }),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.estado, required this.margem});

  final EstadoTarefas estado;
  final double margem;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      color: tema.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, Espacos.esp2, Espacos.esp3),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tarefas', style: tema.textTheme.titleLarge),
                  Text(
                    'O que as personas de ${estado.nomeDaEquipe} têm a fazer',
                    style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(tooltip: 'Recarregar', icon: const Icon(Symbols.refresh), onPressed: estado.carregar),
          ]),
        ),
      ),
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio({required this.icone, required this.texto, this.acao});

  final IconData icone;
  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(Espacos.esp5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, color: cor),
          const SizedBox(height: Espacos.esp2),
          Text(texto, textAlign: TextAlign.center, style: tema.textTheme.bodyMedium?.copyWith(color: cor)),
          if (acao != null) ...[const SizedBox(height: Espacos.esp3), acao!],
        ],
      ),
    );
  }
}

class _NadaSelecionado extends StatelessWidget {
  const _NadaSelecionado({required this.estado, required this.focoDoTitulo});

  final EstadoTarefas estado;
  final FocusNode focoDoTitulo;

  @override
  Widget build(BuildContext context) {
    final tarefas = estado.daEquipe;
    final recente = tarefas.isEmpty ? null : tarefas.reduce((a, b) => b.atualizadaEm.isAfter(a.atualizadaEm) ? b : a);
    return Center(
      child: recente == null
          ? _Vazio(
              icone: Symbols.task_alt,
              texto: 'Nenhuma tarefa nesta equipe.',
              acao: OutlinedButton(onPressed: focoDoTitulo.requestFocus, child: const Text('Criar a primeira tarefa')),
            )
          : _Vazio(
              icone: Symbols.task_alt,
              texto: 'Escolha uma tarefa na lista para ver o andamento.',
              acao: OutlinedButton(
                onPressed: () => estado.abrir(recente.id),
                child: const Text('Abrir a mais recente'),
              ),
            ),
    );
  }
}

String _rotuloDaTransicao(String para) => switch (para) {
      'backlog' => 'Mover para o backlog',
      'a_fazer' => 'Mover para a fazer',
      'em_andamento' => 'Marcar em andamento',
      'em_revisao' => 'Enviar para revisão',
      'bloqueada' => 'Bloquear tarefa',
      'concluida' => 'Concluir tarefa',
      'cancelada' => 'Cancelar tarefa',
      _ => 'Mover para ${nomesDeStatus[para] ?? para}',
    };

class _MenuDaTarefa extends StatelessWidget {
  const _MenuDaTarefa({required this.sala, required this.tarefa, this.comAbrir = false, this.child});

  final Sala sala;
  final Tarefa tarefa;
  final bool comAbrir;
  final Widget? child;

  EstadoTarefas get estado => sala.tarefas;

  Future<void> _mudarStatus(BuildContext context, String para) async {
    final caixa = para == 'cancelada' ? caixaVivaDaTarefa(tarefa, sala.workflows.fluxos) : null;
    if (caixa == null) {
      estado.mudarStatus(tarefa.id, para);
      return;
    }
    final escopo = await escolherEscopoDoCancelamento(context, tarefa.id, caixa);
    if (escopo != null) estado.mudarStatus(tarefa.id, para, escopo: escopo);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final destrutivo = MenuItemButton.styleFrom(foregroundColor: cores.error, iconColor: cores.error);
    return MenuAnchor(
      menuChildren: [
        if (comAbrir)
          MenuItemButton(
            leadingIcon: const Icon(Symbols.open_in_new),
            onPressed: () => estado.abrir(tarefa.id),
            child: const Text('Abrir tarefa'),
          ),
        for (final para in tarefa.proximosStatus) ...[
          if (para == 'cancelada' && (comAbrir || tarefa.proximosStatus.length > 1)) const Divider(),
          MenuItemButton(
            leadingIcon: Icon(iconeDoEstado(para)),
            style: para == 'cancelada' ? destrutivo : null,
            onPressed: () => _mudarStatus(context, para),
            child: Text(_rotuloDaTransicao(para)),
          ),
        ],
      ],
      builder: (context, controle, _) {
        void alternar([Offset? posicao]) =>
            controle.isOpen ? controle.close() : controle.open(position: posicao);
        final alvo = child;
        if (alvo == null) {
          return IconButton(tooltip: 'Mais opções', icon: const Icon(Symbols.more_vert), onPressed: alternar);
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (d) => alternar(d.localPosition),
          onLongPressStart: (d) => alternar(d.localPosition),
          child: alvo,
        );
      },
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.sala, required this.focoDoTitulo, this.selecionada});

  final Sala sala;
  final FocusNode focoDoTitulo;
  final int? selecionada;

  @override
  Widget build(BuildContext context) {
    final estado = sala.tarefas;
    final cores = Theme.of(context).colorScheme;
    if (!estado.carregada) return const Center(child: CircularProgressIndicator());
    final grupos = agruparPorStatus(estado.daEquipe);
    return RolagemDeDesktop(
      builder: (context, controle) => ListView(
        controller: controle,
        padding: const EdgeInsets.only(bottom: Espacos.esp5),
        children: [
          if (estado.equipes.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacos.esp4, Espacos.esp3, Espacos.esp4, 0),
              child: DropdownButtonFormField<String>(
                key: ValueKey(estado.equipe),
                initialValue: estado.equipes.any((e) => e.id == estado.equipe) ? estado.equipe : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Equipe'),
                items: [for (final e in estado.equipes) DropdownMenuItem(value: e.id, child: Text(e.nome))],
                onChanged: (id) => id == null ? null : estado.escolherEquipe(id),
              ),
            ),
          _NovaTarefa(sala: sala, focoDoTitulo: focoDoTitulo),
          if (estado.daEquipe.isEmpty)
            _Vazio(
              icone: Symbols.task_alt,
              texto: 'Nenhuma tarefa nesta equipe ainda.',
              acao: OutlinedButton(onPressed: focoDoTitulo.requestFocus, child: const Text('Escrever a primeira tarefa')),
            ),
          for (final grupo in grupos) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacos.esp4, Espacos.esp4, Espacos.esp4, Espacos.esp1),
              child: Semantics(
                header: true,
                child: RotuloDeEstado(
                  estado: grupo.status,
                  rotulo: '${nomesDeStatus[grupo.status] ?? grupo.status} · ${grupo.tarefas.length}',
                ),
              ),
            ),
            for (final t in grupo.tarefas)
              _MenuDaTarefa(
                sala: sala,
                tarefa: t,
                comAbrir: true,
                child: ListTile(
                  selected: t.id == selecionada,
                  selectedTileColor: cores.secondaryContainer,
                  selectedColor: cores.onSecondaryContainer,
                  title: Text('#${t.id} ${t.titulo}'),
                  subtitle: Text([
                    estado.rotuloDaPosicao(t.posicao),
                    if (t.status == 'em_revisao' && t.comQuem != null) t.comQuem!,
                    quando(t.atualizadaEm),
                  ].join(' · ')),
                  trailing: t.rodando ? const RotuloDeEstado(estado: 'rodando', rotulo: 'rodando') : null,
                  onTap: () => estado.abrir(t.id),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _NovaTarefa extends StatefulWidget {
  const _NovaTarefa({required this.sala, required this.focoDoTitulo});

  final Sala sala;
  final FocusNode focoDoTitulo;

  @override
  State<_NovaTarefa> createState() => _NovaTarefaState();
}

class _NovaTarefaState extends State<_NovaTarefa> {
  final _titulo = TextEditingController();
  final _porque = TextEditingController();
  String? _posicao;
  String? _erroDoTitulo;

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
    if (titulo.isEmpty) {
      setState(() => _erroDoTitulo = 'Escreva o que precisa ser feito.');
      widget.focoDoTitulo.requestFocus();
      return;
    }
    if (posicao == null) return;
    estado.criar(posicao: posicao, titulo: titulo, porque: _porque.text);
    _titulo.clear();
    _porque.clear();
  }

  @override
  Widget build(BuildContext context) {
    final posicoes = widget.sala.tarefas.posicoes;
    final escolhida = posicoes.any((p) => p.id == _posicao) ? _posicao : posicoes.firstOrNull?.id;
    return Card(
      margin: const EdgeInsets.fromLTRB(Espacos.esp3, Espacos.esp3, Espacos.esp3, Espacos.esp1),
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            initialValue: escolhida,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Posição',
              helperText: 'Quem recebe a tarefa',
              errorText: posicoes.isEmpty ? 'Esta equipe não tem posições. Crie uma em Equipes.' : null,
            ),
            items: [for (final p in posicoes) DropdownMenuItem(value: p.id, child: Text(p.rotulo))],
            onChanged: (valor) => setState(() => _posicao = valor),
          ),
          const SizedBox(height: Espacos.esp3),
          TextField(
            controller: _titulo,
            focusNode: widget.focoDoTitulo,
            maxLength: 200,
            decoration: InputDecoration(labelText: 'O que precisa ser feito', counterText: '', errorText: _erroDoTitulo),
            onChanged: (_) {
              if (_erroDoTitulo != null) setState(() => _erroDoTitulo = null);
            },
            onSubmitted: (_) => _criar(),
          ),
          const SizedBox(height: Espacos.esp3),
          TextField(
            controller: _porque,
            decoration: const InputDecoration(
              labelText: 'Por quê',
              helperText: 'Opcional. O objetivo que a persona recebe junto.',
            ),
          ),
          const SizedBox(height: Espacos.esp4),
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
  const _Detalhe({super.key, required this.sala, required this.aberta, required this.emPainel});

  final Sala sala;
  final TarefaAberta aberta;
  final bool emPainel;

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

  RegistroDeTarefa? _ultimo(String tipo) => widget.registros.where((r) => r.tipo == tipo).lastOrNull;

  @override
  Widget build(BuildContext context) {
    final estado = widget.sala.tarefas;
    final t = widget.tarefa;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final secundario = tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros);
    final meta = [
      estado.rotuloDaPosicao(t.posicao),
      if (t.rodando) 'rodando agora',
      'custo ${dinheiro(widget.aberta.custoUSD)}',
    ].join(' · ');
    final ficha = [
      if (t.porque.isNotEmpty) 'Por quê: ${t.porque}',
      if (t.dependeDe.isNotEmpty) 'Depende de: ${t.dependeDe.map((d) => '#$d').join(', ')}',
      if (t.pai != null) 'Parte da tarefa #${t.pai}',
      ?widget.sala.rotinas.criadaPelaRotina(t.criadaPor),
      if (t.fluxo != null) descricaoDaCaixaDaTarefa(t, widget.sala.workflows.fluxos),
      if (t.descricao.isNotEmpty) t.descricao,
    ].join('\n\n');
    final planoEmPedido = t.status == 'em_revisao' && planoPendente(widget.registros) ? _ultimo('plano') : null;
    final entregaEmPedido = t.esperaDecisaoDoUeslei ? _ultimo('entrega') : null;
    final emPedido = {?planoEmPedido, ?entregaEmPedido};
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) estado.fecharDetalhe();
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          color: cores.surface,
          child: SafeArea(
            top: !widget.emPainel,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Espacos.esp1, Espacos.esp1, Espacos.esp1, Espacos.esp1),
              child: Row(children: [
                IconButton(
                  tooltip: widget.emPainel ? 'Fechar' : 'Voltar',
                  icon: Icon(widget.emPainel ? Symbols.close : Symbols.arrow_back),
                  onPressed: estado.fecharDetalhe,
                ),
                const SizedBox(width: Espacos.esp1),
                Expanded(child: Text('#${t.id}', overflow: TextOverflow.ellipsis, style: tema.textTheme.titleMedium)),
                RotuloDeEstado(estado: t.status, rotulo: nomesDeStatus[t.status] ?? t.status),
                const SizedBox(width: Espacos.esp1),
                _MenuDaTarefa(sala: widget.sala, tarefa: t),
              ]),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(builder: (context, limites) {
            final classe = ClasseDeJanela.de(limites.maxWidth);
            final lateral = math.max(classe.margemLateral, (limites.maxWidth - larguraDeLeitura) / 2);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(lateral, Espacos.esp4, lateral, Espacos.esp5),
                  children: [
                    SelectionArea(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.titulo, style: tema.textTheme.titleLarge),
                        const SizedBox(height: Espacos.esp1),
                        Text(meta, style: secundario),
                        if (ficha.isNotEmpty) ...[const SizedBox(height: Espacos.esp3), TextoMarkdown(ficha)],
                      ]),
                    ),
                    if (t.fluxo case final fluxo?)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => widget.sala.abrirFluxo(fluxo, equipe: t.equipe),
                          icon: const Icon(Symbols.schema, size: 20),
                          label: const Text('Ver o workflow'),
                        ),
                      ),
                    if (caixaParadaDaTarefa(t, widget.sala.workflows.fluxos) case final parada?) ...[
                      const SizedBox(height: Espacos.esp4),
                      pedidoDaCaixaParada(context, widget.sala.workflows, parada.fluxo, parada.ficha),
                    ],
                    if (t.politica.isNotEmpty) ...[
                      const SizedBox(height: Espacos.esp3),
                      _Trilha(
                        trilha: trilhaDaTarefa(
                          t,
                          estado.equipes.where((e) => e.id == t.equipe).firstOrNull,
                          (id) => Perfil.porChave(id).nome,
                        ),
                      ),
                    ],
                    if (t.esperaDecisaoDoUeslei) ...[
                      const SizedBox(height: Espacos.esp4),
                      CartaoDePedido(
                        icone: Symbols.verified_user,
                        faixa: entregaEmPedido == null
                            ? 'A etapa espera sua aprovação'
                            : 'Entrega de ${entregaEmPedido.autor} espera sua aprovação',
                        quando: entregaEmPedido == null ? null : quando(entregaEmPedido.em),
                        conteudo: entregaEmPedido == null ? null : _Corpo(entregaEmPedido.texto),
                        acoes: [
                          FilledButton.icon(
                            onPressed: () => estado.aprovarEtapa(t.id),
                            icon: const Icon(Symbols.check),
                            label: const Text('Aprovar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pedirMudanca,
                            icon: const Icon(Symbols.undo),
                            label: const Text('Pedir mudança'),
                          ),
                        ],
                      ),
                    ],
                    if (planoEmPedido != null) ...[
                      const SizedBox(height: Espacos.esp4),
                      CartaoDePedido(
                        icone: Symbols.rate_review,
                        faixa: 'Plano de ${planoEmPedido.autor} espera sua aprovação',
                        quando: quando(planoEmPedido.em),
                        conteudo: _Corpo(planoEmPedido.texto),
                        acoes: [
                          FilledButton.icon(
                            onPressed: () => estado.aprovarPlano(t.id),
                            icon: const Icon(Symbols.check),
                            label: const Text('Aprovar plano'),
                          ),
                        ],
                      ),
                    ],
                    for (final pedido in estado.pedidosDaAberta) ...[
                      const SizedBox(height: Espacos.esp4),
                      _PedidoDeComando(pedido: pedido, estado: estado),
                    ],
                    const SizedBox(height: Espacos.esp4),
                    for (final r in widget.registros)
                      if (!emPedido.contains(r))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: Espacos.esp1),
                          child: r.comentario || r.destacado
                              ? _Registro(registro: r)
                              : Text(
                                  '${r.autor}: ${r.texto} · ${quando(r.em)}',
                                  textAlign: TextAlign.center,
                                  style: tema.textTheme.bodySmall
                                      ?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros),
                                ),
                        ),
                    if (widget.aberta.execucoes.isNotEmpty) ...[
                      const SizedBox(height: Espacos.esp4),
                      _TituloDaSecao(titulo: 'Execuções', contagem: widget.aberta.execucoes.length),
                      for (final e in widget.aberta.execucoes.reversed)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          selected: estado.log?.execucaoId == e.id,
                          leading: Icon(iconeDoEstado(e.status), size: 20, color: corDoEstado(context, e.status)),
                          title: Text('${e.id} · ${nomesDeExecucao[e.status] ?? e.status}'),
                          subtitle: Text(
                            [
                              e.persona,
                              nomesDeGatilho[e.gatilho] ?? e.gatilho,
                              if (e.duracao(DateTime.now()) case final d?) duracaoCurta(d),
                              if (e.custoUSD != null) dinheiro(e.custoUSD),
                              e.erro,
                            ].whereType<String>().join(' · '),
                            style: TextStyle(fontFeatures: _numeros),
                          ),
                          onTap: e.comecou ? () => estado.abrirLog(e.id) : null,
                        ),
                    ],
                    if (estado.log case final log?) ...[
                      const SizedBox(height: Espacos.esp3),
                      _TituloDaSecao(titulo: 'Log da execução ${log.execucaoId}'),
                      const SizedBox(height: Espacos.esp2),
                      _Log(eventos: log.eventos),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(lateral, Espacos.esp2, lateral, Espacos.esp3),
                  child: Row(children: [
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter, control: true): _comentar,
                          const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true): _comentar,
                          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _comentar,
                        },
                        child: TextField(
                          controller: _comentario,
                          minLines: 1,
                          maxLines: 5,
                          decoration: const InputDecoration(labelText: 'Comentar na tarefa'),
                          onSubmitted: (_) => _comentar(),
                        ),
                      ),
                    ),
                    const SizedBox(width: Espacos.esp2),
                    IconButton.filled(
                      tooltip: 'Comentar (Ctrl+Enter)',
                      icon: const Icon(Symbols.send),
                      onPressed: _comentar,
                    ),
                  ]),
                ),
              ),
            ]);
          }),
        ),
      ]),
    );
  }
}

class _TituloDaSecao extends StatelessWidget {
  const _TituloDaSecao({required this.titulo, this.contagem});

  final String titulo;
  final int? contagem;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Semantics(
      header: true,
      child: Row(children: [
        Expanded(child: Text(titulo, style: tema.textTheme.titleSmall)),
        if (contagem case final n?)
          Text(
            '$n',
            style: tema.textTheme.labelMedium
                ?.copyWith(color: tema.colorScheme.onSurfaceVariant, fontFeatures: _numeros),
          ),
      ]),
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
        child: SelectionArea(child: TextoMarkdown(texto)),
      );
}

IconData _iconeDoRegistro(String tipo) => switch (tipo) {
      'entrega' => Symbols.inventory,
      'plano' => Symbols.rate_review,
      'aprovado' => Symbols.check_circle,
      'mudanca' => Symbols.undo,
      'ajuda' => Symbols.help,
      'comentario' => Symbols.chat_bubble,
      _ => Symbols.history,
    };

String _verboDoRegistro(String tipo) => switch (tipo) {
      'entrega' => ' entregou',
      'ajuda' => ' pediu ajuda',
      'plano' => ' propôs um plano',
      'aprovado' => ' aprovou',
      'mudanca' => ' pediu mudança',
      _ => '',
    };

class _Registro extends StatelessWidget {
  const _Registro({required this.registro});

  final RegistroDeTarefa registro;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final r = registro;
    final corDoPapel = r.destacado
        ? corDoEstado(
            context,
            switch (r.tipo) {
              'entrega' || 'plano' || 'aprovado' || 'mudanca' => r.tipo,
              _ => 'bloqueada',
            },
          )
        : null;
    return Card(
      margin: EdgeInsets.zero,
      shape: corDoPapel == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Raios.md),
              side: BorderSide(color: corDoPapel),
            ),
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_iconeDoRegistro(r.tipo), size: 16, color: corDoPapel ?? cores.onSurfaceVariant),
            const SizedBox(width: Espacos.esp2),
            Expanded(
              child: Text(
                '${r.autor}${_verboDoRegistro(r.tipo)} · ${quando(r.em)}',
                style: tema.textTheme.labelMedium?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros),
              ),
            ),
          ]),
          const SizedBox(height: Espacos.esp2),
          _Corpo(r.texto),
        ]),
      ),
    );
  }
}

class _Log extends StatelessWidget {
  const _Log({required this.eventos});

  final List<EventoDeExecucao> eventos;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    if (eventos.isEmpty) {
      return Text('Sem eventos ainda.', style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant));
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cores.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Raios.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp3),
        child: SelectionArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final ev in eventos)
              Text(
                '${quando(ev.em)}  ${ev.conteudo}',
                style: tema.textTheme.bodySmall?.copyWith(
                  fontFamily: ev.tipo == 'texto' ? null : familiaMono,
                  fontFeatures: _numeros,
                  color: switch (ev.tipo) {
                    'texto' => cores.onSurface,
                    'erro' => cores.error,
                    _ => cores.onSurfaceVariant,
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _PedidoDeComando extends StatelessWidget {
  const _PedidoDeComando({required this.pedido, required this.estado});

  final PedidoDePermissao pedido;
  final EstadoTarefas estado;

  @override
  Widget build(BuildContext context) => CartaoDePedido(
        icone: Symbols.terminal,
        faixa: 'Comando pedindo aprovação',
        conteudo: SelectableText(
          pedido.comando,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: familiaMono),
        ),
        acoes: [
          FilledButton(onPressed: () => estado.responder(pedido.id, permitido: true), child: const Text('Permitir')),
          OutlinedButton(onPressed: () => estado.responder(pedido.id, permitido: false), child: const Text('Negar')),
        ],
      );
}

const _nomesDoPasso = {'passada': 'concluída', 'atual': 'agora', 'futura': 'a seguir'};

class _Trilha extends StatelessWidget {
  const _Trilha({required this.trilha});

  final List<PassoDaTrilha> trilha;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Wrap(
      spacing: Espacos.esp1,
      runSpacing: Espacos.esp1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, passo) in trilha.indexed) ...[
          if (i > 0) Icon(Symbols.chevron_right, size: 16, color: cores.onSurfaceVariant),
          _Passo(passo: passo),
        ],
      ],
    );
  }
}

class _Passo extends StatelessWidget {
  const _Passo({required this.passo});

  final PassoDaTrilha passo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final atual = passo.estado == 'atual';
    final (icone, corDoIcone, corDoTexto) = switch (passo.estado) {
      'passada' => (Symbols.check_circle, CoresSemanticas.de(context).sucesso.cor, cores.onSurfaceVariant),
      'atual' => (Symbols.radio_button_checked, cores.onSecondaryContainer, cores.onSecondaryContainer),
      _ => (Symbols.radio_button_unchecked, cores.onSurfaceVariant, cores.onSurface),
    };
    return Semantics(
      label: '${passo.rotulo}, ${_nomesDoPasso[passo.estado] ?? passo.estado}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: atual ? cores.secondaryContainer : null,
          borderRadius: BorderRadius.circular(Raios.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espacos.esp2, vertical: Espacos.esp1),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icone, size: 16, color: corDoIcone),
            const SizedBox(width: Espacos.esp1),
            Text(
              passo.rotulo,
              style: tema.textTheme.labelLarge?.copyWith(
                color: corDoTexto,
                fontWeight: atual ? FontWeight.w600 : null,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
