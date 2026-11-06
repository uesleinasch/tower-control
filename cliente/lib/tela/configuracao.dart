import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../conexao/http.dart';
import '../estado/espelho.dart';
import '../estado/sala.dart';
import '../estado/servidor.dart';
import '../nucleo/acoes.dart';
import '../nucleo/design.dart';
import '../nucleo/enderecos.dart';
import '../nucleo/espelho.dart';
import '../sistema/desktop.dart';
import '../sistema/executor.dart';
import '../sistema/servico_avisos.dart';
import 'comum.dart';
import 'importacao.dart';
import 'tema.dart';

const _larguraDaPorta = 160.0;
const _larguraDoProjeto = 280.0;
const _larguraDaTag = 220.0;
const _larguraDoTipo = 260.0;
const _alturaDoLog = 320.0;
const _alturaMaximaDaSaida = 240.0;
const _tamanhoDoIndicador = 20.0;

typedef Situacao = ({PapelDeEstado papel, IconData icone, String rotulo});

Situacao situacaoDoServico(String ativo) => switch (ativo) {
      'active' => (papel: PapelDeEstado.sucesso, icone: Symbols.check_circle, rotulo: 'rodando'),
      'activating' || 'reloading' => (papel: PapelDeEstado.andamento, icone: Symbols.play_circle, rotulo: 'subindo'),
      'deactivating' => (papel: PapelDeEstado.aviso, icone: Symbols.pause_circle, rotulo: 'parando'),
      'inactive' => (papel: PapelDeEstado.aviso, icone: Symbols.stop_circle, rotulo: 'parado'),
      'failed' => (papel: PapelDeEstado.erro, icone: Symbols.error, rotulo: 'falhou'),
      '…' => (papel: PapelDeEstado.neutro, icone: Symbols.hourglass_empty, rotulo: 'consultando…'),
      _ => (papel: PapelDeEstado.aviso, icone: Symbols.help, rotulo: ativo),
    };

Situacao situacaoDoLogin(String habilitado) => switch (habilitado) {
      'enabled' => (papel: PapelDeEstado.sucesso, icone: Symbols.login, rotulo: 'sobe no login'),
      'disabled' => (papel: PapelDeEstado.aviso, icone: Symbols.do_not_disturb_on, rotulo: 'não sobe no login'),
      'not-found' || 'não instalado' => (papel: PapelDeEstado.aviso, icone: Symbols.block, rotulo: 'não instalado'),
      '…' => (papel: PapelDeEstado.neutro, icone: Symbols.hourglass_empty, rotulo: 'consultando…'),
      _ => (papel: PapelDeEstado.aviso, icone: Symbols.help, rotulo: habilitado),
    };

Situacao situacaoDoLinger(String linger) => switch (linger) {
      'yes' => (papel: PapelDeEstado.sucesso, icone: Symbols.power_settings_new, rotulo: 'linger: sobe no boot'),
      '…' => (papel: PapelDeEstado.neutro, icone: Symbols.hourglass_empty, rotulo: 'linger: consultando…'),
      _ => (papel: PapelDeEstado.aviso, icone: Symbols.power_off, rotulo: 'linger: só com login'),
    };

Situacao situacaoDoEspelho(ConfigDoEspelho? config, EstadoDoEspelho estado) {
  if (config == null) return (papel: PapelDeEstado.neutro, icone: Symbols.hourglass_empty, rotulo: 'carregando…');
  if (!config.ativo) return (papel: PapelDeEstado.neutro, icone: Symbols.sync_disabled, rotulo: 'desligado');
  if (estado.conectado) return (papel: PapelDeEstado.sucesso, icone: Symbols.cloud_done, rotulo: 'conectado');
  if (estado.erro == null && estado.ultimaVolta == null) {
    return (papel: PapelDeEstado.aviso, icone: Symbols.schedule, rotulo: 'esperando a primeira volta');
  }
  return (papel: PapelDeEstado.erro, icone: Symbols.cloud_off, rotulo: 'fora do ar');
}

class TelaConfiguracao extends StatelessWidget {
  const TelaConfiguracao({super.key, required this.sala, required this.servidor, required this.autostart});

  final Sala sala;
  final ServidorLocal servidor;
  final Autostart autostart;

