import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../estado/equipes.dart';
import '../estado/sala.dart';
import '../nucleo/modelos.dart';
import '../nucleo/organograma.dart';
import '../nucleo/tarefas.dart';
import 'comum.dart';

bool get edicaoDisponivel =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS;

class TelaEquipes extends StatelessWidget {
  const TelaEquipes({super.key, required this.sala, this.edicao});

  final Sala sala;
  final bool? edicao;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([sala.equipes, sala]),
        builder: (context, _) {
          final estado = sala.equipes;
          final editar = edicao ?? edicaoDisponivel;
          final equipe = estado.atual;
          final cores = Theme.of(context).colorScheme;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Material(
              color: cores.surface,
              child: SafeArea(bottom: false, child: _Topo(estado: estado, editar: editar)),
            ),
            if (estado.erro != null)
              MaterialBanner(
                content: Text(estado.erro!),
                backgroundColor: cores.errorContainer,
                actions: [TextButton(onPressed: estado.limparErro, child: const Text('Ok'))],
              ),
            const Divider(height: 1),
            Expanded(
              child: !estado.carregada || equipe == null
                  ? const Center(child: CircularProgressIndicator())
                  : editar
                      ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(child: _Canvas(estado: estado, equipe: equipe, editar: true)),
                          const VerticalDivider(width: 1),
                          SizedBox(
                            width: 320,
                            child: estado.selecionada != null && equipe.posicao(estado.selecionada!) != null
                                ? _PainelDaPosicao(
                                    key: ValueKey('${equipe.id}/${estado.selecionada}'),
                                    estado: estado,
                                    posicao: equipe.posicao(estado.selecionada!)!,
                                  )
                                : _PainelDePersonas(estado: estado),
                          ),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(child: _Canvas(estado: estado, equipe: equipe, editar: false)),
                          if (estado.selecionada != null && equipe.posicao(estado.selecionada!) != null)
                            _DetalheDaPosicao(sala: sala, equipe: equipe, posicao: equipe.posicao(estado.selecionada!)!),
                        ]),
            ),
          ]);
        },
      );
}

class _Topo extends StatelessWidget {
  const _Topo({required this.estado, required this.editar});

  final EstadoEquipes estado;
  final bool editar;

  Future<void> _novaEquipe(BuildContext context) async {
    final nome = await pedirTexto(context, titulo: 'Nova equipe', rotulo: 'Nome da equipe');
    if (nome != null) estado.novaEquipe(nome);
  }

  Future<void> _novaPosicao(BuildContext context) async {
    final titulo = await pedirTexto(context, titulo: 'Nova posição', rotulo: 'Título (ex.: revisora)');
    if (titulo != null) estado.novaPosicao(titulo);
  }

  Future<void> _excluirEquipe(BuildContext context, EquipeResumo equipe) async {
    final ok = await confirmar(context, 'Excluir a equipe ${equipe.nome}?', 'Equipe com tarefa aberta não pode ser excluída.');
    if (ok) estado.excluirEquipe();
  }

  @override
  Widget build(BuildContext context) {
    final equipe = estado.atual;
    final ids = {for (final e in estado.equipes) e.id};
    final opcoes = [
      for (final e in estado.equipes) DropdownMenuItem(value: e.id, child: Text(e.nome)),
      if (equipe != null && !ids.contains(equipe.id)) DropdownMenuItem(value: equipe.id, child: Text('${equipe.nome} (nova)')),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Avatar(cor: Color(Perfil.corBoard), inicial: 'E', tamanho: 32),
        DropdownButton<String>(
          value: equipe?.id,
          items: opcoes,
          onChanged: (id) async {
            if (id == null || id == equipe?.id) return;
            if (estado.alterada && !await confirmar(context, 'Descartar as mudanças?', 'Há mudanças não salvas nesta equipe.')) {
              return;
            }
            estado.escolher(id);
          },
        ),
        if (editar) ...[
          if (estado.alterada) const Chip(label: Text('não salvo')),
          OutlinedButton.icon(onPressed: () => _novaEquipe(context), icon: const Icon(Icons.group_add_outlined), label: const Text('Nova equipe')),
          OutlinedButton.icon(onPressed: () => _novaPosicao(context), icon: const Icon(Icons.add_box_outlined), label: const Text('Posição')),
          FilledButton(onPressed: estado.alterada && !estado.salvando ? estado.salvar : null, child: const Text('Salvar')),
          TextButton(onPressed: estado.alterada ? estado.descartar : null, child: const Text('Descartar')),
          if (equipe != null && equipe.id != 'casa')
            IconButton(
              tooltip: 'Excluir equipe',
              onPressed: () => _excluirEquipe(context, equipe),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ]),
    );
  }
}

