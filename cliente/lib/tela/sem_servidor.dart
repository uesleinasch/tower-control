import 'package:flutter/material.dart';

import '../conexao/canal.dart';
import '../estado/sala.dart';
import '../estado/servidor.dart';

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
    final cores = Theme.of(context).colorScheme;
    final pareado = widget.servidor.pareado;
    final tentando = widget.sala.canal.estado == EstadoConexao.reconectando;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(pareado ? Icons.wifi_off : Icons.link, size: 48, color: cores.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                pareado ? 'Servidor não encontrado' : 'Celular ainda não conectado',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                pareado
                    ? 'Nenhum dos endereços guardados respondeu: ${widget.servidor.enderecos.join(', ')}. '
                        'Confira se o computador está ligado e na mesma rede ou no Tailscale.'
                    : 'No computador, abra o Control Tower → Configuração → Celular e toque em '
                        '"Instalar e conectar" com o celular no cabo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cores.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (pareado)
                FilledButton.icon(
                  onPressed: tentando ? null : widget.sala.canal.reconectarJa,
                  icon: tentando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text(tentando ? 'Procurando…' : 'Tentar de novo'),
                ),
              const SizedBox(height: 28),
              Text('Ou informe o endereço à mão', style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: _manual,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(hintText: 'host:porta', errorText: _erro),
                onSubmitted: (_) => _usarManual(),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _usarManual, child: const Text('Conectar')),
            ]),
          ),
        ),
      ),
    );
  }
}
