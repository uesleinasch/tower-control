import 'package:flutter/foundation.dart';

import '../nucleo/protocolo.dart';
import '../nucleo/tarefas.dart';
import 'chat.dart';

const equipeCasa = 'casa';

typedef TarefaAberta = ({
  Tarefa tarefa,
  List<RegistroDeTarefa> registros,
  List<Execucao> execucoes,
  double custoUSD,
});

typedef LogDeExecucao = ({int execucaoId, List<EventoDeExecucao> eventos});

class EstadoTarefas extends ChangeNotifier {
  EstadoTarefas(this._enviar);

  final Enviar _enviar;

  List<Tarefa> lista = const [];
  List<EquipeResumo> equipes = const [];
  String equipe = equipeCasa;
  bool carregada = false;
  TarefaAberta? aberta;
  LogDeExecucao? log;
  final Map<String, PedidoDePermissao> pedidos = {};

  List<PosicaoResumo> get posicoes =>
      equipes.where((e) => e.id == equipe).expand((e) => e.posicoes).toList();

  List<Tarefa> get daEquipe => [for (final t in lista) if (t.equipe == equipe) t];

  String get nomeDaEquipe => equipes.where((e) => e.id == equipe).map((e) => e.nome).firstOrNull ?? equipe;

  String rotuloDaPosicao(String id, {String? daEquipe}) =>
      equipes
          .where((e) => e.id == (daEquipe ?? equipe))
          .expand((e) => e.posicoes)
          .where((p) => p.id == id)
          .map((p) => p.rotulo)
          .firstOrNull ??
      id;

  void escolherEquipe(String id) {
    equipe = id;
    notifyListeners();
  }

  List<PedidoDePermissao> get pedidosDaAberta =>
      [for (final p in pedidos.values) if (p.tarefaId == aberta?.tarefa.id) p];

  void carregar() {
    _enviar(const PedirEquipes());
    _enviar(const PedirTarefas());
  }

  void abrir(int id) => _enviar(PedirTarefa(id));

  void abrirLog(int execucaoId) => _enviar(PedirExecucao(execucaoId));

  void fecharDetalhe() {
    aberta = null;
    log = null;
    notifyListeners();
  }

  void criar({required String posicao, required String titulo, String porque = ''}) =>
      _enviar(CriarTarefa(equipe: equipe, posicao: posicao, titulo: titulo, porque: porque));

  void mudarStatus(int id, String status) => _enviar(MudarStatusTarefa(id, status));

  void comentar(int id, String texto) {
    if (texto.trim().isEmpty) return;
    _enviar(ComentarTarefa(id, texto.trim()));
  }

  void responder(String id, {required bool permitido}) {
    if (pedidos.remove(id) == null) return;
    _enviar(RespostaDePermissao(id, permitido: permitido));
    notifyListeners();
  }

  void _pedirLogSePreciso() {
    final ultima = ultimaIniciada(aberta?.execucoes ?? const []);
    if (ultima != null && log?.execucaoId != ultima.id) abrirLog(ultima.id);
  }

  void tratar(Entrada e) {
    switch (e) {
      case EquipesRecebidas(:final lista):
        equipes = lista;
      case TarefasRecebidas(:final lista):
        this.lista = lista;
        carregada = true;
      case TarefaRecebida(:final tarefa, :final registros, :final execucoes, :final custoUSD, :final pedida):
        lista = comTarefa(lista, tarefa);
        if (!pedida && aberta?.tarefa.id != tarefa.id) break;
        if (aberta?.tarefa.id != tarefa.id) log = null;
        equipe = tarefa.equipe;
        aberta = (tarefa: tarefa, registros: registros, execucoes: execucoes, custoUSD: custoUSD);
        _pedirLogSePreciso();
      case ExecucaoRecebida(:final execucao, :final eventos):
        final atual = aberta;
        if (atual == null || atual.tarefa.id != execucao.tarefa) return;
        aberta = (
          tarefa: atual.tarefa,
          registros: atual.registros,
          execucoes: comExecucao(atual.execucoes, execucao),
          custoUSD: atual.custoUSD,
        );
        if (eventos != null) {
          log = (execucaoId: execucao.id, eventos: eventos);
        } else if (execucao.status == 'rodando') {
          _pedirLogSePreciso();
        }
      case EventoRecebido(:final execucaoId, :final evento):
        final atual = log;
        if (atual == null || atual.execucaoId != execucaoId) return;
        log = (execucaoId: execucaoId, eventos: [...atual.eventos, evento]);
      case final PedidoDePermissao pedido when pedido.tarefaId != null:
        pedidos[pedido.id] = pedido;
      case PermissaoResolvida(:final id):
        if (pedidos.remove(id) == null) return;
      default:
        return;
    }
    notifyListeners();
  }
}
