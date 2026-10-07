import os
import sys

sys.path.insert(0, "/home/unascimento@jacto.local/.claude/skills/creating-excalidraw-diagrams/scripts")
from excalidraw_kit import Canvas

VERDE = "#1e4b34"
c = Canvas(seed=496)

ramos = [
    {"head": "Personas\nquem trabalha", "color": "violet",
     "leaves": ["Identidade\nnome, jeito, memória, modelo", "Papel não é fixo\nvem da equipe",
                "Vocabulário\npersonas, não agentes"]},
    {"head": "Equipes\nos organogramas", "color": "indigo",
     "leaves": ["Várias equipes\nmesma persona, papéis diferentes", "Capacidades\nficam na posição",
                "Casa (padrão)\nespelha o uso de hoje"]},
    {"head": "Tarefas internas\ncom dono", "color": "blue",
     "leaves": ["Sistema próprio\nnão depende do TickTask", "Checkout atômico\num dono, uma trava",
                "TickTask\nespelho de mão única"]},
    {"head": "Workflows\nem grafo", "color": "cyan",
     "leaves": ["Pertence à equipe\nnó aponta para posição", "JSON versionado\ncom o layout dos nós",
                "Executar → revisar → aprovar\nvem antes do grafo"]},
    {"head": "Runtime\no que faz andar", "color": "teal",
     "leaves": ["Fila de acordar\nheartbeat", "Execuções rastreadas\nlog, uso, sessão",
                "Dentro do servidor\nfronteira pronta para separar", "Só Claude Agent SDK\nsem API key"]},
    {"head": "Governança\nlimites e controle", "color": "orange",
     "leaves": ["Orçamento\naviso e parada forçada", "Aprovações e auditoria\ngit dos dados",
                "Sem login por ora\nconfia na rede"]},
    {"head": "Armazenamento\nonde mora", "color": "yellow",
     "leaves": ["Arquivos + git\nequipes, workflows, personas", "bun:sqlite\ntarefas, fila, execuções",
                "O que já existe fica\nconversas, memória, uso"]},
    {"head": "Telas\nquem vê e quem edita", "color": "green",
     "leaves": ["Desktop edita\nFlutter, nó a nó", "Web e celular\nvisualizam e agem",
                "Editor web\nbacklog"]},
]
mapa = c.radial("Orquestrador\nde personas\n\nControl Tower #496", ramos)
fim_mapa = c.mark()


def secao_personas():
    c.text("E1 · Persona, posição e capacidade", 0, -330, 28, VERDE)
    c.text("A persona é uma só; o que ela pode fazer depende da posição que ocupa em cada equipe.",
           0, -280, 17, "#495057")
    passos = c.row([
        ("Persona\nquem ela é: nome, jeito,\nmemória, modelo", "violet"),
        ("Posição na equipe\no papel: executar, revisar,\naprovar, avisar", "indigo"),
        ("Capacidades\ncomandos, arquivos,\nTickTask", "teal"),
        ("Política de aprovação\nsempre · só sensíveis · auto", "orange"),
    ], x0=0, width=2000, cy=0, min_w=330, min_h=130)
    a = c.box("Alfred na equipe Código\nexecutor: roda comandos", 500, 330, 16, color="indigo", min_w=330)
    b = c.box("Alfred na equipe Pessoal\nrevisor: lê e avisa você", 1150, 330, 16, color="indigo", min_w=330)
    c.connect(passos[0], a, "#6741d9", style="dashed", label="mesma persona")
    c.connect(passos[0], b, "#6741d9", style="dashed")


