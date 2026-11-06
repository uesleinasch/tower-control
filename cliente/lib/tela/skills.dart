import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import '../estado/sala.dart';
import '../estado/skills.dart';
import '../nucleo/design.dart';
import '../nucleo/modelos.dart';
import '../nucleo/skills.dart';
import 'comum.dart';
import 'paineis.dart';
import 'tema.dart';

const _larguraDoItemDoMenu = 320.0;
const _larguraDaLista = 400.0;

String nomeDaPosicaoDaSkill(Sala sala, String chave) {
  final barra = chave.indexOf('/');
  if (barra < 0) return chave;
  final equipe = sala.equipes.equipes.where((e) => e.id == chave.substring(0, barra)).firstOrNull;
  final posicao = equipe?.posicao(chave.substring(barra + 1));
  if (equipe == null || posicao == null) return chave;
  return '${posicao.titulo} (${equipe.nome})';
}

double _margemDeLeitura(double largura) =>
    math.max(ClasseDeJanela.de(largura).margemLateral, (largura - larguraDeLeitura) / 2);

class TelaSkills extends StatelessWidget {
  const TelaSkills({super.key, required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([sala.skills, sala.equipes, sala.personas]),
        builder: (context, _) => LayoutBuilder(builder: (context, limites) {
          final estado = sala.skills;
          final classe = ClasseDeJanela.de(limites.maxWidth);
          final editor = estado.rascunho == null
              ? null
              : _EditorDeSkill(
                  key: ValueKey(estado.geracao),
                  sala: sala,
                  estado: estado,
                  emPainel: classe.comDoisPaineis,
                  compacto: classe == ClasseDeJanela.compact,
                );
          if (!classe.comDoisPaineis) {
            return editor ??
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _Cabecalho(estado: estado, margem: classe.margemLateral),
                  Expanded(child: _ListaDeSkills(sala: sala, estado: estado, margem: classe.margemLateral)),
                ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Cabecalho(estado: estado, margem: classe.margemLateral),
            const Divider(height: 1),
            Expanded(
              child: LadoALado(
                painel: 'skills',
                rotulo: 'Largura da lista de skills',
                inicial: _larguraDaLista,
                maximo: 640,
                lateral: _ListaDeSkills(sala: sala, estado: estado, margem: Espacos.esp3),
                principal: editor ?? const _NenhumaAberta(),
              ),
            ),
          ]);
        }),
      );
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.estado, required this.margem});

  final EstadoSkills estado;
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
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Skills', style: tema.textTheme.titleLarge),
                Text(
                  'A biblioteca da Casa e as skills de cada persona',
                  style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                ),
              ]),
            ),
            const SizedBox(width: Espacos.esp3),
            _MenuDeDono(aoEscolher: estado.nova),
          ]),
        ),
      ),
    );
  }
}

class _NenhumaAberta extends StatelessWidget {
  const _NenhumaAberta();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.extension, color: cor),
          const SizedBox(height: Espacos.esp2),
          Text(
            'Escolha uma skill para editar, ou crie uma em Nova skill.',
            textAlign: TextAlign.center,
            style: tema.textTheme.bodyMedium?.copyWith(color: cor),
          ),
        ]),
      ),
    );
  }
}

class _BannerDeErro extends StatelessWidget {
  const _BannerDeErro({required this.texto, required this.aoFechar});

  final String texto;
  final VoidCallback aoFechar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    return MaterialBanner(
      leading: Icon(Symbols.error, color: cores.onErrorContainer),
      content: Text(texto, style: tema.textTheme.bodyMedium?.copyWith(color: cores.onErrorContainer)),
      backgroundColor: cores.errorContainer,
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: cores.onErrorContainer),
          onPressed: aoFechar,
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _MenuDeDono extends StatelessWidget {
  const _MenuDeDono({required this.aoEscolher});

  final void Function(String dono) aoEscolher;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        menuChildren: [
          MenuItemButton(
            leadingIcon: const Icon(Symbols.home),
            onPressed: () => aoEscolher(donoCasa),
            child: const Text('Na biblioteca da Casa'),
          ),
          for (final p in Perfil.todos)
            MenuItemButton(
              leadingIcon: Avatar.doPerfil(p.chave, tamanho: 20),
              onPressed: () => aoEscolher(p.chave),
              child: Text('Própria de ${p.nome}'),
            ),
        ],
        builder: (context, controle, _) => FilledButton.icon(
          onPressed: () => controle.isOpen ? controle.close() : controle.open(),
          icon: const Icon(Symbols.add),
          label: const Text('Nova skill'),
        ),
      );
}

