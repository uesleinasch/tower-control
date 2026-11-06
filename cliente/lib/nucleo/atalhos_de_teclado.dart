typedef Combinacao = List<String>;

class AtalhoDeTeclado {
  const AtalhoDeTeclado(this.alternativas, this.acao);

  final List<Combinacao> alternativas;
  final String acao;
}

class GrupoDeAtalhos {
  const GrupoDeAtalhos(this.titulo, this.atalhos);

  final String titulo;
  final List<AtalhoDeTeclado> atalhos;
}

String textoDaCombinacao(Combinacao teclas) => teclas.join('+');

const grupoGlobal = GrupoDeAtalhos('Em qualquer tela', [
  AtalhoDeTeclado([['Ctrl', '1']], 'Ir para Conversas'),
  AtalhoDeTeclado([['Ctrl', '2']], 'Ir para o Painel'),
  AtalhoDeTeclado([['Ctrl', '3']], 'Ir para Tarefas'),
  AtalhoDeTeclado([['Ctrl', '4']], 'Ir para Equipes'),
  AtalhoDeTeclado([['Ctrl', '5']], 'Ir para o Board'),
  AtalhoDeTeclado([['Ctrl', '6']], 'Ir para Decisões'),
  AtalhoDeTeclado([['Ctrl', '7']], 'Ir para Personas'),
  AtalhoDeTeclado([['Ctrl', 'N']], 'Começar uma conversa nova'),
  AtalhoDeTeclado([['Ctrl', 'K']], 'Buscar decisões, na tela de Decisões'),
  AtalhoDeTeclado([['Esc']], 'Fechar o detalhe ou o painel lateral aberto'),
  AtalhoDeTeclado([['Ctrl', '/']], 'Mostrar os atalhos de teclado'),
  AtalhoDeTeclado([['Tab'], ['Shift', 'Tab']], 'Ir para o próximo controle ou voltar ao anterior'),
]);

const atalhosDeTeclado = <GrupoDeAtalhos>[
  grupoGlobal,
  GrupoDeAtalhos('Painéis lado a lado', [
    AtalhoDeTeclado([['←'], ['→']], 'Com o divisor em foco, estreitar ou alargar o painel'),
  ]),
  GrupoDeAtalhos('Conversa', [
    AtalhoDeTeclado([['Enter']], 'Enviar a mensagem'),
    AtalhoDeTeclado([['Shift', 'Enter']], 'Quebrar a linha'),
    AtalhoDeTeclado([['Ctrl', 'Enter']], 'Enviar a mensagem, também no celular'),
  ]),
  GrupoDeAtalhos('Tarefas', [
    AtalhoDeTeclado([['Ctrl', 'Enter']], 'Enviar o comentário'),
  ]),
  GrupoDeAtalhos('Organograma e desenho do workflow', [
    AtalhoDeTeclado([['Enter']], 'Abrir o cartão ou a caixa em foco'),
    AtalhoDeTeclado([['Shift', 'F10'], ['Menu']], 'Abrir o menu do cartão ou da caixa'),
  ]),
  GrupoDeAtalhos('Ao mover um cartão ou uma caixa', [
    AtalhoDeTeclado([['←'], ['↑'], ['→'], ['↓']], 'Deslocar o cartão ou a caixa, depois de escolher Mover no menu'),
    AtalhoDeTeclado([['Enter'], ['Esc']], 'Terminar de mover'),
  ]),
  GrupoDeAtalhos('Editor de workflow', [
    AtalhoDeTeclado([['Ctrl', 'S']], 'Salvar o workflow'),
    AtalhoDeTeclado([['Ctrl', 'Z']], 'Desfazer, com o desenho em foco'),
    AtalhoDeTeclado([['Ctrl', 'Shift', 'Z'], ['Ctrl', 'Y']], 'Refazer, com o desenho em foco'),
    AtalhoDeTeclado([['Delete'], ['Backspace']], 'Remover a caixa em foco ou selecionada'),
  ]),
];