def secao_equipes():
    c.text("E2 · Equipes (organogramas)", 0, -330, 28, VERDE)
    c.text("Várias equipes convivem. Memória e jeito são um só; o papel muda de equipe para equipe.",
           0, -280, 17, "#495057")
    casa = c.box("Equipe Casa\ncriada na migração", 450, -100, 18, color="indigo", min_w=320)
    conselho = c.box("Conselho\nPoe · Nati · Lucas · Pami\nconversa, memória, board", 220, 180, 16,
                     color="violet", min_w=330)
    executor = c.box("Executor\nAlfred\ncomandos com aprovação", 700, 180, 16, color="teal", min_w=330)
    c.connect(conselho, casa, "#364fc7", label="responde a")
    c.connect(executor, casa, "#364fc7")
    nova = c.box("Persona nova\nentra na Casa como conversa", 450, 430, 16, color="gray", min_w=330)
    c.connect(nova, casa, "#868e96", style="dashed")
    voce = c.box("Ueslei\naprova", 1500, -100, 18, color="green", min_w=260)
    revisora = c.box("Revisora\nNati", 1500, 180, 16, color="violet", min_w=260)
    exe = c.box("Executor\nAlfred", 1500, 430, 16, color="teal", min_w=260)
    c.text("Equipe Código (exemplo)", 1360, -260, 20, "#364fc7")
    c.connect(revisora, voce, "#364fc7", label="responde a")
    c.connect(exe, revisora, "#364fc7", label="responde a")


def secao_tarefas():
    c.text("E3 · Tarefas internas", 0, -330, 28, VERDE)
    c.text("Sistema próprio em bun:sqlite. O TickTask só recebe o que precisa de você.",
           0, -280, 17, "#495057")
    st = c.row([
        ("Backlog", "gray"), ("A fazer", "blue"), ("Em andamento\num dono, uma trava", "blue"),
        ("Em revisão", "cyan"), ("Concluída", "teal"),
    ], x0=0, width=2200, cy=0, min_w=280)
    c.detour(st[2], "Bloqueada\nespera dependência", "red", dy=-230, label="depende de outra")
    tick = c.box("TickTask (espelho)\naprovação pendente,\nentrega para revisar", 1600, 330, 16,
                 color="outside", style="dashed", min_w=330)
    c.connect(st[3], tick, "#868e96", style="dashed", label="sobe só o que é seu")
    c.box("Cancelada\nsai de qualquer etapa", 500, 330, 16, color="gray", min_w=300)


def secao_workflows():
    c.text("E4 · Workflows", 0, -330, 28, VERDE)
    c.text("Pertencem a uma equipe; cada nó aponta para uma posição, não para a persona.",
           0, -280, 17, "#495057")
    st = c.row([
        ("Executar\nposição executora", "teal"), ("Revisar\nposição revisora", "cyan"),
        ("Revisão ok?", "violet", "diamond"), ("Aprovar\nposição ou Ueslei", "green"),
        ("Concluído\nvira registro", "teal"),
    ], x0=0, width=2400, cy=0, min_w=260, labels={2: "sim"})
    c.detour(st[2], "Pede mudança\nvolta ao mesmo executor", "red", dy=260, label="não", rejoin=st[0],
             rejoin_label="e depois ao mesmo revisor")
    c.box("Tipos de nó (fase 9)\nexecutar · revisar · aprovar · decisão humana · condição\n"
          "paralelo · junção · laço com limite · espera · board", 1650, 520, 16, color="cyan", min_w=760)
    c.box("Arquivo JSON por workflow\nlógica + \"layout\" separado\nprompt longo em .md ao lado", 1650, -230,
          16, color="yellow", min_w=420)


