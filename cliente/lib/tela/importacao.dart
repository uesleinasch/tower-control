import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/importacao.dart';
import '../estado/sala.dart';
import '../nucleo/importacao.dart';
import '../nucleo/modelos.dart';
import '../nucleo/protocolo.dart';
import '../nucleo/tarefas.dart';
import '../sistema/arquivos.dart';

const _corDoAviso = Color(0xFFE0A458);

void _avisar(ScaffoldMessengerState? mensageiro, String texto) =>
    mensageiro?.showSnackBar(SnackBar(content: Text(texto)));

Future<void> exportarEquipeComoModelo(BuildContext context, Sala sala, EquipeResumo equipe, {bool alterada = false}) async {
  final opcoes = await showDialog<({bool personas, bool rotinas})>(
    context: context,
    builder: (_) => _DialogoDeExportacao(equipe: equipe, alterada: alterada),
  );
  if (opcoes == null || !context.mounted) return;
  await _exportar(
    context,
    sala.importacao.exportar(equipe.id, personas: opcoes.personas, rotinas: opcoes.rotinas),
  );
}

Future<void> exportarWorkflowComoModelo(BuildContext context, Sala sala, String equipe, String workflow) =>
    _exportar(context, sala.importacao.exportar(equipe, workflow: workflow));

Future<void> _exportar(BuildContext context, Future<ModeloRecebido> pedido) async {
  final mensageiro = ScaffoldMessenger.maybeOf(context);
  try {
    final modelo = await pedido;
    final destino = await salvarArquivo(nome: modelo.nome, bytes: utf8.encode(modelo.conteudo));
    if (destino == null) return;
    _avisar(mensageiro, 'Modelo salvo em $destino');
  } catch (erro) {
    _avisar(mensageiro, 'Não consegui exportar: $erro');
  }
}

Future<void> importarModelo(BuildContext context, Sala sala, {String? destino}) async {
  final mensageiro = ScaffoldMessenger.maybeOf(context);
  final String texto;
  final String nome;
  try {
    final arquivos = await escolherArquivos(extensoes: const ['json']);
    if (arquivos == null || arquivos.isEmpty) return;
    nome = arquivos.first.nome;
    texto = await File(arquivos.first.caminho).readAsString();
  } catch (erro) {
    _avisar(mensageiro, 'Não consegui ler o arquivo: $erro');
    return;
  }
  if (!context.mounted) return;
  sala.importacao.abrir(texto, destino: destino, arquivo: nome);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TelaDeImportacao(sala: sala)));
  sala.importacao.fechar();
}

class _DialogoDeExportacao extends StatefulWidget {
  const _DialogoDeExportacao({required this.equipe, required this.alterada});

  final EquipeResumo equipe;
  final bool alterada;

  @override
  State<_DialogoDeExportacao> createState() => _DialogoDeExportacaoState();
}

class _DialogoDeExportacaoState extends State<_DialogoDeExportacao> {
  var _personas = true;
  var _rotinas = true;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Exportar ${widget.equipe.nome} como modelo'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('O modelo leva a equipe, os workflows e as skills da Casa que ela usa. '
              'Orçamentos, diretórios, memória e conversas nunca saem.'),
          if (widget.alterada)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('As mudanças ainda não salvas desta equipe não entram.', style: TextStyle(color: _corDoAviso)),
            ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _personas,
            onChanged: (v) => setState(() => _personas = v ?? false),
            title: const Text('Levar as personas'),
            subtitle: const Text('Perfil, ritmo e skills próprias. Sem elas, as posições saem vagas.'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _rotinas,
            onChanged: (v) => setState(() => _rotinas = v ?? false),
            title: const Text('Levar as rotinas'),
            subtitle: const Text('Entram desligadas na importação.'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (personas: _personas, rotinas: _rotinas)),
            child: const Text('Exportar…'),
          ),
        ],
      );
}

class TelaDeImportacao extends StatefulWidget {
  const TelaDeImportacao({super.key, required this.sala});

  final Sala sala;

  @override
  State<TelaDeImportacao> createState() => _TelaDeImportacaoState();
}

