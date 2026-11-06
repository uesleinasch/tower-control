import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/importacao.dart';
import '../estado/sala.dart';
import '../nucleo/design.dart';
import '../nucleo/importacao.dart';
import '../nucleo/modelos.dart';
import '../nucleo/protocolo.dart';
import '../nucleo/tarefas.dart';
import '../sistema/arquivos.dart';
import 'tema.dart';

const _numeros = [FontFeature.tabularFigures()];
const _larguraDaIdentidade = 200.0;
const _larguraDaEscolha = 260.0;
const _larguraParaLado = 560.0;
const _larguraDaEscolhaDeSkillEmLinha = 440.0;

void _avisar(ScaffoldMessengerState? mensageiro, String texto) =>
    mensageiro?.showSnackBar(SnackBar(content: Text(texto)));

Future<void> exportarEquipeComoModelo(BuildContext context, Sala sala, EquipeResumo equipe, {bool alterada = false}) async {
  final opcoes = await showDialog<({bool personas, bool rotinas})>(
    context: context,
    builder: (_) => _DialogoDeExportacao(equipe: equipe, alterada: alterada, casa: sala.equipes.nomeDaCasa),
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

enum TomDaMensagem { aviso, erro }

class CaixaDeMensagens extends StatelessWidget {
  const CaixaDeMensagens({super.key, required this.tom, required this.linhas});

  final TomDaMensagem tom;
  final List<String> linhas;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final aviso = CoresSemanticas.de(context).aviso;
    final (fundo, texto, icone) = switch (tom) {
      TomDaMensagem.aviso => (aviso.container, aviso.sobreContainer, Symbols.warning),
      TomDaMensagem.erro => (cores.errorContainer, cores.onErrorContainer, Symbols.error),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(Raios.sm)),
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, l) in linhas.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : Espacos.esp2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icone, size: 20, color: texto),
                const SizedBox(width: Espacos.esp2),
                Expanded(child: Text(l, style: tema.textTheme.bodyMedium?.copyWith(color: texto))),
              ]),
            ),
        ]),
      ),
    );
  }
}

typedef OpcaoSegmentada<T> = ({T valor, String rotulo, IconData? icone, bool habilitada});

class EscolhaSegmentada<T> extends StatelessWidget {
  const EscolhaSegmentada({
    super.key,
    required this.opcoes,
    required this.valor,
    required this.aoEscolher,
    this.larguraParaLinha = 0,
  });

  final List<OpcaoSegmentada<T>> opcoes;
  final T? valor;
  final ValueChanged<T>? aoEscolher;
  final double larguraParaLinha;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, limites) {
        final emLinha = limites.maxWidth >= larguraParaLinha;
        final atual = valor;
        final botao = SegmentedButton<T>(
          direction: emLinha ? Axis.horizontal : Axis.vertical,
          emptySelectionAllowed: atual == null,
          selected: {?atual},
          segments: [
            for (final o in opcoes)
              ButtonSegment(
                value: o.valor,
                label: Text(o.rotulo),
                icon: o.icone == null ? null : Icon(o.icone),
                enabled: o.habilitada,
              ),
          ],
          onSelectionChanged: aoEscolher == null
              ? null
              : (s) {
                  if (s.isNotEmpty && s.first != atual) aoEscolher!(s.first);
                },
        );
        return emLinha
            ? Align(alignment: AlignmentDirectional.centerStart, child: botao)
            : SizedBox(width: double.infinity, child: botao);
      });
}

class _DialogoDeExportacao extends StatefulWidget {
  const _DialogoDeExportacao({required this.equipe, required this.alterada, required this.casa});

