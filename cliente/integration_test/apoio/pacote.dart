import 'dart:io';

const pacoteDeTeste = 'dev.ueslei.controltower.teste';

String pacoteEmExecucao() => File('/proc/self/cmdline').readAsStringSync().split('\u0000').first;

void exigirPacoteDeTeste(String pacote) {
  if (pacote != pacoteDeTeste) {
    throw StateError(
      'o teste do celular está rodando em "$pacote", e não em $pacoteDeTeste: '
      'limpar as prefs apagaria o pareamento do app de verdade (faltou CT_APP_TESTE=1 no build?)',
    );
  }
}