class _Canvas extends StatefulWidget {
  const _Canvas({required this.estado, required this.equipe, required this.editar});

  final EstadoEquipes estado;
  final EquipeResumo equipe;
  final bool editar;

  @override
  State<_Canvas> createState() => _CanvasState();
}

class _CanvasState extends State<_Canvas> {
  final _area = GlobalKey();
  String? _ligandoDe;
  Offset? _ponteiro;

  Offset? _local(Offset global) {
    final caixa = _area.currentContext?.findRenderObject() as RenderBox?;
    return caixa?.globalToLocal(global);
  }

  @override
  Widget build(BuildContext context) {
    final equipe = widget.equipe;
    final tamanho = tamanhoDoOrganograma(equipe);
    final cores = Theme.of(context).colorScheme;
    final ueslei = cantoDoUeslei(equipe);
    final area = SizedBox(
      key: _area,
      width: tamanho.largura,
      height: tamanho.altura,
      child: Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _Ligacoes(
              equipe: equipe,
              cor: cores.outlineVariant,
              destaque: cores.primary,
              ligandoDe: _ligandoDe,
              ponteiro: _ponteiro,
            ),
          ),
        ),
        Positioned(
          left: ueslei.x,
          top: ueslei.y,
          width: larguraDoUeslei,
          height: alturaDoUeslei,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cores.primary, borderRadius: BorderRadius.circular(22)),
            child: Text('Ueslei', style: TextStyle(color: cores.onPrimary, fontWeight: FontWeight.w600)),
          ),
        ),
        for (final p in equipe.posicoes) _cartao(context, equipe, p),
      ]),
    );
    if (equipe.posicoes.isEmpty) {
      return Center(
        child: Text(widget.editar ? 'Equipe sem posições. Use "Posição" para começar.' : 'Equipe sem posições.',
            style: TextStyle(color: cores.onSurfaceVariant)),
      );
    }
    if (!widget.editar) {
      return InteractiveViewer(constrained: false, boundaryMargin: const EdgeInsets.all(200), minScale: 0.4, maxScale: 2, child: area);
    }
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(child: area),
      ),
    );
  }

  Widget _cartao(BuildContext context, EquipeResumo equipe, PosicaoResumo p) {
    final canto = cantoDoCartao(equipe, p.id);
    final escolhida = widget.estado.selecionada == p.id;
    final cartao = _Cartao(posicao: p, escolhida: escolhida);
    return Positioned(
      left: canto.x,
      top: canto.y,
      width: larguraDoCartao,
      height: alturaDoCartao + (widget.editar ? 14 : 0),
      child: Stack(clipBehavior: Clip.none, children: [
        SizedBox(
          width: larguraDoCartao,
          height: alturaDoCartao,
          child: GestureDetector(
            onTap: () => widget.estado.selecionar(escolhida ? null : p.id),
            onPanUpdate: widget.editar
                ? (d) {
                    final atual = (widget.estado.atual ?? equipe).ponto(p.id);
                    widget.estado.aplicar((e) => mover(e, p.id, atual.x + d.delta.dx, atual.y + d.delta.dy));
                  }
                : null,
            child: MouseRegion(cursor: widget.editar ? SystemMouseCursors.move : SystemMouseCursors.click, child: cartao),
          ),
        ),
        if (widget.editar)
          Positioned(
            left: larguraDoCartao / 2 - 9,
            top: alturaDoCartao - 4,
            child: Tooltip(
              message: 'Arraste até outro cartão para ele responder a este, ou até "Ueslei" para soltar',
              child: GestureDetector(
                onPanStart: (d) => setState(() {
                  _ligandoDe = p.id;
                  _ponteiro = _local(d.globalPosition);
                }),
                onPanUpdate: (d) => setState(() => _ponteiro = _local(d.globalPosition)),
                onPanEnd: (_) {
                  final ponto = _ponteiro;
                  final origem = _ligandoDe;
                  setState(() {
                    _ligandoDe = null;
                    _ponteiro = null;
                  });
                  if (ponto == null || origem == null) return;
                  widget.estado.aplicar((e) => ligarPelaAlca(e, origem, alvoEm(e, ponto.dx, ponto.dy)));
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.precise,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.posicao, required this.escolhida});

  final PosicaoResumo posicao;
  final bool escolhida;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final persona = posicao.persona;
    final nome = persona == null ? 'vaga' : (posicao.personaNome ?? Perfil.porChave(persona).nome);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: cores.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: escolhida ? cores.primary : cores.outlineVariant, width: escolhida ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          persona == null
              ? Avatar(cor: cores.outlineVariant, inicial: '?', tamanho: 26)
              : Avatar.doPerfil(persona, tamanho: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(posicao.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
        ]),
        const Spacer(),
        Text(
          posicao.capacidades.map((c) => nomesDeCapacidade[c] ?? c).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11),
        ),
      ]),
    );
  }
}