class _ListaDeSkills extends StatelessWidget {
  const _ListaDeSkills({required this.sala, required this.estado, required this.margem});

  final Sala sala;
  final EstadoSkills estado;
  final double margem;

  Future<void> _excluir(BuildContext context, Skill s) async {
    final ok = await confirmar(
      context,
      'Excluir a skill ${s.id}?',
      s.daCasa
          ? 'A pasta da skill sai da biblioteca da Casa. Skill anexada a alguém não pode ser excluída.'
          : 'A pasta da skill sai das skills próprias de ${rotuloDoDono(s.dono)}.',
      acao: 'Excluir skill',
    );
    if (ok) estado.excluir(s);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final aberta = estado.rascunho;
    return ListView(padding: EdgeInsets.fromLTRB(margem, Espacos.esp3, margem, Espacos.esp5), children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
        child: Text(
          'A persona vê só o nome e a descrição e abre a skill quando o pedido casa com ela. '
          'As da Casa valem para quem as tiver anexadas; as próprias valem sempre para a persona.',
          style: secundario,
        ),
      ),
      if (estado.erro != null && aberta == null)
        Padding(
          padding: const EdgeInsets.only(top: Espacos.esp3),
          child: _BannerDeErro(texto: estado.erro!, aoFechar: estado.limparErro),
        ),
      if (!estado.carregada)
        const Padding(padding: EdgeInsets.all(Espacos.esp5), child: Center(child: CircularProgressIndicator()))
      else
        for (final grupo in agruparSkills(estado.lista)) ...[
          const SizedBox(height: Espacos.esp5),
          Row(children: [
            if (grupo.dono == donoCasa)
              Icon(Symbols.home, size: 20, color: cores.onSurfaceVariant)
            else
              Avatar.doPerfil(grupo.dono, tamanho: 20),
            const SizedBox(width: Espacos.esp2),
            Text(grupo.dono == donoCasa ? 'Casa' : rotuloDoDono(grupo.dono), style: tema.textTheme.titleSmall),
          ]),
          const SizedBox(height: Espacos.esp2),
          if (grupo.skills.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Espacos.esp4),
              child: Row(children: [
                Icon(Symbols.extension, size: 20, color: cores.onSurfaceVariant),
                const SizedBox(width: Espacos.esp2),
                Expanded(child: Text('Nenhuma skill na biblioteca da Casa.', style: secundario)),
              ]),
            ),
          for (final s in grupo.skills)
            Padding(
              padding: const EdgeInsets.only(bottom: Espacos.esp3),
              child: _CartaoDeSkill(
                sala: sala,
                skill: s,
                aberta: aberta != null && !aberta.nova && aberta.dono == s.dono && aberta.id == s.id,
                aoExcluir: () => _excluir(context, s),
              ),
            ),
        ],
    ]);
  }
}

class _CartaoDeSkill extends StatefulWidget {
  const _CartaoDeSkill({required this.sala, required this.skill, required this.aberta, required this.aoExcluir});

  final Sala sala;
  final Skill skill;
  final bool aberta;
  final VoidCallback aoExcluir;

  @override
  State<_CartaoDeSkill> createState() => _CartaoDeSkillState();
}

class _CartaoDeSkillState extends State<_CartaoDeSkill> {
  final _menu = MenuController();
  final _ancora = GlobalKey();