class _TelaDeImportacaoState extends State<TelaDeImportacao> {
  EstadoImportacao get _e => widget.sala.importacao;
  var _saiu = false;

  @override
  void initState() {
    super.initState();
    _e.addListener(_aoMudar);
  }

  @override
  void dispose() {
    _e.removeListener(_aoMudar);
    super.dispose();
  }

  void _aoMudar() {
    final importado = _e.importado;
    if (importado == null || _saiu || !mounted) return;
    _saiu = true;
    final mensageiro = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    widget.sala.abrirImportado(importado);
    _avisar(
      mensageiro,
      importado.workflow == null
          ? 'Modelo importado como a equipe ${importado.equipe}.'
          : 'Workflow ${importado.workflow} importado na equipe ${importado.equipe}.',
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_e, widget.sala.equipes]),
        builder: (context, _) {
          final previa = _e.previa;
          final deWorkflow = previa?.deWorkflow ?? _e.destino != null;
          return Scaffold(
            appBar: AppBar(title: Text(deWorkflow ? 'Importar workflow' : 'Importar modelo')),
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: previa == null ? _carregando() : _Previa(sala: widget.sala, previa: previa),
                ),
              ),
            ),
            bottomNavigationBar: _Rodape(estado: _e),
          );
        },
      );

  Widget _carregando() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_e.erro == null) const CircularProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_e.erro ?? 'Lendo o modelo ${_e.arquivo ?? ''}…'),
          ),
        ]),
      );
}

class _Rodape extends StatelessWidget {
  const _Rodape({required this.estado});

  final EstadoImportacao estado;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final previa = estado.previa;
    final situacao = estado.importando
        ? 'Importando…'
        : estado.pendente
            ? 'Atualizando a prévia…'
            : previa != null && previa.erros.isNotEmpty
                ? 'Corrija os erros para importar.'
                : '';
    return Material(
      color: cores.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            if (estado.importando || estado.pendente)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Expanded(child: Text(situacao, style: TextStyle(color: cores.onSurfaceVariant))),
            TextButton(
              onPressed: estado.importando ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: estado.podeImportar ? estado.importar : null,
              icon: const Icon(Symbols.download_done),
              label: const Text('Importar'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Previa extends StatelessWidget {
  const _Previa({required this.sala, required this.previa});

  final Sala sala;
  final PreviaDoModelo previa;

  EstadoImportacao get _e => sala.importacao;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final resumo = previa.resumo;
    final habilitado = !_e.importando;
    final escolhas = _e.escolhas;
    final destino = sala.equipes.equipes.where((e) => e.id == _e.destino).firstOrNull;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      if (resumo != null) _Cabecalho(resumo: resumo, arquivo: _e.arquivo, destino: destino?.nome ?? _e.destino),
      if (resumo != null && !resumo.deWorkflow) ...[
        const _Titulo('Equipe'),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _Campo(
            key: const ValueKey('equipe-id'),
            rotulo: 'Id',
            inicial: escolhas.equipeId ?? '',
            dica: previa.escolhas.equipeId,
            habilitado: habilitado,
            aoMudar: (v) => _e.mudar(_e.escolhas.comEquipe(id: v), digitando: true),
          ),
          _Campo(
            key: const ValueKey('equipe-nome'),
            rotulo: 'Nome',
            inicial: escolhas.equipeNome ?? '',
            dica: previa.escolhas.equipeNome,
            habilitado: habilitado,
            largura: 300,
            aoMudar: (v) => _e.mudar(_e.escolhas.comEquipe(nome: v), digitando: true),
          ),
        ]),
      ],
      if (resumo != null && resumo.deWorkflow) ...[
        const _Titulo('Workflow'),
        _Campo(
          key: const ValueKey('workflow-id'),
          rotulo: 'Id',
          inicial: escolhas.workflowId ?? '',
          dica: previa.escolhas.workflowId,
          habilitado: habilitado,
          aoMudar: (v) => _e.mudar(_e.escolhas.comWorkflow(v), digitando: true),
        ),
      ],
      if (previa.personas.isNotEmpty) ...[
        const _Titulo('Personas'),
        for (final p in previa.personas) _LinhaDaPersona(estado: _e, persona: p, habilitado: habilitado),
      ],
      if (previa.skillsEmColisao.isNotEmpty) ...[
        const _Titulo('Skills com conteúdo diferente daqui'),
        for (final id in previa.skillsEmColisao) _LinhaDaSkill(estado: _e, id: id, habilitado: habilitado),
      ],
      if (resumo != null && resumo.deWorkflow && previa.posicoes.isNotEmpty) ...[
        _Titulo('Posições na equipe ${destino?.nome ?? _e.destino ?? ''}'),
        for (final p in previa.posicoes)
          _LinhaDaPosicao(estado: _e, posicao: p, destino: destino?.posicoes ?? const [], habilitado: habilitado),
      ],
      if (previa.entra.isNotEmpty) ...[
        const _Titulo('O que entra'),
        for (final linha in previa.entra)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Symbols.add, size: 16, color: cores.primary),
              const SizedBox(width: 6),
              Expanded(child: Text(linha)),
            ]),
          ),
      ],
      if (previa.avisos.isNotEmpty) ...[
        const _Titulo('Avisos'),
        _Caixa(cor: _corDoAviso, icone: Symbols.warning_amber, linhas: previa.avisos),
      ],
      if (previa.erros.isNotEmpty) ...[
        const _Titulo('Erros'),
        _Caixa(cor: cores.error, icone: Symbols.error, linhas: previa.erros),
      ],
      if (_e.erro != null) ...[
        const SizedBox(height: 12),
        _Caixa(cor: cores.error, icone: Symbols.error, linhas: [_e.erro!]),
      ],
    ]);
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.resumo, this.arquivo, this.destino});

  final ResumoDoModelo resumo;
  final String? arquivo;
  final String? destino;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final estilo = TextStyle(color: cores.onSurfaceVariant, fontSize: 13);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(resumo.nome, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            [
              resumo.deWorkflow ? 'modelo de workflow' : 'modelo de equipe',
              if (resumo.exportado().isNotEmpty) resumo.exportado(),
              ?arquivo,
            ].join(' · '),
            style: estilo,
          ),
          Text(resumo.contagem, style: estilo),
          if (resumo.deWorkflow && destino != null) Text('entra na equipe $destino', style: estilo),
        ]),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          texto.toUpperCase(),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11, letterSpacing: 1),
        ),
      );
}

