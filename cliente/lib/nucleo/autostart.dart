String _aspasDesktop(String texto) =>
    '"${texto.replaceAllMapped(RegExp(r'[\\"`$]'), (m) => '\\${m[0]}')}"';

String entradaDesktop(String executavel, {required bool bandeja, String? icone}) => [
      '[Desktop Entry]',
      'Type=Application',
      'Name=Control Tower',
      'Comment=Sala de decisões',
      'Exec=${_aspasDesktop(executavel)}${bandeja ? ' --bandeja' : ''}',
      if (icone != null) 'Icon=$icone',
      'Terminal=false',
      'Categories=Utility;',
      'StartupWMClass=dev.ueslei.controltower',
      if (bandeja) 'X-GNOME-Autostart-enabled=true',
      '',
    ].join('\n');

String caminhoAutostart(Map<String, String> ambiente) {
  final config = ambiente['XDG_CONFIG_HOME'];
  final base = config != null && config.isNotEmpty ? config : '${ambiente['HOME']}/.config';
  return '$base/autostart/control-tower.desktop';
}

bool pedeBandeja(List<String> argumentos) => argumentos.contains('--bandeja');
