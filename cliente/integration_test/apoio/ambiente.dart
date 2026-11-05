import 'dart:convert';
import 'dart:io';

class AmbienteDeTeste {
  const AmbienteDeTeste({
    required this.servidor,
    required this.porta,
    required this.modelo,
    required this.dados,
    required this.ticktask,
  });

  factory AmbienteDeTeste.lido() {
    const embutido = String.fromEnvironment('CT_AMBIENTE_JSON');
    const caminho = String.fromEnvironment('CT_AMBIENTE');
    final String texto;
    if (embutido.isNotEmpty) {
      texto = utf8.decode(base64.decode(embutido));
    } else if (caminho.isNotEmpty) {
      texto = File(caminho).readAsStringSync();
    } else {
      throw StateError('sem ambiente: passe --dart-define=CT_AMBIENTE=<pasta>/ambiente.json ou CT_AMBIENTE_JSON');
    }
    final json = jsonDecode(texto) as Map<String, dynamic>;
    return AmbienteDeTeste(
      servidor: json['servidor'] as String,
      porta: (json['porta'] as num).toInt(),
      modelo: json['modelo'] as String,
      dados: json['dados'] as String,
      ticktask: json['ticktask'] as String,
    );
  }

  final String servidor;
  final int porta;
  final String modelo;
  final String dados;
  final String ticktask;
}

final ambiente = AmbienteDeTeste.lido();