class _Caixa extends StatelessWidget {
  const _Caixa({required this.cor, required this.icone, required this.linhas});

  final Color cor;
  final IconData icone;
  final List<String> linhas;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          border: Border.all(color: cor.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in linhas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icone, size: 16, color: cor),
                const SizedBox(width: 8),
                Expanded(child: Text(l)),
              ]),
            ),
        ]),
      );
}

class _LinhaDaPersona extends StatelessWidget {
  const _LinhaDaPersona({required this.estado, required this.persona, required this.habilitado});

  final EstadoImportacao estado;
  final PersonaDoModelo persona;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final daqui = [for (final p in Perfil.todos) p.chave];
    final acao = estado.escolhas.personas[persona.id];
    final opcao = acao?.opcao(persona.id);
    bool disponivel(OpcaoDePersona o) => switch (o) {
          OpcaoDePersona.daqui => daqui.contains(persona.id),
          OpcaoDePersona.outra => daqui.any((p) => p != persona.id),
          OpcaoDePersona.criar || OpcaoDePersona.criarComNome => persona.traz,
          OpcaoDePersona.vaga => true,
        };
    final escolhida = acao?.persona;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 180,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(persona.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              persona.traz ? persona.id : '${persona.id} · o modelo não traz o perfil',
              style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
            ),
          ]),
        ),
        DropdownButton<OpcaoDePersona>(
          value: opcao,
          hint: const Text('escolha'),
          onChanged: !habilitado
              ? null
              : (o) {
                  if (o == null || o == opcao) return;
                  estado.mudar(estado.escolhas.comOpcaoDePersona(
                    persona.id,
                    o,
                    nomeNoModelo: persona.nome,
                    personasDaqui: daqui,
                  ));
                },
          items: [
            for (final o in OpcaoDePersona.values)
              DropdownMenuItem(value: o, enabled: disponivel(o), child: Text(rotulosDeOpcaoDePersona[o]!)),
          ],
        ),
        if (opcao == OpcaoDePersona.outra)
          DropdownButton<String>(
            value: escolhida,
            onChanged: !habilitado
                ? null
                : (p) {
                    if (p != null && p != escolhida) estado.mudar(estado.escolhas.comPersonaDaqui(persona.id, p));
                  },
            items: [
              for (final p in Perfil.todos) DropdownMenuItem(value: p.chave, child: Text(p.nome)),
              if (escolhida != null && !daqui.contains(escolhida))
                DropdownMenuItem(value: escolhida, child: Text('$escolhida (não existe)')),
            ],
          ),
        if (opcao == OpcaoDePersona.criarComNome)
          _Campo(
            key: ValueKey('persona-nome-${persona.id}'),
            rotulo: 'Nome da persona nova',
            inicial: acao?.nome ?? '',
            habilitado: habilitado,
            aoMudar: (v) => estado.mudar(estado.escolhas.comNomeDePersona(persona.id, v), digitando: true),
          ),
      ]),
    );
  }
}

