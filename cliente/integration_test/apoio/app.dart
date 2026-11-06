import 'dart:io';

import 'package:control_tower/estado/equipes.dart';
import 'package:control_tower/estado/sala.dart';
import 'package:control_tower/main.dart' as app;
import 'package:control_tower/tela/painel.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'ambiente.dart';
import 'esperas.dart';

const tamanhoDaJanela = Size(1600, 1000);

app.ControlTower? _montado;

Future<void> subirDesktop(WidgetTester t, AmbienteDeTeste a) async {
  final montado = _montado;
  if (montado != null) {
    await t.pumpWidget(montado);
  } else {
    exigirXdgDeTeste(Platform.environment);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('porta', a.porta);
    Object? falhou;
    var subiu = false;
    app
        .main(['--sem-bandeja'])
        .then<void>(
          (_) => subiu = true,
          onError: (Object erro) {
            falhou = erro;
          },
        );
    await esperarAte(t, () {
      if (falhou != null) throw StateError('o main() do app falhou: $falhou');
      return subiu && find.byType(app.ControlTower).evaluate().isNotEmpty;
    }, descricao: 'o app subir');
    _montado = t.widget<app.ControlTower>(find.byType(app.ControlTower));
    await windowManager.setSize(tamanhoDaJanela);
    await esperarAte(
      t,
      () => t.view.physicalSize.width / t.view.devicePixelRatio >= tamanhoDaJanela.width - 1,
      descricao: 'a janela crescer para ${tamanhoDaJanela.width}',
    );
  }
  await esperarAte(t, () => salaDe(t).canal.conectado, descricao: 'o app conectar no servidor de teste');
}

void exigirXdgDeTeste(Map<String, String> ambiente) {
  for (final variavel in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_RUNTIME_DIR']) {
    final valor = ambiente[variavel] ?? '';
    final caminho = valor.isEmpty ? '' : Directory(valor).absolute.uri.normalizePath().toFilePath();
    if (!caminho.startsWith('/tmp/ct-xdg-')) {
      throw StateError('$variavel="$valor" não é uma pasta de teste em /tmp/ct-xdg-*: o app encostaria no app instalado');
    }
  }
}

Sala salaDe(WidgetTester t) => t.widget<app.ControlTower>(find.byType(app.ControlTower)).sala;

Future<void> aparecer(WidgetTester t, Finder alvo, {String? descricao, Duration prazo = prazoPadrao}) => esperarAte(
  t,
  () => alvo.evaluate().isNotEmpty,
  descricao: descricao ?? alvo.toString(describeSelf: true),
  prazo: prazo,
);

Future<void> tocar(WidgetTester t, Finder alvo, {String? descricao}) async {
  await aparecer(t, alvo, descricao: descricao);
  await t.ensureVisible(alvo.first);
  await t.pump();
  await t.tap(alvo.first);
  await t.pump();
}

Future<void> rolarAte(WidgetTester t, Finder alvo, {required Finder dentroDe}) async {
  await t.pump();
  if (alvo.evaluate().isNotEmpty) return;
  await aparecer(t, dentroDe);
  final rolagem = find.ancestor(of: dentroDe.first, matching: find.byType(Scrollable)).first;
  await t.scrollUntilVisible(alvo, 120, scrollable: rolagem, maxScrolls: 100);
  await t.pump();
}

Future<void> digitar(WidgetTester t, Finder campo, String texto) async {
  await aparecer(t, campo, descricao: campo.toString(describeSelf: true));
  await t.ensureVisible(campo.first);
  await t.enterText(campo.first, texto);
  await t.pump();
}

Finder campoRotulado(String rotulo) => find.ancestor(of: find.text(rotulo), matching: find.byType(TextField));