  final EquipeResumo equipe;
  final bool alterada;
  final String casa;

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
          Text('O modelo leva a equipe, os workflows e as skills da ${widget.casa} que ela usa. '
              'Orçamentos, diretórios, memória e conversas nunca saem.'),
          if (widget.alterada) ...[
            const SizedBox(height: Espacos.esp3),
            const CaixaDeMensagens(
              tom: TomDaMensagem.aviso,
              linhas: ['As mudanças ainda não salvas desta equipe não entram.'],
            ),
          ],
          const SizedBox(height: Espacos.esp2),
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
            body: SafeArea(child: previa == null ? _carregando(context) : _Previa(sala: widget.sala, previa: previa)),
            bottomNavigationBar: _Rodape(estado: _e),
          );
        },
      );

  Widget _carregando(BuildContext context) {
    final tema = Theme.of(context);
    final erro = _e.erro;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (erro == null)
              const CircularProgressIndicator()
            else
              Icon(Symbols.error, color: tema.colorScheme.error),
            const SizedBox(height: Espacos.esp4),
            Text(erro ?? 'Lendo o modelo ${_e.arquivo ?? ''}…', textAlign: TextAlign.center, style: tema.textTheme.bodyMedium),
          ]),
        ),
      ),
    );
  }
}

class _Rodape extends StatelessWidget {
  const _Rodape({required this.estado});

