import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/personas.dart';
import '../estado/sala.dart';
import '../nucleo/design.dart';
import '../nucleo/modelos.dart';
import '../nucleo/organograma.dart';
import '../nucleo/painel.dart';
import '../nucleo/skills.dart';
import '../nucleo/tarefas.dart';
import 'comum.dart';
import 'equipes.dart' show pedirTexto;
import 'paineis.dart';
import 'skills.dart';
import 'tema.dart';

const _larguraDaLista = 360.0;
const _larguraDoConteudo = 880.0;
const _larguraDeDuasColunas = 640.0;
const _larguraDoCabecalhoEstreito = 560.0;
const _numeros = [FontFeature.tabularFigures()];

typedef _NovaPersona = ({String nome, String titulo, String base, String? modelo, String? cor});

const _coresSugeridas = [
  ('#e0a458', 'âmbar'),
  ('#9a6ee8', 'roxo'),
  ('#4fae7c', 'verde'),
  ('#e06a8a', 'rosa'),
  ('#58b7c9', 'ciano'),
  ('#c9a227', 'mostarda'),
  ('#5b8def', 'azul'),
  ('#d9774b', 'laranja'),
];

const _opcoesDeModelo = {'haiku': 'Haiku', 'sonnet': 'Sonnet', 'opus': 'Opus'};

Future<void> criarNovaPersona(BuildContext context, Sala sala) async {
  final dados = await showDialog<_NovaPersona>(context: context, builder: (_) => const _DialogoNovaPersona());
  if (dados == null) return;
  sala.equipes.criarPersona(nome: dados.nome, base: dados.base, titulo: dados.titulo, modelo: dados.modelo, cor: dados.cor);
}

Future<void> _editarOrcamento(BuildContext context, Sala sala, Perfil p) async {
  final limites = await showDialog<({double? usd, int? tokens})>(
    context: context,
    builder: (_) => _DialogoDeOrcamento(persona: p),
  );
  if (limites != null) sala.equipes.salvarOrcamento(p.chave, usd: limites.usd, tokens: limites.tokens);
}

Future<void> _excluir(BuildContext context, Sala sala, Perfil p) async {
  final confirmacao = await pedirTexto(
    context,
    titulo: 'Excluir persona ${p.nome}?',
    rotulo: 'Digite ${p.nome} para confirmar',
    explicacao: 'As posições dela ficam vagas e as conversas viram só leitura. A memória fica guardada, e o nome não pode ser reusado.',
    acao: 'Excluir persona',
    destrutivo: true,
  );
  if (confirmacao != null) sala.equipes.excluirPersona(p.chave, confirmacao);
}

void _alternarPausa(Sala sala, Perfil p) => p.pausa == 'ueslei' ? sala.equipes.retomar(p.chave) : sala.equipes.pausar(p.chave);

({String estado, String rotulo})? _estadoDaPersona(Perfil p, Set<String> rodando) {
  if (estadoDaPausa(p.pausa) case final estado?) {
    return (estado: estado, rotulo: p.pausa == 'orcamento' ? rotulosDeEstado[estado]! : nomesDePausa[p.pausa] ?? 'pausada');
  }
  if (rodando.contains(p.chave)) return (estado: 'rodando', rotulo: rotulosDeEstado['rodando']!);
  return null;
}

String _posicoes(int n) => switch (n) {
      0 => 'nenhuma posição',
      1 => '1 posição',
      _ => '$n posições',
    };

String _descricao(Perfil p) => [p.papel.trim(), p.modelo ?? 'padrão', if (p.gerandoPerfil) 'gerando perfil…']
    .where((s) => s.isNotEmpty)
    .join(' · ');

