import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../conexao/http.dart';
import '../estado/sala.dart';
import '../estado/servidor.dart';
import '../nucleo/acoes.dart';
import '../nucleo/enderecos.dart';
import '../sistema/desktop.dart';
import '../sistema/executor.dart';
import '../sistema/servico_avisos.dart';
import 'comum.dart';

class TelaConfiguracao extends StatelessWidget {
  const TelaConfiguracao({super.key, required this.sala, required this.servidor, required this.autostart});

  final Sala sala;
  final ServidorLocal servidor;
  final Autostart autostart;

  @override
  Widget build(BuildContext context) => Column(children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: const ListTile(leading: Icon(Icons.settings_outlined), title: Text('Configuração')),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _BlocoServidor(sala: sala, servidor: servidor),
              _BlocoInicializacao(autostart: autostart),
              _BlocoRede(servidor: servidor),
              _BlocoCelular(servidor: servidor),
              const _BlocoLogs(),
            ]
                .map((b) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: Padding(padding: const EdgeInsets.only(bottom: 16), child: b),
                      ),
                    ))
                .toList(),
          ),
        ),
      ]);
}

class TelaConfiguracaoCelular extends StatelessWidget {
  const TelaConfiguracaoCelular({super.key, required this.sala, required this.servico, required this.prefs});

  final Sala sala;
  final ServicoDeAvisos servico;
  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) => Column(children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: ListTile(
              leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => sala.ir(Tela.conversas)),
              title: const Text('Configuração'),
            ),
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _BlocoAvisos(servico: servico, prefs: prefs),
          ]),
        ),
      ]);
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

  @override
  Widget build(BuildContext context) => _Bloco(
        titulo: 'Avisos',
        icone: Icons.notifications_outlined,
        acao: _Etiqueta(_rodando ? 'escutando' : 'parado', _rodando ? _verde : _ambar),
        filhos: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _ligados,
            onChanged: _ocupado ? null : _alternar,
            title: const Text('Avisos com o app fechado'),
            subtitle: const Text(
                'Respostas, aprovações do Alfred e lembretes do TickTask. Fica uma notificação fixa discreta enquanto escuta.'),
          ),
          if (!_permitidas)
            const _Saida('As notificações estão bloqueadas para o Control Tower nas configurações do Android.',
                erro: true),
        ],
      );
}

class _Bloco extends StatelessWidget {
  const _Bloco({required this.titulo, required this.icone, required this.filhos, this.acao});

  final String titulo;
  final IconData icone;
  final List<Widget> filhos;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cores.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icone, size: 20, color: cores.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleSmall)),
          ?acao,
        ]),
        const SizedBox(height: 12),
        ...filhos,
      ]),
    );
  }
}

class _Saida extends StatelessWidget {
  const _Saida(this.texto, {this.erro = false});

  final String texto;
  final bool erro;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          texto,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: erro ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      );
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, this.cor);

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: cor.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
        child: Text(texto, style: TextStyle(color: cor, fontSize: 12)),
      );
}