  final EstadoImportacao estado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
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
          padding: const EdgeInsets.symmetric(horizontal: Espacos.esp4, vertical: Espacos.esp3),
          child: LayoutBuilder(builder: (context, limites) {
            final aviso = Row(children: [
              if (estado.importando || estado.pendente)
                const Padding(
                  padding: EdgeInsets.only(right: Espacos.esp3),
                  child: SizedBox.square(dimension: Espacos.esp4, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              Expanded(
                child: Text(situacao, style: tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant)),
              ),
            ]);
            final botoes = Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                onPressed: estado.importando ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: Espacos.esp2),
              FilledButton.icon(
                onPressed: estado.podeImportar ? estado.importar : null,
                icon: const Icon(Symbols.download_done),
                label: const Text('Importar'),
              ),
            ]);
            if (ClasseDeJanela.de(limites.maxWidth) != ClasseDeJanela.compact) {
              return Row(children: [Expanded(child: aviso), const SizedBox(width: Espacos.esp3), botoes]);
            }
            final ocupado = situacao.isNotEmpty || estado.importando || estado.pendente;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (ocupado) ...[aviso, const SizedBox(height: Espacos.esp2)],
              Align(alignment: AlignmentDirectional.centerEnd, child: botoes),
            ]);
          }),
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
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final resumo = previa.resumo;
    final habilitado = !_e.importando;
    final escolhas = _e.escolhas;
    final destino = sala.equipes.equipes.where((e) => e.id == _e.destino).firstOrNull;
    final soltos = previa.errosSoltos;
    return LayoutBuilder(builder: (context, limites) {
      final margem = math.max(
        ClasseDeJanela.de(limites.maxWidth).margemLateral,
        (limites.maxWidth - larguraDeLeitura) / 2,
      );
      return ListView(padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, margem, Espacos.esp6), children: [
        if (resumo != null) _Cabecalho(resumo: resumo, arquivo: _e.arquivo, destino: destino?.nome ?? _e.destino),
        if (resumo != null && !resumo.deWorkflow) ...[
          const _Titulo('Equipe'),
          _Campo(
            key: const ValueKey('equipe-id'),
            rotulo: 'Id',
            inicial: escolhas.equipeId ?? '',
            dica: previa.escolhas.equipeId,
            ajuda: 'nome da pasta da equipe; não muda depois',
            validar: erroDeId,
            erroDoServidor: errosDoCampo(previa.erros, const [prefixoDaEquipe]).firstOrNull,
            habilitado: habilitado,
            aoMudar: (v) => _e.mudar(_e.escolhas.comEquipe(id: v), digitando: true),
          ),
          const SizedBox(height: Espacos.esp3),
          _Campo(
            key: const ValueKey('equipe-nome'),
            rotulo: 'Nome',
            inicial: escolhas.equipeNome ?? '',
            dica: previa.escolhas.equipeNome,
            habilitado: habilitado,
            aoMudar: (v) => _e.mudar(_e.escolhas.comEquipe(nome: v), digitando: true),
          ),
        ],
        if (resumo != null && resumo.deWorkflow) ...[
          const _Titulo('Workflow'),
          _Campo(
            key: const ValueKey('workflow-id'),
            rotulo: 'Id',
            inicial: escolhas.workflowId ?? '',
            dica: previa.escolhas.workflowId,
            ajuda: 'nome do arquivo do workflow; as rotinas apontam para ele',
            validar: erroDeId,
            erroDoServidor: errosDoCampo(previa.erros, const [prefixoDoWorkflow]).firstOrNull,
            habilitado: habilitado,
            aoMudar: (v) => _e.mudar(_e.escolhas.comWorkflow(v), digitando: true),
          ),
        ],
        if (previa.personas.isNotEmpty) ...[
          const _Titulo('Personas'),
          for (final p in previa.personas)
            _LinhaDaPersona(
              estado: _e,
              persona: p,
              erros: errosDoCampo(previa.erros, prefixosDaPersona(p)),
              habilitado: habilitado,
            ),
        ],
        if (previa.skillsEmColisao.isNotEmpty) ...[
          const _Titulo('Skills com conteúdo diferente daqui'),
          for (final id in previa.skillsEmColisao)
            _LinhaDaSkill(
              estado: _e,
              id: id,
              erros: errosDoCampo(previa.erros, [prefixoDaSkill(id)]),
              habilitado: habilitado,
            ),
        ],
        if (resumo != null && resumo.deWorkflow && previa.posicoes.isNotEmpty) ...[
          _Titulo('Posições na equipe ${destino?.nome ?? _e.destino ?? ''}'),
          for (final p in previa.posicoes)
            _LinhaDaPosicao(
              estado: _e,
              posicao: p,
              destino: destino?.posicoes ?? const [],
              erros: errosDoCampo(previa.erros, [prefixoDaPosicao(p)]),
              habilitado: habilitado,
            ),
        ],
        if (previa.entra.isNotEmpty) ...[
          const _Titulo('O que entra'),
          for (final linha in previa.entra)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Espacos.esp1),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Symbols.add, size: 20, color: cores.primary),
                const SizedBox(width: Espacos.esp2),
                Expanded(child: Text(linha, style: tema.textTheme.bodyMedium)),
              ]),
            ),
        ],
        if (previa.avisos.isNotEmpty) ...[
          const _Titulo('Avisos'),
          CaixaDeMensagens(tom: TomDaMensagem.aviso, linhas: previa.avisos),
        ],
        if (soltos.isNotEmpty) ...[
          const _Titulo('Erros'),
          CaixaDeMensagens(tom: TomDaMensagem.erro, linhas: soltos),
        ],
        if (_e.erro != null) ...[
          const SizedBox(height: Espacos.esp3),
          CaixaDeMensagens(tom: TomDaMensagem.erro, linhas: [_e.erro!]),
        ],
      ]);
    });
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.resumo, this.arquivo, this.destino});

  final ResumoDoModelo resumo;
  final String? arquivo;
  final String? destino;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estilo = tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant, fontFeatures: _numeros);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(resumo.deWorkflow ? Symbols.schema : Symbols.account_tree, size: 20, color: tema.colorScheme.onSurfaceVariant),
            const SizedBox(width: Espacos.esp2),
            Expanded(child: Text(resumo.nome, style: tema.textTheme.titleMedium)),
          ]),
          const SizedBox(height: Espacos.esp1),
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
        padding: const EdgeInsets.only(top: Espacos.esp5, bottom: Espacos.esp2),
        child: Text(texto, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Consequencia extends StatelessWidget {
  const _Consequencia({required this.icone, required this.texto, this.cor});

  final IconData icone;
  final String texto;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final efetiva = cor ?? tema.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: Espacos.esp2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 16, color: efetiva),
        const SizedBox(width: Espacos.esp1),
        Expanded(child: Text(texto, style: tema.textTheme.bodySmall?.copyWith(color: efetiva))),
      ]),
    );
  }
}

class _CartaoDeEscolha extends StatelessWidget {
  const _CartaoDeEscolha({required this.identidade, required this.escolha, this.depois = const []});

  final Widget identidade;
  final Widget escolha;
  final List<Widget> depois;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Espacos.esp3),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Espacos.esp4),
            child: LayoutBuilder(builder: (context, limites) {
              final lado = limites.maxWidth >= _larguraParaLado;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (lado)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: identidade),
                    const SizedBox(width: Espacos.esp4),
                    SizedBox(width: _larguraDaEscolha, child: escolha),
                  ])
                else ...[
                  identidade,
                  const SizedBox(height: Espacos.esp3),
                  escolha,
                ],
                ...depois,
              ]);
            }),
          ),
        ),
      );
}