class _Ligacoes extends CustomPainter {
  _Ligacoes({required this.equipe, required this.cor, required this.destaque, this.ligandoDe, this.ponteiro});

  final EquipeResumo equipe;
  final Color cor;
  final Color destaque;
  final String? ligandoDe;
  final Offset? ponteiro;

  @override
  void paint(Canvas canvas, Size size) {
    final traco = Paint()
      ..color = cor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final ueslei = cantoDoUeslei(equipe);
    for (final p in equipe.posicoes) {
      final de = cantoDoCartao(equipe, p.id);
      final chefe = p.respondeA == null ? null : equipe.posicao(p.respondeA!);
      final x1 = de.x + larguraDoCartao / 2;
      final y1 = de.y;
      final (x2, y2) = chefe == null
          ? (ueslei.x + larguraDoUeslei / 2, ueslei.y + alturaDoUeslei)
          : (cantoDoCartao(equipe, chefe.id).x + larguraDoCartao / 2, cantoDoCartao(equipe, chefe.id).y + alturaDoCartao);
      final meio = (y1 + y2) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(x1, y1)
          ..lineTo(x1, meio)
          ..lineTo(x2, meio)
          ..lineTo(x2, y2),
        traco,
      );
    }
    final origem = ligandoDe;
    if (origem != null && ponteiro != null && equipe.posicao(origem) != null) {
      final c = cantoDoCartao(equipe, origem);
      canvas.drawLine(
        Offset(c.x + larguraDoCartao / 2, c.y + alturaDoCartao),
        ponteiro!,
        Paint()
          ..color = destaque
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Ligacoes antigo) =>
      antigo.equipe != equipe || antigo.ligandoDe != ligandoDe || antigo.ponteiro != ponteiro || antigo.cor != cor;
}

class _PainelDaPosicao extends StatefulWidget {
  const _PainelDaPosicao({super.key, required this.estado, required this.posicao});

  final EstadoEquipes estado;
  final PosicaoResumo posicao;

  @override
  State<_PainelDaPosicao> createState() => _PainelDaPosicaoState();
}

class _PainelDaPosicaoState extends State<_PainelDaPosicao> {
  late final _titulo = TextEditingController(text: widget.posicao.titulo);
  late final _diretorio = TextEditingController(text: widget.posicao.diretorio ?? '');

  @override
  void dispose() {
    _titulo.dispose();
    _diretorio.dispose();
    super.dispose();
  }

  void _editar(PosicaoResumo Function(PosicaoResumo) mudar) =>
      widget.estado.aplicar((e) => editarPosicao(e, widget.posicao.id, mudar));