  @override
  Widget build(BuildContext context) => _Moldura(
        sala: sala,
        subtitulo: 'servidor, celular e integrações',
        blocos: [
          _BlocoServidor(sala: sala, servidor: servidor),
          _BlocoInicializacao(autostart: autostart),
          _BlocoEspelho(espelho: sala.espelho),
          _BlocoRede(servidor: servidor),
          _BlocoCelular(servidor: servidor),
          const _BlocoLogs(),
        ],
      );
}

class TelaConfiguracaoCelular extends StatelessWidget {
  const TelaConfiguracaoCelular({super.key, required this.sala, required this.servico, required this.prefs});

  final Sala sala;
  final ServicoDeAvisos servico;
  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) => _Moldura(
        sala: sala,
        subtitulo: 'avisos deste aparelho',
        blocos: [_BlocoAvisos(servico: servico, prefs: prefs)],
      );
}

class _Moldura extends StatelessWidget {
  const _Moldura({required this.sala, required this.subtitulo, required this.blocos});

  final Sala sala;
  final String subtitulo;
  final List<Widget> blocos;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, limites) {
        final classe = ClasseDeJanela.de(limites.maxWidth);
        final margem = classe.margemLateral;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Cabecalho(
            subtitulo: subtitulo,
            margem: margem,
            aoVoltar: classe == ClasseDeJanela.compact ? () => sala.ir(Tela.conversas) : null,
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: margem, vertical: Espacos.esp5),
              children: [
                for (final (i, bloco) in blocos.indexed)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: larguraDeLeitura),
                      child: Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : Espacos.esp4), child: bloco),
                    ),
                  ),
              ],
            ),
          ),
        ]);
      });
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.subtitulo, required this.margem, this.aoVoltar});

  final String subtitulo;
  final double margem;
  final VoidCallback? aoVoltar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      color: tema.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(aoVoltar == null ? margem : Espacos.esp1, Espacos.esp4, margem, Espacos.esp3),
          child: Row(children: [
            if (aoVoltar != null) ...[
              IconButton(tooltip: 'Voltar', icon: const Icon(Symbols.arrow_back), onPressed: aoVoltar),
              const SizedBox(width: Espacos.esp1),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(header: true, child: Text('Configuração', style: tema.textTheme.titleLarge)),
                Text(subtitulo, style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class BlocoDeConfiguracao extends StatelessWidget {
  const BlocoDeConfiguracao({
    super.key,
    required this.titulo,
    required this.icone,
    required this.filhos,
    this.descricao,
    this.acao,
  });

  final String titulo;
  final IconData icone;
  final List<Widget> filhos;
  final String? descricao;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Espacos.esp4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icone, size: 20, color: cores.primary),
            const SizedBox(width: Espacos.esp3),
            Expanded(child: Semantics(header: true, child: Text(titulo, style: tema.textTheme.titleMedium))),
            if (acao case final a?) ...[const SizedBox(width: Espacos.esp2), Flexible(child: a)],
          ]),
          if (descricao case final d?) ...[
            const SizedBox(height: Espacos.esp2),
            Text(d, style: tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant)),
          ],
          const SizedBox(height: Espacos.esp3),
          ...filhos,
        ]),
      ),
    );
  }
}

class _Situacao extends StatelessWidget {
  const _Situacao(this.situacao);

  final Situacao situacao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = corDoPapel(situacao.papel, tema.colorScheme, CoresSemanticas.de(context));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(situacao.icone, size: 16, color: cor),
      const SizedBox(width: Espacos.esp1),
      Flexible(
        child: Text(
          situacao.rotulo,
          style: tema.textTheme.labelMedium?.copyWith(color: cor, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ),
    ]);
  }
}

class _Saida extends StatefulWidget {
  const _Saida(this.texto);

  final String texto;

  @override
  State<_Saida> createState() => _SaidaState();
}

class _SaidaState extends State<_Saida> {
  final _rolagem = ScrollController();

