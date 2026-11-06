import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../conexao/canal.dart';
import '../estado/sala.dart';
import '../estado/servidor.dart';
import '../nucleo/design.dart';

const _larguraDoConteudo = 420.0;

Widget? bloqueioDoCelular(Sala sala, ServidorRemoto servidor) {
  final perdido = sala.canal.estado == EstadoConexao.semServidor && !sala.conversas.carregada;
  if (servidor.pareado && !perdido) return null;
  return TelaSemServidor(sala: sala, servidor: servidor);
}

class TelaSemServidor extends StatefulWidget {
  const TelaSemServidor({super.key, required this.sala, required this.servidor});

  final Sala sala;
  final ServidorRemoto servidor;

  @override
  State<TelaSemServidor> createState() => _TelaSemServidorState();
}

class _TelaSemServidorState extends State<TelaSemServidor> {
  final _manual = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _usarManual() async {
    if (!await widget.servidor.adicionarManual(_manual.text)) {
      setState(() => _erro = 'Use o formato host:porta, por exemplo 100.113.47.75:7878');
      return;
    }
    setState(() => _erro = null);
    widget.sala.canal.reconectarJa();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final pareado = widget.servidor.pareado;
    final tentando = widget.sala.canal.estado == EstadoConexao.reconectando;
    final secundario = tema.textTheme.bodyMedium?.copyWith(color: cores.onSurfaceVariant);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Espacos.esp5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _larguraDoConteudo),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(pareado ? Symbols.wifi_off : Symbols.link, size: Espacos.esp7, color: cores.onSurfaceVariant),
              const SizedBox(height: Espacos.esp4),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  pareado ? 'Servidor não encontrado' : 'Celular ainda não conectado',
                  textAlign: TextAlign.center,
                  style: tema.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: Espacos.esp2),
              Text(
                pareado
                    ? 'Nenhum dos endereços guardados respondeu: ${widget.servidor.enderecos.join(', ')}. '
                        'Confira se o computador está ligado e na mesma rede ou no Tailscale.'
                    : 'No computador, abra o Control Tower → Configuração → Celular e toque em '
                        '"Instalar e conectar" com o celular no cabo.',
                textAlign: TextAlign.center,
                style: secundario,
              ),
              if (pareado) ...[
                const SizedBox(height: Espacos.esp5),
                FilledButton.icon(
                  onPressed: tentando ? null : widget.sala.canal.reconectarJa,
                  icon: tentando
                      ? const SizedBox.square(
                          dimension: Espacos.esp4,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Symbols.refresh),
                  label: Text(tentando ? 'Procurando…' : 'Tentar de novo'),
                ),
              ],
              const SizedBox(height: Espacos.esp6),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(Espacos.esp4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Informar o endereço à mão', style: tema.textTheme.titleMedium),
                    const SizedBox(height: Espacos.esp1),
                    Text('Use quando souber o IP do computador na rede ou no Tailscale.', style: secundario),
                    const SizedBox(height: Espacos.esp4),
                    TextField(
                      controller: _manual,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Endereço do servidor',
                        hintText: 'host:porta',
                        helperText: _erro == null ? 'Por exemplo 100.113.47.75:7878' : null,
                        errorText: _erro,
                      ),
                      onSubmitted: (_) => _usarManual(),
                    ),
                    const SizedBox(height: Espacos.esp3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: pareado
                          ? OutlinedButton(onPressed: _usarManual, child: const Text('Conectar'))
                          : FilledButton.tonal(onPressed: _usarManual, child: const Text('Conectar')),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
