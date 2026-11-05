import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart' as bandeja;
import 'package:window_manager/window_manager.dart';

import '../conexao/canal.dart';
import '../estado/sala.dart';
import '../nucleo/acoes.dart';
import '../nucleo/autostart.dart';
import 'executor.dart';

String get _soquete {
  final base = Platform.environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path;
  return '$base/control-tower-cliente.sock';
}

Future<bool> assumirInstanciaUnica(void Function() aoChamar) async {
  final endereco = InternetAddress(_soquete, type: InternetAddressType.unix);
  Socket? outro;
  try {
    outro = await Socket.connect(endereco, 0).timeout(const Duration(seconds: 1));
  } catch (_) {
    final arquivo = File(_soquete);
    if (arquivo.existsSync()) arquivo.deleteSync();
  }
  if (outro != null) {
    outro.destroy();
    return false;
  }
  final servidor = await ServerSocket.bind(endereco, 0);
  servidor.listen((conexao) {
    aoChamar();
    conexao.destroy();
  });
  return true;
}

class Autostart {
  File get _arquivo => File(caminhoAutostart(Platform.environment));

  bool get ligado => _arquivo.existsSync();

  Future<void> definir(bool ligar) async {
    if (!ligar) {
      if (_arquivo.existsSync()) await _arquivo.delete();
      return;
    }
    await _arquivo.parent.create(recursive: true);
    await _arquivo.writeAsString(entradaDesktop(Platform.resolvedExecutable, bandeja: true, icone: 'control-tower'));
  }
}

class Desktop with WindowListener {
  Desktop(this.sala);

  final Sala sala;
  bandeja.TrayIcon? _icone;
  String? _iconeAtual;

  Future<void> iniciar({required bool naBandeja, bool comBandeja = true}) async {
    sala.presenca.definirPrimeiroPlano(!naBandeja);
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(size: Size(1180, 780), minimumSize: Size(420, 560), center: true, title: 'Control Tower'),
      () async {
        await windowManager.setPreventClose(true);
        if (!naBandeja) await mostrar();
      },
    );
    windowManager.addListener(this);
    if (!comBandeja) return;
    _montarBandeja();
    sala.canal.addListener(_atualizarBandeja);
    _atualizarBandeja();
  }

  Future<void> mostrar() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> sair() async {
    sala.canal.removeListener(_atualizarBandeja);
    _icone?.dispose();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onWindowClose() {
    sala.presenca.definirPrimeiroPlano(false);
    windowManager.hide();
  }

  @override
  void onWindowFocus() => sala.presenca.definirPrimeiroPlano(true);

  @override
  void onWindowBlur() => sala.presenca.definirPrimeiroPlano(false);

  void _montarBandeja() {
    final icone = bandeja.TrayIcon.create();
    if (icone == null) return;
    final menu = bandeja.Menu.create()!;
    void item(String rotulo, void Function() acao) {
      final i = bandeja.MenuItem.createWithLabelAndType(rotulo, bandeja.MenuItemType.normal);
      if (i == null) return;
      i.addListener((e) {
        if (e is bandeja.MenuItemClickedEvent) acao();
      });
      menu.addItem(i);
    }

    item('Abrir Control Tower', mostrar);
    item('Nova conversa', () async {
      await mostrar();
      sala.pedirNovaConversa();
    });
    menu.addSeparator();
    item('Reiniciar servidor', () => rodar(servico(VerboServico.reiniciar)));
    menu.addSeparator();
    item('Sair', sair);
    // No Linux o cnativeapi ignora o Activate do StatusNotifierItem e só exporta o menu
    // com o gatilho "clicked"; sem isto o clique no ícone não faz nada.
    icone
      ..setContextMenu(menu)
      ..setContextMenuTrigger(bandeja.ContextMenuTrigger.clicked)
      ..setVisible(true);
    _icone = icone;
  }

  void _atualizarBandeja() {
    final icone = _icone;
    if (icone == null) return;
    final (arquivo, dica) = switch (sala.canal.estado) {
      EstadoConexao.conectado => ('assets/bandeja-ok.png', 'Control Tower — servidor de pé'),
      EstadoConexao.reconectando => ('assets/bandeja-reconectando.png', 'Control Tower — reconectando'),
      EstadoConexao.semServidor => ('assets/bandeja-parado.png', 'Control Tower — servidor parado'),
    };
    if (arquivo == _iconeAtual) return;
    final imagem = bandeja.ImageAsset.fromAsset(arquivo);
    if (imagem == null) return;
    icone
      ..icon = imagem
      ..setTooltip(dica);
    _iconeAtual = arquivo;
  }
}