  @override
  void dispose() {
    _rolagem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Espacos.esp2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tema.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Raios.sm),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _alturaMaximaDaSaida),
          child: Scrollbar(
            controller: _rolagem,
            thumbVisibility: ehDesktop,
            child: SingleChildScrollView(
              controller: _rolagem,
              padding: const EdgeInsets.all(Espacos.esp3),
              child: SelectableText(
                widget.texto,
                style: tema.textTheme.bodySmall?.copyWith(fontFamily: familiaMono, color: tema.colorScheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Comando extends StatelessWidget {
  const _Comando(this.comando);

  final String comando;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Espacos.esp2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tema.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Raios.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: Espacos.esp3),
          child: Row(children: [
            Expanded(
              child: SelectableText(comando, style: tema.textTheme.bodyMedium?.copyWith(fontFamily: familiaMono)),
            ),
            IconButton(
              tooltip: 'Copiar comando',
              icon: const Icon(Symbols.content_copy, size: 20),
              onPressed: () => copiar(context, comando),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({required this.rotulo});

  final String rotulo;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: _tamanhoDoIndicador,
        child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: rotulo),
      );
}

class _BlocoAvisos extends StatefulWidget {
  const _BlocoAvisos({required this.servico, required this.prefs});

  final ServicoDeAvisos servico;
  final SharedPreferences prefs;

  @override
  State<_BlocoAvisos> createState() => _BlocoAvisosState();
}

class _BlocoAvisosState extends State<_BlocoAvisos> {
  bool _rodando = false;
  bool _permitidas = true;
  bool _ocupado = false;

  bool get _ligados => widget.prefs.getBool(chaveAvisosLigados) ?? true;

  @override
  void initState() {
    super.initState();
    _conferir();
  }

  Future<void> _conferir() async {
    final rodando = await widget.servico.ligado();
    final permitidas = await widget.servico.notificacoesPermitidas();
    if (!mounted) return;
    setState(() {
      _rodando = rodando;
      _permitidas = permitidas;
    });
  }

  Future<void> _alternar(bool ligar) async {
    setState(() => _ocupado = true);
    await widget.prefs.setBool(chaveAvisosLigados, ligar);
    await (ligar ? widget.servico.ligar() : widget.servico.desligar());
    await _conferir();
    if (mounted) setState(() => _ocupado = false);
  }

  Situacao get _situacao {
    if (_rodando) return (papel: PapelDeEstado.sucesso, icone: Symbols.notifications_active, rotulo: 'escutando');
    if (_ligados) return (papel: PapelDeEstado.aviso, icone: Symbols.notifications_paused, rotulo: 'parado');
    return (papel: PapelDeEstado.neutro, icone: Symbols.notifications_off, rotulo: 'desligado');
  }

  @override
  Widget build(BuildContext context) => BlocoDeConfiguracao(
        titulo: 'Avisos',
        icone: Symbols.notifications,
        acao: _Situacao(_situacao),
        filhos: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _ligados,
            onChanged: _ocupado ? null : _alternar,
            title: const Text('Avisos com o app fechado'),
            subtitle: const Text(
                'Respostas, aprovações do Alfred e lembretes do TickTask. Fica uma notificação fixa discreta enquanto escuta.'),
          ),
          if (!_permitidas) ...[
            const SizedBox(height: Espacos.esp2),
            const CaixaDeMensagens(
              tom: TomDaMensagem.aviso,
              linhas: [
                'As notificações estão bloqueadas para o Control Tower. Libere nas configurações do Android, em Apps.',
              ],
            ),
          ],
        ],
      );
}

class _BlocoServidor extends StatefulWidget {
  const _BlocoServidor({required this.sala, required this.servidor});

  final Sala sala;
  final ServidorLocal servidor;

  @override
  State<_BlocoServidor> createState() => _BlocoServidorState();
}

class _BlocoServidorState extends State<_BlocoServidor> {
  String _ativo = '…';
  String _habilitado = '…';
  String _linger = '…';
  Resultado? _ultimo;
  String? _erroDaPorta;
  var _ocupado = false;
  Timer? _relogio;
  late final _porta = TextEditingController(text: '${widget.servidor.porta}');

  @override
  void initState() {
    super.initState();
    _consultar();
    _relogio = Timer.periodic(const Duration(seconds: 5), (_) => _consultar());
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _porta.dispose();
    super.dispose();
  }

  Future<void> _consultar() async {
    final usuario = Platform.environment['USER'] ?? '';
    final resultados = await Future.wait([
      rodar(servico(VerboServico.estado)),
      rodar(servico(VerboServico.habilitado)),
      if (usuario.isNotEmpty) rodar(linger(usuario)),
    ]);
    if (!mounted) return;
    setState(() {
      _ativo = resultados[0].saida.trim().isEmpty ? 'desconhecido' : resultados[0].saida.trim();
      _habilitado = resultados[1].saida.trim().isEmpty ? 'não instalado' : resultados[1].saida.trim();
      _linger = resultados.length > 2 ? resultados[2].saida.trim() : 'desconhecido';
    });
  }

  Future<void> _executar(VerboServico verbo) async {
    setState(() => _ocupado = true);
    final r = await rodar(servico(verbo));
    await _consultar();
    widget.sala.canal.reconectarJa();
    if (mounted) {
      setState(() {
        _ocupado = false;
        _ultimo = r;
      });
    }
  }

  Future<void> _salvarPorta() async {
    final porta = int.tryParse(_porta.text.trim());
    if (porta == null || porta < 1 || porta > 65535) {
      setState(() => _erroDaPorta = 'Use um número de 1 a 65535');
      return;
    }
    setState(() => _erroDaPorta = null);
    await widget.servidor.definirPorta(porta);
    widget.sala.canal
      ..pausar()
      ..iniciar();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conectando em 127.0.0.1:$porta')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final ativo = _ativo == 'active';
    final consultando = _ativo == '…';
    final ultimo = _ultimo;
    return BlocoDeConfiguracao(
      titulo: 'Servidor',
      icone: Symbols.dns,
      acao: IconButton(tooltip: 'Atualizar estado', icon: const Icon(Symbols.refresh), onPressed: _consultar),
      filhos: [
        Wrap(spacing: Espacos.esp4, runSpacing: Espacos.esp2, children: [
          _Situacao(situacaoDoServico(_ativo)),
          _Situacao(situacaoDoLogin(_habilitado)),
          _Situacao(situacaoDoLinger(_linger)),
        ]),
        if (_linger == 'no') ...[
          const SizedBox(height: Espacos.esp3),
          Text(
            'Para o servidor subir no boot mesmo sem login, rode no terminal:',
            style: tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant),
          ),
          const _Comando('loginctl enable-linger \$USER'),
        ],
        if (_habilitado == 'not-found' || _habilitado == 'não instalado') ...[
          const SizedBox(height: Espacos.esp3),
          const CaixaDeMensagens(
            tom: TomDaMensagem.aviso,
            linhas: ['O serviço ainda não está instalado. No repositório, rode o comando abaixo.'],
          ),
          const _Comando('bash scripts/servico.sh'),
        ],
        const SizedBox(height: Espacos.esp4),
        Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (ativo) ...[
            FilledButton.tonalIcon(
              onPressed: _ocupado ? null : () => _executar(VerboServico.reiniciar),
              icon: const Icon(Symbols.restart_alt),
              label: const Text('Reiniciar servidor'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cores.error, side: BorderSide(color: cores.error)),
              onPressed: _ocupado ? null : () => _executar(VerboServico.parar),
              icon: const Icon(Symbols.stop),
              label: const Text('Parar servidor'),
            ),
          ] else
            FilledButton.icon(
              onPressed: _ocupado || consultando ? null : () => _executar(VerboServico.iniciar),
              icon: const Icon(Symbols.play_arrow),
              label: const Text('Iniciar servidor'),
            ),
          if (_ocupado) const _Indicador(rotulo: 'Executando o comando'),
        ]),
        if (ultimo != null && !ultimo.ok) ...[
          const SizedBox(height: Espacos.esp3),
          const CaixaDeMensagens(
            tom: TomDaMensagem.erro,
            linhas: ['O systemctl não executou o comando. A saída está abaixo.'],
          ),
          _Saida(ultimo.mensagem),
        ],
        const Divider(height: Espacos.esp6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: _larguraDaPorta,
            child: TextField(
              controller: _porta,
              keyboardType: TextInputType.number,
              style: tema.textTheme.bodyLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              decoration: InputDecoration(labelText: 'Porta', errorText: _erroDaPorta),
              onSubmitted: (_) => _salvarPorta(),
            ),
          ),
          const SizedBox(width: Espacos.esp2),
          OutlinedButton(onPressed: _salvarPorta, child: const Text('Aplicar porta')),
        ]),
      ],
    );
  }
}