const _verde = Color(0xFF4FAE7C);
const _ambar = Color(0xFFE0A458);
const _vermelho = Color(0xFFE05A5A);

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
    if (porta == null || porta < 1 || porta > 65535) return;
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
    final ativo = _ativo == 'active';
    return _Bloco(
      titulo: 'Servidor',
      icone: Icons.dns_outlined,
      acao: IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _consultar),
      filhos: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Etiqueta(ativo ? 'rodando' : _ativo, ativo ? _verde : (_ativo == '…' ? _ambar : _vermelho)),
          _Etiqueta(
              _habilitado == 'enabled' ? 'sobe no login' : _habilitado, _habilitado == 'enabled' ? _verde : _ambar),
          _Etiqueta(_linger == 'yes' ? 'linger: sobe no boot' : 'linger: só com login', _linger == 'yes' ? _verde : _ambar),
        ]),
        if (_linger == 'no')
          const _Saida('Para o servidor subir no boot mesmo sem login, rode no terminal:\n'
              'loginctl enable-linger \$USER'),
        if (_habilitado == 'not-found' || _habilitado == 'não instalado')
          const _Saida('O serviço ainda não está instalado. No repositório, rode:\nbash scripts/servico.sh'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.tonalIcon(
            onPressed: _ocupado || ativo ? null : () => _executar(VerboServico.iniciar),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar'),
          ),
          FilledButton.tonalIcon(
            onPressed: _ocupado || !ativo ? null : () => _executar(VerboServico.parar),
            icon: const Icon(Icons.stop),
            label: const Text('Parar'),
          ),
          FilledButton.tonalIcon(
            onPressed: _ocupado ? null : () => _executar(VerboServico.reiniciar),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reiniciar'),
          ),
          if (_ocupado) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        if (_ultimo != null && !_ultimo!.ok) _Saida(_ultimo!.mensagem, erro: true),
        const SizedBox(height: 16),
        Row(children: [
          SizedBox(
            width: 140,
            child: TextField(
              controller: _porta,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Porta'),
              onSubmitted: (_) => _salvarPorta(),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: _salvarPorta, child: const Text('Aplicar')),
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
  Widget build(BuildContext context) => _Bloco(
        titulo: 'Inicialização',
        icone: Icons.power_settings_new,
        filhos: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: widget.autostart.ligado,
            onChanged: _alternar,
            title: const Text('Abrir na bandeja ao entrar na sessão'),
            subtitle: const Text('Só o ícone aparece no login; a janela abre ao clicar nele.'),
          ),
          if (_erro != null) _Saida(_erro!, erro: true),
        ],
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
    final r = _resposta;
    final porta = r?['porta'] ?? widget.servidor.porta;
    Widget linha(String rotulo, String? host) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(rotulo),
          subtitle: Text(host == null ? 'indisponível' : 'http://$host:$porta'),
          trailing: host == null
              ? null
              : IconButton(
                  tooltip: 'Copiar',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => copiar(context, 'http://$host:$porta'),
                ),
        );
    return _Bloco(
      titulo: 'Rede',
      icone: Icons.lan_outlined,
      acao: IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _carregar),
      filhos: [
        if (_carregando)
          const LinearProgressIndicator()
        else if (r == null)
          const _Saida('O servidor não respondeu em /enderecos. Ele está rodando?', erro: true)
        else ...[
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
    final cores = Theme.of(context).colorScheme;
    return _Bloco(
      titulo: 'Celular',
      icone: Icons.phone_android,
      filhos: [
        Text(
          'Conecte o celular no cabo com a depuração USB ligada. "Instalar e conectar" instala o app '
          'e já entrega a ele os endereços deste computador.',
          style: TextStyle(color: cores.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (_semAdb != null)
          _Saida('adb não encontrado. Instale com: sudo apt install adb\n$_semAdb', erro: true)
        else if (_dispositivos.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.usb_off),
            title: Text('Nenhum aparelho no cabo'),
          )
        else
          for (final d in _dispositivos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.smartphone),
              title: Text(d.modelo),
              subtitle: Text(switch (d.estado) {
                'device' => d.serial,
                'unauthorized' => 'Aceite o pedido de depuração USB na tela do celular',
                _ => '${d.serial} · ${d.estado}',
              }),
              trailing: _instalando == d.serial
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : FilledButton(
                      onPressed: d.pronto && _apk != null && _instalando == null ? () => _instalarEConectar(d) : null,
                      child: const Text('Instalar e conectar'),
                    ),
            ),
        if (_apk == null)
          const _Saida('APK não encontrado. Gere com: bash scripts/instalar-cliente.sh', erro: true)
        else
          Text('APK: $_apk', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
        if (_log.isNotEmpty) _Saida(_log.where((l) => l.trim().isNotEmpty).join('\n'), erro: _falhou),
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
      setState(() => _erro = 'journalctl não encontrado');
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
    final f = _filtro.toLowerCase();
    final visiveis = f.isEmpty ? _linhas : _linhas.where((l) => l.toLowerCase().contains(f)).toList();
    return _Bloco(
      titulo: 'Logs do servidor',
      icone: Icons.receipt_long_outlined,
      acao: IconButton(
        tooltip: 'Copiar',
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () => copiar(context, visiveis.join('\n')),
      ),
      filhos: [
        TextField(
          onChanged: (v) => setState(() => _filtro = v),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.filter_list), hintText: 'Filtrar'),
        ),
        const SizedBox(height: 8),
        if (_erro != null) _Saida(_erro!, erro: true),
        Container(
          height: 320,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            controller: _rolagem,
            reverse: true,
            padding: const EdgeInsets.all(10),
            itemCount: visiveis.length,
            itemBuilder: (context, i) => SelectableText(
              visiveis[visiveis.length - 1 - i],
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