  void _abrirMenu(BuildContext botao) {
    final origem = botao.findRenderObject();
    final cartao = _ancora.currentContext?.findRenderObject();
    if (origem is! RenderBox || cartao is! RenderBox) return _menu.open();
    _menu.open(position: origem.localToGlobal(Offset(0, origem.size.height), ancestor: cartao));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final s = widget.skill;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final uso = s.daCasa
        ? 'usada por: ${descreverUso(s.usadaPor, nomeDaPersona: (p) => Perfil.porChave(p).nome, nomeDaPosicao: (p) => nomeDaPosicaoDaSkill(widget.sala, p))}'
        : 'vale sempre para ${rotuloDoDono(s.dono)}';
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Symbols.edit),
          onPressed: () => widget.sala.skills.editar(s),
          child: const Text('Editar'),
        ),
        MenuItemButton(
          leadingIcon: Icon(Symbols.delete, color: cores.error),
          style: MenuItemButton.styleFrom(foregroundColor: cores.error),
          onPressed: widget.aoExcluir,
          child: const Text('Excluir skill'),
        ),
      ],
      child: GestureDetector(
        key: _ancora,
        onSecondaryTapUp: (d) => _menu.open(position: d.localPosition),
        child: Card(
          margin: EdgeInsets.zero,
          color: widget.aberta ? cores.secondaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Espacos.esp4, Espacos.esp3, Espacos.esp2, Espacos.esp4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Symbols.extension, size: 20, color: cores.onSurfaceVariant),
                const SizedBox(width: Espacos.esp2),
                Expanded(child: Text(s.id, style: tema.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
                IconButton(tooltip: 'Editar ${s.id}', icon: const Icon(Symbols.edit), onPressed: () => widget.sala.skills.editar(s)),
                Builder(
                  builder: (botao) => IconButton(
                    tooltip: 'Mais opções de ${s.id}',
                    icon: const Icon(Symbols.more_vert),
                    onPressed: () => _menu.isOpen ? _menu.close() : _abrirMenu(botao),
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(right: Espacos.esp2),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
                  child: SelectionArea(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (s.descricao.isNotEmpty) Text(s.descricao, maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Espacos.esp1),
                      Text(uso, style: secundario),
                      if (s.arquivos.isNotEmpty)
                        Text('arquivos de apoio: ${s.arquivos.join(', ')}', style: secundario?.copyWith(fontFamily: familiaMono)),
                    ]),
                  ),
                ),
              ),
              if (s.erro != null)
                Padding(
                  padding: const EdgeInsets.only(top: Espacos.esp2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Symbols.error, size: 16, color: cores.error),
                    const SizedBox(width: Espacos.esp1),
                    Expanded(child: Text('inválida: ${s.erro}', style: tema.textTheme.bodySmall?.copyWith(color: cores.error))),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _EditorDeSkill extends StatefulWidget {
  const _EditorDeSkill({super.key, required this.sala, required this.estado, required this.emPainel, required this.compacto});

  final Sala sala;
  final EstadoSkills estado;
  final bool emPainel;
  final bool compacto;

  @override
  State<_EditorDeSkill> createState() => _EditorDeSkillState();
}

class _EditorDeSkillState extends State<_EditorDeSkill> {
  late final RascunhoDeSkill _inicial = widget.estado.rascunho!;
  late final _id = TextEditingController(text: _inicial.id);
  late final _descricao = TextEditingController(text: _inicial.descricao);
  late final _corpo = TextEditingController(text: _inicial.corpo);
  final _tocados = <CampoDaSkill>{};
  var _mostrarTudo = false;

  @override
  void dispose() {
    _id.dispose();
    _descricao.dispose();
    _corpo.dispose();
    super.dispose();
  }

  Future<void> _descartar() async {
    final r = widget.estado.rascunho;
    final mudou = r != null && (r.id != _inicial.id || r.descricao != _inicial.descricao || r.corpo != _inicial.corpo);
    if (mudou && !await confirmar(context, 'Descartar as mudanças?', 'O rascunho desta skill se perde.', acao: 'Descartar')) return;
    widget.estado.descartar();
  }

  void _salvar() {
    if (widget.estado.errosDoRascunhoAtual.isNotEmpty) {
      setState(() => _mostrarTudo = true);
      return;
    }
    widget.estado.salvar();
  }

  Widget _validaAoSair(CampoDaSkill campo, Widget campoDeTexto) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focado) {
          if (!focado && !_tocados.contains(campo)) setState(() => _tocados.add(campo));
        },
        child: campoDeTexto,
      );

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    final r = estado.rascunho!;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final mono = tema.textTheme.bodyMedium?.copyWith(fontFamily: familiaMono);
    final erros = errosDosCamposDaSkill(r, existentes: estado.lista);
    String? erroDe(CampoDaSkill campo) => _mostrarTudo || _tocados.contains(campo) ? erros[campo] : null;
    final erroDoId = r.id.isNotEmpty ? erros[CampoDaSkill.id] : erroDe(CampoDaSkill.id);
    final descricaoLonga = r.descricao.trim().length > limiteDaDescricao;
    final corpoLongo = r.corpo.length > limiteDoCorpo;
    final titulo = r.nova ? 'Nova skill em ${rotuloDoDono(r.dono)}' : 'Skill ${r.id} (${rotuloDoDono(r.dono)})';
    final descartar = estado.salvando ? null : _descartar;
    final conteudo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Espacos.esp2, Espacos.esp2, Espacos.esp4, Espacos.esp2),
        child: Row(children: [
          if (widget.emPainel)
            IconButton(tooltip: 'Fechar o editor', icon: const Icon(Symbols.close), onPressed: _descartar)
          else
            IconButton(tooltip: 'Voltar às skills', icon: const Icon(Symbols.arrow_back), onPressed: _descartar),
          const SizedBox(width: Espacos.esp1),
          Expanded(child: Text(titulo, style: tema.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
          if (estado.salvando)
            const Padding(
              padding: EdgeInsets.only(right: Espacos.esp3),
              child: SizedBox.square(dimension: Espacos.esp4, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (widget.compacto)
            IconButton(tooltip: 'Descartar', icon: const Icon(Symbols.undo), onPressed: descartar)
          else
            OutlinedButton.icon(onPressed: descartar, icon: const Icon(Symbols.undo), label: const Text('Descartar')),
          const SizedBox(width: Espacos.esp2),
          FilledButton.icon(
            onPressed: estado.salvando ? null : _salvar,
            icon: const Icon(Symbols.save),
            label: const Text('Salvar'),
          ),
        ]),
      ),
      if (estado.erro != null) _BannerDeErro(texto: estado.erro!, aoFechar: estado.limparErro),
      const Divider(height: 1),
      Expanded(
        child: LayoutBuilder(builder: (context, limites) {
          final margem = _margemDeLeitura(limites.maxWidth);
          return ListView(padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, margem, Espacos.esp5), children: [
            TextField(
              controller: _id,
              enabled: r.nova,
              style: mono,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
              decoration: InputDecoration(
                labelText: 'Id',
                helperText: r.nova
                    ? 'letras minúsculas, números e hífen, começando por letra; não muda depois de criada'
                    : 'o id não muda; para renomear, crie outra skill e exclua esta',
                helperMaxLines: 2,
                errorText: erroDoId,
                errorMaxLines: 2,
              ),
              onChanged: (v) {
                _tocados.add(CampoDaSkill.id);
                estado.mudar(id: v);
              },
            ),
            const SizedBox(height: Espacos.esp3),
            _validaAoSair(
              CampoDaSkill.descricao,
              TextField(
                controller: _descricao,
                minLines: 2,
                maxLines: 5,
                maxLength: limiteDaDescricao,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                decoration: InputDecoration(
                  labelText: 'Descrição',
                  alignLabelWithHint: true,
                  helperText: 'o que a skill faz e quando usar: é o que a persona lê para decidir abrir',
                  helperMaxLines: 2,
                  errorText: descricaoLonga ? erros[CampoDaSkill.descricao] : erroDe(CampoDaSkill.descricao),
                ),
                onChanged: (v) => estado.mudar(descricao: v),
              ),
            ),
            const SizedBox(height: Espacos.esp3),
            _validaAoSair(
              CampoDaSkill.corpo,
              TextField(
                controller: _corpo,
                minLines: 18,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: mono,
                decoration: InputDecoration(
                  labelText: 'Corpo (Markdown)',
                  alignLabelWithHint: true,
                  helperText: 'o SKILL.md que a persona lê quando abre a skill',
                  errorText: corpoLongo ? erros[CampoDaSkill.corpo] : erroDe(CampoDaSkill.corpo),
                ),
                onChanged: (v) => estado.mudar(corpo: v),
              ),
            ),
            if (_mostrarTudo && erros.isNotEmpty) ...[
              const SizedBox(height: Espacos.esp2),
              Text('Corrija os campos marcados para salvar.', style: tema.textTheme.bodySmall?.copyWith(color: cores.error)),
            ],
            const SizedBox(height: Espacos.esp5),
            Text('Arquivos de apoio', style: tema.textTheme.titleSmall),
            const SizedBox(height: Espacos.esp2),
            if (r.arquivos.isEmpty)
              Text('nenhum', style: secundario)
            else
              SelectionArea(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final a in r.arquivos)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Espacos.esp1),
                      child: Row(children: [
                        Icon(Symbols.description, size: 16, color: cores.onSurfaceVariant),
                        const SizedBox(width: Espacos.esp2),
                        Expanded(child: Text(a, style: mono)),
                      ]),
                    ),
                ]),
              ),
            const SizedBox(height: Espacos.esp2),
            Text('Arquivo de apoio se edita à mão, na pasta da skill dentro da pasta de dados.', style: secundario),
          ]);
        }),
      ),
    ]);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (saiu, _) {
        if (!saiu && !estado.salvando) _descartar();
      },
      child: conteudo,
    );
  }
}

