import 'tarefas.dart';

const capacidadesDePosicao = ['arquivos', 'comandos', 'ticktask', 'memoria', 'board'];

const nomesDeCapacidade = {
  'arquivos': 'arquivos',
  'comandos': 'comandos',
  'ticktask': 'TickTask',
  'memoria': 'memória',
  'board': 'board',
};

const politicasDeAprovacao = {
  'sempre': 'pede todo comando',
  'sensiveis': 'pede só os sensíveis',
  'auto': 'automático (sensíveis ainda pedem)',
};

const larguraDoCartao = 220.0;
const alturaDoCartao = 78.0;
const topoDoOrganograma = 110.0;
const margemDoOrganograma = 20.0;
const distanciaX = 280.0;
const larguraDoUeslei = 120.0;
const alturaDoUeslei = 44.0;

final _slug = RegExp(r'^[a-z][a-z0-9-]{0,47}$');
final _persona = RegExp(r'^[a-z]{2,24}$');

class ErroDeOrganograma implements Exception {
  const ErroDeOrganograma(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

const _semAcento = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'é': 'e', 'ê': 'e', 'è': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i',
  'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

String slugDe(String texto) {
  final base = texto.toLowerCase().split('').map((c) => _semAcento[c] ?? c).join();
  final slug = base.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  final comLetra = slug.isEmpty || !RegExp(r'^[a-z]').hasMatch(slug) ? 'p-$slug' : slug;
  return comLetra.length > 48 ? comLetra.substring(0, 48).replaceAll(RegExp(r'-+$'), '') : comLetra;
}

String idLivre(String base, Iterable<String> usados) {
  final ocupados = usados.toSet();
  if (!ocupados.contains(base)) return base;
  for (var n = 2;; n++) {
    final candidato = '$base-$n';
    if (!ocupados.contains(candidato)) return candidato;
  }
}

bool formaCiclo(EquipeResumo e, String filho, String chefe) {
  final chefes = {for (final p in e.posicoes) p.id: p.respondeA, filho: chefe};
  final vistos = <String>{};
  for (String? atual = filho; atual != null; atual = chefes[atual]) {
    if (!vistos.add(atual)) return true;
  }
  return false;
}

EquipeResumo _trocar(EquipeResumo e, String id, PosicaoResumo Function(PosicaoResumo) mudar) {
  if (e.posicao(id) == null) throw ErroDeOrganograma('a posição $id não existe');
  return e.copiar(posicoes: [for (final p in e.posicoes) p.id == id ? mudar(p) : p]);
}

EquipeResumo mover(EquipeResumo e, String id, double x, double y) {
  if (e.posicao(id) == null) throw ErroDeOrganograma('a posição $id não existe');
  return e.copiar(layout: {...e.layout, id: (x: x < 0 ? 0 : x.roundToDouble(), y: y < 0 ? 0 : y.roundToDouble())});
}

EquipeResumo ligar(EquipeResumo e, String filho, String chefe) {
  if (filho == chefe) throw const ErroDeOrganograma('uma posição não pode responder a si mesma');
  if (e.posicao(chefe) == null) throw ErroDeOrganograma('a posição $chefe não existe');
  if (formaCiclo(e, filho, chefe)) throw const ErroDeOrganograma('essa ligação formaria um ciclo em "responde a"');
  return _trocar(e, filho, (p) => p.copiar(respondeA: () => chefe));
}

EquipeResumo soltar(EquipeResumo e, String id) => _trocar(e, id, (p) => p.copiar(respondeA: () => null));

({EquipeResumo equipe, String id}) adicionarPosicao(EquipeResumo e, String titulo) {
  final limpo = titulo.trim().isEmpty ? 'posição' : titulo.trim();
  final id = idLivre(slugDe(limpo), e.posicoes.map((p) => p.id));
  final maiorX = e.layout.values.fold<double>(-distanciaX, (m, p) => p.x > m ? p.x : m);
  final nova = PosicaoResumo(id: id, titulo: limpo, capacidades: const ['arquivos']);
  return (
    equipe: e.copiar(posicoes: [...e.posicoes, nova], layout: {...e.layout, id: (x: maiorX + distanciaX, y: 0)}),
    id: id,
  );
}

EquipeResumo removerPosicao(EquipeResumo e, String id) {
  final alvo = e.posicao(id);
  if (alvo == null) throw ErroDeOrganograma('a posição $id não existe');
  return e.copiar(
    posicoes: [
      for (final p in e.posicoes)
        if (p.id != id) p.respondeA == id ? p.copiar(respondeA: () => alvo.respondeA) : p,
    ],
    layout: {...e.layout}..remove(id),
  );
}

EquipeResumo editarPosicao(EquipeResumo e, String id, PosicaoResumo Function(PosicaoResumo) mudar) => _trocar(e, id, mudar);

List<String> validarOrganograma(EquipeResumo e, Set<String> personas) {
  final erros = <String>[];
  if (!_slug.hasMatch(e.id)) erros.add('equipe: id inválido (${e.id})');
  if (e.nome.trim().isEmpty) erros.add('equipe: nome obrigatório');
  final ids = <String>{};
  final ocupadas = <String>{};
  for (final p in e.posicoes) {
    if (!_slug.hasMatch(p.id)) erros.add('posição: id inválido (${p.id})');
    if (!ids.add(p.id)) erros.add('posição ${p.id}: id repetido');
    if (p.titulo.trim().isEmpty) erros.add('posição ${p.id}: título obrigatório');
    final persona = p.persona;
    if (persona != null) {
      if (!_persona.hasMatch(persona) || !personas.contains(persona)) erros.add('posição ${p.id}: persona desconhecida ($persona)');
      if (!ocupadas.add(persona)) erros.add('persona $persona: ocupa mais de uma posição na mesma equipe');
    }
    final estranha = p.capacidades.where((c) => !capacidadesDePosicao.contains(c));
    if (estranha.isNotEmpty) erros.add('posição ${p.id}: capacidade desconhecida (${estranha.first})');
  }
  for (final p in e.posicoes) {
    final chefe = p.respondeA;
    if (chefe == null) continue;
    if (chefe == p.id) {
      erros.add('posição ${p.id}: não pode responder a si mesma');
    } else if (!ids.contains(chefe)) {
      erros.add('posição ${p.id}: responde a posição inexistente ($chefe)');
    }
  }
  final ciclo = e.posicoes.where((p) => p.respondeA != null && formaCiclo(e, p.id, p.respondeA!)).firstOrNull;
  if (ciclo != null) erros.add('posição ${ciclo.id}: a cadeia de "responde a" forma um ciclo');
  return erros;
}

Ponto cantoDoCartao(EquipeResumo e, String id) {
  final p = e.ponto(id);
  return (x: p.x + margemDoOrganograma, y: p.y + topoDoOrganograma);
}

({double largura, double altura}) tamanhoDoOrganograma(EquipeResumo e) {
  var largura = larguraDoUeslei + 2 * margemDoOrganograma;
  var altura = topoDoOrganograma + margemDoOrganograma;
  for (final p in e.posicoes) {
    final canto = cantoDoCartao(e, p.id);
    if (canto.x + larguraDoCartao + margemDoOrganograma > largura) largura = canto.x + larguraDoCartao + margemDoOrganograma;
    if (canto.y + alturaDoCartao + margemDoOrganograma > altura) altura = canto.y + alturaDoCartao + margemDoOrganograma;
  }
  return (largura: largura + distanciaX, altura: altura + 160);
}

Ponto cantoDoUeslei(EquipeResumo e) {
  final raizes = e.posicoes.where((p) => p.respondeA == null || e.posicao(p.respondeA!) == null).toList();
  if (raizes.isEmpty) return (x: margemDoOrganograma, y: 16);
  final xs = raizes.map((p) => cantoDoCartao(e, p.id).x);
  final meio = (xs.reduce((a, b) => a < b ? a : b) + xs.reduce((a, b) => a > b ? a : b) + larguraDoCartao) / 2;
  return (x: meio - larguraDoUeslei / 2 < 0 ? 0 : meio - larguraDoUeslei / 2, y: 16);
}

sealed class Alvo {
  const Alvo();
}

class NoUeslei extends Alvo {
  const NoUeslei();
}

class NaPosicao extends Alvo {
  const NaPosicao(this.id);
  final String id;
}

Alvo? alvoEm(EquipeResumo e, double x, double y) {
  final u = cantoDoUeslei(e);
  if (x >= u.x && x <= u.x + larguraDoUeslei && y >= u.y && y <= u.y + alturaDoUeslei) return const NoUeslei();
  for (final p in e.posicoes.reversed) {
    final c = cantoDoCartao(e, p.id);
    if (x >= c.x && x <= c.x + larguraDoCartao && y >= c.y && y <= c.y + alturaDoCartao) return NaPosicao(p.id);
  }
  return null;
}

EquipeResumo ligarPelaAlca(EquipeResumo e, String origem, Alvo? destino) => switch (destino) {
      NoUeslei() => soltar(e, origem),
      NaPosicao(:final id) when id != origem => ligar(e, id, origem),
      _ => e,
    };