class TelaPersonas extends StatelessWidget {
  const TelaPersonas({super.key, required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([sala, sala.personas, sala.equipes, sala.skills, sala.tarefas]),
        builder: (context, _) => LayoutBuilder(builder: (context, limites) {
          final classe = ClasseDeJanela.de(limites.maxWidth);
          final comBotao = ClasseDeJanela.de(MediaQuery.sizeOf(context).width) != ClasseDeJanela.compact;
          final aberta = sala.personas.aberta;
          if (!classe.comDoisPaineis) {
            return aberta == null
                ? _Lista(sala: sala, margem: classe.margemLateral, comCabecalho: true, comBotao: comBotao)
                : _Detalhe(key: ValueKey(aberta.chave), sala: sala, persona: aberta, emPainel: false);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Cabecalho(sala: sala, margem: classe.margemLateral, comBotao: comBotao),
            const Divider(height: 1),
            Expanded(
              child: LadoALado(
                painel: 'personas',
                rotulo: 'Largura da lista de personas',
                inicial: _larguraDaLista,
                lateral: _Lista(sala: sala, margem: Espacos.esp3, comCabecalho: false, comBotao: false),
                principal: aberta == null
                    ? _NadaSelecionado(sala: sala)
                    : _Detalhe(key: ValueKey(aberta.chave), sala: sala, persona: aberta, emPainel: true),
              ),
            ),
          ]);
        }),
      );
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.sala, required this.margem, required this.comBotao});

  final Sala sala;
  final double margem;
  final bool comBotao;

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
                Text('Personas', style: tema.textTheme.titleLarge),
                Text(
                  comBotao ? 'Quem trabalha na casa e em cada equipe' : 'Toque numa persona para ver e editar',
                  style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                ),
              ]),
            ),
            if (comBotao) ...[
              const SizedBox(width: Espacos.esp3),
              FilledButton.icon(
                onPressed: () => criarNovaPersona(context, sala),
                icon: const Icon(Symbols.person_add),
                label: const Text('Nova persona'),
              ),
            ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, color: cor),
          const SizedBox(height: Espacos.esp2),
          Text(texto, textAlign: TextAlign.center, style: tema.textTheme.bodyMedium?.copyWith(color: cor)),
          if (acao != null) ...[const SizedBox(height: Espacos.esp3), acao!],
        ]),
      ),
    );
  }
}

class _NadaSelecionado extends StatelessWidget {
  const _NadaSelecionado({required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) {
    final lista = sala.personas.filtradas;
    if (Perfil.todos.isEmpty) {
      return _Vazio(
        icone: Symbols.person,
        texto: 'Nenhuma persona ainda.',
        acao: OutlinedButton(onPressed: () => criarNovaPersona(context, sala), child: const Text('Criar a primeira persona')),
      );
    }
    return _Vazio(
      icone: Symbols.person,
      texto: 'Escolha uma persona na lista para ver e editar.',
      acao: lista.isEmpty
          ? null
          : OutlinedButton(
              onPressed: () => sala.personas.abrir(lista.first.chave),
              child: const Text('Abrir a primeira'),
            ),
    );
  }
}

class _Lista extends StatefulWidget {
  const _Lista({required this.sala, required this.margem, required this.comCabecalho, required this.comBotao});

  final Sala sala;
  final double margem;
  final bool comCabecalho;
  final bool comBotao;

  @override
  State<_Lista> createState() => _ListaState();
}

class _ListaState extends State<_Lista> {
  late final _busca = TextEditingController(text: widget.sala.personas.filtro);

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _limpar() {
    _busca.clear();
    widget.sala.personas.filtrar('');
  }