class _BlocoInicializacao extends StatefulWidget {
  const _BlocoInicializacao({required this.autostart});

  final Autostart autostart;

  @override
  State<_BlocoInicializacao> createState() => _BlocoInicializacaoState();
}

class _BlocoInicializacaoState extends State<_BlocoInicializacao> {
  String? _erro;

  Future<void> _alternar(bool ligar) async {
    try {
      await widget.autostart.definir(ligar);
      setState(() => _erro = null);
    } catch (e) {
      setState(() => _erro = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => BlocoDeConfiguracao(
        titulo: 'Inicialização',
        icone: Symbols.power_settings_new,
        filhos: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: widget.autostart.ligado,
            onChanged: _alternar,
            title: const Text('Abrir na bandeja ao entrar na sessão'),
            subtitle: const Text('Só o ícone aparece no login; a janela abre ao clicar nele.'),
          ),
          if (_erro case final e?) ...[
            const SizedBox(height: Espacos.esp2),
            CaixaDeMensagens(tom: TomDaMensagem.erro, linhas: ['Não deu para mudar a inicialização: $e']),
          ],
        ],
      );
}

class _BlocoEspelho extends StatefulWidget {
  const _BlocoEspelho({required this.espelho});

  final EstadoEspelho espelho;

  @override
  State<_BlocoEspelho> createState() => _BlocoEspelhoState();
}

class _BlocoEspelhoState extends State<_BlocoEspelho> {
  final _projeto = TextEditingController();
  final _tag = TextEditingController();

