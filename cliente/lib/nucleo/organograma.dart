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
const topoDoOrganograma = 40.0;
const margemDoOrganograma = 20.0;
const distanciaX = 280.0;
const distanciaY = 160.0;

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
  for (final p in e.posicoes) {
    erros.addAll(errosDaPolitica(e, p));
  }
  return erros;
}

List<String> errosDaPolitica(EquipeResumo e, PosicaoResumo posicao) {
  final politica = posicao.politica;
  final onde = 'posição ${posicao.id}';
  final invalida = politica.indexWhere((etapa) => !etapa.valida);
  if (invalida >= 0) return ['$onde: etapa ${invalida + 1}: quem decide é inválido'];
  final erros = <String>[];
  final aprovacoes = politica.where((etapa) => etapa.aprovacao).length;
  if (aprovacoes > 1) {
    erros.add('$onde: só pode haver uma aprovação');
  } else if (aprovacoes == 1 && !politica.last.aprovacao) {
    erros.add('$onde: a aprovação precisa ser a última etapa');
  }
  for (final (i, etapa) in politica.indexed) {
    final aqui = '$onde: etapa ${i + 1}';
    if (etapa.doBoard) {
      final membros = e.posicoes.where(
          (p) => p.capacidades.contains('board') && p.persona != null && p.persona != posicao.persona);
      if (membros.isEmpty) erros.add('$aqui: o board da equipe não tem membros');
      continue;
    }
    final ref = etapa.posicao;
    if (ref == null) continue;
    final alvo = e.posicao(ref);
    if (alvo == null) {
      erros.add('$aqui: posição inexistente ($ref)');
    } else if (alvo.id == posicao.id) {
      erros.add('$aqui: não pode revisar a própria posição');
    } else if (alvo.persona != null && alvo.persona == posicao.persona) {
      erros.add('$aqui: ${alvo.persona} revisaria o próprio trabalho');
    }
  }
  return erros;
}

EquipeResumo adicionarEtapa(EquipeResumo e, String id, EtapaDePolitica etapa) => _trocar(e, id, (p) {
      final politica = [...p.politica];
      final aprovacaoNoFim = politica.isNotEmpty && politica.last.aprovacao;
      if (etapa.revisao && aprovacaoNoFim) {
        politica.insert(politica.length - 1, etapa);
      } else {
        politica.add(etapa);
      }
      return p.copiar(politica: politica);
    });

EquipeResumo moverEtapa(EquipeResumo e, String id, int indice, int destino) => _trocar(e, id, (p) {
      if (indice < 0 || indice >= p.politica.length || destino < 0 || destino >= p.politica.length) return p;
      final politica = [...p.politica];
      politica.insert(destino, politica.removeAt(indice));
      return p.copiar(politica: politica);
    });

EquipeResumo removerEtapa(EquipeResumo e, String id, int indice) => _trocar(e, id, (p) {
      if (indice < 0 || indice >= p.politica.length) return p;
      return p.copiar(politica: [...p.politica]..removeAt(indice));
    });

Ponto cantoDoCartao(EquipeResumo e, String id) {
  final p = e.ponto(id);
  return (x: p.x + margemDoOrganograma, y: p.y + topoDoOrganograma);
}

({double largura, double altura}) tamanhoDoOrganograma(EquipeResumo e) {
  var largura = 2 * margemDoOrganograma;
  var altura = topoDoOrganograma + margemDoOrganograma;
  for (final p in e.posicoes) {
    final canto = cantoDoCartao(e, p.id);
    if (canto.x + larguraDoCartao + margemDoOrganograma > largura) largura = canto.x + larguraDoCartao + margemDoOrganograma;
    if (canto.y + alturaDoCartao + margemDoOrganograma > altura) altura = canto.y + alturaDoCartao + margemDoOrganograma;
  }
  return (largura: largura + distanciaX, altura: altura + distanciaY);
}

class NaPosicao {
  const NaPosicao(this.id);
  final String id;
}

NaPosicao? alvoEm(EquipeResumo e, double x, double y) {
  for (final p in e.posicoes.reversed) {
    final c = cantoDoCartao(e, p.id);
    if (x >= c.x && x <= c.x + larguraDoCartao && y >= c.y && y <= c.y + alturaDoCartao) return NaPosicao(p.id);
  }
  return null;
}

const raioDaAlca = 13.0;
const escalaMinima = 0.25;
const escalaMaxima = 2.5;

Ponto centroDaAlca(EquipeResumo e, String id) {
  final c = cantoDoCartao(e, id);
  return (x: c.x + larguraDoCartao / 2, y: c.y + alturaDoCartao + 6);
}

String? alcaEm(EquipeResumo e, double x, double y) {
  for (final p in e.posicoes.reversed) {
    final centro = centroDaAlca(e, p.id);
    final dx = x - centro.x;
    final dy = y - centro.y;
    if (dx * dx + dy * dy <= (raioDaAlca + 4) * (raioDaAlca + 4)) return p.id;
  }
  return null;
}

bool _sobrepoe(EquipeResumo e, String ignorar, double x, double y) => e.posicoes.any((p) {
      if (p.id == ignorar || !e.layout.containsKey(p.id)) return false;
      final o = e.ponto(p.id);
      return (o.x - x).abs() < larguraDoCartao + 20 && (o.y - y).abs() < alturaDoCartao + 20;
    });

EquipeResumo posicionarAbaixo(EquipeResumo e, String filho, String chefe) {
  final base = e.ponto(chefe);
  final y = base.y + distanciaY;
  final irmaos = e.posicoes.where((p) => p.respondeA == chefe && p.id != filho).length;
  var x = base.x + irmaos * distanciaX;
  while (_sobrepoe(e, filho, x, y)) {
    x += distanciaX;
  }
  return mover(e, filho, x, y);
}

