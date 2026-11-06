import 'dart:async';
import 'dart:io';

// O flutter_markdown_plus ainda lê o ThemeData do material antigo, publicado pela ponte em main.dart.
import 'package:flutter/material.dart' as legado show Theme;
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../conexao/http.dart';
import '../estado/chat.dart';
import '../estado/sala.dart';
import '../nucleo/design.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import 'anexar.dart';
import 'comum.dart';
import 'tema.dart';

const _larguraDaConversa = larguraDeLeitura + Espacos.esp7 * 2;
const _colunaDoAvatar = Espacos.esp6 + Espacos.esp2;
const _alturaDaMiniatura = 160.0;
const _atrasoDoStatus = Duration(seconds: 1);
const _numeros = [FontFeature.tabularFigures()];

ClasseDeJanela _classe(BuildContext context) => ClasseDeJanela.de(MediaQuery.sizeOf(context).width);

TextStyle? _estiloDaMensagem(BuildContext context) {
  final texto = Theme.of(context).textTheme;
  return _classe(context) == ClasseDeJanela.compact ? texto.bodyLarge : texto.bodyMedium;
}

TextStyle? _estiloDaHora(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall
    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontFeatures: _numeros);

class TelaChat extends StatefulWidget {
  const TelaChat({super.key, required this.sala, required this.compacto});

  final Sala sala;
  final bool compacto;

  @override
  State<TelaChat> createState() => _TelaChatState();
}

class _TelaChatState extends State<TelaChat> {
  final _entrada = TextEditingController();
  final _foco = FocusNode();
  final _irAoFim = ValueNotifier(0);

  EstadoChat get _chat => widget.sala.chat;

  @override
  void initState() {
    super.initState();
    _entrada.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _entrada.dispose();
    _foco.dispose();
    _irAoFim.dispose();
    super.dispose();
  }

  void _enviar([String? texto]) {
    if (!_chat.enviar(texto ?? _entrada.text)) return;
    if (texto == null) _entrada.clear();
    _irAoFim.value++;
  }

  void _citar(String texto) {
    _chat.definirCitacao(texto);
    _foco.requestFocus();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_chat, widget.sala.canal, widget.sala.conversas]),
        builder: (context, _) {
          if (!_chat.ativo) return const _Vazio();
          return Column(
            children: [
              _Cabecalho(sala: widget.sala, compacto: widget.compacto),
              const Divider(),
              Expanded(
                child: _Mensagens(
                  key: ValueKey(_chat.conversaId ?? 'nova:${_chat.perfil}'),
                  sala: widget.sala,
                  aoCitar: _citar,
                  irAoFim: _irAoFim,
                ),
              ),
              for (final p in _chat.itens.whereType<Permissao>())
                if (p.situacao == SituacaoPermissao.pendente)
                  _NaColuna(child: _CartaoPermissao(chat: _chat, permissao: p)),
              if (Perfil.todos.any((p) => p.chave == _chat.perfil))
                _Compositor(
                  sala: widget.sala,
                  entrada: _entrada,
                  foco: _foco,
                  compacto: widget.compacto,
                  aoEnviar: _enviar,
                )
              else
                const _SoLeitura(),
            ],
          );
        },
      );
}

class _NaColuna extends StatelessWidget {
  const _NaColuna({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _larguraDaConversa),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _classe(context).margemLateral),
            child: child,
          ),
        ),
      );
}

