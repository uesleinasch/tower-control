import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../estado/sala.dart';
import '../estado/skills.dart';
import '../nucleo/modelos.dart';
import '../nucleo/skills.dart';
import 'comum.dart';

String nomeDaPosicaoDaSkill(Sala sala, String chave) {
  final barra = chave.indexOf('/');
  if (barra < 0) return chave;
  final equipe = sala.equipes.equipes.where((e) => e.id == chave.substring(0, barra)).firstOrNull;
  final posicao = equipe?.posicao(chave.substring(barra + 1));
  if (equipe == null || posicao == null) return chave;
  return '${posicao.titulo} (${equipe.nome})';
}

class PainelDeSkills extends StatelessWidget {
  const PainelDeSkills({super.key, required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sala.skills,
        builder: (context, _) {
          final estado = sala.skills;
          if (estado.rascunho != null) {
            return _EditorDeSkill(key: ValueKey(estado.geracao), sala: sala, estado: estado);
          }
          return _ListaDeSkills(sala: sala, estado: estado);
        },
      );
}

class _MenuDeDono extends StatelessWidget {
  const _MenuDeDono({required this.aoEscolher});

  final void Function(String dono) aoEscolher;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        menuChildren: [
          MenuItemButton(onPressed: () => aoEscolher(donoCasa), child: const Text('Na biblioteca da Casa')),
          for (final p in Perfil.todos)
            MenuItemButton(
              leadingIcon: Avatar.doPerfil(p.chave, tamanho: 20),
              onPressed: () => aoEscolher(p.chave),
              child: Text('Própria de ${p.nome}'),
            ),
        ],
        builder: (context, controle, _) => FilledButton.icon(
          onPressed: () => controle.isOpen ? controle.close() : controle.open(),
          icon: const Icon(Icons.add),
          label: const Text('Nova skill'),
        ),
      );
}

class _ListaDeSkills extends StatelessWidget {
  const _ListaDeSkills({required this.sala, required this.estado});

  final Sala sala;
  final EstadoSkills estado;

  Future<void> _excluir(BuildContext context, Skill s) async {
    final ok = await confirmar(
      context,
      'Excluir a skill ${s.id}?',
      s.daCasa
          ? 'A pasta da skill sai da biblioteca da Casa. Skill anexada a alguém não pode ser excluída.'
          : 'A pasta da skill sai das skills próprias de ${rotuloDoDono(s.dono)}.',
    );
    if (ok) estado.excluir(s);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('Skills', style: textos.titleMedium)),
        _MenuDeDono(aoEscolher: estado.nova),
      ]),
      const SizedBox(height: 4),
      Text(
        'A persona vê só o nome e a descrição e abre a skill quando o pedido casa com ela. '
        'As da Casa valem para quem as tiver anexadas; as próprias valem sempre para a persona.',
        style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
      ),
      if (estado.erro != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: MaterialBanner(
            content: Text(estado.erro!),
            backgroundColor: cores.errorContainer,
            actions: [TextButton(onPressed: estado.limparErro, child: const Text('Ok'))],
          ),
        ),
      if (!estado.carregada)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else
        for (final grupo in agruparSkills(estado.lista)) ...[
          const SizedBox(height: 20),
          Row(children: [
            if (grupo.dono == donoCasa)
              const Icon(Icons.home_outlined, size: 20)
            else
              Avatar.doPerfil(grupo.dono, tamanho: 20),
            const SizedBox(width: 8),
            Text(grupo.dono == donoCasa ? 'Casa' : rotuloDoDono(grupo.dono), style: textos.titleSmall),
          ]),
          const SizedBox(height: 4),
          if (grupo.skills.isEmpty)
            Text('Nenhuma skill na biblioteca da Casa.', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
          for (final s in grupo.skills) _CartaoDeSkill(sala: sala, skill: s, aoExcluir: () => _excluir(context, s)),
        ],
    ]);
  }
}

class _CartaoDeSkill extends StatelessWidget {
  const _CartaoDeSkill({required this.sala, required this.skill, required this.aoExcluir});

  final Sala sala;
  final Skill skill;
  final VoidCallback aoExcluir;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final s = skill;
    final uso = s.daCasa
        ? 'usada por: ${descreverUso(s.usadaPor, nomeDaPersona: (p) => Perfil.porChave(p).nome, nomeDaPosicao: (p) => nomeDaPosicaoDaSkill(sala, p))}'
        : 'vale sempre para ${rotuloDoDono(s.dono)}';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.id, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (s.descricao.isNotEmpty) Text(s.descricao, maxLines: 3, overflow: TextOverflow.ellipsis),
              Text(uso, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
              if (s.arquivos.isNotEmpty)
                Text('arquivos de apoio: ${s.arquivos.join(', ')}', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
              if (s.erro != null) Text('inválida: ${s.erro}', style: TextStyle(color: cores.error, fontSize: 12)),
            ]),
          ),
          IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => sala.skills.editar(s)),
          IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: aoExcluir),
        ]),
      ),
    );
  }
}