EquipeResumo ligarAbaixo(EquipeResumo e, String filho, String chefe) {
  final ligada = ligar(e, filho, chefe);
  return ligada.ponto(filho).y > ligada.ponto(chefe).y ? ligada : posicionarAbaixo(ligada, filho, chefe);
}

EquipeResumo ligarPelaAlca(EquipeResumo e, String origem, NaPosicao? destino) =>
    destino == null || destino.id == origem ? e : ligarAbaixo(e, destino.id, origem);

({EquipeResumo equipe, String id}) adicionarSubordinada(EquipeResumo e, String chefe, String titulo) {
  if (e.posicao(chefe) == null) throw ErroDeOrganograma('a posição $chefe não existe');
  final r = adicionarPosicao(e, titulo);
  return (equipe: ligarAbaixo(r.equipe, r.id, chefe), id: r.id);
}

List<PosicaoResumo> chefesPossiveis(EquipeResumo e, String id) =>
    [for (final p in e.posicoes) if (p.id != id && !formaCiclo(e, id, p.id)) p];

EquipeResumo organizar(EquipeResumo e) {
  final ids = {for (final p in e.posicoes) p.id};
  String? chefeDe(PosicaoResumo p) => p.respondeA != null && ids.contains(p.respondeA) ? p.respondeA : null;
  List<PosicaoResumo> filhos(String? chefe) => [for (final p in e.posicoes) if (chefeDe(p) == chefe) p];
  final largura = <String, int>{};
  int medir(PosicaoResumo p) {
    final f = filhos(p.id);
    return largura[p.id] = f.isEmpty ? 1 : f.map(medir).reduce((a, b) => a + b);
  }

  final layout = <String, Ponto>{};
  void colocar(PosicaoResumo p, int inicio, int nivel) {
    final colunas = largura[p.id]!;
    layout[p.id] = (x: (inicio + (colunas - 1) / 2) * distanciaX, y: nivel * distanciaY);
    var proximo = inicio;
    for (final f in filhos(p.id)) {
      colocar(f, proximo, nivel + 1);
      proximo += largura[f.id]!;
    }
  }

  var coluna = 0;
  for (final raiz in filhos(null)) {
    medir(raiz);
    colocar(raiz, coluna, 0);
    coluna += largura[raiz.id]!;
  }
  return e.copiar(layout: layout);
}

typedef Vista = ({double dx, double dy, double escala});

Ponto paraMundo(Vista v, double x, double y) => (x: (x - v.dx) / v.escala, y: (y - v.dy) / v.escala);

Vista deslocarVista(Vista v, double dx, double dy) => (dx: v.dx + dx, dy: v.dy + dy, escala: v.escala);

Vista zoomEm(Vista v, double focoX, double focoY, double escala) {
  final nova = escala.clamp(escalaMinima, escalaMaxima).toDouble();
  final mundo = paraMundo(v, focoX, focoY);
  return (dx: focoX - mundo.x * nova, dy: focoY - mundo.y * nova, escala: nova);
}

Vista ajustarVista(EquipeResumo e, double largura, double altura) {
  if (e.posicoes.isEmpty || largura <= 0 || altura <= 0) return (dx: 0, dy: 0, escala: 1);
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final p in e.posicoes) {
    final c = cantoDoCartao(e, p.id);
    if (c.x < minX) minX = c.x;
    if (c.y < minY) minY = c.y;
    if (c.x + larguraDoCartao > maxX) maxX = c.x + larguraDoCartao;
    if (c.y + alturaDoCartao + 20 > maxY) maxY = c.y + alturaDoCartao + 20;
  }
  const folga = 32.0;
  final escala = [
    (largura - 2 * folga) / (maxX - minX),
    (altura - 2 * folga) / (maxY - minY),
    1.0,
  ].reduce((a, b) => a < b ? a : b).clamp(escalaMinima, escalaMaxima).toDouble();
  return (
    dx: (largura - (maxX - minX) * escala) / 2 - minX * escala,
    dy: (altura - (maxY - minY) * escala) / 2 - minY * escala,
    escala: escala,
  );
}

List<Ponto> caminhoDaLigacao(EquipeResumo e, String filho) {
  final p = e.posicao(filho);
  final chefe = p?.respondeA == null ? null : e.posicao(p!.respondeA!);
  if (chefe == null) return const [];
  final de = cantoDoCartao(e, filho);
  final ate = cantoDoCartao(e, chefe.id);
  final x1 = de.x + larguraDoCartao / 2;
  final y1 = de.y;
  final x2 = ate.x + larguraDoCartao / 2;
  final y2 = ate.y + alturaDoCartao;
  final meio = (y1 + y2) / 2;
  return [(x: x1, y: y1), (x: x1, y: meio), (x: x2, y: meio), (x: x2, y: y2)];
}

double _distanciaAoSegmento(Ponto p, Ponto a, Ponto b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final comprimento = dx * dx + dy * dy;
  final t = comprimento == 0 ? 0.0 : (((p.x - a.x) * dx + (p.y - a.y) * dy) / comprimento).clamp(0.0, 1.0);
  final qx = a.x + t * dx - p.x;
  final qy = a.y + t * dy - p.y;
  return qx * qx + qy * qy;
}

String? ligacaoEm(EquipeResumo e, double x, double y, {double tolerancia = 7}) {
  final ponto = (x: x, y: y);
  for (final p in e.posicoes) {
    final caminho = caminhoDaLigacao(e, p.id);
    for (var i = 0; i + 1 < caminho.length; i++) {
      if (_distanciaAoSegmento(ponto, caminho[i], caminho[i + 1]) <= tolerancia * tolerancia) return p.id;
    }
  }
  return null;
}