  @override
  Widget build(BuildContext context) {
    final p = widget.posicao;
    final cores = Theme.of(context).colorScheme;
    final equipe = widget.estado.atual!;
    final chefe = p.respondeA == null ? null : equipe.posicao(p.respondeA!);
    final comandos = p.capacidades.contains('comandos');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('Posição ${p.id}', style: Theme.of(context).textTheme.titleSmall)),
        IconButton(tooltip: 'Fechar', icon: const Icon(Icons.close), onPressed: () => widget.estado.selecionar(null)),
      ]),
      TextField(
        controller: _titulo,
        decoration: const InputDecoration(labelText: 'Título'),
        onChanged: (v) => _editar((x) => x.copiar(titulo: v)),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: p.persona ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Persona'),
        items: [
          const DropdownMenuItem(value: '', child: Text('vaga')),
          for (final persona in Perfil.todos) DropdownMenuItem(value: persona.chave, child: Text(persona.nome)),
        ],
        onChanged: (v) => _editar((x) => x.copiar(persona: () => v == null || v.isEmpty ? null : v)),
      ),
      const SizedBox(height: 12),
      Text('Responde a: ${chefe?.titulo ?? 'Ueslei'}', style: TextStyle(color: cores.onSurfaceVariant)),
      if (chefe != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => widget.estado.aplicar((e) => soltar(e, p.id)),
            child: const Text('Responder ao Ueslei'),
          ),
        ),
      const SizedBox(height: 8),
      Text('Capacidades', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
      for (final c in capacidadesDePosicao)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: p.capacidades.contains(c),
          title: Text(nomesDeCapacidade[c] ?? c),
          onChanged: (marcado) => _editar((x) => x.copiar(
                capacidades: [
                  for (final k in capacidadesDePosicao)
                    if (k == c ? marcado == true : x.capacidades.contains(k)) k,
                ],
              )),
        ),
      if (comandos) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: politicasDeAprovacao.containsKey(p.aprovacao) ? p.aprovacao : 'sempre',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Aprovação de comando'),
          items: [for (final MapEntry(:key, :value) in politicasDeAprovacao.entries) DropdownMenuItem(value: key, child: Text(value))],
          onChanged: (v) => _editar((x) => x.copiar(aprovacao: v)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _diretorio,
          decoration: const InputDecoration(labelText: 'Diretório dos comandos (vazio = pasta de dados)'),
          onChanged: (v) => _editar((x) => x.copiar(diretorio: () => v.trim().isEmpty ? null : v.trim())),
        ),
      ],
      const SizedBox(height: 20),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: cores.error),
        onPressed: () {
          widget.estado.aplicar((e) => removerPosicao(e, p.id));
          widget.estado.selecionar(null);
        },
        icon: const Icon(Icons.delete_outline),
        label: const Text('Remover posição'),
      ),
    ]);
  }
}

class _PainelDePersonas extends StatelessWidget {
  const _PainelDePersonas({required this.estado});

  final EstadoEquipes estado;

  Future<void> _nova(BuildContext context) async {
    final dados = await showDialog<_NovaPersona>(context: context, builder: (_) => const _DialogoNovaPersona());
    if (dados == null) return;
    estado.criarPersona(nome: dados.nome, base: dados.base, titulo: dados.titulo, modelo: dados.modelo, cor: dados.cor);
  }

  Future<void> _excluir(BuildContext context, Perfil p) async {
    final confirmacao = await pedirTexto(
      context,
      titulo: 'Excluir ${p.nome}?',
      rotulo: 'Digite ${p.nome} para confirmar',
      explicacao: 'As posições dela ficam vagas e as conversas viram só leitura. A memória fica guardada, e o nome não pode ser reusado.',
      acao: 'Excluir',
    );
    if (confirmacao != null) estado.excluirPersona(p.chave, confirmacao);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('Personas', style: Theme.of(context).textTheme.titleSmall)),
        FilledButton.icon(onPressed: () => _nova(context), icon: const Icon(Icons.person_add_alt), label: const Text('Nova')),
      ]),
      const SizedBox(height: 4),
      Text('Clique num cartão para editar a posição.', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
      const SizedBox(height: 8),
      for (final p in Perfil.todos)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Avatar.doPerfil(p.chave, tamanho: 28),
          title: Text(p.nome),
          subtitle: Text([p.papel, p.modelo, if (p.gerandoPerfil) 'gerando perfil…'].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
          trailing: p.excluivel
              ? IconButton(tooltip: 'Excluir ${p.nome}', icon: const Icon(Icons.person_remove_outlined), onPressed: () => _excluir(context, p))
              : null,
        ),
    ]);
  }
}

typedef _NovaPersona = ({String nome, String titulo, String base, String? modelo, String? cor});

const _coresSugeridas = ['#e0a458', '#9a6ee8', '#4fae7c', '#e06a8a', '#58b7c9', '#c9a227', '#5b8def', '#d9774b'];

class _DialogoNovaPersona extends StatefulWidget {
  const _DialogoNovaPersona();

