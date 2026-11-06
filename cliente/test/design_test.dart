import 'dart:math';

import 'package:control_tower/nucleo/design.dart';
import 'package:control_tower/tela/tema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double contraste(Color a, Color b) {
  final (claro, escuro) = (max(a.computeLuminance(), b.computeLuminance()), min(a.computeLuminance(), b.computeLuminance()));
  return (claro + 0.05) / (escuro + 0.05);
}

void main() {
  test('classe de janela segue os cortes do Material 3', () {
    expect(ClasseDeJanela.de(360), ClasseDeJanela.compact);
    expect(ClasseDeJanela.de(599.9), ClasseDeJanela.compact);
    expect(ClasseDeJanela.de(600), ClasseDeJanela.medium);
    expect(ClasseDeJanela.de(839), ClasseDeJanela.medium);
    expect(ClasseDeJanela.de(840), ClasseDeJanela.expanded);
    expect(ClasseDeJanela.de(1199), ClasseDeJanela.expanded);
    expect(ClasseDeJanela.de(1200), ClasseDeJanela.large);
    expect(ClasseDeJanela.de(1600), ClasseDeJanela.extraLarge);
    expect(ClasseDeJanela.compact.margemLateral, 16);
    expect(ClasseDeJanela.medium.margemLateral, 24);
    expect(ClasseDeJanela.medium.comDoisPaineis, isFalse);
    expect(ClasseDeJanela.expanded.comDoisPaineis, isTrue);
  });

  test('estados do domínio caem no papel da tabela 3.4 do design system', () {
    const esperado = {
      'backlog': PapelDeEstado.neutro,
      'a_fazer': PapelDeEstado.fila,
      'na_fila': PapelDeEstado.fila,
      'em_andamento': PapelDeEstado.andamento,
      'rodando': PapelDeEstado.andamento,
      'em_revisao': PapelDeEstado.revisao,
      'esperando': PapelDeEstado.revisao,
      'bloqueada': PapelDeEstado.aviso,
      'pausada': PapelDeEstado.aviso,
      'sem_orcamento': PapelDeEstado.aviso,
      'parada': PapelDeEstado.aviso,
      'concluida': PapelDeEstado.sucesso,
      'concluido': PapelDeEstado.sucesso,
      'criada': PapelDeEstado.sucesso,
      'cancelada': PapelDeEstado.cancelado,
      'cancelado': PapelDeEstado.cancelado,
      'pulada': PapelDeEstado.cancelado,
      'falhou': PapelDeEstado.erro,
    };
    for (final MapEntry(key: estado, value: papel) in esperado.entries) {
      expect(papelDoEstado(estado), papel, reason: estado);
    }
    expect(papelDoEstado(null), PapelDeEstado.neutro);
    expect(papelDoEstado('desconhecido'), PapelDeEstado.neutro);
  });

  for (final brilho in Brightness.values) {
    test('cor de todo estado tem contraste de texto (4,5:1) sobre as superfícies no tema ${brilho.name}', () {
      final t = tema(brilho);
      final semanticas = t.extension<CoresSemanticas>()!;
      for (final papel in PapelDeEstado.values) {
        final cor = corDoPapel(papel, t.colorScheme, semanticas);
        for (final fundo in [t.colorScheme.surface, t.colorScheme.surfaceContainer, t.colorScheme.surfaceContainerLow]) {
          expect(contraste(cor, fundo), greaterThanOrEqualTo(4.5), reason: '$papel sobre $fundo');
        }
      }
    });

    test('pares das cores semânticas têm contraste de texto no tema ${brilho.name}', () {
      final s = tema(brilho).extension<CoresSemanticas>()!;
      for (final c in [s.sucesso, s.aviso]) {
        expect(contraste(c.sobre, c.cor), greaterThanOrEqualTo(4.5));
        expect(contraste(c.sobreContainer, c.container), greaterThanOrEqualTo(4.5));
      }
    });
  }

  test('inicial do avatar fica em preto ou branco com contraste de 4,5:1 sobre a cor da persona', () {
    expect(corDoTextoSobre(const Color(0xFFA9B0BF)), Colors.black);
    expect(corDoTextoSobre(const Color(0xFF10131A)), Colors.white);
    for (final cor in const [
      Color(0xFFA9B0BF),
      Color(0xFF5B8DEF),
      Color(0xFF9A6EE8),
      Color(0xFFE05A5A),
      Color(0xFF4FAE7C),
      Color(0xFF1F3A93),
      Color(0xFFFFD54F),
    ]) {
      expect(contraste(corDoTextoSobre(cor), cor), greaterThanOrEqualTo(4.5), reason: '$cor');
      expect(razaoDeContraste(cor, Colors.white), closeTo(contraste(cor, Colors.white), 1e-9));
    }
  });

  for (final brilho in Brightness.values) {
    test('nome na cor da persona chega a 4,5:1 sobre o cartão no tema ${brilho.name}', () {
      final fundo = tema(brilho).colorScheme.surfaceContainerLow;
      for (final cor in const [Color(0xFFA9B0BF), Color(0xFF5B8DEF), Color(0xFF9A6EE8), Color(0xFF1F3A93)]) {
        expect(contraste(corLegivelSobre(cor, fundo), fundo), greaterThanOrEqualTo(4.5), reason: '$cor');
      }
    });
  }

  test('cor da persona que já tem contraste não muda, e a clara escurece no tema claro', () {
    final fundo = tema(Brightness.light).colorScheme.surfaceContainerLow;
    const escura = Color(0xFF1F3A93);
    expect(corLegivelSobre(escura, fundo), escura);
    const alfred = Color(0xFFA9B0BF);
    final ajustada = corLegivelSobre(alfred, fundo);
    expect(ajustada, isNot(alfred));
    expect(ajustada.computeLuminance(), lessThan(alfred.computeLuminance()));
  });

  test('o tema usa a Inter e não sobrescreve papéis do esquema gerado', () {
    final t = tema(Brightness.dark);
    final gerado = ColorScheme.fromSeed(seedColor: corSemente, brightness: Brightness.dark);
    expect(t.textTheme.bodyMedium?.fontFamily, familiaTexto);
    expect(t.textTheme.bodyLarge?.letterSpacing, 0);
    expect(t.colorScheme.surface, gerado.surface);
    expect(t.colorScheme.primary, gerado.primary);
    expect(t.scaffoldBackgroundColor, gerado.surface);
  });

  test('a largura do painel fica entre o mínimo e o máximo e deixa espaço ao lado', () {
    expect(limitarLargura(320, minimo: 240, maximo: 560), 320);
    expect(limitarLargura(100, minimo: 240, maximo: 560), 240);
    expect(limitarLargura(900, minimo: 240, maximo: 560), 560);
    expect(limitarLargura(500, minimo: 240, maximo: 560, disponivel: 800, restoMinimo: 400), 400);
    expect(limitarLargura(500, minimo: 240, maximo: 560, disponivel: 500, restoMinimo: 400), 240);
    expect(passoDoDivisor, 16);
  });
}