class _LinhaDaSkill extends StatelessWidget {
  const _LinhaDaSkill({required this.estado, required this.id, required this.habilitado});

  final EstadoImportacao estado;
  final String id;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final acao = estado.escolhas.skills[id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 180, child: Text(id, style: const TextStyle(fontWeight: FontWeight.w600))),
        DropdownButton<OpcaoDeSkill>(
          value: acao?.opcao ?? OpcaoDeSkill.daqui,
          onChanged: !habilitado
              ? null
              : (o) {
                  if (o != null && o != acao?.opcao) estado.mudar(estado.escolhas.comOpcaoDeSkill(id, o));
                },
          items: [
            for (final o in OpcaoDeSkill.values) DropdownMenuItem(value: o, child: Text(rotulosDeOpcaoDeSkill[o]!)),
          ],
        ),
        if (acao?.opcao == OpcaoDeSkill.importar)
          _Campo(
            key: ValueKey('skill-id-$id'),
            rotulo: 'Id da skill importada',
            inicial: acao?.id ?? '',
            habilitado: habilitado,
            aoMudar: (v) => estado.mudar(estado.escolhas.comIdDeSkill(id, v), digitando: true),
          ),
      ]),
    );
  }
}

class _LinhaDaPosicao extends StatelessWidget {
  const _LinhaDaPosicao({required this.estado, required this.posicao, required this.destino, required this.habilitado});

  final EstadoImportacao estado;
  final PosicaoDoModelo posicao;
  final List<PosicaoResumo> destino;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final alvo = estado.escolhas.posicoes[posicao.id];
    final ids = {for (final p in destino) p.id};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 180,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(posicao.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(posicao.id, style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
          ]),
        ),
        const Icon(Symbols.arrow_forward, size: 18),
        DropdownButton<String?>(
          value: alvo,
          onChanged: !habilitado
              ? null
              : (p) {
                  if (p != alvo) estado.mudar(estado.escolhas.comPosicao(posicao.id, p));
                },
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('sem ligação')),
            for (final p in destino) DropdownMenuItem<String?>(value: p.id, child: Text('${p.titulo} (${p.id})')),
            if (alvo != null && !ids.contains(alvo)) DropdownMenuItem<String?>(value: alvo, child: Text('$alvo (não existe)')),
          ],
        ),
      ]),
    );
  }
}

class _Campo extends StatefulWidget {
  const _Campo({
    super.key,
    required this.rotulo,
    required this.inicial,
    required this.aoMudar,
    this.dica,
    this.habilitado = true,
    this.largura = 220,
  });

  final String rotulo;
  final String inicial;
  final String? dica;
  final bool habilitado;
  final double largura;
  final ValueChanged<String> aoMudar;

  @override
  State<_Campo> createState() => _CampoState();
}

class _CampoState extends State<_Campo> {
  late final _controle = TextEditingController(text: widget.inicial);

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.largura,
        child: TextField(
          controller: _controle,
          enabled: widget.habilitado,
          decoration: InputDecoration(
            labelText: widget.rotulo,
            hintText: widget.dica,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: widget.aoMudar,
        ),
      );
}