Finder botao(String texto) =>
    find.ancestor(of: find.text(texto), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

Future<void> verAba(WidgetTester t, AbaDaEquipe aba) async {
  final equipes = salaDe(t).equipes;
  if (equipes.aba == aba) return;
  const rotulos = {AbaDaEquipe.rotinas: 'Rotinas', AbaDaEquipe.workflows: 'Workflows', AbaDaEquipe.skills: 'Skills'};
  await tocar(t, botao(rotulos[aba == AbaDaEquipe.organograma ? equipes.aba : aba]!));
  await esperarAte(t, () => equipes.aba == aba, descricao: 'a aba $aba');
}

Finder seletorRotulado(String rotulo) =>
    find.ancestor(of: find.text(rotulo), matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField));

Future<void> escolherNoSeletor(WidgetTester t, Finder seletor, String opcao) async {
  await tocar(t, seletor);
  await aparecer(t, find.text(opcao), descricao: 'a opção "$opcao" no menu');
  await t.tap(find.text(opcao).last);
  await t.pump();
}

Future<void> irPara(WidgetTester t, String destino) async {
  await tocar(t, find.widgetWithText(ListTile, destino), descricao: 'o destino "$destino" na lateral');
}

Future<void> escolherEquipe(WidgetTester t, String id, String nome) async {
  await irPara(t, 'Equipes');
  final equipes = salaDe(t).equipes;
  await esperarAte(t, () => equipes.carregada, descricao: 'as equipes carregarem');
  if (equipes.atual?.id == id) return;
  await tocar(t, find.byWidgetPredicate((w) => w is DropdownButton<String>), descricao: 'o seletor de equipe');
  await aparecer(t, find.text(nome));
  await t.tap(find.text(nome).last);
  await esperarAte(t, () => equipes.atual?.id == id, descricao: 'a equipe $id na tela');
}

String? _janela;

Future<String> _xdotool(List<String> argumentos) async {
  final r = await Process.run('xdotool', argumentos);
  if (r.exitCode != 0) throw StateError('xdotool ${argumentos.join(' ')} falhou: ${r.stderr}');
  return '${r.stdout}'.trim();
}

// Sem a letra no mapa, o xdotool digita por um keycode sem tecla física, e o Flutter em debug
// derruba o app na asserção `physical != 0`. Por isso os acentos vão para as teclas F1 a F12.
const _teclasLivres = [67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 95, 96];
final _mapeadas = <int>{};

var _xvfbConferido = false;

Future<void> _exigirXvfb() async {
  if (_xvfbConferido) return;
  final tela = (Platform.environment['DISPLAY'] ?? '').split('.').first;
  final r = await Process.run('pgrep', ['-a', 'Xvfb']);
  final doXvfb = '${r.stdout}'.split('\n').any((linha) => linha.split(' ').contains(tela));
  if (tela.isEmpty || !doXvfb) {
    throw StateError('o teclado de teste digita em janelas do X e só roda dentro do Xvfb (DISPLAY=$tela)');
  }
  _xvfbConferido = true;
}

Future<void> _mapearAcentos(String texto) async {
  final faltam = {
    for (final c in texto.runes)
      if (c > 0x7e) c,
  }.difference(_mapeadas);
  if (faltam.isEmpty) return;
  await _exigirXvfb();
  final livres = _teclasLivres.skip(_mapeadas.length).toList();
  if (faltam.length > livres.length) {
    throw StateError('acentos demais para as teclas livres: ${String.fromCharCodes(faltam)}');
  }
  final argumentos = <String>[];
  for (final (i, c) in faltam.indexed) {
    if (c > 0xff) throw StateError('o teclado de teste só digita Latin-1: ${String.fromCharCode(c)}');
    argumentos.addAll(['-e', 'keycode ${livres[i]} = 0x${c.toRadixString(16).padLeft(4, '0')}']);
  }
  final r = await Process.run('xmodmap', argumentos);
  if (r.exitCode != 0) throw StateError('xmodmap falhou: ${r.stderr}');
  _mapeadas.addAll(faltam);
}

