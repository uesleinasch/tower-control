import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'conexao/pareamento.dart';
import 'estado/sala.dart';
import 'estado/servidor.dart';
import 'nucleo/autostart.dart';
import 'sistema/aviso_na_tela.dart';
import 'sistema/desktop.dart';
import 'sistema/notificador.dart';
import 'sistema/servico_avisos.dart';
import 'tela/configuracao.dart';
import 'tela/raiz.dart';
import 'tela/sem_servidor.dart';
import 'tela/tema.dart';

Future<void> main(List<String> argumentos) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  if (Platform.isAndroid) {
    final servidor = ServidorRemoto(prefs);
    final sala = Sala(servidor);
    const avisos = ServicoDeAvisos();
    avisos.preparar();
    final notificador = Notificador(aparelho: aparelhoCelular);
    Future<String?> endereco() async => sala.canal.endereco ?? await servidor.resolver();
    await notificador.iniciar(
      aoResponder: (resposta) => responderAoAviso(resposta, sala, notificador, endereco),
      emSegundoPlano: agirEmSegundoPlano,
    );
    Future<void> ligarAvisos() async {
      final primeiraVez = !prefs.containsKey(chaveAvisosLigados);
      if (!(prefs.getBool(chaveAvisosLigados) ?? true) || !servidor.pareado) return;
      await prefs.setBool(chaveAvisosLigados, true);
      await avisos.ligar(pedirPermissoes: primeiraVez);
    }

    await ligarPareamento(servidor, aoParear: () {
      sala.canal
        ..pausar()
        ..iniciar();
      unawaited(ligarAvisos());
    });
    Timer? fechar;
    AppLifecycleListener(
      onPause: () => fechar = Timer(const Duration(seconds: 30), sala.canal.pausar),
      onResume: () {
        fechar?.cancel();
        sala.canal.iniciar();
      },
      onStateChange: (estado) => sala.presenca.definirPrimeiroPlano(estado == AppLifecycleState.resumed),
    );
    sala.iniciar();
    runApp(ControlTower(
      sala: sala,
      bloqueio: (_) => bloqueioDoCelular(sala, servidor),
      configuracao: (_) => TelaConfiguracaoCelular(sala: sala, servico: avisos, prefs: prefs),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ligarAvisos();
      final abriu = await notificador.respostaQueAbriuOApp();
      if (abriu != null) await responderAoAviso(abriu, sala, notificador, endereco);
    });
    return;
  }
  final servidor = ServidorLocal(prefs);
  final sala = Sala(servidor);
  final desktop = Desktop(sala);
  if (!await assumirInstanciaUnica(desktop.mostrar)) exit(0);
  sala.iniciar();
  AppLifecycleListener(
    onStateChange: (estado) => sala.presenca.definirPrimeiroPlano(estado == AppLifecycleState.resumed),
  );
  final autostart = Autostart();
  runApp(ControlTower(
    sala: sala,
    configuracao: (_) => TelaConfiguracao(sala: sala, servidor: servidor, autostart: autostart),
  ));
  await desktop.iniciar(naBandeja: pedeBandeja(argumentos));
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
