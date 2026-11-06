import 'dart:async';
import 'dart:io';

// O flutter_markdown_plus ainda lê o ThemeData do material antigo, publicado pela ponte em main.dart.
import 'package:flutter/material.dart' as legado show Theme;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../conexao/http.dart';
import '../estado/chat.dart';
import '../estado/sala.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import 'anexar.dart';
import 'comum.dart';
import 'tema.dart';

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
    super.dispose();
  }

  void _enviar([String? texto]) {
    if (_chat.enviar(texto ?? _entrada.text) && texto == null) _entrada.clear();
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
              Expanded(child: _Mensagens(sala: widget.sala, aoCitar: _citar)),
              for (final p in _chat.itens.whereType<Permissao>())
                if (p.situacao == SituacaoPermissao.pendente) _CartaoPermissao(chat: _chat, permissao: p),
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

class _SoLeitura extends StatelessWidget {
  const _SoLeitura();

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Só leitura: a persona desta conversa foi excluída.',
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}

class _Vazio extends StatelessWidget {
  const _Vazio();

  @override
  Widget build(BuildContext context) => Center(
        child: Text('Escolha uma conversa ou comece uma nova.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.sala, required this.compacto});

  final Sala sala;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final chat = sala.chat;
    final cores = Theme.of(context).colorScheme;
    return Material(
      color: cores.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
          child: Row(
            children: [
              if (compacto)
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => sala.ir(Tela.conversas))
              else
                const SizedBox(width: 12),
              Avatar.doPerfil(chat.perfil!, tamanho: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(chat.titulo,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
              ),
              if (chat.executor)
                Tooltip(
                  message: 'Registro direto no TickTask: o Alfred usa as ferramentas do app',
                  child: FilterChip(
                    label: const Text('TickTask'),
                    selected: chat.ticktask,
                    onSelected: chat.emCurso ? null : (_) => chat.alternarTicktask(),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (chat.executor) const SizedBox(width: 4),
              if (chat.executor)
                Tooltip(
                  message: 'Modo auto: comandos rodam sem pedir aprovação (os sensíveis ainda pedem) e usa $modeloDoAuto',
                  child: FilterChip(
                    label: Text(chat.auto && !compacto ? 'auto · $modeloDoAuto' : 'auto'),
                    selected: chat.auto,
                    onSelected: chat.emCurso ? null : (_) => chat.alternarAuto(),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: chat.executor && chat.auto ? 'No modo auto o Alfred usa $modeloDoAuto' : 'Modelo',
                enabled: !(chat.executor && chat.auto),
                initialValue: chat.modelo,
                onSelected: chat.definirModelo,
                itemBuilder: (_) => [
                  for (final m in modelos.entries) PopupMenuItem(value: m.key, child: Text(m.value)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(chat.executor && chat.auto ? modeloDoAuto : chat.modelo,
                        style: TextStyle(color: cores.onSurfaceVariant)),
                    Icon(Icons.expand_more, size: 18, color: cores.onSurfaceVariant),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mensagens extends StatelessWidget {
  const _Mensagens({required this.sala, required this.aoCitar});

  final Sala sala;
  final void Function(String) aoCitar;

  @override
  Widget build(BuildContext context) {
    final chat = sala.chat;
    final blocos = <Widget>[
      for (final item in chat.itens) ?_item(context, item),
    ];
    final perfilStreaming = chat.perfilStreaming;
    if (chat.emCurso && perfilStreaming != null) {
      final emCurso = chat.emStreaming;
      for (var i = 0; i < emCurso.fechados.length; i++) {
        blocos.add(_BalaoPerfil(perfil: perfilStreaming, texto: emCurso.fechados[i], primeiro: i == 0, aoCitar: aoCitar));
      }
      if (emCurso.aberto.isNotEmpty) {
        blocos.add(_BalaoPerfil(
            perfil: perfilStreaming, texto: emCurso.aberto, primeiro: emCurso.fechados.isEmpty, aoCitar: aoCitar));
      }
      blocos.add(_Digitando(perfil: perfilStreaming));
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: blocos.length,
      itemBuilder: (context, i) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: blocos[blocos.length - 1 - i],
        ),
      ),
    );
  }

  Widget? _item(BuildContext context, ItemChat item) => switch (item) {
        DoUsuario() => _BalaoUsuario(item: item, endereco: sala.canal.endereco),
        BalaoPerfil() =>
          _BalaoPerfil(perfil: item.perfil, texto: item.texto, primeiro: item.primeiro, ts: item.ts, aoCitar: aoCitar),
        Registro(:final comando) => _Linha(icone: Icons.terminal, texto: comando, mono: true),
        AvisoChat(:final texto) => _Linha(icone: Icons.info_outline, texto: texto),
        ErroChat(:final texto) =>
          _Linha(icone: Icons.error_outline, texto: texto, cor: Theme.of(context).colorScheme.error),
        Permissao(:final situacao) when situacao == SituacaoPermissao.pendente => null,
        Permissao(:final comando, :final situacao) => _Linha(
            icone: situacao == SituacaoPermissao.permitido ? Icons.check_circle_outline : Icons.block,
            texto: '${switch (situacao) {
              SituacaoPermissao.permitido => 'permitido',
              SituacaoPermissao.negado => 'negado',
              SituacaoPermissao.expirado => 'expirou — comando negado',
              _ => 'conexão caiu — comando negado',
            }}: $comando',
            mono: true,
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 16, color: c),
        const SizedBox(width: 8),
        Expanded(
          child: Text(texto,
              style: TextStyle(color: c, fontSize: 13, fontFamily: mono ? familiaMono : null)),
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
        margin: const EdgeInsets.only(top: 10, bottom: 2, left: 48),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: cores.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16).copyWith(bottomRight: const Radius.circular(4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.citacao != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: cores.primary, width: 3))),
                child: Text(item.citacao!, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 13)),
              ),
            if (item.anexos.isNotEmpty && endereco != null)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [for (final a in item.anexos) _AnexoEnviado(anexo: a, endereco: endereco!)],
              ),
            if (item.texto.isNotEmpty) Text(item.texto),
            if (item.ts != null)
              Text(hora(item.ts!), style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _AnexoEnviado extends StatelessWidget {
  const _AnexoEnviado({required this.anexo, required this.endereco});

  final Anexo anexo;
  final String endereco;

  @override
  Widget build(BuildContext context) {
    final url = urlDoAnexo(endereco, anexo.id);
    void abrir() => launchUrl(url, mode: LaunchMode.externalApplication);
    if (anexo.tipo == TipoAnexo.imagem) {
      return InkWell(
        onTap: abrir,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(url.toString(),
              height: 160, fit: BoxFit.cover, errorBuilder: (_, _, _) => _chip(context, abrir)),
        ),
      );
    }
    return _chip(context, abrir);
  }

  Widget _chip(BuildContext context, VoidCallback abrir) => ActionChip(
        avatar: Icon(anexo.tipo == TipoAnexo.pdf ? Icons.picture_as_pdf_outlined : Icons.description_outlined, size: 18),
        label: Text('${anexo.nome} · ${formatarBytes(anexo.bytes)}'),
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
      padding: EdgeInsets.only(top: primeiro ? 12 : 3, right: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: primeiro
                ? Avatar(cor: cor, inicial: perfil == 'board' ? 'B' : p.inicial, tamanho: 28)
                : null,
          ),
          Flexible(
            child: MenuDeToque(
              itens: () => [
                (Icons.reply, 'Responder a este trecho', () => aoCitar(texto)),
                (Icons.copy, 'Copiar', () => copiar(context, texto)),
              ],
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                decoration: BoxDecoration(
                  color: cores.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16).copyWith(topLeft: Radius.circular(primeiro ? 4 : 16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (primeiro)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(perfil == 'board' ? 'Board' : p.nome,
                            style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    TextoMarkdown(texto),
                    if (ts != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(hora(ts!), style: TextStyle(color: cores.onSurfaceVariant, fontSize: 11)),
                      ),
                  ],
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
  const TextoMarkdown(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return MarkdownBody(
      data: texto,
      styleSheet: MarkdownStyleSheet.fromTheme(legado.Theme.of(context)).copyWith(
        p: tema.textTheme.bodyMedium?.copyWith(height: 1.45),
        code: TextStyle(
          fontFamily: familiaMono,
          fontSize: 13,
          backgroundColor: tema.colorScheme.surface,
        ),
        codeblockDecoration: BoxDecoration(
          color: tema.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
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

class _Digitando extends StatelessWidget {
  const _Digitando({required this.perfil});

  final String perfil;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 34, top: 6, bottom: 4),
        child: Row(children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(Perfil.porChave(perfil).cor)),
          ),
          const SizedBox(width: 8),
          Text('${Perfil.porChave(perfil).nome} está escrevendo…',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ]),
      );
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

  @override
  void initState() {
    super.initState();
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final p = widget.permissao;
    final restante = Permissao.prazo - DateTime.now().difference(p.criadoEm);
    final segundos = restante.inSeconds.clamp(0, Permissao.prazo.inSeconds);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      constraints: const BoxConstraints(maxWidth: 820),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: cores.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0A458)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.shield_outlined, size: 18, color: Color(0xFFE0A458)),
            const SizedBox(width: 8),
            const Expanded(child: Text('Alfred quer rodar um comando', style: TextStyle(fontWeight: FontWeight.w600))),
            Text('${segundos}s', style: TextStyle(color: cores.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cores.surface, borderRadius: BorderRadius.circular(8)),
            child: SelectableText(p.comando, style: const TextStyle(fontFamily: familiaMono, fontSize: 13)),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => widget.chat.responderPermissao(p, permitido: false),
              child: const Text('Negar'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => widget.chat.responderPermissao(p, permitido: true),
              child: const Text('Permitir'),
            ),
          ]),
        ],
      ),
    );
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
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Câmera'),
            onTap: () => Navigator.pop(context, FonteAnexo.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Galeria'),
            onTap: () => Navigator.pop(context, FonteAnexo.galeria),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('Arquivo'),
            onTap: () => Navigator.pop(context, FonteAnexo.arquivo),
          ),
        ]),
      ),
    );
    if (fonte != null) await anexar(sala, fonte);
  }

  @override
  Widget build(BuildContext context) {
    final chat = sala.chat;
    final cores = Theme.of(context).colorScheme;
    final conectado = sala.canal.conectado;
    final podeEnviar = conectado && !chat.emCurso && chat.subindo == 0;
    final atalhos = sala.conversas.atalhos;
    final mostrarAtalhos = atalhos.isNotEmpty && entrada.text.trim().isEmpty && chat.anexos.isEmpty;
    return Material(
      color: cores.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!conectado)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Sem conexão — o envio volta quando o servidor responder.',
                      textAlign: TextAlign.center, style: TextStyle(color: cores.error, fontSize: 12)),
                ),
              if (chat.citacao != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: cores.primary, width: 3))),
                  child: Row(children: [
                    Expanded(
                      child: Text(chat.citacao!,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cores.onSurfaceVariant)),
                    ),
                    IconButton(icon: const Icon(Icons.close, size: 18), onPressed: chat.limparCitacao),
                  ]),
                ),
              if (chat.anexos.isNotEmpty || chat.subindo > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final a in chat.anexos)
                      InputChip(
                        avatar: Icon(
                            switch (a.tipo) {
                              TipoAnexo.imagem => Icons.image_outlined,
                              TipoAnexo.pdf => Icons.picture_as_pdf_outlined,
                              TipoAnexo.texto => Icons.description_outlined,
                            },
                            size: 18),
                        label: Text('${a.nome} · ${formatarBytes(a.bytes)}'),
                        onDeleted: () => chat.removerAnexo(a.id),
                      ),
                    if (chat.subindo > 0)
                      const Chip(
                        avatar: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        label: Text('enviando anexo…'),
                      ),
                  ]),
                ),
              if (mostrarAtalhos)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: atalhos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) => Tooltip(
                      message: atalhos[i].texto,
                      child: ActionChip(
                        label: Text(atalhos[i].rotulo),
                        onPressed: podeEnviar ? () => aoEnviar(atalhos[i].texto) : null,
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Anexar',
                    icon: const Icon(Icons.attach_file),
                    onPressed: conectado ? () => _clipe(context) : null,
                  ),
                  Expanded(
                    child: Focus(
                      onKeyEvent: (_, evento) {
                        if (compacto || evento is! KeyDownEvent) return KeyEventResult.ignored;
                        if (evento.logicalKey != LogicalKeyboardKey.enter &&
                            evento.logicalKey != LogicalKeyboardKey.numpadEnter) {
                          return KeyEventResult.ignored;
                        }
                        if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
                        aoEnviar();
                        return KeyEventResult.handled;
                      },
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
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: 'Enviar',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: podeEnviar ? aoEnviar : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