  @override
  Widget build(BuildContext context) {
    final sala = widget.sala;
    final estado = sala.personas;
    final tema = Theme.of(context);
    final secundario = tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant, fontFeatures: _numeros);
    final lista = estado.filtradas;
    final aberta = estado.aberta?.chave;
    final equipes = sala.equipes.equipes;
    final rodando = personasRodando(sala.tarefas.lista, equipes);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.comCabecalho) _Cabecalho(sala: sala, margem: widget.margem, comBotao: widget.comBotao),
      Padding(
        padding: EdgeInsets.fromLTRB(widget.margem, Espacos.esp2, widget.margem, Espacos.esp3),
        child: TextField(
          controller: _busca,
          onChanged: estado.filtrar,
          decoration: InputDecoration(
            prefixIcon: const Icon(Symbols.search),
            labelText: 'Buscar personas',
            hintText: 'Nome',
            suffixIcon: _busca.text.isEmpty
                ? null
                : IconButton(tooltip: 'Limpar busca', icon: const Icon(Symbols.close), onPressed: _limpar),
          ),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: Perfil.todos.isEmpty
            ? _Vazio(
                icone: Symbols.person,
                texto: 'Nenhuma persona ainda.',
                acao: OutlinedButton(
                  onPressed: () => criarNovaPersona(context, sala),
                  child: const Text('Criar a primeira persona'),
                ),
              )
            : lista.isEmpty
                ? _Vazio(
                    icone: Symbols.search_off,
                    texto: 'Nenhuma persona com essa busca.',
                    acao: OutlinedButton(onPressed: _limpar, child: const Text('Limpar busca')),
                  )
                : RolagemDeDesktop(
                    builder: (context, controle) => ListView.separated(
                      controller: controle,
                      padding: const EdgeInsets.only(bottom: Espacos.esp7 * 2),
                      itemCount: lista.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: Espacos.esp4, endIndent: Espacos.esp4),
                      itemBuilder: (context, i) {
                        final p = lista[i];
                        final estadoDaPersona = _estadoDaPersona(p, rodando);
                        final detalhes = [
                          if (p.papel.trim().isNotEmpty) p.papel.trim(),
                          _posicoes(contarPosicoes(equipes, p.chave)),
                        ];
                        return ListTile(
                          selected: p.chave == aberta,
                          leading: Avatar.doPerfil(p.chave, tamanho: 40),
                          title: Text(p.nome, style: tema.textTheme.titleSmall),
                          subtitle: Text(detalhes.join(' · '), style: secundario),
                          trailing: estadoDaPersona == null
                              ? null
                              : RotuloDeEstado(estado: estadoDaPersona.estado, rotulo: estadoDaPersona.rotulo),
                          onTap: () => estado.abrir(p.chave),
                        );
                      },
                    ),
                  ),
      ),
    ]);
  }
}

class _Detalhe extends StatelessWidget {
  const _Detalhe({super.key, required this.sala, required this.persona, required this.emPainel});

  final Sala sala;
  final Perfil persona;
  final bool emPainel;

  @override
  Widget build(BuildContext context) {
    final p = persona;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final corpo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Material(
        color: cores.surface,
        child: SafeArea(bottom: false, child: _CabecalhoDoDetalhe(sala: sala, persona: p, emPainel: emPainel)),
      ),
      const Divider(height: 1),
      Expanded(
        child: RolagemDeDesktop(
          builder: (context, controle) => SingleChildScrollView(
            controller: controle,
            padding: EdgeInsets.all(emPainel ? Espacos.esp5 : Espacos.esp4),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _larguraDoConteudo),
                child: LayoutBuilder(builder: (context, limites) {
                  final duas = limites.maxWidth >= _larguraDeDuasColunas;
                  final largura = duas ? (limites.maxWidth - Espacos.esp4) / 2 : limites.maxWidth;
                  final cartoes = [
                    _CartaoDeDados(key: ValueKey('dados-${p.chave}'), sala: sala, persona: p),
                    _CartaoDeOrcamento(sala: sala, persona: p),
                    _CartaoDeEquipes(sala: sala, persona: p),
                    _CartaoDeSkills(sala: sala, persona: p),
                  ];
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(
                      spacing: Espacos.esp4,
                      runSpacing: Espacos.esp4,
                      children: [for (final c in cartoes) SizedBox(width: largura, child: c)],
                    ),
                    if (p.excluivel) ...[
                      const SizedBox(height: Espacos.esp5),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: cores.error, side: BorderSide(color: cores.error)),
                        onPressed: () => _excluir(context, sala, p),
                        icon: const Icon(Symbols.person_remove),
                        label: const Text('Excluir persona'),
                      ),
                    ],
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
    ]);
    if (emPainel) return corpo;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) sala.personas.fecharDetalhe();
      },
      child: corpo,
    );
  }
}

class _CabecalhoDoDetalhe extends StatelessWidget {
  const _CabecalhoDoDetalhe({required this.sala, required this.persona, required this.emPainel});