class SecaoDeSkills extends StatelessWidget {
  const SecaoDeSkills({
    super.key,
    required this.itens,
    required this.anexaveis,
    this.aoAnexar,
    this.aoTirar,
    this.titulo = 'Skills',
  });

  final List<SkillDescrita> itens;
  final List<Skill> anexaveis;
  final void Function(String id)? aoAnexar;
  final void Function(String id)? aoTirar;
  final String titulo;

  bool get _edita => aoAnexar != null && aoTirar != null;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(titulo, style: tema.textTheme.titleSmall)),
        if (_edita)
          MenuAnchor(
            menuChildren: [
              if (anexaveis.isEmpty) const MenuItemButton(child: Text('nenhuma skill da Casa para anexar')),
              for (final s in anexaveis)
                MenuItemButton(
                  leadingIcon: const Icon(Symbols.extension),
                  onPressed: () => aoAnexar!(s.id),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _larguraDoItemDoMenu),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(s.id),
                      Text(s.descricao, maxLines: 2, overflow: TextOverflow.ellipsis, style: secundario),
                    ]),
                  ),
                ),
            ],
            builder: (context, controle, _) => IconButton(
              tooltip: 'Anexar skill da Casa',
              icon: const Icon(Symbols.add),
              onPressed: () => controle.isOpen ? controle.close() : controle.open(),
            ),
          ),
      ]),
      if (itens.isEmpty)
        Text('nenhuma', style: secundario)
      else
        Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: [
          for (final s in itens)
            InputChip(
              avatar: Icon(
                s.erro != null ? Symbols.error : Symbols.extension,
                size: 16,
                color: s.erro != null ? cores.error : cores.onSurfaceVariant,
              ),
              label: Text(s.propria ? '${s.rotulo} · própria' : s.rotulo),
              labelStyle: tema.textTheme.labelLarge?.copyWith(color: s.erro != null ? cores.error : null),
              tooltip: s.descricao.isEmpty ? null : s.descricao,
              onDeleted: _edita && !s.propria ? () => aoTirar!(s.id) : null,
              deleteIcon: const Icon(Symbols.close, size: 16),
              deleteButtonTooltipMessage: 'Tirar ${s.id}',
            ),
        ]),
    ]);
  }
}