class _SoLeitura extends StatelessWidget {
  const _SoLeitura();

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Divider(),
      Material(
        color: cores.surfaceContainer,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Espacos.esp4),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Symbols.lock, size: 20, color: cores.onSurfaceVariant),
              const SizedBox(width: Espacos.esp2),
              Flexible(
                child: Text(
                  'Só leitura: a persona desta conversa foi excluída.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio();

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Espacos.esp7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.forum, size: Espacos.esp7, color: cores.onSurfaceVariant),
          const SizedBox(height: Espacos.esp4),
          Text(
            'Escolha uma conversa ou comece uma nova.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cores.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.sala, required this.compacto});

  final Sala sala;
  final bool compacto;

  List<Widget> _modos(BuildContext context, {required bool estreito}) {
    final chat = sala.chat;
    final rotulo = Theme.of(context).textTheme.labelMedium;
    final estilo = TextStyle(
      fontSize: rotulo?.fontSize,
      height: rotulo?.height,
      fontWeight: rotulo?.fontWeight,
      letterSpacing: rotulo?.letterSpacing,
    );
    return [
      Tooltip(
        message: 'Registro direto no TickTask: o Alfred usa as ferramentas do app',
        child: FilterChip(
          label: const Text('TickTask'),
          labelStyle: estilo,
          selected: chat.ticktask,
          onSelected: chat.emCurso ? null : (_) => chat.alternarTicktask(),
          visualDensity: VisualDensity.compact,
        ),
      ),
      Tooltip(
        message: 'Modo auto: comandos rodam sem pedir aprovação (os sensíveis ainda pedem) e usa $modeloDoAuto',
        child: FilterChip(
          label: Text(chat.auto && !estreito ? 'auto · $modeloDoAuto' : 'auto'),
          labelStyle: estilo,
          selected: chat.auto,
          onSelected: chat.emCurso ? null : (_) => chat.alternarAuto(),
          visualDensity: VisualDensity.compact,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final chat = sala.chat;
    final cores = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final seletorDeModelo = PopupMenuButton<String>(
      tooltip: chat.executor && chat.auto ? 'No modo auto o Alfred usa $modeloDoAuto' : 'Modelo',
      enabled: !(chat.executor && chat.auto),
      initialValue: chat.modelo,
      onSelected: chat.definirModelo,
      itemBuilder: (_) => [
        for (final m in modelos.entries) PopupMenuItem(value: m.key, child: Text(m.value)),
      ],
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(chat.executor && chat.auto ? modeloDoAuto : chat.modelo,
              style: texto.labelLarge?.copyWith(color: cores.onSurfaceVariant)),
          Icon(Symbols.expand_more, size: 20, color: cores.onSurfaceVariant),
        ]),
      ),
    );
    return Material(
      color: cores.surface,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, limites) {
          final estreito = ClasseDeJanela.de(limites.maxWidth) == ClasseDeJanela.compact;
          final modos = chat.executor ? _modos(context, estreito: estreito) : const <Widget>[];
          final recuo = compacto ? Espacos.esp7 : Espacos.esp3;
          final linha = Row(
            children: [
              if (compacto)
                IconButton(
                  tooltip: 'Voltar',
                  icon: const Icon(Symbols.arrow_back),
                  onPressed: () => sala.ir(Tela.conversas),
                )
              else
                SizedBox(width: recuo),
              Avatar.doPerfil(chat.perfil!, tamanho: Espacos.esp6),
              const SizedBox(width: Espacos.esp3),
              Expanded(
                child: Text(chat.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: texto.titleSmall),
              ),
              if (!estreito)
                for (final modo in modos) Padding(padding: const EdgeInsets.only(left: Espacos.esp2), child: modo),
              const SizedBox(width: Espacos.esp1),
              seletorDeModelo,
            ],
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(Espacos.esp1, Espacos.esp1, Espacos.esp2, Espacos.esp1),
            child: estreito && modos.isNotEmpty
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    linha,
                    Padding(
                      padding: EdgeInsets.only(left: recuo, bottom: Espacos.esp1),
                      child: Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp1, children: modos),
                    ),
                  ])
                : linha,
          );
        }),
      ),
    );
  }
}

class _Mensagens extends StatefulWidget {
  const _Mensagens({super.key, required this.sala, required this.aoCitar, required this.irAoFim});

  final Sala sala;
  final void Function(String) aoCitar;
  final Listenable irAoFim;