Future<void> _focarJanela() async {
  await _exigirXvfb();
  _janela ??= (await _xdotool(['search', '--onlyvisible', '--name', '^Control Tower\$'])).split('\n').first;
  await _xdotool(['windowfocus', '--sync', _janela!]);
}

EditableText _editavel(WidgetTester t, Finder campo) =>
    t.widget<EditableText>(find.descendant(of: campo.first, matching: find.byType(EditableText)));

Future<void> digitarNoTeclado(WidgetTester t, Finder campo, String texto, {Future<void> Function()? noMeio}) async {
  await _exigirXvfb();
  await aparecer(t, campo, descricao: campo.toString(describeSelf: true));
  await t.ensureVisible(campo.first);
  await t.pump();
  await _mapearAcentos(texto);
  await _focarJanela();
  await t.tap(campo.first);
  await esperarAte(
    t,
    () => _editavel(t, campo).focusNode.hasFocus,
    descricao: 'o foco em ${campo.toString(describeSelf: true)}',
  );
  final letras = texto.runes.length;
  final metade = String.fromCharCodes(texto.runes.take(letras ~/ 2));
  final resto = String.fromCharCodes(texto.runes.skip(letras ~/ 2));
  final inicio = _editavel(t, campo).controller.text.runes.length;
  final nome = campo.toString(describeSelf: true);
  for (final (i, (parte, esperadas)) in [(metade, inicio + letras ~/ 2), (resto, inicio + letras)].indexed) {
    if (i == 1) {
      await aparecer(t, campo, descricao: '$nome continuar na tela depois do ruído', prazo: const Duration(seconds: 5));
    }
    final antes = _editavel(t, campo).controller.text;
    for (final linha in parte.split('\n').indexed) {
      if (linha.$1 > 0) await _xdotool(['key', '--delay', '15', 'Return']);
      if (linha.$2.isNotEmpty) await _xdotool(['type', '--delay', '15', '--', linha.$2]);
    }
    await esperarAte(
      t,
      () => _editavel(t, campo).controller.text.runes.length >= esperadas,
      descricao: '$esperadas letras em $nome (antes de digitar "$parte", o campo tinha "$antes")',
      prazo: const Duration(seconds: 15),
    );
    if (i == 0) await noMeio?.call();
  }
}

Future<void> aparecerNoPainel(WidgetTester t, Finder alvo, {required String descricao, Duration prazo = prazoPadrao}) {
  final lista = find.descendant(of: find.byType(TelaPainel), matching: find.byType(Scrollable)).first;
  return esperarAte(t, () {
    if (alvo.evaluate().isNotEmpty) return true;
    final posicao = t.state<ScrollableState>(lista).position;
    final fim = posicao.maxScrollExtent;
    posicao.jumpTo(posicao.pixels >= fim ? 0 : (posicao.pixels + 300).clamp(0, fim).toDouble());
    return false;
  }, descricao: descricao, prazo: prazo);
}

Future<void> aprovarNoPainel(WidgetTester t, int tarefa, {Duration prazo = prazoPadrao}) async {
  final titulo = find.text('#$tarefa espera sua aprovação');
  await aparecerNoPainel(t, titulo, descricao: 'o pedido de aprovação de #$tarefa no painel', prazo: prazo);
  final cartao = find.ancestor(of: titulo, matching: find.byType(Card)).first;
  await tocar(t, find.descendant(of: cartao, matching: botao('Aprovar')));
}

Finder cartaoDaPosicao(String id) => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_Cartao' && ((w as dynamic).posicao as dynamic).id == id,
  description: 'o cartão da posição $id',
);

Future<void> arrastar(WidgetTester t, Offset de, Offset ate) async {
  final gesto = await t.startGesture(de, kind: PointerDeviceKind.mouse);
  await t.pump();
  const passos = 12;
  for (var i = 1; i <= passos; i++) {
    await gesto.moveTo(Offset.lerp(de, ate, i / passos)!);
    await t.pump();
  }
  await gesto.up();
  await t.pump();
}
