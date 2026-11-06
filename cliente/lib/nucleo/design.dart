abstract final class Espacos {
  static const double esp1 = 4;
  static const double esp2 = 8;
  static const double esp3 = 12;
  static const double esp4 = 16;
  static const double esp5 = 24;
  static const double esp6 = 32;
  static const double esp7 = 48;
}

abstract final class Raios {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 28;
}

const double larguraDeLeitura = 720;

enum ClasseDeJanela {
  compact,
  medium,
  expanded,
  large,
  extraLarge;

  static ClasseDeJanela de(double largura) {
    if (largura < 600) return compact;
    if (largura < 840) return medium;
    if (largura < 1200) return expanded;
    if (largura < 1600) return large;
    return extraLarge;
  }

  bool get comBarraInferior => this == compact;
  bool get comDoisPaineis => index >= expanded.index;
  double get margemLateral => this == compact ? Espacos.esp4 : Espacos.esp5;
}

enum PapelDeEstado { neutro, fila, andamento, revisao, aviso, sucesso, cancelado, erro }

PapelDeEstado papelDoEstado(String? estado) => switch (estado) {
      'backlog' => PapelDeEstado.neutro,
      'a_fazer' || 'na_fila' => PapelDeEstado.fila,
      'em_andamento' || 'rodando' => PapelDeEstado.andamento,
      'em_revisao' || 'esperando' || 'plano' => PapelDeEstado.revisao,
      'bloqueada' || 'pausada' || 'sem_orcamento' || 'mudanca' || 'parada' => PapelDeEstado.aviso,
      'concluida' || 'concluido' || 'aprovado' || 'entrega' || 'criada' => PapelDeEstado.sucesso,
      'cancelada' || 'cancelado' || 'interrompida' || 'pulada' => PapelDeEstado.cancelado,
      'falhou' || 'falha' || 'recusada' || 'erro' => PapelDeEstado.erro,
      _ => PapelDeEstado.neutro,
    };

const double passoDoDivisor = 16;

double limitarLargura(
  double desejada, {
  required double minimo,
  required double maximo,
  double disponivel = double.infinity,
  double restoMinimo = 0,
}) {
  final teto = maximo < disponivel - restoMinimo ? maximo : disponivel - restoMinimo;
  if (teto <= minimo || desejada < minimo) return minimo;
  return desejada > teto ? teto : desejada;
}
