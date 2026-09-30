import 'package:control_tower/nucleo/acoes.dart';
import 'package:control_tower/nucleo/autostart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ações', () {
    test('serviço mapeia verbo para systemctl --user na unidade fixa', () {
      final c = servico(VerboServico.reiniciar);
      expect(c.executavel, 'systemctl');
      expect(c.argumentos, ['--user', 'restart', 'control-tower.service']);
      expect(servico(VerboServico.estado).argumentos[1], 'is-active');
    });

    test('adb recusa serial que não é serial', () {
      expect(() => adbInstalar('abc; rm -rf ~', '/x.apk'), throwsArgumentError);
      expect(() => adbConectar('\$(id)', ['a:1']), throwsArgumentError);
      expect(adbInstalar('0088238899', '/x.apk').argumentos, ['-s', '0088238899', 'install', '-r', '/x.apk']);
    });

    test('conectar leva o JSON entre aspas simples para o shell do aparelho', () {
      final c = adbConectar('emulator-5554', ['10.0.0.2:7878', '100.1.1.1:7878']);
      expect(c.argumentos.sublist(2, 7), ['shell', 'am', 'start', '-n', 'dev.ueslei.controltower/.MainActivity']);
      expect(c.argumentos.last, '\'["10.0.0.2:7878","100.1.1.1:7878"]\'');
    });

    test('reverso pelo cabo e endereço local por último', () {
      expect(adbReverso('0088238899', 7878).argumentos, ['-s', '0088238899', 'reverse', 'tcp:7878', 'tcp:7878']);
      expect(enderecosParaCelular(['10.0.0.2:7878'], 7878), ['10.0.0.2:7878', '127.0.0.1:7878']);
    });

    test('aspas simples escapam aspas simples', () {
      expect(aspasShell("it's"), "'it'\\''s'");
    });

    test('linger valida o usuário', () {
      expect(linger('unascimento@jacto.local').argumentos, [
        'show-user',
        'unascimento@jacto.local',
        '--property=Linger',
        '--value',
      ]);
      expect(() => linger('a b'), throwsArgumentError);
    });

    test('lê a saída do adb devices -l', () {
      const saida = '''List of devices attached
* daemon started successfully
0088238899             device usb:1-1 product:rhode model:moto_g52 device:rhode transport_id:1
emulator-5554          unauthorized transport_id:2

''';
      final lista = dispositivosAdb(saida);
      expect(lista.map((d) => d.serial), ['0088238899', 'emulator-5554']);
      expect(lista.first.modelo, 'moto g52');
      expect(lista.first.pronto, isTrue);
      expect(lista.last.pronto, isFalse);
      expect(lista.last.modelo, 'emulator-5554');
    });
  });

  group('apk', () {
    test('procura o instalado e, rodando do build, as saídas do projeto', () {
      expect(candidatosApk(home: '/h', executavel: '/h/.local/share/control-tower-cliente/control-tower'),
          ['/h/.local/share/control-tower-cliente/control-tower.apk']);
      expect(
        candidatosApk(home: '/h', executavel: '/r/cliente/build/linux/x64/release/bundle/control-tower', forcado: '/x.apk'),
        [
          '/x.apk',
          '/h/.local/share/control-tower-cliente/control-tower.apk',
          '/r/cliente/build/app/outputs/flutter-apk/app-release.apk',
          '/r/cliente/build/app/outputs/flutter-apk/app-debug.apk',
        ],
      );
    });

    test('instalado pelo .deb, o APK fica ao lado do executável', () {
      expect(candidatosApk(home: '/h', executavel: '/opt/control-tower/cliente/control-tower'), [
        '/opt/control-tower/cliente/control-tower.apk',
        '/h/.local/share/control-tower-cliente/control-tower.apk',
      ]);
    });
  });

  group('autostart', () {
    test('entrada de autostart sobe na bandeja', () {
      final t = entradaDesktop('/home/a b/ct', bandeja: true, icone: 'control-tower');
      expect(t, contains('Exec="/home/a b/ct" --bandeja\n'));
      expect(t, contains('X-GNOME-Autostart-enabled=true'));
      expect(t, startsWith('[Desktop Entry]\n'));
    });

    test('entrada de menu não leva --bandeja e escapa caracteres especiais', () {
      final t = entradaDesktop(r'/opt/$x"y', bandeja: false);
      expect(t, contains(r'Exec="/opt/\$x\"y"' '\n'));
      expect(t, isNot(contains('--bandeja')));
    });

    test('caminho respeita XDG_CONFIG_HOME', () {
      expect(caminhoAutostart({'HOME': '/h'}), '/h/.config/autostart/control-tower.desktop');
      expect(caminhoAutostart({'HOME': '/h', 'XDG_CONFIG_HOME': '/c'}), '/c/autostart/control-tower.desktop');
    });

    test('argumento --bandeja', () {
      expect(pedeBandeja(['--bandeja']), isTrue);
      expect(pedeBandeja([]), isFalse);
    });
  });
}