def secao_runtime():
    c.text("E5 · Runtime", 0, -330, 28, VERDE)
    c.text("Como uma persona acorda e trabalha. Roda dentro do servidor, com fronteira pronta para separar.",
           0, -280, 17, "#495057")
    st = c.row([
        ("Gatilho\natribuição · mensagem\naprovação · timer", "blue"),
        ("Fila de acordar\njunta pedidos repetidos", "teal"),
        ("Orçamento\nok?", "orange", "diamond"),
        ("Prepara\nposição, capacidades,\nmemória", "indigo"),
        ("Chama o\nClaude Agent SDK", "teal"),
        ("Registra a execução\nlog · uso · sessão · resultado", "yellow"),
    ], x0=0, width=2800, cy=0, min_w=280, labels={2: "sim"})
    c.detour(st[2], "Pausa a persona\nmotivo: orçamento", "red", dy=260, label="não")
    c.layers(0, 480, 2800, [
        ("Servidor Bun · um processo", "gray", 110,
         ["orquestra/ · núcleo puro\nmodelo, regras, transições", "Adaptadores\nSQLite · disco · SDK",
          "Já existe e é reaproveitado\nsessions.ts · memória · avisos · WebSocket"]),
    ])


def secao_governanca():
    c.text("E6 · Governança", 0, -330, 28, VERDE)
    c.text("Limites e controle, a partir do que já existe (uso.jsonl e git dos dados).",
           0, -280, 17, "#495057")
    c.layers(0, -200, 2400, [
        ("Orçamento", "orange", 120, ["Por persona, workflow\ne projeto", "Aviso no limite\nparada forçada",
                                      "Vem do uso.jsonl\njá registrado hoje"]),
        ("Aprovações", "green", 120, ["Aprovação de plano\nantes de executar", "Comando do Alfred\nvira um caso disto",
                                      "Pausar · retomar\nencerrar persona"]),
        ("Auditoria", "yellow", 120, ["Quem fez o quê\ne por quê", "Configuração no git\ncom rollback",
                                      "Cada decisão\nvira registro"]),
        ("Risco conhecido", "red", 120, ["Sem login por ora\nconfia na rede local e Tailscale",
                                         "Qualquer aparelho\npode editar equipes", "Login\nfica para o futuro"]),
    ])


def secao_armazenamento():
    c.text("E7 · Armazenamento", 0, -330, 28, VERDE)
    c.text("Definição em arquivo versionado; o que muda a cada segundo no SQLite.",
           0, -280, 17, "#495057")
    c.layers(0, -200, 2400, [
        ("Definições\narquivos + git", "yellow", 130,
         ["equipes/<id>/equipe.json\nposições e capacidades", "equipes/<id>/workflows/\n<nome>.json + layout",
          "profiles/<persona>/\nidentidade", "Prompts .md\ndas etapas"]),
        ("Runtime\nbun:sqlite", "teal", 130,
         ["Tarefas\ne dependências", "Fila de acordar", "Travas\ncheckout atômico", "Execuções\nlog e resultado"]),
        ("Já existe\ncontinua igual", "gray", 130,
         ["conversations/", "ai-memory\nmemória das personas", "uso.jsonl\ntokens e custo",
          "decisions/ e board/"]),
    ])


def secao_telas():
    c.text("E8 · Telas", 0, -330, 28, VERDE)
    c.text("Agir = aprovar · pedir mudança · pausar · retomar.", 0, -280, 17, "#495057")
    desk = c.box("App desktop (Flutter)\nedita organograma e workflows\nnó a nó", 300, -60, 16, color="green",
                 min_w=360)
    web = c.box("Web\nvisualiza e age", 300, 170, 16, color="blue", min_w=360)
    cel = c.box("Celular\nvisualiza e age", 300, 380, 16, color="blue", min_w=360)
    srv = c.box("Servidor\nvalida tudo ao salvar", 1100, 170, 18, color="gray", min_w=340, min_h=150)
    for t in (desk, web, cel):
        c.connect(t, srv, "#495057")
    back = c.box("Editor web\nbacklog", 1100, -120, 16, color="gray", style="dashed", min_w=300)
    c.connect(web, back, "#868e96", style="dashed", label="depois")


secoes = [secao_personas, secao_equipes, secao_tarefas, secao_workflows,
          secao_runtime, secao_governanca, secao_armazenamento, secao_telas]
faixas = []
for fn in secoes:
    s = c.mark()
    fn()
    faixas.append((s, c.mark()))