  final Sala sala;
  final Perfil persona;
  final bool emPainel;

  @override
  Widget build(BuildContext context) {
    final p = persona;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final pausadaPorVoce = p.pausa == 'ueslei';
    final pausar = OutlinedButton.icon(
      onPressed: () => _alternarPausa(sala, p),
      icon: Icon(pausadaPorVoce ? Symbols.play_arrow : Symbols.pause),
      label: Text(pausadaPorVoce ? 'Retomar ${p.nome}' : 'Pausar ${p.nome}'),
    );
    final destrutivo = MenuItemButton.styleFrom(foregroundColor: cores.error, iconColor: cores.error);
    final menu = MenuAnchor(
      menuChildren: [
        if (p.conversa)
          MenuItemButton(
            leadingIcon: const Icon(Symbols.forum),
            onPressed: () => sala.novaConversa(p.chave),
            child: Text('Conversar com ${p.nome}'),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.savings),
          onPressed: () => _editarOrcamento(context, sala, p),
          child: const Text('Editar orçamento'),
        ),
        if (p.excluivel)
          MenuItemButton(
            style: destrutivo,
            leadingIcon: const Icon(Symbols.person_remove),
            onPressed: () => _excluir(context, sala, p),
            child: const Text('Excluir persona'),
          ),
      ],
      builder: (context, controle, _) => IconButton(
        tooltip: 'Mais opções de ${p.nome}',
        icon: const Icon(Symbols.more_vert),
        onPressed: () => controle.isOpen ? controle.close() : controle.open(),
      ),
    );
    return LayoutBuilder(builder: (context, limites) {
      final estreito = limites.maxWidth < _larguraDoCabecalhoEstreito;
      final linha = Row(children: [
        if (!emPainel)
          IconButton(tooltip: 'Voltar', icon: const Icon(Symbols.arrow_back), onPressed: sala.personas.fecharDetalhe),
        if (!emPainel) const SizedBox(width: Espacos.esp1),
        Avatar.doPerfil(p.chave, tamanho: estreito ? 40 : 56),
        const SizedBox(width: Espacos.esp4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              p.nome,
              style: estreito ? tema.textTheme.titleLarge : tema.textTheme.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(_descricao(p), style: tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant)),
          ]),
        ),
        if (!estreito) ...[pausar, const SizedBox(width: Espacos.esp1)],
        menu,
      ]);
      return Padding(
        padding: EdgeInsets.fromLTRB(
          emPainel ? Espacos.esp5 : Espacos.esp1,
          Espacos.esp4,
          Espacos.esp3,
          Espacos.esp4,
        ),
        child: estreito
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                linha,
                Padding(
                  padding: EdgeInsets.only(left: emPainel ? 0 : Espacos.esp3, top: Espacos.esp3),
                  child: pausar,
                ),
              ])
            : linha,
      );
    });
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({this.titulo, this.subtitulo, required this.child});

  final String? titulo;
  final String? subtitulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (titulo != null) Text(titulo!, style: tema.textTheme.titleMedium),
          if (subtitulo != null)
            Padding(
              padding: const EdgeInsets.only(top: Espacos.esp1),
              child: Text(
                subtitulo!,
                style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              ),
            ),
          if (titulo != null || subtitulo != null) const SizedBox(height: Espacos.esp3),
          child,
        ]),
      ),
    );
  }
}

class _CartaoDeDados extends StatefulWidget {
  const _CartaoDeDados({super.key, required this.sala, required this.persona});

  final Sala sala;
  final Perfil persona;

  @override
  State<_CartaoDeDados> createState() => _CartaoDeDadosState();
}

class _CartaoDeDadosState extends State<_CartaoDeDados> {
  late final _nome = TextEditingController(text: widget.persona.nome);
  late String? _modelo = widget.persona.modelo;
  String? _cor;
  bool _mudouCor = false;
  int _versao = 0;

  EstadoPersonas get _estado => widget.sala.personas;