  EstadoEspelho get _e => widget.espelho;

  @override
  void initState() {
    super.initState();
    _e.addListener(_sincronizarCampos);
    _sincronizarCampos();
    _e.definirAberto(true);
  }

  @override
  void dispose() {
    _e.removeListener(_sincronizarCampos);
    _e.definirAberto(false);
    _projeto.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _sincronizarCampos() {
    if (_e.rascunho != null) return;
    final c = _e.vista;
    if (_projeto.text != c.projeto) _projeto.text = c.projeto;
    if (_tag.text != c.tag) _tag.text = c.tag;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _e,
        builder: (context, _) {
          final tema = Theme.of(context);
          final cores = tema.colorScheme;
          final secundario = tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant);
          final vista = _e.vista;
          final estado = _e.estado;
          final rascunho = _e.rascunho;
          final editavel = _e.carregado && !_e.salvando;
          final ligadoSalvo = _e.config?.ativo ?? false;
          return BlocoDeConfiguracao(
            titulo: 'Espelho no TickTask',
            icone: Symbols.sync_alt,
            acao: _Situacao(situacaoDoEspelho(_e.config, estado)),
            descricao: 'Os itens de "Precisa de você" sobem como tarefas no TickTask. Finalizar lá faz a ação '
                'aqui (aprovar, concluir, liberar ou escolher a opção). Pedir mudança continua só no control-tower.',
            filhos: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: vista.ativo,
                onChanged: editavel ? (v) => _e.mudar(ativo: v ?? false) : null,
                title: const Text('Espelhar no TickTask'),
                subtitle: const Text('Vale depois de salvar.'),
              ),
              const SizedBox(height: Espacos.esp2),
              Wrap(spacing: Espacos.esp3, runSpacing: Espacos.esp3, children: [
                SizedBox(
                  width: _larguraDoProjeto,
                  child: TextField(
                    controller: _projeto,
                    enabled: editavel,
                    onChanged: (v) => _e.mudar(projeto: v),
                    decoration: InputDecoration(
                      labelText: 'Projeto do TickTask',
                      errorText:
                          rascunho != null && rascunho.projeto.trim().isEmpty ? 'Informe o projeto do TickTask' : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: _larguraDaTag,
                  child: TextField(
                    controller: _tag,
                    enabled: editavel,
                    onChanged: (v) => _e.mudar(tag: v),
                    decoration: InputDecoration(
                      labelText: 'Tag',
                      errorText: rascunho != null && rascunho.tag.trim().isEmpty ? 'Informe a tag' : null,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: Espacos.esp4),
              Text('O que sobe', style: tema.textTheme.titleSmall),
              const SizedBox(height: Espacos.esp1),
              Wrap(children: [
                for (final MapEntry(key: tipo, value: rotulo) in rotulosDoEspelho.entries)
                  SizedBox(
                    width: _larguraDoTipo,
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: vista.tipos.contains(tipo),
                      onChanged: editavel ? (v) => _e.marcarTipo(tipo, v ?? false) : null,
                      title: Text(rotulo),
                    ),
                  ),
              ]),
              if (_e.alterado || _e.salvando) ...[
                const SizedBox(height: Espacos.esp2),
                Wrap(
                  spacing: Espacos.esp2,
                  runSpacing: Espacos.esp2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton(onPressed: _e.podeSalvar ? _e.salvar : null, child: const Text('Salvar')),
                    TextButton(onPressed: _e.salvando ? null : _e.descartar, child: const Text('Descartar')),
                    if (_e.salvando) const _Indicador(rotulo: 'Salvando'),
                  ],
                ),
              ],
              if (_e.erro case final erro?) ...[
                const SizedBox(height: Espacos.esp3),
                CaixaDeMensagens(tom: TomDaMensagem.erro, linhas: [erro]),
              ],
              const Divider(height: Espacos.esp6),
              Text('Sincronização', style: tema.textTheme.titleSmall),
              const SizedBox(height: Espacos.esp2),
              Wrap(spacing: Espacos.esp4, runSpacing: Espacos.esp2, children: [
                _Situacao((papel: PapelDeEstado.neutro, icone: Symbols.task_alt, rotulo: '${estado.abertos} no TickTask')),
                _Situacao((
                  papel: estado.pendentes > 0 ? PapelDeEstado.aviso : PapelDeEstado.neutro,
                  icone: Symbols.upload,
                  rotulo: '${estado.pendentes} esperando para subir ou fechar',
                )),
              ]),
              const SizedBox(height: Espacos.esp2),
              Text(ultimaVoltaDoEspelho(estado), style: secundario),
              if (estado.erro case final erro?) ...[
                const SizedBox(height: Espacos.esp3),
                CaixaDeMensagens(tom: TomDaMensagem.erro, linhas: ['Último erro: $erro']),
              ],
              const SizedBox(height: Espacos.esp3),
              Wrap(spacing: Espacos.esp2, runSpacing: Espacos.esp2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                FilledButton.tonalIcon(
                  onPressed: ligadoSalvo && !_e.sincronizando ? _e.sincronizar : null,
                  icon: const Icon(Symbols.sync),
                  label: const Text('Sincronizar agora'),
                ),
                if (_e.sincronizando) const _Indicador(rotulo: 'Sincronizando'),
                if (!ligadoSalvo && _e.carregado)
                  Text('Marque "Espelhar no TickTask" e salve para sincronizar.', style: secundario),
              ]),
            ],
          );
        },
      );
}

class _BlocoRede extends StatefulWidget {
  const _BlocoRede({required this.servidor});

