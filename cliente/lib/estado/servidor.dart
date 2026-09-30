import 'package:shared_preferences/shared_preferences.dart';

import '../conexao/http.dart';
import '../nucleo/enderecos.dart';

abstract class Servidor {
  Future<String?> resolver();
}

class ServidorLocal implements Servidor {
  ServidorLocal(this._prefs);

  final SharedPreferences _prefs;

  int get porta => _prefs.getInt('porta') ?? 7878;
  Future<void> definirPorta(int porta) => _prefs.setInt('porta', porta);

  @override
  Future<String?> resolver() async => '127.0.0.1:$porta';
}

class ServidorRemoto implements Servidor {
  ServidorRemoto(this._prefs, {this.sonda = sondar});

  final SharedPreferences _prefs;
  final Sonda sonda;

  List<String> get enderecos => _prefs.getStringList('enderecos') ?? const [];
  bool get pareado => enderecos.isNotEmpty;

  Future<void> definir(List<String> lista) => _prefs.setStringList('enderecos', lista);

  Future<bool> adicionarManual(String bruto) async {
    final endereco = normalizarEndereco(bruto);
    if (endereco == null) return false;
    await definir([endereco, ...enderecos.where((e) => e != endereco)]);
    return true;
  }

  @override
  Future<String?> resolver() async {
    final vencedor = await disputar(enderecos, sonda);
    if (vencedor == null) return null;
    await definir(renovar([vencedor.endereco, ...enderecos], vencedor.resposta));
    return vencedor.endereco;
  }
}
