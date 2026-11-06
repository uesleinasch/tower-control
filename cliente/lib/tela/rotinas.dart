import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../conexao/http.dart';
import '../estado/rotinas.dart';
import '../estado/sala.dart';
import '../nucleo/design.dart';
import '../nucleo/enderecos.dart';
import '../nucleo/formato.dart';
import '../nucleo/rotinas.dart';
import '../nucleo/tarefas.dart';
import '../nucleo/workflows.dart';
import 'comum.dart' show copiar;
import 'equipes.dart' show confirmar;
import 'importacao.dart' show CaixaDeMensagens, EscolhaSegmentada, TomDaMensagem;
import 'paineis.dart';
import 'tema.dart';

const _larguraDoEditor = 420.0;
const _larguraDoCampoCurto = 112.0;
const _larguraDoDiaDaSemana = 180.0;
const _larguraParaSegmentosEmLinha = 360.0;
const _numeros = [FontFeature.tabularFigures()];

const _rotulosDeConcorrencia = {'pular': 'Pular', 'enfileirar': 'Enfileirar', 'substituir': 'Substituir'};
const _explicacoesDeConcorrencia = {
  'pular': 'Não cria a nova se a anterior ainda está aberta.',
  'enfileirar': 'A nova espera a anterior terminar.',
  'substituir': 'Cancela a anterior e cria a nova.',
};
const _rotulosDePerdidos = {'um': 'Disparar uma vez', 'ignorar': 'Ignorar'};
const _explicacoesDePerdidos = {
  'um': 'Dispara uma vez ao voltar, mesmo que tenha perdido vários horários.',
  'ignorar': 'Ignora os horários perdidos e espera o próximo.',
};

Future<void> _excluirRotina(BuildContext context, EstadoRotinas estado, Rotina r) async {
  final ok = await confirmar(
    context,
    'Excluir a rotina ${r.nome.isEmpty ? r.id : r.nome}?',
    'Os disparos já feitos ficam no histórico. As tarefas criadas por ela continuam.',
    acao: 'Excluir rotina',
    destrutivo: true,
  );
  if (!ok) return;
  if (estado.rascunho?.id != r.id || estado.equipeDoRascunho != r.equipe) estado.editar(r);
  estado.excluir();
}

class PainelDeRotinas extends StatelessWidget {
  const PainelDeRotinas({super.key, required this.sala, required this.equipe, required this.editar, required this.largo});

  final Sala sala;
  final EquipeResumo equipe;
  final bool editar;
  final bool largo;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([sala.rotinas, sala.workflows]),
        builder: (context, _) {
          final estado = sala.rotinas;
          final lista = _ListaDeRotinas(sala: sala, equipe: equipe, editar: editar);
          final editando = editar && estado.rascunho != null && estado.equipeDoRascunho == equipe.id;
          if (!editando) return lista;
          final editor = _EditorDeRotina(
            key: ValueKey('${equipe.id}/${estado.nova ? '+' : estado.rascunho!.id}'),
            sala: sala,
            equipe: equipe,
          );
          if (!largo) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: larguraDeLeitura), child: editor),
            );
          }
          return LadoALado(
            painel: 'rotinas',
            rotulo: 'Largura do editor de rotina',
            inicial: _larguraDoEditor,
            minimo: 360,
            maximo: 640,
            lateralADireita: true,
            principal: lista,
            lateral: Material(color: Theme.of(context).colorScheme.surfaceContainer, child: editor),
          );
        },
      );
}