  @override
  void didUpdateWidget(covariant _CartaoDeDados antigo) {
    super.didUpdateWidget(antigo);
    final a = antigo.persona;
    final n = widget.persona;
    if (a.nome != n.nome || a.modelo != n.modelo || a.cor != n.cor) _restaurar();
  }

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  void _restaurar() {
    _nome.text = widget.persona.nome;
    _modelo = widget.persona.modelo;
    _cor = null;
    _mudouCor = false;
    _versao++;
  }

  bool get _alterado {
    final p = widget.persona;
    final corMudou = _mudouCor && (_cor == null || corDeHex(_cor) != p.cor);
    return _nome.text.trim() != p.nome || _modelo != p.modelo || corMudou;
  }

  void _salvar() {
    _estado.salvarDados(widget.persona, nome: _nome.text, modelo: _modelo, cor: _cor, mudarCor: _mudouCor);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.persona;
    final tema = Theme.of(context);
    final secundario = tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant);
    final sugerida = _coresSugeridas.where((c) => corDeHex(c.$1) == p.cor).map((c) => c.$1).firstOrNull;
    final opcoes = {..._opcoesDeModelo, if (p.modelo != null && !_opcoesDeModelo.containsKey(p.modelo)) p.modelo!: p.modelo!};
    final nomeVazio = _nome.text.trim().isEmpty;
    return _Cartao(
      titulo: 'Dados',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _nome,
          maxLength: 40,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Nome',
            counterText: '',
            errorText: nomeVazio ? 'Falta o nome. Escreva como ela vai aparecer nas conversas.' : null,
          ),
        ),
        const SizedBox(height: Espacos.esp3),
        DropdownButtonFormField<String?>(
          key: ValueKey('modelo-$_versao'),
          initialValue: _modelo,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Modelo'),
          items: [
            const DropdownMenuItem(value: null, child: Text('padrão')),
            for (final MapEntry(:key, :value) in opcoes.entries) DropdownMenuItem(value: key, child: Text(value)),
          ],
          onChanged: (v) => setState(() => _modelo = v),
        ),
        const SizedBox(height: Espacos.esp3),
        Text('Papel', style: secundario),
        Text(p.papel.trim().isEmpty ? 'sem papel' : p.papel, style: tema.textTheme.bodyMedium),
        Text('O papel vem da criação da persona e não muda aqui.', style: secundario),
        const SizedBox(height: Espacos.esp4),
        Text('Cor', style: secundario),
        const SizedBox(height: Espacos.esp2),
        Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: [
          if (sugerida == null)
            ChoiceChip(
              label: const Text('atual'),
              avatar: CircleAvatar(backgroundColor: Color(p.cor)),
              selected: !_mudouCor,
              onSelected: (_) => setState(() {
                _mudouCor = false;
                _cor = null;
              }),
            ),
          ChoiceChip(
            label: const Text('automática'),
            selected: _mudouCor && _cor == null,
            onSelected: (_) => setState(() {
              _mudouCor = true;
              _cor = null;
            }),
          ),
          for (final (hex, nome) in _coresSugeridas)
            ChoiceChip(
              label: Text(nome),
              avatar: CircleAvatar(backgroundColor: Color(corDeHex(hex))),
              selected: _mudouCor ? _cor == hex : hex == sugerida,
              onSelected: (_) => setState(() {
                _mudouCor = hex != sugerida;
                _cor = _mudouCor ? hex : null;
              }),
            ),
        ]),
        const SizedBox(height: Espacos.esp4),
        Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: [
          FilledButton.tonal(onPressed: _alterado && !nomeVazio ? _salvar : null, child: const Text('Salvar dados')),
          if (_alterado) TextButton(onPressed: () => setState(_restaurar), child: const Text('Descartar')),
        ]),
      ]),
    );
  }
}

class _CartaoDeOrcamento extends StatelessWidget {
  const _CartaoDeOrcamento({required this.sala, required this.persona});

  final Sala sala;
  final Perfil persona;

