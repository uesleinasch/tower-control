import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'conexao/pareamento.dart';
import 'estado/sala.dart';
import 'estado/servidor.dart';
import 'tela/raiz.dart';
import 'tela/sem_servidor.dart';
import 'tela/tema.dart';

Future<void> main(List<String> argumentos) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  if (Platform.isAndroid) {
    final servidor = ServidorRemoto(prefs);
    final sala = Sala(servidor);
    await ligarPareamento(servidor, aoParear: () => sala.canal..pausar()..iniciar());
    Timer? fechar;
    AppLifecycleListener(
      onPause: () => fechar = Timer(const Duration(seconds: 30), sala.canal.pausar),
      onResume: () {
        fechar?.cancel();
        sala.canal.iniciar();
      },
    );
    sala.iniciar();
    runApp(ControlTower(sala: sala, bloqueio: (_) => bloqueioDoCelular(sala, servidor)));
    return;
  }
  final sala = Sala(ServidorLocal(prefs))..iniciar();
  runApp(ControlTower(sala: sala));
}

class ControlTower extends StatelessWidget {
  const ControlTower({super.key, required this.sala, this.configuracao, this.bloqueio});

  final Sala sala;
  final WidgetBuilder? configuracao;
  final Widget? Function(BuildContext context)? bloqueio;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Control Tower',
        debugShowCheckedModeBanner: false,
        theme: temaClaro,
        darkTheme: temaEscuro,
        home: Raiz(sala: sala, configuracao: configuracao, bloqueio: bloqueio),
      );
}