  @override
  State<_Mensagens> createState() => _MensagensState();
}

class _MensagensState extends State<_Mensagens> {
  final _rolagem = ScrollController();
  final _historico = UniqueKey();
  late int _ancora = widget.sala.chat.itens.length;
  var _noFim = true;

  @override
  void initState() {
    super.initState();
    _rolagem.addListener(_aoRolar);
    widget.irAoFim.addListener(_voltarAoFim);
  }

  @override
  void dispose() {
    widget.irAoFim.removeListener(_voltarAoFim);
    _rolagem.dispose();
    super.dispose();
  }

  void _aoRolar() {
    final p = _rolagem.position;
    _noFim = p.pixels <= p.minScrollExtent + Espacos.esp5;
  }

  void _irAoFim() {
    if (!_rolagem.hasClients) return;
    final p = _rolagem.position;
    if (p.pixels != p.minScrollExtent) p.jumpTo(p.minScrollExtent);
  }

  void _voltarAoFim() {
    _noFim = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _irAoFim());
  }

  bool _aoMudarMedidas(ScrollMetricsNotification n) {
    if (n.depth == 0 && _noFim) _irAoFim();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.sala.chat;
    final itens = chat.itens;
    if (_ancora > itens.length) _ancora = itens.length;
    final novos = <Widget>[
      for (var i = _ancora; i < itens.length; i++) ?_item(context, itens[i]),
    ];
    final perfilStreaming = chat.perfilStreaming;
    if (chat.emCurso && perfilStreaming != null) {
      final emCurso = chat.emStreaming;
      for (var i = 0; i < emCurso.fechados.length; i++) {
        novos.add(_BalaoPerfil(
            perfil: perfilStreaming, texto: emCurso.fechados[i], primeiro: i == 0, aoCitar: widget.aoCitar));
      }
      if (emCurso.aberto.isNotEmpty) {
        novos.add(_BalaoPerfil(
            perfil: perfilStreaming,
            texto: emCurso.aberto,
            primeiro: emCurso.fechados.isEmpty,
            aoCitar: widget.aoCitar));
      }
      final escrito = emCurso.fechados.fold(emCurso.aberto.length, (soma, t) => soma + t.length);
      novos.add(_Status(perfil: perfilStreaming, escrito: escrito));
    }
    return SelectionArea(
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _aoMudarMedidas,
        child: CustomScrollView(
          controller: _rolagem,
          reverse: true,
          center: _historico,
          slivers: [
            SliverList.list(children: [
              for (final w in novos) _NaColuna(child: w),
              const SizedBox(height: Espacos.esp2),
            ]),
            SliverList.builder(
              key: _historico,
              itemCount: _ancora,
              itemBuilder: (context, i) =>
                  _NaColuna(child: _item(context, itens[_ancora - 1 - i]) ?? const SizedBox.shrink()),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: Espacos.esp3)),
          ],
        ),
      ),
    );
  }

  Widget? _item(BuildContext context, ItemChat item) => switch (item) {
        DoUsuario() => _BalaoUsuario(item: item, endereco: widget.sala.canal.endereco),
        BalaoPerfil() => _BalaoPerfil(
            perfil: item.perfil, texto: item.texto, primeiro: item.primeiro, ts: item.ts, aoCitar: widget.aoCitar),
        Registro(:final comando) => _Linha(icone: Symbols.terminal, texto: comando, mono: true),
        AvisoChat(:final texto) => _Linha(icone: Symbols.info, texto: texto),
        ErroChat(:final texto) => _Linha(icone: Symbols.error, texto: texto, cor: Theme.of(context).colorScheme.error),
        Permissao(:final situacao) when situacao == SituacaoPermissao.pendente => null,
        Permissao() => _CartaoPermissao(chat: widget.sala.chat, permissao: item),
      };
}

class _Linha extends StatelessWidget {
  const _Linha({required this.icone, required this.texto, this.cor, this.mono = false});