List<Widget> _errosDaLinha(BuildContext context, List<String> erros) => [
      for (final e in erros) _Consequencia(icone: Symbols.error, texto: e, cor: Theme.of(context).colorScheme.error),
    ];

class _LinhaDaPersona extends StatelessWidget {
  const _LinhaDaPersona({required this.estado, required this.persona, required this.erros, required this.habilitado});

  final EstadoImportacao estado;
  final PersonaDoModelo persona;
  final List<String> erros;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
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
    final consequencia = switch (opcao) {
      OpcaoDePersona.daqui => (Symbols.person, 'Usa a persona ${persona.nome} que já existe aqui.', null),
      OpcaoDePersona.outra => (
          Symbols.swap_horiz,
          'Usa ${escolhida == null ? 'outra persona' : Perfil.porChave(escolhida).nome} no lugar de ${persona.nome}.',
          null,
        ),
      OpcaoDePersona.criar => (Symbols.person_add, 'Cria a persona ${persona.nome} com o perfil do modelo.', null),
      OpcaoDePersona.criarComNome => (Symbols.person_add, 'Cria uma persona nova com o perfil do modelo e o nome abaixo.', null),
      OpcaoDePersona.vaga => (Symbols.person_off, 'As posições de ${persona.nome} ficam vagas.', CoresSemanticas.de(context).aviso.cor),
      null => (Symbols.help, 'Escolha o que fazer com ${persona.nome}.', null),
    };
    return _CartaoDeEscolha(
      identidade: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(persona.nome, style: tema.textTheme.titleSmall),
        Text(
          persona.traz ? persona.id : '${persona.id} · o modelo não traz o perfil',
          style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant),
        ),
        _Consequencia(icone: consequencia.$1, texto: consequencia.$2, cor: consequencia.$3),
      ]),
      escolha: EscolhaSegmentada<OpcaoDePersona>(
        larguraParaLinha: double.infinity,
        valor: opcao,
        aoEscolher: !habilitado
            ? null
            : (o) => estado.mudar(estado.escolhas.comOpcaoDePersona(
                  persona.id,
                  o,
                  nomeNoModelo: persona.nome,
                  personasDaqui: daqui,
                )),
        opcoes: [
          for (final o in OpcaoDePersona.values)
            (valor: o, rotulo: rotulosDeOpcaoDePersona[o]!, icone: null, habilitada: disponivel(o)),
        ],
      ),
      depois: [
        if (opcao == OpcaoDePersona.outra) ...[
          const SizedBox(height: Espacos.esp3),
          DropdownButtonFormField<String>(
            initialValue: escolhida,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Persona daqui'),
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
        ],
        if (opcao == OpcaoDePersona.criarComNome) ...[
          const SizedBox(height: Espacos.esp3),
          _Campo(
            key: ValueKey('persona-nome-${persona.id}'),
            rotulo: 'Nome da persona nova',
            inicial: acao?.nome ?? '',
            ajuda: 'o id sai do nome',
            habilitado: habilitado,
            aoMudar: (v) => estado.mudar(estado.escolhas.comNomeDePersona(persona.id, v), digitando: true),
          ),
        ],
        ..._errosDaLinha(context, erros),
      ],
    );
  }
}

class _LinhaDaSkill extends StatelessWidget {
  const _LinhaDaSkill({required this.estado, required this.id, required this.erros, required this.habilitado});

