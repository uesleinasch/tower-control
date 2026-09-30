import 'dart:convert';

const unidade = 'control-tower.service';
const pacoteAndroid = 'dev.ueslei.controltower';

final _serial = RegExp(r'^[A-Za-z0-9.:_-]+$');
final _usuario = RegExp(r'^[A-Za-z0-9._@-]+$');

class Comando {
  const Comando(this.executavel, this.argumentos);

  final String executavel;
  final List<String> argumentos;

  @override
  String toString() => [executavel, ...argumentos].join(' ');
}

enum VerboServico { estado, habilitado, iniciar, parar, reiniciar }

Comando servico(VerboServico verbo) => Comando('systemctl', [
      '--user',
      switch (verbo) {
        VerboServico.estado => 'is-active',
        VerboServico.habilitado => 'is-enabled',
        VerboServico.iniciar => 'start',
        VerboServico.parar => 'stop',
        VerboServico.reiniciar => 'restart',
      },
      unidade,
    ]);

Comando linger(String usuario) {
  if (!_usuario.hasMatch(usuario)) throw ArgumentError.value(usuario, 'usuario');
  return Comando('loginctl', ['show-user', usuario, '--property=Linger', '--value']);
}

Comando logs() => const Comando('journalctl', ['--user', '-u', unidade, '-n', '200', '-f', '--no-pager', '-o', 'short']);

Comando adbDispositivos() => const Comando('adb', ['devices', '-l']);

String _exigirSerial(String serial) {
  if (!_serial.hasMatch(serial)) throw ArgumentError.value(serial, 'serial');
  return serial;
}

Comando adbInstalar(String serial, String apk) =>
    Comando('adb', ['-s', _exigirSerial(serial), 'install', '-r', apk]);

// adb shell junta o argv numa string e a entrega ao shell do aparelho: o JSON precisa
// ir entre aspas simples, senão as aspas duplas somem e o extra chega corrompido.
Comando adbConectar(String serial, List<String> enderecos) => Comando('adb', [
      '-s',
      _exigirSerial(serial),
      'shell',
      'am',
      'start',
      '-n',
      '$pacoteAndroid/.MainActivity',
      '--es',
      'servidores',
      aspasShell(jsonEncode(enderecos)),
    ]);

String aspasShell(String texto) => "'${texto.replaceAll("'", r"'\''")}'";

class Dispositivo {
  const Dispositivo(this.serial, this.estado, this.modelo);

  final String serial;
  final String estado;
  final String modelo;

  bool get pronto => estado == 'device';
}

List<Dispositivo> dispositivosAdb(String saida) => [
      for (final linha in const LineSplitter().convert(saida))
        if (!linha.startsWith('List of devices') && !linha.startsWith('*') && linha.trim().isNotEmpty)
          if (linha.trim().split(RegExp(r'\s+')) case [final serial, final estado, ...final resto]
              when _serial.hasMatch(serial))
            Dispositivo(
              serial,
              estado,
              resto
                  .firstWhere((c) => c.startsWith('model:'), orElse: () => 'model:$serial')
                  .substring(6)
                  .replaceAll('_', ' '),
            ),
    ];

List<String> candidatosApk({required String home, required String executavel, String? forcado}) {
  final bundle = executavel.substring(0, executavel.lastIndexOf('/'));
  final projeto = bundle.contains('/build/linux/') ? bundle.substring(0, bundle.indexOf('/build/linux/')) : null;
  return [
    if (forcado != null && forcado.isNotEmpty) forcado,
    '$home/.local/share/control-tower-cliente/control-tower.apk',
    if (projeto != null) ...[
      '$projeto/build/app/outputs/flutter-apk/app-release.apk',
      '$projeto/build/app/outputs/flutter-apk/app-debug.apk',
    ],
  ];
}