  final ServidorLocal servidor;

  @override
  State<_BlocoRede> createState() => _BlocoRedeState();
}

class _BlocoRedeState extends State<_BlocoRede> {
  Map<String, dynamic>? _resposta;
  var _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final r = await sondar('127.0.0.1:${widget.servidor.porta}');
    if (mounted) {
      setState(() {
        _resposta = r;
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final r = _resposta;
    final porta = r?['porta'] ?? widget.servidor.porta;
    Widget linha(String rotulo, String? host) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(rotulo),
          subtitle: host == null
              ? const Text('indisponível')
              : SelectableText('http://$host:$porta', style: tema.textTheme.bodySmall?.copyWith(fontFamily: familiaMono)),
          trailing: host == null
              ? null
              : IconButton(
                  tooltip: 'Copiar endereço',
                  icon: const Icon(Symbols.content_copy, size: 20),
                  onPressed: () => copiar(context, 'http://$host:$porta'),
                ),
        );
    return BlocoDeConfiguracao(
      titulo: 'Rede',
      icone: Symbols.lan,
      acao: IconButton(tooltip: 'Atualizar endereços', icon: const Icon(Symbols.refresh), onPressed: _carregar),
      filhos: [
        if (_carregando)
          const LinearProgressIndicator(semanticsLabel: 'Consultando os endereços')
        else if (r == null) ...[
          const CaixaDeMensagens(
            tom: TomDaMensagem.erro,
            linhas: ['O servidor não respondeu em /enderecos. Confira se ele está rodando no bloco Servidor.'],
          ),
          const SizedBox(height: Espacos.esp2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _carregar,
              icon: const Icon(Symbols.refresh),
              label: const Text('Tentar de novo'),
            ),
          ),
        ] else ...[
          linha('Rede local', r['lan'] as String?),
          linha('Tailscale', r['tailscale'] as String?),
        ],
      ],
    );
  }
}

class _BlocoCelular extends StatefulWidget {
  const _BlocoCelular({required this.servidor});