  final EstadoImportacao estado;
  final String id;
  final List<String> erros;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acao = estado.escolhas.skills[id];
    final opcao = acao?.opcao ?? OpcaoDeSkill.daqui;
    return _CartaoDeEscolha(
      identidade: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Symbols.extension, size: 20, color: tema.colorScheme.onSurfaceVariant),
          const SizedBox(width: Espacos.esp2),
          Expanded(child: Text(id, style: tema.textTheme.titleSmall?.copyWith(fontFamily: familiaMono))),
        ]),
        _Consequencia(
          icone: Symbols.warning,
          texto: 'O conteúdo no modelo é diferente da skill $id daqui.',
          cor: CoresSemanticas.de(context).aviso.cor,
        ),
        _Consequencia(
          icone: opcao == OpcaoDeSkill.daqui ? Symbols.extension : Symbols.add,
          texto: opcao == OpcaoDeSkill.daqui
              ? 'A equipe usa a skill daqui, e a do modelo não entra.'
              : 'A skill do modelo entra com outro id, ao lado da daqui.',
        ),
      ]),
      escolha: EscolhaSegmentada<OpcaoDeSkill>(
        larguraParaLinha: _larguraDaEscolhaDeSkillEmLinha,
        valor: opcao,
        aoEscolher: !habilitado ? null : (o) => estado.mudar(estado.escolhas.comOpcaoDeSkill(id, o)),
        opcoes: [
          for (final o in OpcaoDeSkill.values) (valor: o, rotulo: rotulosDeOpcaoDeSkill[o]!, icone: null, habilitada: true),
        ],
      ),
      depois: [
        if (acao?.opcao == OpcaoDeSkill.importar) ...[
          const SizedBox(height: Espacos.esp3),
          _Campo(
            key: ValueKey('skill-id-$id'),
            rotulo: 'Id da skill importada',
            inicial: acao?.id ?? '',
            validar: (v) => erroDeId(v, maximo: 64),
            erroDoServidor: erros.firstOrNull,
            habilitado: habilitado,
            aoMudar: (v) => estado.mudar(estado.escolhas.comIdDeSkill(id, v), digitando: true),
          ),
        ] else
          ..._errosDaLinha(context, erros),
      ],
    );
  }
}

class _LinhaDaPosicao extends StatelessWidget {
  const _LinhaDaPosicao({
    required this.estado,
    required this.posicao,
    required this.destino,
    required this.erros,
    required this.habilitado,
  });

  final EstadoImportacao estado;
  final PosicaoDoModelo posicao;
  final List<PosicaoResumo> destino;
  final List<String> erros;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final alvo = estado.escolhas.posicoes[posicao.id];
    final ids = {for (final p in destino) p.id};
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacos.esp3),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Espacos.esp4),
          child: Wrap(
            spacing: Espacos.esp4,
            runSpacing: Espacos.esp3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: _larguraDaIdentidade,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(posicao.titulo, style: tema.textTheme.titleSmall),
                  Text(posicao.id, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
                ]),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _larguraDaEscolha + _larguraDaIdentidade),
                child: DropdownButtonFormField<String?>(
                  initialValue: alvo,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Posição da equipe',
                    errorText: erros.isEmpty ? null : erros.join('\n'),
                    errorMaxLines: 3,
                  ),
                  onChanged: !habilitado
                      ? null
                      : (p) {
                          if (p != alvo) estado.mudar(estado.escolhas.comPosicao(posicao.id, p));
                        },
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('sem ligação')),
                    for (final p in destino) DropdownMenuItem<String?>(value: p.id, child: Text('${p.titulo} (${p.id})')),
                    if (alvo != null && !ids.contains(alvo))
                      DropdownMenuItem<String?>(value: alvo, child: Text('$alvo (não existe)')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
    this.ajuda,
    this.validar,
    this.erroDoServidor,
    this.habilitado = true,
  });

  final String rotulo;
  final String inicial;
  final String? dica;
  final String? ajuda;
  final String? Function(String)? validar;
  final String? erroDoServidor;
  final bool habilitado;
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
  Widget build(BuildContext context) {
    final texto = _controle.text;
    final local = texto.isEmpty && widget.dica != null ? null : widget.validar?.call(texto);
    return TextField(
      controller: _controle,
      enabled: widget.habilitado,
      decoration: InputDecoration(
        labelText: widget.rotulo,
        hintText: widget.dica,
        helperText: widget.ajuda,
        errorText: local ?? widget.erroDoServidor,
        errorMaxLines: 3,
      ),
      onChanged: (v) {
        setState(() {});
        widget.aoMudar(v);
      },
    );
  }
}