  final IconData icone;
  final String texto;
  final Color? cor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = cor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espacos.esp1, horizontal: Espacos.esp2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 16, color: c),
        const SizedBox(width: Espacos.esp2),
        Expanded(
          child: Text(texto,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c, fontFamily: mono ? familiaMono : null)),
        ),
      ]),
    );
  }
}

class _BalaoUsuario extends StatelessWidget {
  const _BalaoUsuario({required this.item, required this.endereco});

  final DoUsuario item;
  final String? endereco;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: Espacos.esp3, left: Espacos.esp7),
        constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
        padding: const EdgeInsets.symmetric(horizontal: Espacos.esp3, vertical: Espacos.esp2),
        decoration: BoxDecoration(
          color: cores.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Raios.md).copyWith(bottomRight: const Radius.circular(Raios.xs)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.citacao != null)
              Container(
                margin: const EdgeInsets.only(bottom: Espacos.esp2),
                padding: const EdgeInsets.only(left: Espacos.esp2),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: cores.primary, width: Espacos.esp1))),
                child: Text(item.citacao!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant)),
              ),
            if (item.anexos.isNotEmpty && endereco != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Espacos.esp1),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Espacos.esp2,
                  runSpacing: Espacos.esp2,
                  children: [for (final a in item.anexos) _AnexoEnviado(anexo: a, endereco: endereco!)],
                ),
              ),
            if (item.texto.isNotEmpty) Text(item.texto, style: _estiloDaMensagem(context)),
            if (item.ts != null)
              Padding(
                padding: const EdgeInsets.only(top: Espacos.esp1),
                child: Text(hora(item.ts!), style: _estiloDaHora(context)),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _iconeDoAnexo(TipoAnexo tipo) => switch (tipo) {
      TipoAnexo.imagem => Symbols.image,
      TipoAnexo.pdf => Symbols.picture_as_pdf,
      TipoAnexo.texto => Symbols.description,
    };

class _AnexoEnviado extends StatelessWidget {
  const _AnexoEnviado({required this.anexo, required this.endereco});

  final Anexo anexo;
  final String endereco;

  @override
  Widget build(BuildContext context) {
    final url = urlDoAnexo(endereco, anexo.id);
    void abrir() => launchUrl(url, mode: LaunchMode.externalApplication);
    if (anexo.tipo == TipoAnexo.imagem) {
      return Tooltip(
        message: 'Abrir ${anexo.nome}',
        child: InkWell(
          onTap: abrir,
          borderRadius: BorderRadius.circular(Raios.sm),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Raios.sm),
            child: Image.network(url.toString(),
                height: _alturaDaMiniatura,
                fit: BoxFit.cover,
                semanticLabel: anexo.nome,
                errorBuilder: (_, _, _) => _chip(abrir)),
          ),
        ),
      );
    }
    return _chip(abrir);
  }

  Widget _chip(VoidCallback abrir) => ActionChip(
        avatar: Icon(_iconeDoAnexo(anexo.tipo), size: 16),
        label: Text('${anexo.nome} · ${formatarBytes(anexo.bytes)}'),
        tooltip: 'Abrir ${anexo.nome}',
        onPressed: abrir,
      );
}

class _BalaoPerfil extends StatelessWidget {
  const _BalaoPerfil({required this.perfil, required this.texto, required this.aoCitar, this.primeiro = false, this.ts});

