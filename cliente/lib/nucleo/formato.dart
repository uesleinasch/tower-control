String formatarBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.round()} kB';
  final mb = (kb / 1024).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '').replaceFirst('.', ',');
  return '$mb MB';
}

String _doisDigitos(int n) => n.toString().padLeft(2, '0');

String hora(DateTime data) => '${_doisDigitos(data.hour)}:${_doisDigitos(data.minute)}';

const _meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

String quando(DateTime? data, {DateTime? agora}) {
  if (data == null) return '';
  final hoje = agora ?? DateTime.now();
  bool mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (mesmoDia(data, hoje)) return hora(data);
  if (mesmoDia(data, DateTime(hoje.year, hoje.month, hoje.day - 1))) return 'ontem';
  return '${data.day}/${_meses[data.month - 1]}';
}

const limiteAnexo = 10 * 1024 * 1024;