  @override
  Widget build(BuildContext context) {
    final p = persona;
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final semanticas = CoresSemanticas.de(context);
    final secundario = tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant);
    final valor = tema.textTheme.bodyLarge?.copyWith(fontFeatures: _numeros);
    final usd = 'US\$ ${p.gastoMesUSD.toStringAsFixed(2)}'
        '${p.orcamentoMensalUSD != null ? ' de US\$ ${p.orcamentoMensalUSD!.toStringAsFixed(2)}' : ' · sem limite'}';
    final tokens = formatarTokens(p.tokensMes) +
        (p.orcamentoMensalTokens != null ? ' de ${formatarTokens(p.orcamentoMensalTokens!)}' : ' · sem limite');
    return _Cartao(
      titulo: 'Orçamento do mês',
      subtitulo: 'Conta só as tarefas. O que estourar primeiro segura as tarefas.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Gasto em tarefas', style: secundario),
        Text(usd, style: valor),
        if (p.proporcaoDoOrcamento case final proporcao?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Espacos.esp2),
            child: LinearProgressIndicator(
              value: proporcao,
              backgroundColor: cores.surfaceContainerHighest,
              color: proporcao >= 1
                  ? cores.error
                  : proporcao >= 0.8
                      ? semanticas.aviso.cor
                      : semanticas.sucesso.cor,
            ),
          ),
        const SizedBox(height: Espacos.esp2),
        Text('Tokens', style: secundario),
        Text(tokens, style: valor),
        const SizedBox(height: Espacos.esp4),
        OutlinedButton.icon(
          onPressed: () => _editarOrcamento(context, sala, p),
          icon: const Icon(Symbols.savings),
          label: const Text('Editar orçamento'),
        ),
      ]),
    );
  }
}

class _CartaoDeEquipes extends StatelessWidget {
  const _CartaoDeEquipes({required this.sala, required this.persona});

  final Sala sala;
  final Perfil persona;

  @override
  Widget build(BuildContext context) {
    final p = persona;
    final tema = Theme.of(context);
    final secundario = tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant);
    final equipes = equipesDaPersona(sala.equipes.equipes, p.chave);
    return _Cartao(
      titulo: 'Equipes',
      subtitulo: 'Para pôr ${p.nome} numa equipe, use "Adicionar personas" na tela da equipe.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!sala.equipes.carregada)
          Text('Carregando as equipes…', style: secundario)
        else if (equipes.isEmpty)
          Text('${p.nome} ainda não está em nenhuma equipe.', style: tema.textTheme.bodyMedium)
        else
          for (final (i, (:equipe, :posicoes)) in equipes.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Symbols.account_tree, size: 20),
              minLeadingWidth: Espacos.esp5,
              title: Text(equipe.nome),
              subtitle: Text(posicoes.join(', '), style: secundario),
              trailing: TextButton(onPressed: () => sala.abrirEquipe(equipe.id), child: const Text('Abrir equipe')),
            ),
          ],
      ]),
    );
  }
}

class _CartaoDeSkills extends StatelessWidget {
  const _CartaoDeSkills({required this.sala, required this.persona});

  final Sala sala;
  final Perfil persona;