  final String perfil;
  final String texto;
  final bool primeiro;
  final DateTime? ts;
  final void Function(String) aoCitar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final p = Perfil.porChave(perfil);
    final cor = perfil == 'board' ? const Color(Perfil.corBoard) : Color(p.cor);
    return Padding(
      padding: EdgeInsets.only(top: primeiro ? Espacos.esp3 : Espacos.esp1, right: Espacos.esp7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _colunaDoAvatar,
            child: primeiro
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Avatar(cor: cor, inicial: perfil == 'board' ? 'B' : p.inicial, tamanho: Espacos.esp6),
                  )
                : null,
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
              child: MenuDeToque(
                itens: () => [
                  (Symbols.reply, 'Responder a este trecho', () => aoCitar(texto)),
                  (Symbols.content_copy, 'Copiar', () => copiar(context, texto)),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Espacos.esp3, vertical: Espacos.esp2),
                  decoration: BoxDecoration(
                    color: cores.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(Raios.md)
                        .copyWith(topLeft: Radius.circular(primeiro ? Raios.xs : Raios.md)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (primeiro)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Espacos.esp1),
                          child: Text(perfil == 'board' ? 'Board' : p.nome,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: corLegivelSobre(cor, cores.surfaceContainerLow))),
                        ),
                      TextoMarkdown(texto, estilo: _estiloDaMensagem(context)),
                      if (ts != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: Espacos.esp1),
                            child: Text(hora(ts!), style: _estiloDaHora(context)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TextoMarkdown extends StatelessWidget {
  const TextoMarkdown(this.texto, {super.key, this.estilo});

  final String texto;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final corpo = estilo ?? tema.textTheme.bodyMedium;
    return MarkdownBody(
      data: texto,
      styleSheet: MarkdownStyleSheet.fromTheme(legado.Theme.of(context)).copyWith(
        p: corpo,
        code: corpo?.copyWith(
          fontFamily: familiaMono,
          backgroundColor: tema.colorScheme.surfaceContainerHighest,
        ),
        codeblockPadding: const EdgeInsets.all(Espacos.esp3),
        codeblockDecoration: BoxDecoration(
          color: tema.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Raios.sm),
        ),
      ),
      onTapLink: (_, href, _) {
        final uri = href == null ? null : Uri.tryParse(href);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}

class _Status extends StatefulWidget {
  const _Status({required this.perfil, required this.escrito});

  final String perfil;
  final int escrito;

  @override
  State<_Status> createState() => _StatusState();
}

class _StatusState extends State<_Status> {
  Timer? _relogio;
  var _visivel = false;

  @override
  void initState() {
    super.initState();
    _armar();
  }

  @override
  void didUpdateWidget(_Status antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.escrito != widget.escrito) {
      _visivel = false;
      _armar();
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  void _armar() {
    _relogio?.cancel();
    _relogio = Timer(_atrasoDoStatus, () {
      if (mounted) setState(() => _visivel = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final nome = Perfil.porChave(widget.perfil).nome;
    return AnimatedOpacity(
      opacity: _visivel ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Durations.short2,
      child: Semantics(
        liveRegion: _visivel,
        child: Padding(
          padding: const EdgeInsets.only(left: _colunaDoAvatar, top: Espacos.esp2, bottom: Espacos.esp1),
          child: Row(children: [
            const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: Espacos.esp2),
            Flexible(
              child: Text('$nome está pensando…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CartaoPermissao extends StatefulWidget {
  const _CartaoPermissao({required this.chat, required this.permissao});

  final EstadoChat chat;
  final Permissao permissao;

  @override
  State<_CartaoPermissao> createState() => _CartaoPermissaoState();
}

class _CartaoPermissaoState extends State<_CartaoPermissao> {
  Timer? _relogio;

  bool get _pendente => widget.permissao.situacao == SituacaoPermissao.pendente;

  @override
  void initState() {
    super.initState();
    if (_pendente) _relogio = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final p = widget.permissao;
    final perfil = widget.chat.perfil ?? Perfil.alfred.chave;
    final nome = Perfil.porChave(perfil).nome;
    final pendente = _pendente;
    if (!pendente) _relogio?.cancel();
    final restante = Permissao.prazo - DateTime.now().difference(p.criadoEm);
    final segundos = restante.inSeconds.clamp(0, Permissao.prazo.inSeconds);
    final sobreFaixa = pendente ? cores.onTertiaryContainer : cores.onSurface;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: Espacos.esp2),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: pendente ? cores.tertiaryContainer : cores.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: Espacos.esp4, vertical: Espacos.esp3),
            child: Row(children: [
              Avatar.doPerfil(perfil, tamanho: Espacos.esp5),
              const SizedBox(width: Espacos.esp3),
              Expanded(
                child: Text(pendente ? '$nome quer rodar um comando' : '$nome pediu para rodar um comando',
                    style: texto.titleSmall?.copyWith(color: sobreFaixa)),
              ),
              if (pendente)
                Text('${segundos}s', style: texto.labelMedium?.copyWith(color: sobreFaixa, fontFeatures: _numeros)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(Espacos.esp4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(Espacos.esp3),
                  decoration: BoxDecoration(
                    color: cores.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(Raios.sm),
                  ),
                  child: SelectableText(p.comando, style: texto.bodyMedium?.copyWith(fontFamily: familiaMono)),
                ),
                const SizedBox(height: Espacos.esp3),
                if (pendente)
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: Espacos.esp2,
                    runSpacing: Espacos.esp2,
                    children: [
                      OutlinedButton(
                        onPressed: () => widget.chat.responderPermissao(p, permitido: false),
                        child: const Text('Negar'),
                      ),
                      FilledButton(
                        onPressed: () => widget.chat.responderPermissao(p, permitido: true),
                        child: const Text('Permitir'),
                      ),
                    ],
                  )
                else
                  _Resultado(p.situacao),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Resultado extends StatelessWidget {
  const _Resultado(this.situacao);

  final SituacaoPermissao situacao;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final semanticas = CoresSemanticas.de(context);
    final (icone, cor, texto) = switch (situacao) {
      SituacaoPermissao.permitido => (Symbols.check_circle, semanticas.sucesso.cor, 'Comando permitido'),
      SituacaoPermissao.negado => (Symbols.block, cores.error, 'Comando negado'),
      SituacaoPermissao.expirado => (Symbols.timer_off, semanticas.aviso.cor, 'O prazo acabou e o comando foi negado'),
      _ => (Symbols.wifi_off, semanticas.aviso.cor, 'A conexão caiu e o comando foi negado'),
    };
    return Row(children: [
      Icon(icone, size: 20, color: cor),
      const SizedBox(width: Espacos.esp2),
      Expanded(child: Text(texto, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cor))),
    ]);
  }
}

class _Compositor extends StatelessWidget {
  const _Compositor({
    required this.sala,
    required this.entrada,
    required this.foco,
    required this.compacto,
    required this.aoEnviar,
  });

  final Sala sala;
  final TextEditingController entrada;
  final FocusNode foco;
  final bool compacto;
  final void Function([String? texto]) aoEnviar;

  Future<void> _clipe(BuildContext context) async {
    if (!Platform.isAndroid) {
      await anexar(sala, FonteAnexo.arquivo);
      return;
    }
    final fonte = await showModalBottomSheet<FonteAnexo>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Symbols.photo_camera),
            title: const Text('Câmera'),
            onTap: () => Navigator.pop(context, FonteAnexo.camera),
          ),
          ListTile(
            leading: const Icon(Symbols.photo_library),
            title: const Text('Galeria'),
            onTap: () => Navigator.pop(context, FonteAnexo.galeria),
          ),
          ListTile(
            leading: const Icon(Symbols.attach_file),
            title: const Text('Arquivo'),
            onTap: () => Navigator.pop(context, FonteAnexo.arquivo),
          ),
        ]),
      ),
    );
    if (fonte != null) await anexar(sala, fonte);
  }

  KeyEventResult _tecla(KeyEvent evento) {
    if (evento is! KeyDownEvent) return KeyEventResult.ignored;
    if (evento.logicalKey != LogicalKeyboardKey.enter && evento.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final teclado = HardwareKeyboard.instance;
    final comAtalho = teclado.isControlPressed || teclado.isMetaPressed;
    if (!comAtalho && (compacto || teclado.isShiftPressed)) return KeyEventResult.ignored;
    aoEnviar();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final chat = sala.chat;
    final cores = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final conectado = sala.canal.conectado;
    final podeEnviar = conectado && !chat.emCurso && chat.subindo == 0;
    final atalhos = sala.conversas.atalhos;
    final mostrarAtalhos = atalhos.isNotEmpty && entrada.text.trim().isEmpty && chat.anexos.isEmpty;
    final semBorda = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Raios.xl),
      borderSide: BorderSide.none,
    );
    return Material(
      color: cores.surface,
      child: SafeArea(
        top: false,
        child: _NaColuna(
          child: Padding(
            padding: const EdgeInsets.only(top: Espacos.esp1, bottom: Espacos.esp2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!conectado)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacos.esp2),
                    child: Text('Sem conexão. O envio volta quando o servidor responder.',
                        textAlign: TextAlign.center, style: texto.bodySmall?.copyWith(color: cores.error)),
                  ),
                if (chat.citacao != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: Espacos.esp2),
                    padding: const EdgeInsets.only(left: Espacos.esp3),
                    decoration:
                        BoxDecoration(border: Border(left: BorderSide(color: cores.primary, width: Espacos.esp1))),
                    child: Row(children: [
                      Expanded(
                        child: Text(chat.citacao!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: texto.bodyMedium?.copyWith(color: cores.onSurfaceVariant)),
                      ),
                      IconButton(
                        tooltip: 'Remover citação',
                        icon: const Icon(Symbols.close, size: 20),
                        onPressed: chat.limparCitacao,
                      ),
                    ]),
                  ),
                if (chat.anexos.isNotEmpty || chat.subindo > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacos.esp2),
                    child: Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: [
                      for (final a in chat.anexos)
                        InputChip(
                          avatar: Icon(_iconeDoAnexo(a.tipo), size: 16),
                          label: Text('${a.nome} · ${formatarBytes(a.bytes)}'),
                          tooltip: a.nome,
                          deleteButtonTooltipMessage: 'Remover anexo',
                          onDeleted: () => chat.removerAnexo(a.id),
                        ),
                      if (chat.subindo > 0)
                        const Chip(
                          avatar: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          label: Text('enviando anexo…'),
                        ),
                    ]),
                  ),
                if (mostrarAtalhos)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: Espacos.esp2),
                    child: Row(children: [
                      for (final atalho in atalhos)
                        Padding(
                          padding: const EdgeInsets.only(right: Espacos.esp2),
                          child: Tooltip(
                            message: atalho.texto,
                            child: ActionChip(
                              label: Text(atalho.rotulo),
                              onPressed: podeEnviar ? () => aoEnviar(atalho.texto) : null,
                            ),
                          ),
                        ),
                    ]),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Anexar',
                      icon: const Icon(Symbols.attach_file),
                      onPressed: conectado ? () => _clipe(context) : null,
                    ),
                    const SizedBox(width: Espacos.esp1),
                    Expanded(
                      child: Focus(
                        onKeyEvent: (_, evento) => _tecla(evento),
                        child: TextField(
                          controller: entrada,
                          focusNode: foco,
                          autofocus: !compacto,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: chat.ticktask
                                ? 'O que registrar no TickTask…'
                                : 'Mensagem para ${Perfil.porChave(chat.perfil!).nome}…',
                            filled: true,
                            fillColor: cores.surfaceContainerHighest,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: Espacos.esp4, vertical: Espacos.esp3),
                            border: semBorda,
                            enabledBorder: semBorda,
                            disabledBorder: semBorda,
                            focusedBorder: semBorda.copyWith(borderSide: BorderSide(color: cores.primary, width: 2)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Espacos.esp2),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Espacos.esp1),
                      child: IconButton.filled(
                        tooltip: 'Enviar',
                        icon: const Icon(Symbols.arrow_upward),
                        onPressed: podeEnviar ? aoEnviar : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