class _TituloDeSecao extends StatelessWidget {
  const _TituloDeSecao(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Espacos.esp5, bottom: Espacos.esp2),
        child: Text(texto, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _ListaDeRotinas extends StatelessWidget {
  const _ListaDeRotinas({required this.sala, required this.equipe, required this.editar});

  final Sala sala;
  final EquipeResumo equipe;
  final bool editar;

  @override
  Widget build(BuildContext context) {
    final estado = sala.rotinas;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final daEquipe = estado.daEquipe(equipe.id);
    final sistema = equipe.id == 'casa' ? estado.doSistema : const <Rotina>[];
    final equipeSalva = sala.equipes.equipes.any((e) => e.id == equipe.id);
    final podeCriar = equipeSalva && !estado.salvando;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    return LayoutBuilder(builder: (context, limites) {
      final margem = ClasseDeJanela.de(limites.maxWidth).margemLateral;
      return ListView(padding: EdgeInsets.fromLTRB(margem, Espacos.esp4, margem, Espacos.esp5), children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rotinas de ${equipe.nome}', style: tema.textTheme.titleMedium),
              Text('Tarefas e workflows que a equipe começa sozinha, por horário ou por webhook', style: secundario),
            ]),
          ),
          const SizedBox(width: Espacos.esp3),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Espacos.esp2,
              runSpacing: Espacos.esp2,
              children: [
                if (editar)
                  FilledButton.icon(
                    onPressed: podeCriar ? () => estado.novaRotina(equipe) : null,
                    icon: const Icon(Symbols.add),
                    label: const Text('Nova rotina'),
                  ),
                IconButton(tooltip: 'Recarregar', icon: const Icon(Symbols.refresh), onPressed: estado.carregar),
              ],
            ),
          ),
        ]),
        if (editar && !equipeSalva)
          Padding(
            padding: const EdgeInsets.only(top: Espacos.esp2),
            child: Text('Salve a equipe antes de criar rotinas.', style: secundario),
          ),
        const SizedBox(height: Espacos.esp4),
        if (!estado.carregada)
          const Padding(padding: EdgeInsets.all(Espacos.esp5), child: Center(child: CircularProgressIndicator()))
        else if (daEquipe.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Espacos.esp7, horizontal: Espacos.esp4),
            child: Column(children: [
              Icon(Symbols.event_repeat, color: cores.onSurfaceVariant),
              const SizedBox(height: Espacos.esp2),
              Text(
                editar ? 'Nenhuma rotina nesta equipe.' : 'Nenhuma rotina nesta equipe. Rotinas se criam no desktop.',
                textAlign: TextAlign.center,
                style: tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant),
              ),
              if (editar && podeCriar) ...[
                const SizedBox(height: Espacos.esp3),
                FilledButton.tonalIcon(
                  onPressed: () => estado.novaRotina(equipe),
                  icon: const Icon(Symbols.add),
                  label: const Text('Nova rotina'),
                ),
              ],
            ]),
          ),
        for (final r in daEquipe)
          Padding(
            padding: const EdgeInsets.only(bottom: Espacos.esp3),
            child: _CartaoDaRotina(
              sala: sala,
              equipe: equipe,
              rotina: r,
              editar: editar,
              selecionada: estado.rascunho?.id == r.id && estado.equipeDoRascunho == equipe.id && !estado.nova,
            ),
          ),
        if (sistema.isNotEmpty) ...[
          const _TituloDeSecao('Rotinas do sistema'),
          for (final r in sistema)
            Padding(
              padding: const EdgeInsets.only(bottom: Espacos.esp3),
              child: _CartaoDaRotina(sala: sala, equipe: equipe, rotina: r, editar: false, selecionada: false),
            ),
        ],
      ]);
    });
  }
}

class _SituacaoDaRotina extends StatelessWidget {
  const _SituacaoDaRotina({required this.rotina});

  final Rotina rotina;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final (icone, rotulo, cor) = rotina.sistema
        ? (Symbols.settings, 'sistema', cores.onSurfaceVariant)
        : rotina.ativa
            ? (Symbols.play_circle, 'ativa', cores.primary)
            : (Symbols.pause_circle, 'inativa', cores.onSurfaceVariant);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icone, size: 16, color: cor),
      const SizedBox(width: Espacos.esp1),
      Text(rotulo, style: tema.textTheme.labelMedium?.copyWith(color: cor)),
    ]);
  }
}

class _ResultadoDoDisparo extends StatelessWidget {
  const _ResultadoDoDisparo({required this.resultado, required this.texto});

  final String resultado;
  final String texto;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
        style: const TextStyle(fontFeatures: _numeros),
        child: RotuloDeEstado(estado: resultado, rotulo: texto),
      );
}

class _CartaoDaRotina extends StatefulWidget {
  const _CartaoDaRotina({
    required this.sala,
    required this.equipe,
    required this.rotina,
    required this.editar,
    required this.selecionada,
  });

  final Sala sala;
  final EquipeResumo equipe;
  final Rotina rotina;
  final bool editar;
  final bool selecionada;

  @override
  State<_CartaoDaRotina> createState() => _CartaoDaRotinaState();
}