  @override
  Widget build(BuildContext context) {
    final p = persona;
    final skills = sala.skills;
    return _Cartao(
      child: SecaoDeSkills(
        itens: skillsDaPersona(skills.lista, p),
        anexaveis: anexaveis(skills.lista, p.skills),
        aoAnexar: (id) => skills.anexarNaPersona(p.chave, id),
        aoTirar: (id) => skills.tirarDaPersona(p.chave, id),
      ),
    );
  }
}

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
  bool _tentou = false;

  @override
  void dispose() {
    _nome.dispose();
    _titulo.dispose();
    _base.dispose();
    super.dispose();
  }

  String? get _erroDoNome =>
      _tentou && _nome.text.trim().isEmpty ? 'Falta o nome. Escreva como ela vai aparecer nas conversas.' : null;

  String? get _erroDaBase =>
      _tentou && _base.text.trim().isEmpty ? 'Falta a descrição. Sem ela não dá para gerar o perfil.' : null;

  void _revalidar(String _) {
    if (_tentou) setState(() {});
  }

  void _criar() {
    if (_nome.text.trim().isEmpty || _base.text.trim().isEmpty) {
      setState(() => _tentou = true);
      return;
    }
    Navigator.pop<_NovaPersona>(
      context,
      (nome: _nome.text, titulo: _titulo.text, base: _base.text, modelo: _modelo, cor: _cor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return AlertDialog(
      title: const Text('Nova persona'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _nome,
              maxLength: 40,
              onChanged: _revalidar,
              decoration: InputDecoration(
                labelText: 'Nome',
                helperText: 'Aparece nas conversas e no organograma.',
                errorText: _erroDoNome,
                counterText: '',
              ),
            ),
            const SizedBox(height: Espacos.esp3),
            TextField(
              controller: _titulo,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Papel curto (aparece na lista)', counterText: ''),
            ),
            const SizedBox(height: Espacos.esp3),
            TextField(
              controller: _base,
              minLines: 4,
              maxLines: 8,
              maxLength: 4000,
              onChanged: _revalidar,
              decoration: InputDecoration(
                labelText: 'Quem é, que papel tem com você e qual é o jeito dela',
                helperText: 'O perfil completo é gerado a partir deste texto.',
                errorText: _erroDaBase,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Espacos.esp3),
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
            const SizedBox(height: Espacos.esp4),
            Text('Cor', style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
            const SizedBox(height: Espacos.esp2),
            Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, children: [
              ChoiceChip(
                label: const Text('automática'),
                selected: _cor == null,
                onSelected: (_) => setState(() => _cor = null),
              ),
              for (final (hex, nome) in _coresSugeridas)
                ChoiceChip(
                  label: Text(nome),
                  avatar: CircleAvatar(backgroundColor: Color(corDeHex(hex))),
                  selected: _cor == hex,
                  onSelected: (_) => setState(() => _cor = hex),
                ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _criar, child: const Text('Criar')),
      ],
    );
  }
}

class _DialogoDeOrcamento extends StatefulWidget {
  const _DialogoDeOrcamento({required this.persona});

  final Perfil persona;

  @override
  State<_DialogoDeOrcamento> createState() => _DialogoDeOrcamentoState();
}

class _DialogoDeOrcamentoState extends State<_DialogoDeOrcamento> {
  late final _usd = TextEditingController(text: widget.persona.orcamentoMensalUSD?.toString() ?? '');
  late final _tokens = TextEditingController(text: widget.persona.orcamentoMensalTokens?.toString() ?? '');
  String? _erro;

  @override
  void dispose() {
    _usd.dispose();
    _tokens.dispose();
    super.dispose();
  }

  void _salvar() {
    final usdTexto = _usd.text.trim().replaceAll(',', '.');
    final tokensTexto = _tokens.text.trim().replaceAll('.', '').replaceAll(' ', '');
    final usd = usdTexto.isEmpty ? null : double.tryParse(usdTexto);
    final tokens = tokensTexto.isEmpty ? null : int.tryParse(tokensTexto);
    if ((usdTexto.isNotEmpty && (usd == null || usd < 0)) || (tokensTexto.isNotEmpty && (tokens == null || tokens < 0))) {
      setState(() => _erro = 'Use números positivos; tokens sem casas decimais.');
      return;
    }
    Navigator.pop<({double? usd, int? tokens})>(context, (usd: usd, tokens: tokens));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.persona;
    return AlertDialog(
      title: Text('Orçamento de ${p.nome}'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'Neste mês, em tarefas: US\$ ${p.gastoMesUSD.toStringAsFixed(2)} e ${formatarTokens(p.tokensMes)}. '
            'O que estourar primeiro segura as tarefas.',
            style: const TextStyle(fontFeatures: _numeros),
          ),
          const SizedBox(height: Espacos.esp4),
          TextField(
            controller: _usd,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Limite mensal em US\$', helperText: 'Vazio fica sem limite.'),
          ),
          const SizedBox(height: Espacos.esp3),
          TextField(
            controller: _tokens,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Limite mensal em tokens (ex.: 2000000)',
              helperText: 'Vazio fica sem limite.',
              errorText: _erro,
            ),
            onSubmitted: (_) => _salvar(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