class _EditorDeSkill extends StatefulWidget {
  const _EditorDeSkill({super.key, required this.sala, required this.estado});

  final Sala sala;
  final EstadoSkills estado;

  @override
  State<_EditorDeSkill> createState() => _EditorDeSkillState();
}

class _EditorDeSkillState extends State<_EditorDeSkill> {
  late final RascunhoDeSkill _inicial = widget.estado.rascunho!;
  late final _id = TextEditingController(text: _inicial.id);
  late final _descricao = TextEditingController(text: _inicial.descricao);
  late final _corpo = TextEditingController(text: _inicial.corpo);

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

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    final r = estado.rascunho!;
    final cores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    final erros = estado.errosDoRascunhoAtual;
    final titulo = r.nova ? 'Nova skill em ${rotuloDoDono(r.dono)}' : 'Skill ${r.id} (${rotuloDoDono(r.dono)})';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(children: [
          IconButton(tooltip: 'Voltar às skills', icon: const Icon(Icons.arrow_back), onPressed: _descartar),
          const SizedBox(width: 4),
          Expanded(child: Text(titulo, style: textos.titleMedium, overflow: TextOverflow.ellipsis)),
          if (estado.salvando) const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          OutlinedButton.icon(onPressed: estado.salvando ? null : _descartar, icon: const Icon(Icons.undo), label: const Text('Descartar')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: estado.podeSalvar ? estado.salvar : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar'),
          ),
        ]),
      ),
      if (estado.erro != null)
        MaterialBanner(
          content: Text(estado.erro!),
          backgroundColor: cores.errorContainer,
          actions: [TextButton(onPressed: estado.limparErro, child: const Text('Ok'))],
        ),
      const Divider(height: 1),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _id,
            enabled: r.nova,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: InputDecoration(
              labelText: 'Id',
              helperText: r.nova
                  ? 'letras minúsculas, números e hífen, começando por letra; não muda depois de criada'
                  : 'o id não muda; para renomear, crie outra skill e exclua esta',
            ),
            onChanged: (v) => estado.mudar(id: v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descricao,
            minLines: 2,
            maxLines: 5,
            maxLength: limiteDaDescricao,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            decoration: const InputDecoration(
              labelText: 'Descrição',
              helperText: 'o que a skill faz e quando usar: é o que a persona lê para decidir abrir',
            ),
            onChanged: (v) => estado.mudar(descricao: v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _corpo,
            minLines: 18,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Corpo (Markdown)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => estado.mudar(corpo: v),
          ),
          if (erros.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final e in erros) Text(e, style: TextStyle(color: cores.error, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Text('Arquivos de apoio', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 4),
          if (r.arquivos.isEmpty)
            Text('nenhum', style: TextStyle(color: cores.onSurfaceVariant))
          else
            for (final a in r.arquivos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  const Icon(Icons.description_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(a, style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
                ]),
              ),
          const SizedBox(height: 4),
          Text(
            'Arquivo de apoio se edita à mão, na pasta da skill dentro da pasta de dados.',
            style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
          ),
        ]),
      ),
    ]);
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
    final cores = Theme.of(context).colorScheme;
    final pequeno = TextStyle(color: cores.onSurfaceVariant, fontSize: 12);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(titulo, style: pequeno)),
        if (_edita)
          MenuAnchor(
            menuChildren: [
              if (anexaveis.isEmpty)
                const MenuItemButton(child: Text('nenhuma skill da Casa para anexar')),
              for (final s in anexaveis)
                MenuItemButton(
                  onPressed: () => aoAnexar!(s.id),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(s.id),
                      Text(s.descricao, maxLines: 2, overflow: TextOverflow.ellipsis, style: pequeno),
                    ]),
                  ),
                ),
            ],
            builder: (context, controle, _) => IconButton(
              tooltip: 'Anexar skill da Casa',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => controle.isOpen ? controle.close() : controle.open(),
            ),
          ),
      ]),
      if (itens.isEmpty) Text('nenhuma', style: pequeno),
      for (final s in itens)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.propria ? '${s.rotulo} · própria' : s.rotulo,
                    style: TextStyle(color: s.erro != null ? cores.error : null)),
                if (s.descricao.isNotEmpty) Text(s.descricao, maxLines: 3, overflow: TextOverflow.ellipsis, style: pequeno),
              ]),
            ),
            if (_edita && !s.propria)
              IconButton(
                tooltip: 'Tirar ${s.id}',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => aoTirar!(s.id),
              ),
          ]),
        ),
    ]);
  }
}