class _CartaoDaRotinaState extends State<_CartaoDaRotina> {
  final _menu = MenuController();
  final _ancora = GlobalKey();

  void _abrirTarefa(int id) {
    widget.sala.tarefas.escolherEquipe(widget.equipe.id);
    widget.sala.abrirTarefa(id);
  }

  void _abrirMenu(BuildContext botao) {
    final origem = botao.findRenderObject();
    final cartao = _ancora.currentContext?.findRenderObject();
    if (origem is! RenderBox || cartao is! RenderBox) return _menu.open();
    _menu.open(position: origem.localToGlobal(Offset(0, origem.size.height), ancestor: cartao));
  }

  @override
  Widget build(BuildContext context) {
    final sala = widget.sala;
    final estado = sala.rotinas;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final r = widget.rotina;
    final nome = r.nome.isEmpty ? r.id : r.nome;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant, fontFeatures: _numeros);
    final posicao = r.sistema ? null : widget.equipe.posicao(r.posicao);
    final ultimo = r.ultimoDisparo;
    final comMenu = widget.editar && !r.sistema;
    final menu = [
      MenuItemButton(
        leadingIcon: const Icon(Symbols.edit),
        onPressed: () => estado.editar(r),
        child: const Text('Editar'),
      ),
      MenuItemButton(
        leadingIcon: Icon(r.ativa ? Symbols.pause_circle : Symbols.play_circle),
        onPressed: () => estado.alternarAtiva(r),
        child: Text(r.ativa ? 'Desativar' : 'Ativar'),
      ),
      MenuItemButton(
        leadingIcon: Icon(Symbols.delete, color: cores.error),
        style: MenuItemButton.styleFrom(foregroundColor: cores.error),
        onPressed: estado.salvando ? null : () => _excluirRotina(context, estado, r),
        child: const Text('Excluir rotina'),
      ),
    ];
    return MenuAnchor(
      controller: _menu,
      menuChildren: comMenu ? menu : const [],
      child: GestureDetector(
        key: _ancora,
        onSecondaryTapUp: comMenu ? (d) => _menu.open(position: d.localPosition) : null,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          color: widget.selecionada ? cores.secondaryContainer : null,
          child: InkWell(
            onTap: comMenu ? () => estado.editar(r) : null,
            child: Padding(
              padding: const EdgeInsets.all(Espacos.esp4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(r.sistema ? Symbols.settings : Symbols.event_repeat, size: 20, color: cores.onSurfaceVariant),
                  const SizedBox(width: Espacos.esp2),
                  Expanded(child: Text(nome, style: tema.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: Espacos.esp2),
                  _SituacaoDaRotina(rotina: r),
                  if (comMenu)
                    Builder(
                      builder: (botao) => IconButton(
                        tooltip: 'Mais opções de $nome',
                        onPressed: () => _menu.isOpen ? _menu.close() : _abrirMenu(botao),
                        icon: const Icon(Symbols.more_vert),
                      ),
                    ),
                ]),
                const SizedBox(height: Espacos.esp1),
                Text(
                  [
                    if (r.iniciaWorkflow)
                      'inicia ${sala.workflows.nomeDoWorkflow(widget.equipe.id, r.workflow)}'
                    else if (posicao != null)
                      posicao.rotulo
                    else if (!r.sistema)
                      '${r.posicao} (sumiu)',
                    descricaoDoGatilho(r),
                  ].join(' · '),
                  style: secundario,
                ),
                Text('próximo: ${r.proximo == null ? 'sem horário' : horarioCurto(r.proximo!)}', style: secundario),
                const SizedBox(height: Espacos.esp2),
                if (ultimo != null)
                  _ResultadoDoDisparo(resultado: ultimo.resultado, texto: 'último: ${quando(ultimo.em)} · ${ultimo.resumo}')
                else
                  Text('nunca disparou', style: secundario),
                if (!r.sistema) ...[
                  const SizedBox(height: Espacos.esp3),
                  Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: [
                    FilledButton.tonalIcon(
                      onPressed: () => estado.disparar(r),
                      icon: const Icon(Symbols.play_arrow),
                      label: const Text('Disparar agora'),
                    ),
                    if (comMenu)
                      OutlinedButton.icon(
                        onPressed: () => estado.editar(r),
                        icon: const Icon(Symbols.edit),
                        label: const Text('Editar'),
                      ),
                    TextButton.icon(
                      onPressed: () => estado.alternarAtiva(r),
                      icon: Icon(r.ativa ? Symbols.pause_circle : Symbols.play_circle),
                      label: Text(r.ativa ? 'Desativar' : 'Ativar'),
                    ),
                  ]),
                ],
                if (r.disparos.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(
                      'Últimos disparos (${r.disparos.length})',
                      style: tema.textTheme.titleSmall?.copyWith(fontFeatures: _numeros),
                    ),
                    children: [
                      for (final d in r.disparos)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: _ResultadoDoDisparo(resultado: d.resultado, texto: '${horarioCurto(d.em)} · ${d.resumo}'),
                          trailing: d.tarefa == null
                              ? null
                              : Icon(Symbols.open_in_new, size: 20, color: cores.onSurfaceVariant),
                          onTap: d.tarefa == null ? null : () => _abrirTarefa(d.tarefa!),
                        ),
                    ],
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorDeRotina extends StatefulWidget {
  const _EditorDeRotina({super.key, required this.sala, required this.equipe});

  final Sala sala;
  final EquipeResumo equipe;

  @override
  State<_EditorDeRotina> createState() => _EditorDeRotinaState();
}

class _EditorDeRotinaState extends State<_EditorDeRotina> {
  EstadoRotinas get estado => widget.sala.rotinas;
  Rotina get r => estado.rascunho!;

  late final _nome = TextEditingController(text: r.nome);
  late final _titulo = TextEditingController(text: r.titulo);
  late final _descricao = TextEditingController(text: r.descricao);
  late final _porque = TextEditingController(text: r.porque);
  late final _cron = TextEditingController(text: r.cron);
  final _hora = TextEditingController(text: '08:30');
  final _horas = TextEditingController(text: '4');
  var _dia = 1;
  String? _endereco;
  final _tocados = <CampoDaRotina>{};
  var _mostrarTudo = false;

  @override
  void initState() {
    super.initState();
    _resolverEndereco();
  }

  Future<void> _resolverEndereco() async {
    final local = widget.sala.canal.endereco;
    if (local == null) return;
    final resposta = await sondar(local);
    final lan = resposta == null ? const <String>[] : enderecosDaResposta(resposta);
    if (mounted) setState(() => _endereco = lan.firstOrNull ?? local);
  }

  @override
  void dispose() {
    for (final c in [_nome, _titulo, _descricao, _porque, _cron, _hora, _horas]) {
      c.dispose();
    }
    super.dispose();
  }

  void _usarCron(String cron) {
    _cron.text = cron;
    estado.mudar((x) => x.copiar(cron: cron));
  }

  void _atalho(String Function(int hora, int minuto) montar) {
    final hm = lerHoraMinuto(_hora.text);
    if (hm == null) return;
    _usarCron(montar(hm.hora, hm.minuto));
  }

  int? get _horasDoAtalho {
    final n = int.tryParse(_horas.text.trim());
    return n != null && n >= 1 && n <= 23 ? n : null;
  }

  String? _erroAoSair(Map<CampoDaRotina, String> erros, CampoDaRotina campo) =>
      _mostrarTudo || _tocados.contains(campo) ? erros[campo] : null;

  Widget _validaAoSair(CampoDaRotina campo, Widget campoDeTexto) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focado) {
          if (!focado && !_tocados.contains(campo)) setState(() => _tocados.add(campo));
        },
        child: campoDeTexto,
      );

  void _salvar(List<Workflow> definicoes) {
    if (estado.errosDoRascunho(widget.equipe, workflows: definicoes).isNotEmpty) {
      setState(() => _mostrarTudo = true);
      return;
    }
    estado.salvar(widget.equipe, workflows: definicoes);
  }

  Widget _webhook(BuildContext context, Rotina? salva) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final token = salva?.token;
    final caminho = salva?.url;
    if (!r.webhook) return const SizedBox.shrink();
    if (salva?.webhook != true || token == null || caminho == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Espacos.esp2),
        child: Text('Salve para gerar a URL e o token.', style: secundario),
      );
    }
    final url = urlDoWebhook(_endereco ?? widget.sala.canal.endereco ?? 'host:7878', caminho);
    final mono = tema.textTheme.bodySmall?.copyWith(fontFamily: familiaMono);
    Widget linha(String rotulo, String valor, String dica) => Padding(
          padding: const EdgeInsets.only(bottom: Espacos.esp2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rotulo, style: secundario),
                SelectableText(valor, style: mono),
              ]),
            ),
            IconButton(tooltip: dica, icon: const Icon(Symbols.content_copy, size: 20), onPressed: () => copiar(context, valor)),
          ]),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: cores.outlineVariant),
        borderRadius: BorderRadius.circular(Raios.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Espacos.esp3, Espacos.esp3, Espacos.esp1, Espacos.esp1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          linha('URL (POST)', url, 'Copiar URL'),
          linha('Token (cabeçalho X-Token ou ?token=)', token, 'Copiar token'),
          linha('Exemplo', curlDoWebhook(url, token), 'Copiar exemplo'),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(onPressed: estado.trocarToken, icon: const Icon(Symbols.autorenew), label: const Text('Trocar token')),
          ),
        ]),
      ),
    );
  }

  Widget _politica(BuildContext context, String rotulo, Widget escolha, String? explicacao) {
    final tema = Theme.of(context);
    final secundario = tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacos.esp4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rotulo, style: tema.textTheme.bodyMedium),
        const SizedBox(height: Espacos.esp2),
        escolha,
        if (explicacao != null) ...[
          const SizedBox(height: Espacos.esp1),
          Text(explicacao, style: secundario),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final equipe = widget.equipe;
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final rotina = r;
    final salva = estado.salva(equipe.id, rotina.id);
    final definicoes = widget.sala.workflows.definicoes;
    final erros = errosDosCamposDaRotina(rotina, equipe, workflows: definicoes);
    final soltos = [
      for (final c in const [CampoDaRotina.id, CampoDaRotina.concorrencia, CampoDaRotina.perdidos]) ?erros[c],
    ];
    final possiveis = workflowsParaRotina(definicoes, equipe.id);
    final porWorkflow = rotina.iniciaWorkflow;
    final escolhido = definicoes.where((w) => w.equipe == equipe.id && w.id == rotina.workflow).firstOrNull;
    final agora = DateTime.now();
    final proximos = rotina.cron.trim().isEmpty ? const <DateTime>[] : proximosDoCron(rotina.cron, agora);
    final previa = tituloDaTarefa(rotina.titulo, proximos.firstOrNull ?? agora);
    final proximas = previaDoCron(rotina.cron, agora);
    final posicaoValida = equipe.posicao(rotina.posicao) != null;
    final concorrencia = concorrencias.containsKey(rotina.concorrencia) ? rotina.concorrencia : 'pular';
    final perdidos = perdidosDaRotina.containsKey(rotina.perdidos) ? rotina.perdidos : 'um';
    final horaInvalida = lerHoraMinuto(_hora.text) == null;
    final horasInvalidas = _horasDoAtalho == null;

    return ListView(padding: const EdgeInsets.all(Espacos.esp4), children: [
      Row(children: [
        Expanded(
          child: Text(
            estado.nova ? 'Nova rotina' : 'Rotina ${rotina.id}',
            style: tema.textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(tooltip: 'Fechar', icon: const Icon(Symbols.close), onPressed: estado.fecharEditor),
      ]),
      if (estado.erro != null)
        Padding(
          padding: const EdgeInsets.only(top: Espacos.esp2),
          child: MaterialBanner(
            leading: Icon(Symbols.error, color: cores.onErrorContainer),
            content: Text(estado.erro!, style: tema.textTheme.bodyMedium?.copyWith(color: cores.onErrorContainer)),
            backgroundColor: cores.errorContainer,
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: cores.onErrorContainer),
                onPressed: estado.limparErro,
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
      const SizedBox(height: Espacos.esp3),
      _validaAoSair(
        CampoDaRotina.nome,
        TextField(
          controller: _nome,
          decoration: InputDecoration(
            labelText: 'Nome',
            helperText: 'id: ${rotina.id}${estado.nova ? ' (fixo depois de salvar)' : ''}',
            errorText: _erroAoSair(erros, CampoDaRotina.nome),
          ),
          onChanged: (v) => estado.mudar((x) => x.copiar(nome: v)),
        ),
      ),
      const _TituloDeSecao('Destino'),
      EscolhaSegmentada<bool>(
        larguraParaLinha: _larguraParaSegmentosEmLinha,
        valor: porWorkflow,
        aoEscolher: (v) => estado.mudar((x) => x.copiar(workflow: v ? possiveis.first.id : '')),
        opcoes: [
          (valor: false, rotulo: 'Criar tarefa', icone: Symbols.task_alt, habilitada: true),
          (valor: true, rotulo: 'Iniciar workflow', icone: Symbols.schema, habilitada: porWorkflow || possiveis.isNotEmpty),
        ],
      ),
      if (!porWorkflow && possiveis.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: Espacos.esp1),
          child: Text(
            'Nenhum workflow desta equipe pode ser iniciado por rotina (a entrada precisa ser vazia ou só "dados" em texto).',
            style: secundario,
          ),
        ),
      const SizedBox(height: Espacos.esp4),
      if (porWorkflow)
        DropdownButtonFormField<String>(
          initialValue: escolhido?.id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Workflow',
            helperText: escolhido != null && escolhido.entrada.containsKey('dados')
                ? 'o corpo do webhook vai em entrada.dados'
                : null,
            errorText: erros[CampoDaRotina.workflow],
            errorMaxLines: 3,
          ),
          items: [
            for (final w in [...possiveis, if (escolhido != null && !possiveis.contains(escolhido)) escolhido])
              DropdownMenuItem(value: w.id, child: Text(w.nome, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => v == null ? null : estado.mudar((x) => x.copiar(workflow: v)),
        )
      else ...[
        DropdownButtonFormField<String>(
          initialValue: posicaoValida ? rotina.posicao : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Posição que recebe a tarefa',
            errorText: erros[CampoDaRotina.posicao],
          ),
          items: [for (final p in equipe.posicoes) DropdownMenuItem(value: p.id, child: Text(p.rotulo, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => v == null ? null : estado.mudar((x) => x.copiar(posicao: v)),
        ),
        const _TituloDeSecao('Tarefa'),
        _validaAoSair(
          CampoDaRotina.titulo,
          TextField(
            controller: _titulo,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: 'Título',
              helperText: rotina.titulo.trim().isEmpty ? 'aceita {data} e {hora}' : 'prévia: $previa',
              helperStyle: secundario?.copyWith(fontFeatures: _numeros),
              errorText: _erroAoSair(erros, CampoDaRotina.titulo),
              counterText: '',
            ),
            onChanged: (v) => estado.mudar((x) => x.copiar(titulo: v)),
          ),
        ),
        const SizedBox(height: Espacos.esp3),
        TextField(
          controller: _descricao,
          minLines: 2,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Descrição', alignLabelWithHint: true),
          onChanged: (v) => estado.mudar((x) => x.copiar(descricao: v)),
        ),
        const SizedBox(height: Espacos.esp3),
        TextField(
          controller: _porque,
          decoration: const InputDecoration(labelText: 'Por quê'),
          onChanged: (v) => estado.mudar((x) => x.copiar(porque: v)),
        ),
      ],
      const _TituloDeSecao('Gatilho'),
      Text('Atalhos para montar o cron', style: secundario),
      const SizedBox(height: Espacos.esp2),
      Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: _larguraDoCampoCurto,
          child: TextField(
            controller: _hora,
            style: const TextStyle(fontFeatures: _numeros),
            decoration: InputDecoration(labelText: 'às', errorText: horaInvalida ? 'use HH:MM' : null),
            onChanged: (_) => setState(() {}),
          ),
        ),
        ActionChip(label: const Text('todo dia'), onPressed: horaInvalida ? null : () => _atalho(cronTodoDia)),
        ActionChip(label: const Text('dias úteis'), onPressed: horaInvalida ? null : () => _atalho(cronDiasUteis)),
      ]),
      const SizedBox(height: Espacos.esp3),
      Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: _larguraDoDiaDaSemana,
          child: DropdownButtonFormField<int>(
            initialValue: _dia,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Dia da semana'),
            items: [for (final (i, d) in diasDaSemana.indexed) DropdownMenuItem(value: i, child: Text(d))],
            onChanged: (v) => setState(() => _dia = v ?? _dia),
          ),
        ),
        ActionChip(
          label: const Text('toda semana neste dia'),
          onPressed: horaInvalida ? null : () => _atalho((h, m) => cronSemanal(_dia, h, m)),
        ),
      ]),
      const SizedBox(height: Espacos.esp3),
      Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: _larguraDoCampoCurto,
          child: TextField(
            controller: _horas,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontFeatures: _numeros),
            decoration: InputDecoration(labelText: 'N horas', errorText: horasInvalidas ? 'de 1 a 23' : null),
            onChanged: (_) => setState(() {}),
          ),
        ),
        ActionChip(
          label: const Text('a cada N horas'),
          onPressed: horasInvalidas ? null : () => _usarCron(cronACadaHoras(_horasDoAtalho!)),
        ),
      ]),
      const SizedBox(height: Espacos.esp4),
      TextField(
        controller: _cron,
        style: const TextStyle(fontFamily: familiaMono, fontFeatures: _numeros),
        decoration: InputDecoration(
          labelText: 'Cron (minuto hora dia mês dia-da-semana)',
          helperText: proximas.isEmpty ? 'vazio: sem horário (só webhook ou manual)' : proximas,
          helperStyle: secundario?.copyWith(fontFeatures: _numeros),
          helperMaxLines: 2,
          errorText: erros[CampoDaRotina.cron],
          errorMaxLines: 3,
        ),
        onChanged: (v) => estado.mudar((x) => x.copiar(cron: v)),
      ),
      const SizedBox(height: Espacos.esp2),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: rotina.webhook,
        title: const Text('Webhook'),
        subtitle: const Text('aceita disparo por POST de fora'),
        onChanged: (v) => estado.mudar((x) => x.copiar(webhook: v ?? false)),
      ),
      if (webhookArriscado(rotina, equipe))
        const Padding(
          padding: EdgeInsets.only(bottom: Espacos.esp3),
          child: CaixaDeMensagens(
            tom: TomDaMensagem.aviso,
            linhas: [
              'Esta posição roda comandos no automático. O texto do webhook vem de fora '
                  'e entra na tarefa como dado; comando sensível ainda pede aprovação.',
            ],
          ),
        ),
      _webhook(context, salva),
      const _TituloDeSecao('Política'),
      _politica(
        context,
        porWorkflow ? 'Com o workflow anterior ainda aberto' : 'Com a tarefa anterior ainda aberta',
        EscolhaSegmentada<String>(
          larguraParaLinha: _larguraParaSegmentosEmLinha,
          valor: concorrencia,
          aoEscolher: (v) => estado.mudar((x) => x.copiar(concorrencia: v)),
          opcoes: [
            for (final c in concorrencias.keys)
              (valor: c, rotulo: _rotulosDeConcorrencia[c] ?? c, icone: null, habilitada: true),
          ],
        ),
        _explicacoesDeConcorrencia[concorrencia],
      ),
      _politica(
        context,
        'Horário perdido (servidor desligado)',
        EscolhaSegmentada<String>(
          larguraParaLinha: _larguraParaSegmentosEmLinha,
          valor: perdidos,
          aoEscolher: (v) => estado.mudar((x) => x.copiar(perdidos: v)),
          opcoes: [
            for (final p in perdidosDaRotina.keys)
              (valor: p, rotulo: _rotulosDePerdidos[p] ?? p, icone: null, habilitada: true),
          ],
        ),
        _explicacoesDePerdidos[perdidos],
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: rotina.ativa,
        title: const Text('Ativa'),
        onChanged: (v) => estado.mudar((x) => x.copiar(ativa: v ?? false)),
      ),
      if (soltos.isNotEmpty) ...[
        const SizedBox(height: Espacos.esp2),
        CaixaDeMensagens(tom: TomDaMensagem.erro, linhas: soltos),
      ],
      if (_mostrarTudo && erros.isNotEmpty) ...[
        const SizedBox(height: Espacos.esp2),
        Text('Corrija os campos marcados para salvar.', style: tema.textTheme.bodySmall?.copyWith(color: cores.error)),
      ],
      const SizedBox(height: Espacos.esp4),
      Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: [
        FilledButton.icon(
          onPressed: estado.salvando ? null : () => _salvar(definicoes),
          icon: const Icon(Symbols.save),
          label: Text(estado.salvando ? 'Salvando…' : 'Salvar'),
        ),
        if (!estado.nova)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cores.error, side: BorderSide(color: cores.error)),
            onPressed: estado.salvando ? null : () => _excluirRotina(context, estado, rotina),
            icon: const Icon(Symbols.delete),
            label: const Text('Excluir rotina'),
          ),
      ]),
    ]);
  }
}
