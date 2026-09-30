import 'package:flutter/services.dart';

import '../estado/servidor.dart';
import '../nucleo/enderecos.dart';

const _canal = MethodChannel('control_tower/pareamento');

Future<bool> ligarPareamento(ServidorRemoto servidor, {required void Function() aoParear}) async {
  Future<bool> aplicar(Object? bruto) async {
    if (bruto is! String) return false;
    final lista = enderecosDoPareamento(bruto);
    if (lista.isEmpty) return false;
    await servidor.definir(lista);
    return true;
  }

  _canal.setMethodCallHandler((chamada) async {
    if (chamada.method == 'servidores' && await aplicar(chamada.arguments)) aoParear();
  });
  try {
    return await aplicar(await _canal.invokeMethod<String>('pendente'));
  } on PlatformException {
    return false;
  }
}