  final ServidorLocal servidor;

  @override
  State<_BlocoCelular> createState() => _BlocoCelularState();
}

class _BlocoCelularState extends State<_BlocoCelular> {
  List<Dispositivo> _dispositivos = const [];
  String? _semAdb;
  String? _apk;
  Timer? _relogio;
  String? _instalando;
  final _log = <String>[];
  var _falhou = false;

  @override
  void initState() {
    super.initState();
    _apk = _acharApk();
    _listar();
    _relogio = Timer.periodic(const Duration(seconds: 3), (_) => _listar());
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  String? _acharApk() {
    final candidatos = candidatosApk(
      home: Platform.environment['HOME'] ?? '',
      executavel: Platform.resolvedExecutable,
      forcado: Platform.environment['CONTROL_TOWER_APK'],
    );
    for (final c in candidatos) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  Future<void> _listar() async {
    if (_instalando != null) return;
    final r = await rodar(adbDispositivos(), limite: const Duration(seconds: 5));
    if (!mounted) return;
    setState(() {
      _semAdb = r.codigo == -1 ? r.erro : null;
      _dispositivos = r.ok ? dispositivosAdb(r.saida) : const [];
      _apk ??= _acharApk();
    });
  }

  Future<void> _instalarEConectar(Dispositivo d) async {
    final apk = _apk;
    if (apk == null) return;
    setState(() {
      _instalando = d.serial;
      _log.clear();
      _falhou = false;
    });
    void registrar(String linha) => setState(() => _log.add(linha));

    registrar('Lendo os endereços do servidor…');
    final resposta = await sondar('127.0.0.1:${widget.servidor.porta}');
    final enderecos = resposta == null ? const <String>[] : enderecosDaResposta(resposta);
    if (enderecos.isEmpty) {
      registrar('O servidor não informou endereço de rede. Ele está rodando?');
      return _fim(falhou: true);
    }
    registrar('Endereços: ${enderecos.join(', ')}');

    registrar('Instalando ${apk.split('/').last} em ${d.modelo}…');
    final instalacao = await rodar(adbInstalar(d.serial, apk), limite: const Duration(minutes: 3));
    registrar(instalacao.mensagem);
    if (!instalacao.ok || instalacao.saida.contains('Failure')) return _fim(falhou: true);

    final porta = widget.servidor.porta;
    final reverso = await rodar(adbReverso(d.serial, porta));
    registrar(reverso.ok
        ? 'Cabo: o celular alcança o servidor em 127.0.0.1:$porta enquanto estiver plugado.'
        : 'Sem túnel pelo cabo: ${reverso.mensagem}');

    registrar('Abrindo o app com os endereços…');
    final abertura = await rodar(adbConectar(d.serial, reverso.ok ? enderecosParaCelular(enderecos, porta) : enderecos));
    registrar(abertura.mensagem);
    if (!abertura.ok || abertura.saida.contains('Error')) return _fim(falhou: true);
    registrar('Pronto: o app abriu no celular já conectado.');
    _fim(falhou: false);
  }

  void _fim({required bool falhou}) {
    if (!mounted) return;
    setState(() {
      _instalando = null;
      _falhou = falhou;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final semAdb = _semAdb;
    final apk = _apk;
    final linhasDoLog = _log.where((l) => l.trim().isNotEmpty).join('\n');
    return BlocoDeConfiguracao(
      titulo: 'Celular',
      icone: Symbols.phone_android,
      descricao: 'Conecte o celular no cabo com a depuração USB ligada. "Instalar e conectar" instala o app '
          'e já entrega a ele os endereços deste computador.',
      filhos: [
        if (semAdb != null) ...[
          const CaixaDeMensagens(
            tom: TomDaMensagem.erro,
            linhas: ['adb não encontrado. Instale com o comando abaixo e a lista de aparelhos aparece sozinha.'],
          ),
          const _Comando('sudo apt install adb'),
          if (semAdb.trim().isNotEmpty) _Saida(semAdb),
        ] else if (_dispositivos.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Symbols.usb_off),
            title: Text('Nenhum aparelho no cabo'),
            subtitle: Text('A lista se atualiza sozinha a cada 3 segundos.'),
          )
        else
          for (final d in _dispositivos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Symbols.smartphone),
              title: Text(d.modelo),
              subtitle: Text(switch (d.estado) {
                'device' => d.serial,
                'unauthorized' => 'Aceite o pedido de depuração USB na tela do celular',
                _ => '${d.serial} · ${d.estado}',
              }),
              trailing: _instalando == d.serial
                  ? const _Indicador(rotulo: 'Instalando')
                  : FilledButton(
                      onPressed: d.pronto && apk != null && _instalando == null ? () => _instalarEConectar(d) : null,
                      child: const Text('Instalar e conectar'),
                    ),
            ),
        const SizedBox(height: Espacos.esp2),
        if (apk == null) ...[
          const CaixaDeMensagens(
            tom: TomDaMensagem.aviso,
            linhas: ['APK não encontrado. Gere com o comando abaixo, no repositório.'],
          ),
          const _Comando('bash scripts/instalar-cliente.sh'),
        ] else
          SelectableText(
            'APK: $apk',
            style: tema.textTheme.bodySmall?.copyWith(fontFamily: familiaMono, color: cores.onSurfaceVariant),
          ),
        if (linhasDoLog.isNotEmpty) ...[
          if (_falhou) ...[
            const SizedBox(height: Espacos.esp3),
            const CaixaDeMensagens(
              tom: TomDaMensagem.erro,
              linhas: ['A instalação não terminou. Veja na saída abaixo onde parou.'],
            ),
          ],
          _Saida(linhasDoLog),
        ],
      ],
    );
  }
}

class _BlocoLogs extends StatefulWidget {
  const _BlocoLogs();

  @override
  State<_BlocoLogs> createState() => _BlocoLogsState();
}

class _BlocoLogsState extends State<_BlocoLogs> {
  final _linhas = <String>[];
  Process? _processo;
  String _filtro = '';
  String? _erro;
  final _rolagem = ScrollController();

  static const _maximo = 1000;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final p = await acompanhar(logs());
    if (!mounted) {
      p?.kill();
      return;
    }
    if (p == null) {
      setState(() => _erro = 'journalctl não encontrado. Sem ele não dá para acompanhar os logs aqui.');
      return;
    }
    _processo = p;
    void adicionar(String linha) {
      if (!mounted) return;
      setState(() {
        _linhas.add(linha);
        if (_linhas.length > _maximo) _linhas.removeRange(0, _linhas.length - _maximo);
      });
    }

    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(adicionar);
    p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(adicionar);
  }

  @override
  void dispose() {
    _processo?.kill();
    _rolagem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final f = _filtro.toLowerCase();
    final visiveis = f.isEmpty ? _linhas : _linhas.where((l) => l.toLowerCase().contains(f)).toList();
    final mono = tema.textTheme.bodySmall?.copyWith(fontFamily: familiaMono, color: cores.onSurface);
    return BlocoDeConfiguracao(
      titulo: 'Logs do servidor',
      icone: Symbols.receipt_long,
      acao: IconButton(
        tooltip: 'Copiar logs',
        icon: const Icon(Symbols.content_copy, size: 20),
        onPressed: visiveis.isEmpty ? null : () => copiar(context, visiveis.join('\n')),
      ),
      filhos: [
        TextField(
          onChanged: (v) => setState(() => _filtro = v),
          decoration: const InputDecoration(prefixIcon: Icon(Symbols.filter_list), labelText: 'Filtrar'),
        ),
        const SizedBox(height: Espacos.esp2),
        if (_erro case final e?) ...[
          CaixaDeMensagens(tom: TomDaMensagem.erro, linhas: [e]),
          const SizedBox(height: Espacos.esp2),
        ],
        SizedBox(
          height: _alturaDoLog,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cores.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Raios.sm),
            ),
            child: visiveis.isEmpty
                ? Center(
                    child: Text(
                      _linhas.isEmpty ? 'Nenhuma linha de log ainda.' : 'Nenhuma linha com "$_filtro".',
                      style: tema.textTheme.bodySmall?.copyWith(color: cores.onSurfaceVariant),
                    ),
                  )
                : Scrollbar(
                    controller: _rolagem,
                    thumbVisibility: ehDesktop,
                    child: ListView.builder(
                      controller: _rolagem,
                      reverse: true,
                      padding: const EdgeInsets.all(Espacos.esp3),
                      itemCount: visiveis.length,
                      itemBuilder: (context, i) => SelectableText(visiveis[visiveis.length - 1 - i], style: mono),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