  @override
  State<_DialogoNovaPersona> createState() => _DialogoNovaPersonaState();
}

class _DialogoNovaPersonaState extends State<_DialogoNovaPersona> {
  final _nome = TextEditingController();
  final _titulo = TextEditingController();
  final _base = TextEditingController();
  String? _modelo;
  String? _cor;

  @override
  void dispose() {
    _nome.dispose();
    _titulo.dispose();
    _base.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nova persona'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: _nome, maxLength: 40, decoration: const InputDecoration(labelText: 'Nome', counterText: '')),
              const SizedBox(height: 8),
              TextField(controller: _titulo, maxLength: 60, decoration: const InputDecoration(labelText: 'Papel curto (aparece na lista)', counterText: '')),
              const SizedBox(height: 8),
              TextField(
                controller: _base,
                minLines: 4,
                maxLines: 8,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'Quem é, que papel tem com você e qual é o jeito dela'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _modelo,
                decoration: const InputDecoration(labelText: 'Modelo'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('padrão')),
                  DropdownMenuItem(value: 'sonnet', child: Text('Sonnet')),
                  DropdownMenuItem(value: 'opus', child: Text('Opus')),
                ],
                onChanged: (v) => setState(() => _modelo = v),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('cor automática'), selected: _cor == null, onSelected: (_) => setState(() => _cor = null)),
                for (final c in _coresSugeridas)
                  ChoiceChip(
                    label: const SizedBox(width: 12, height: 12),
                    avatar: CircleAvatar(backgroundColor: Color(corDeHex(c))),
                    selected: _cor == c,
                    onSelected: (_) => setState(() => _cor = c),
                  ),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (_nome.text.trim().isEmpty || _base.text.trim().isEmpty) return;
              Navigator.pop<_NovaPersona>(
                context,
                (nome: _nome.text, titulo: _titulo.text, base: _base.text, modelo: _modelo, cor: _cor),
              );
            },
            child: const Text('Criar'),
          ),
        ],
      );
}

class _DetalheDaPosicao extends StatelessWidget {
  const _DetalheDaPosicao({required this.sala, required this.equipe, required this.posicao});

  final Sala sala;
  final EquipeResumo equipe;
  final PosicaoResumo posicao;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final chefe = posicao.respondeA == null ? null : equipe.posicao(posicao.respondeA!);
    final abertas = sala.tarefas.lista
        .where((t) => t.equipe == equipe.id && t.posicao == posicao.id && t.status != 'concluida' && t.status != 'cancelada')
        .toList();
    return Material(
      color: cores.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(posicao.titulo, style: Theme.of(context).textTheme.titleSmall)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => sala.equipes.selecionar(null)),
            ]),
            Text('Persona: ${posicao.persona == null ? 'vaga' : Perfil.porChave(posicao.persona!).nome}'),
            Text('Responde a: ${chefe?.titulo ?? 'Ueslei'}'),
            Text('Capacidades: ${posicao.capacidades.map((c) => nomesDeCapacidade[c] ?? c).join(', ')}'),
            if (posicao.capacidades.contains('comandos')) Text('Aprovação: ${politicasDeAprovacao[posicao.aprovacao] ?? posicao.aprovacao}'),
            if (abertas.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final t in abertas.take(5))
                InkWell(
                  onTap: () {
                    sala.tarefas.escolherEquipe(equipe.id);
                    sala.ir(Tela.tarefas);
                    sala.tarefas.abrir(t.id);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('#${t.id} ${t.titulo} · ${nomesDeStatus[t.status] ?? t.status}',
                        style: TextStyle(color: cores.primary)),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String rotulo,
  String? explicacao,
  String acao = 'Ok',
}) {
  final controle = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: Text(titulo),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (explicacao != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(explicacao)),
        TextField(
          controller: controle,
          autofocus: true,
          decoration: InputDecoration(labelText: rotulo),
          onSubmitted: (v) => Navigator.pop(contexto, v.trim().isEmpty ? null : v),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(contexto), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(contexto, controle.text.trim().isEmpty ? null : controle.text),
          child: Text(acao),
        ),
      ],
    ),
  ).whenComplete(controle.dispose);
}

Future<bool> confirmar(BuildContext context, String titulo, String texto) async =>
    await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Confirmar')),
        ],
      ),
    ) ==
    true;