def bbox_de(s, e):
    return c.bbox(s, e)


def desloca(s, e, dx, dy):
    for el in c.elements[s:e]:
        el["x"] += dx
        el["y"] += dy


celula = {0: (0, 1), 1: (0, 0), 2: (1, 0), 3: (2, 0), 4: (2, 1), 5: (2, 2), 6: (1, 2), 7: (0, 2)}
GAP = 700
caixas = {i: bbox_de(*faixas[i]) for i in range(len(secoes))}
mx0, my0, mx1, my1 = c.bbox(0, fim_mapa)
larg_col = {0: max(caixas[i][2] - caixas[i][0] for i in (0, 1, 7)), 1: mx1 - mx0,
            2: max(caixas[i][2] - caixas[i][0] for i in (3, 4, 5))}
alt_lin = {0: max(caixas[i][3] - caixas[i][1] for i in (1, 2, 3)), 1: my1 - my0,
           2: max(caixas[i][3] - caixas[i][1] for i in (5, 6, 7))}
x_col = {1: mx0, 0: mx0 - GAP - larg_col[0], 2: mx1 + GAP}
y_lin = {1: my0, 0: my0 - GAP - alt_lin[0], 2: my1 + GAP}
for i, (col, lin) in celula.items():
    x0, y0, x1, y1 = caixas[i]
    cx = x_col[col] + larg_col[col] / 2
    cy = y_lin[lin] + alt_lin[lin] / 2
    desloca(*faixas[i], cx - (x0 + x1) / 2, cy - (y0 + y1) / 2)

molduras = {}
for i in reversed(range(len(secoes))):
    molduras[i] = c.enclose(faixas[i][0])
    x0, y0, x1, y1 = c.bbox(faixas[i][0] + 1, faixas[i][1] + 1)
    f = molduras[i]
    pad = 140
    f["x"], f["y"], f["width"], f["height"] = x0 - pad, y0 - pad, x1 - x0 + 2 * pad, y1 - y0 + 2 * pad

for i, bloco in enumerate(mapa["blocks"]):
    c.connect(bloco, molduras[i], "#1e4b34", style="dashed", label=f"explosão E{i + 1}")

tudo = c.bbox()
c.text("Control Tower · Orquestrador de personas — visão macro e decisões (07/10/2026)",
       tudo[0], tudo[1] - 260, 44, VERDE)
c.text("Centro: o que estamos criando e as decisões já tomadas. Ao redor: a explosão de cada ponto.",
       tudo[0], tudo[1] - 190, 20, "#495057")
c.legend(tudo[2] + 200, tudo[1], [("blue", "tarefa e tela de visualização"), ("teal", "execução"),
                                 ("green", "você aprova ou edita"), ("gray", "infraestrutura ou backlog"),
                                 ("red", "risco ou desvio"), ("outside", "fora do sistema (TickTask)", "dashed")])

fases = c.mark()
c.text("Ordem das fases (subtarefas da #496)", 0, -90, 28, VERDE)
c.layers(0, 0, 3600, [
    ("Base", "teal", 110, ["1 · Spec de arquitetura", "2 · Tarefas internas", "3 · Runtime"]),
    ("Organização", "indigo", 110, ["4 · Organograma de personas", "5 · Governança"]),
    ("Fluxo", "cyan", 110, ["6 · Executar → revisar → aprovar", "7 · Rotinas e gatilhos"]),
    ("Visual", "green", 110, ["8 · Painel", "9 · Workflows em grafo", "10 · Editor visual (desktop)"]),
    ("Extras", "gray", 110, ["11 · Skills por persona", "12 · Adaptador do TickTask", "13 · Templates"]),
])
c.place_below(fases, c.bbox(0, fases), gap=500)

destino = os.path.join(os.path.dirname(os.path.abspath(__file__)), "orquestrador-personas.excalidraw")
c.save(destino, force="--force" in sys.argv)
