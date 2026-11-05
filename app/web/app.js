"use strict"

const FIXOS = {
  board: { nome: "Board", inicial: "B" },
  decisoes: { nome: "Decisões", inicial: "D" },
  tarefas: { nome: "Tarefas", inicial: "T" },
  equipes: { nome: "Equipes", inicial: "E" },
}
const ROTULOS_PERMISSAO = { aprovado: "permitido", negado: "negado", expirado: "expirou — comando negado" }
const ICONES_ANEXO = { imagem: "🖼", texto: "📄", pdf: "📕" }
const LADO_MAXIMO = 1600
const LIMITE_ANEXO = 10 * 1024 * 1024

const estado = {
  ws: null,
  modo: "chat", // chat | board | decisoes | tarefas
  perfil: null,
  conversaId: null,
  respostaEmCurso: null,
  citacao: null,
  anexos: [],
  atalhos: [],
  auto: false,
  foco: null,
  personas: [],
  pausadoTudo: false,
  painel: null,
  assinandoPainel: false,
  filtroPersona: "",
  filtroTipo: "",
  equipeDoPainel: "casa",
  rotinas: [],
  equipes: [],
  equipeVista: "casa",
  equipeDasTarefas: "casa",
  posicaoVista: null,
  tarefas: [],
  tarefaId: null,
  detalhe: null,
  log: null,
  pedidosDeTarefa: new Map(),
}

const el = {
  mensagens: document.getElementById("mensagens"),
  entrada: document.getElementById("entrada"),
  enviar: document.getElementById("enviar"),
  titulo: document.getElementById("titulo-conversa"),
  avatar: document.getElementById("avatar-conversa"),
  voltar: document.getElementById("voltar"),
  conexao: document.getElementById("estado-conexao"),
  listaConversas: document.getElementById("lista-conversas"),
  citacao: document.getElementById("citacao"),
  citacaoTexto: document.getElementById("citacao-texto"),
  modelo: document.getElementById("seletor-modelo"),
  auto: document.getElementById("auto"),
  ticktask: document.getElementById("ticktask"),
  clipe: document.getElementById("clipe"),
  pendentes: document.getElementById("pendentes"),
  atalhos: document.getElementById("atalhos"),
  veu: document.getElementById("veu"),
  fab: document.getElementById("nova-conversa"),
}

const personaDe = (id) => estado.personas.find((p) => p.id === id)
const nomeDe = (id) => personaDe(id)?.nome ?? FIXOS[id]?.nome ?? id
const inicialDe = (id) => personaDe(id)?.inicial ?? FIXOS[id]?.inicial ?? "?"
const ehExecutor = (id) => personaDe(id)?.executor === true

// ── telas ──────────────────────────────────────────────────────────

const compacto = () => window.matchMedia("(max-width: 899px)").matches

function ocultarFolha() {
  delete document.body.dataset.folha
  el.fab.setAttribute("aria-expanded", "false")
}

function abrirFolha() {
  if (document.body.dataset.folha === "aberta") return
  document.body.dataset.folha = "aberta"
  el.fab.setAttribute("aria-expanded", "true")
  if (compacto()) history.pushState({ tela: "lista", folha: true }, "")
}

function fecharFolha() {
  if (document.body.dataset.folha !== "aberta") return
  ocultarFolha()
  if (history.state?.folha) history.back()
}

// Fora de cena a tela de conversa não é renderizada, e o scrollTop de #mensagens
// zera quando ela volta.
const rolarAoFim = () => {
  el.mensagens.scrollTop = el.mensagens.scrollHeight
}

function mostrarTela(tela) {
  document.body.dataset.tela = tela
  if (tela === "conversa") requestAnimationFrame(rolarAoFim)
  informarVisivel()
}

// O servidor só avisa no celular e no desktop quando nenhum cliente mostra a conversa.
let visivelInformado
function informarVisivel() {
  const naTela =
    document.visibilityState === "visible" &&
    estado.modo === "chat" &&
    (!compacto() || document.body.dataset.tela === "conversa")
  const conversaId = naTela ? estado.conversaId : null
  if (conversaId === visivelInformado || estado.ws?.readyState !== WebSocket.OPEN) return
  visivelInformado = conversaId
  enviar({ tipo: "visivel", conversaId })
}

function irParaConversa() {
  ocultarFolha()
  if (document.body.dataset.tela === "conversa") return
  mostrarTela("conversa")
  if (!compacto()) return
  // Trocar a entrada da folha pela da conversa deixa um único "voltar" entre
  // a conversa e a lista; um history.back() aqui correria com o pushState.
  if (history.state?.folha) history.replaceState({ tela: "conversa" }, "")
  else history.pushState({ tela: "conversa" }, "")
}

function irParaLista() {
  mostrarTela("lista")
  if (history.state?.tela === "conversa") history.back()
}

function definirCabecalho(perfil, texto) {
  el.titulo.textContent = texto
  el.avatar.hidden = !perfil
  if (perfil) {
    el.avatar.className = `avatar ${perfil}`
    el.avatar.textContent = inicialDe(perfil)
  }
}

function focarEntrada() {
  if (!compacto()) el.entrada.focus()
}

function refletirAuto() {
  const ligado = estado.auto && ehExecutor(estado.perfil)
  el.auto.setAttribute("aria-pressed", String(estado.auto))
  el.auto.textContent = ligado ? "auto · Opus 5.5" : "auto"
  el.modelo.disabled = ligado
  el.modelo.title = ligado ? "no modo auto o Alfred usa Opus 5.5" : "modelo usado nas respostas desta conversa"
}

function refletirFoco() {
  const ligado = estado.foco === "ticktask"
  el.ticktask.setAttribute("aria-pressed", String(ligado))
  if (estado.modo === "chat" && estado.perfil) {
    el.entrada.placeholder = ligado ? "O que registrar no TickTask…" : `Mensagem para ${nomeDe(estado.perfil)}…`
  }
}

function sincronizarPainel() {
  const quer = estado.modo === "painel"
  if (quer === estado.assinandoPainel) return
  estado.assinandoPainel = quer
  enviar({ tipo: "painel", ativo: quer })
}

function ajustarAoModo() {
  sincronizarPainel()
  const executor = estado.modo === "chat" && ehExecutor(estado.perfil)
  el.clipe.hidden = estado.modo !== "chat"
  el.auto.hidden = !executor
  el.ticktask.hidden = !executor
  refletirAuto()
  refletirFoco()
  refletirComposerDeTarefas()
  limparAnexos()
  renderAtalhos()
}

// respostaEmCurso, o botão de enviar e os chips de atalho são o mesmo sinal; separar
// os três deixava eles saírem de sincronia.
function definirEmCurso(modo) {
  estado.respostaEmCurso = modo
  el.enviar.disabled = Boolean(modo)
  renderAtalhos()
}

// ── atalhos ────────────────────────────────────────────────────────

function usarAtalho(atalho) {
  if (estado.respostaEmCurso) return
  el.entrada.value = atalho.texto
  ajustarEntrada()
  submeter()
}

function renderAtalhos() {
  const mostrar =
    estado.modo === "chat" && estado.atalhos.length > 0 && !el.entrada.value.trim()
  el.atalhos.hidden = !mostrar
  if (!mostrar) return
  // Reconstruir a cada tecla perderia a rolagem horizontal da faixa.
  if (el.atalhos.childElementCount !== estado.atalhos.length) {
    el.atalhos.innerHTML = ""
    for (const atalho of estado.atalhos) {
      const botao = document.createElement("button")
      botao.textContent = atalho.rotulo
      botao.title = atalho.texto
      botao.onclick = () => usarAtalho(atalho)
      el.atalhos.appendChild(botao)
    }
  }
  for (const botao of el.atalhos.children) botao.disabled = Boolean(estado.respostaEmCurso)
}

// ── anexos ─────────────────────────────────────────────────────────

function formatarBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`
  const kb = bytes / 1024
  if (kb < 1024) return `${Math.round(kb)} kB`
  return `${(kb / 1024).toFixed(1).replace(/\.0$/, "").replace(".", ",")} MB`
}

function limparAnexos() {
  estado.anexos = []
  renderPendentes()
}

function renderPendentes() {
  el.pendentes.innerHTML = ""
  el.pendentes.hidden = !estado.anexos.length
  for (const anexo of estado.anexos) {
    const chip = document.createElement("span")
    chip.className = "chip"
    chip.innerHTML =
      `<b>${ICONES_ANEXO[anexo.tipo] ?? "📄"}</b>` +
      `<span>${escapar(anexo.nome)}</span>` +
      `<small>${formatarBytes(anexo.bytes)}</small>` +
      `<button aria-label="Remover anexo">×</button>`
    chip.querySelector("button").onclick = () => {
      estado.anexos = estado.anexos.filter((a) => a.id !== anexo.id)
      renderPendentes()
    }
    el.pendentes.appendChild(chip)
  }
}

function trocarExtensao(nome, extensao) {
  return `${nome.replace(/\.[^.]*$/, "")}.${extensao}`
}

// Foto de celular sobe com 8-12 MB e custa token à toa na leitura da imagem.
// GIF fica de fora porque o canvas descartaria a animação.
async function reduzirImagem(arquivo) {
  if (!arquivo.type.startsWith("image/") || arquivo.type === "image/gif") return arquivo
  const bitmap = await createImageBitmap(arquivo).catch(() => null)
  if (!bitmap) return arquivo
  const maior = Math.max(bitmap.width, bitmap.height)
  if (maior <= LADO_MAXIMO) {
    bitmap.close()
    return arquivo
  }
  const escala = LADO_MAXIMO / maior
  const tela = document.createElement("canvas")
  tela.width = Math.round(bitmap.width * escala)
  tela.height = Math.round(bitmap.height * escala)
  tela.getContext("2d").drawImage(bitmap, 0, 0, tela.width, tela.height)
  bitmap.close()
  const blob = await new Promise((pronto) => tela.toBlob(pronto, "image/jpeg", 0.85))
  if (!blob) return arquivo
  return new File([blob], trocarExtensao(arquivo.name, "jpg"), { type: "image/jpeg" })
}

async function subirAnexo(arquivo) {
  const form = new FormData()
  form.set("arquivo", arquivo)
  const resposta = await fetch("/anexo", { method: "POST", body: form })
  const corpo = await resposta.json().catch(() => ({}))
  if (!resposta.ok) throw new Error(corpo.erro ?? `falha no upload (${resposta.status})`)
  return corpo
}

async function anexarArquivos(lista) {
  for (const bruto of lista) {
    try {
      const arquivo = await reduzirImagem(bruto)
      if (arquivo.size > LIMITE_ANEXO) {
        adicionarMensagem(
          "erro",
          escapar(`"${bruto.name}" tem ${formatarBytes(arquivo.size)}; o limite é 10 MB.`),
        )
        continue
      }
      estado.anexos.push(await subirAnexo(arquivo))
      renderPendentes()
    } catch (erro) {
      adicionarMensagem("erro", escapar(`${bruto.name}: ${erro.message}`))
    }
  }
}

function cartaoDePermissao(msg) {
  const quem = msg.tarefaId ? `Comando na tarefa #${msg.tarefaId}` : "Alfred quer rodar um comando"
  const cartao = adicionarMensagem(
    "permissao",
    `<span class="autor alfred">${escapar(quem)}</span>` +
      `<pre>${escapar(msg.comando)}</pre>` +
      `<div class="acoes">` +
      `<button data-ok="1">Permitir</button><button data-ok="0">Negar</button>` +
      `</div>`,
  )
  cartao.dataset.permissao = msg.id
  const acoes = cartao.querySelector(".acoes")
  acoes.addEventListener("click", (ev) => {
    const botao = ev.target.closest("button")
    if (!botao) return
    const permitido = botao.dataset.ok === "1"
    enviar({ tipo: "permissao-resposta", id: msg.id, permitido })
    acoes.innerHTML = `<small>${permitido ? "permitido" : "negado"}</small>`
  })
}

function blocoDeAnexos(anexos) {
  if (!anexos?.length) return ""
  return anexos
    .map((a) => {
      const url = `/anexo/${encodeURIComponent(a.id)}`
      if (a.tipo === "imagem") {
        return (
          `<a class="anexo-imagem" href="${url}" target="_blank" rel="noopener">` +
          `<img src="${url}" alt="${escapar(a.nome)}" loading="lazy"></a>`
        )
      }
      return (
        `<a class="anexo-arquivo" href="${url}" target="_blank" rel="noopener">` +
        `<b>${ICONES_ANEXO[a.tipo] ?? "📄"}</b><span>${escapar(a.nome)}</span>` +
        `<small>${formatarBytes(a.bytes)}</small></a>`
      )
    })
    .join("")
}

function definirCitacao(texto) {
  estado.citacao = texto.length > 180 ? `${texto.slice(0, 180)}…` : texto
  el.citacaoTexto.textContent = estado.citacao
  el.citacao.hidden = false
  el.entrada.focus()
}

function limparCitacao() {
  estado.citacao = null
  el.citacao.hidden = true
}

function blocoCitacao(texto) {
  return `<span class="citacao-bloco">${escapar(texto)}</span>`
}

function conectar() {
  const ws = new WebSocket(`ws://${location.host}/ws`)
  ws.onopen = () => {
    el.conexao.classList.add("ok")
    enviar({ tipo: "listar" })
    visivelInformado = undefined
    informarVisivel()
    estado.assinandoPainel = false
    sincronizarPainel()
  }
  ws.onclose = () => {
    el.conexao.classList.remove("ok")
    setTimeout(conectar, 1500)
  }
  ws.onmessage = (ev) => tratar(JSON.parse(ev.data))
  estado.ws = ws
}

function enviar(msg) {
  if (estado.ws?.readyState === WebSocket.OPEN) estado.ws.send(JSON.stringify(msg))
}

function escapar(texto) {
  const div = document.createElement("div")
  div.textContent = texto
  return div.innerHTML
}

function formatar(texto) {
  return escapar(texto)
    .replace(/^### (.*)$/gm, "<h3>$1</h3>")
    .replace(/^## (.*)$/gm, "<h2>$1</h2>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, "<code>$1</code>")
}

function hora(ts) {
  const data = ts instanceof Date ? ts : new Date(ts)
  if (Number.isNaN(data.getTime())) return ""
  return data.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })
}

const MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

function quando(ts) {
  const data = new Date(ts)
  if (Number.isNaN(data.getTime())) return ""
  const dia = (d) => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
  const hoje = new Date()
  if (dia(data) === dia(hoje)) return hora(data)
  const ontem = new Date(hoje)
  ontem.setDate(hoje.getDate() - 1)
  if (dia(data) === dia(ontem)) return "ontem"
  return `${data.getDate()}/${MESES[data.getMonth()]}`
}

function adicionarMensagem(classe, html, ts) {
  const div = document.createElement("div")
  const marca = ts ? hora(ts) : ""
  div.className = marca ? `msg ${classe} com-hora` : `msg ${classe}`
  div.innerHTML = marca ? `${html}<time class="hora">${marca}</time>` : html
  el.mensagens.appendChild(div)
  el.mensagens.scrollTop = el.mensagens.scrollHeight
  return div
}

function mensagemDoUsuario(texto, citacao, ts, anexos) {
  const cabeca = (citacao ? blocoCitacao(citacao) : "") + blocoDeAnexos(anexos)
  return adicionarMensagem("usuario", `${cabeca}<span class="corpo">${escapar(texto)}</span>`, ts)
}

function mensagemDoPerfil(perfil, texto, comAutor = true, ts = new Date()) {
  const cabeca = comAutor
    ? `<span class="avatar avatar-balao ${perfil}">${inicialDe(perfil)}</span>` +
      `<span class="autor ${perfil}">${escapar(nomeDe(perfil))}</span>`
    : ""
  const div = adicionarMensagem(
    comAutor ? "perfil-msg inicio-grupo" : "perfil-msg",
    `${cabeca}<span class="corpo">${formatar(texto)}</span>`,
    ts,
  )
  return div.querySelector(".corpo")
}

const SEPARADOR_BALAO = /\n\s*-{3,}\s*\n/

function balcoesDoPerfil(perfil, texto, ts) {
  const partes = texto.split(SEPARADOR_BALAO).map((p) => p.trim()).filter(Boolean)
  partes.forEach((parte, i) => mensagemDoPerfil(perfil, parte, i === 0, ts))
}

function limparTela() {
  el.mensagens.innerHTML = ""
}

function selecionarBotao(seletor) {
  document.querySelectorAll("#perfis button").forEach((b) => b.classList.remove("ativo"))
  if (seletor) document.querySelector(seletor)?.classList.add("ativo")
}

// ── modos ──────────────────────────────────────────────────────────

function abrirPerfil(perfil) {
  estado.modo = "chat"
  estado.perfil = perfil
  estado.conversaId = null
  estado.foco = null
  estado.auto = false
  ajustarAoModo()
  selecionarBotao(`[data-perfil="${perfil}"]`)
  definirCabecalho(perfil, `Nova conversa com ${nomeDe(perfil)}`)
  limparTela()
  adicionarMensagem("aviso", `Você está falando com ${nomeDe(perfil)}. A conversa é criada na primeira mensagem.`)
  irParaConversa()
  informarVisivel()
  focarEntrada()
}

function abrirBoard() {
  estado.modo = "board"
  estado.perfil = null
  estado.conversaId = null
  ajustarAoModo()
  selecionarBotao("#botao-board")
  definirCabecalho("board", "Board — deliberação em conselho")
  limparTela()
  adicionarMensagem(
    "aviso",
    "Apresente a pauta. Os conselheiros do board vão deliberar em paralelo e você recebe a síntese; a ata completa fica em board/minutes/.",
  )
  el.entrada.placeholder = "Pauta para o board…"
  irParaConversa()
  informarVisivel()
  focarEntrada()
}

function abrirDecisoes() {
  estado.modo = "decisoes"
  ajustarAoModo()
  selecionarBotao("#botao-decisoes")
  definirCabecalho("decisoes", "Decisões registradas")
  limparTela()
  irParaConversa()
  informarVisivel()
  enviar({ tipo: "decisoes" })
}

// ── tarefas ────────────────────────────────────────────────────────

const NOMES_STATUS = {
  backlog: "backlog",
  a_fazer: "a fazer",
  em_andamento: "em andamento",
  em_revisao: "em revisão",
  bloqueada: "bloqueada",
  concluida: "concluída",
  cancelada: "cancelada",
}
// Espelho de TRANSICOES em app/src/orquestra/tarefa.ts: só decide quais botões aparecem;
// quem valida a mudança é o servidor.
const TRANSICOES_TAREFA = {
  backlog: ["a_fazer", "cancelada"],
  a_fazer: ["em_andamento", "backlog", "bloqueada", "cancelada"],
  em_andamento: ["em_revisao", "concluida", "bloqueada", "a_fazer", "cancelada"],
  em_revisao: ["concluida", "em_andamento", "a_fazer", "bloqueada", "cancelada"],
  bloqueada: ["a_fazer", "cancelada"],
  concluida: ["a_fazer"],
  cancelada: ["backlog"],
}
const NOMES_EXECUCAO = {
  na_fila: "na fila",
  rodando: "rodando",
  concluida: "concluída",
  falhou: "falhou",
  interrompida: "interrompida",
}
const NOMES_GATILHO = {
  atribuicao: "atribuição",
  comentario: "comentário",
  dependencia: "dependência",
  retomada: "retomada",
  nova_tentativa: "nova tentativa",
  plano_aprovado: "plano aprovado",
  revisao: "entrega para revisar",
  mudanca: "pedido de mudança",
}
const ORDEM_STATUS = ["em_andamento", "em_revisao", "a_fazer", "bloqueada", "backlog", "concluida", "cancelada"]

const equipeDe = (id) => estado.equipes.find((e) => e.id === id)

function posicoesDa(equipe) {
  return equipeDe(equipe)?.posicoes ?? []
}

function rotuloDaPosicao(id, equipe = estado.equipeDasTarefas) {
  const p = posicoesDa(equipe).find((x) => x.id === id)
  if (!p) return id
  return p.personaNome ? `${p.personaNome} · ${p.titulo}` : `${p.titulo} (vaga)`
}

function refletirComposerDeTarefas() {
  const listando = (estado.modo === "tarefas" && !estado.tarefaId) || estado.modo === "equipes" || estado.modo === "painel"
  el.entrada.disabled = listando
  if (estado.modo === "tarefas") {
    el.entrada.placeholder = listando ? "Abra uma tarefa para comentar" : "Comentar na tarefa…"
  }
  if (estado.modo === "equipes") el.entrada.placeholder = "Edite as equipes no app desktop"
  if (estado.modo === "painel") el.entrada.placeholder = "Use os botões do painel"
}

function abrirTarefas() {
  estado.modo = "tarefas"
  estado.perfil = null
  estado.conversaId = null
  estado.tarefaId = null
  ajustarAoModo()
  selecionarBotao("#botao-tarefas")
  definirCabecalho("tarefas", tituloDasTarefas())
  limparTela()
  irParaConversa()
  informarVisivel()
  enviar({ tipo: "equipes" })
  enviar({ tipo: "tarefas" })
  enviar({ tipo: "rotinas" })
}

function tituloDasTarefas() {
  return `Tarefas — ${equipeDe(estado.equipeDasTarefas)?.nome ?? estado.equipeDasTarefas}`
}

function barraDePausa() {
  const barra = document.createElement("div")
  barra.className = `barra-pausa${estado.pausadoTudo ? " pausado" : ""}`
  const texto = document.createElement("span")
  texto.textContent = estado.pausadoTudo ? "Tudo pausado: nenhuma tarefa começa." : "Personas trabalhando normalmente."
  const botao = document.createElement("button")
  botao.textContent = estado.pausadoTudo ? "Retomar tudo" : "Pausar tudo"
  botao.onclick = () => enviar(estado.pausadoTudo ? { tipo: "retomar", alvo: "*" } : { tipo: "pausar", alvo: "*" })
  barra.append(texto, botao)
  return barra
}

function formatarTokens(n) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1).replace(".", ",")} mi tokens`
  if (n >= 1_000) return `${Math.round(n / 1_000)} mil tokens`
  return `${Math.round(n)} tokens`
}

function nomeNaTrilha(etapa, equipe) {
  if (etapa.por.board) return "board"
  if (etapa.por.ueslei) return "Ueslei"
  const p = posicoesDa(equipe).find((x) => x.id === etapa.por.posicao)
  return p?.personaNome ?? p?.titulo ?? etapa.por.posicao
}

function descreverPolitica(politica, equipe) {
  return politica.map((e) => `${nomeNaTrilha(e, equipe)} ${e.tipo === "revisao" ? "revisa" : "aprova"}`)
}

function trilhaDaTarefa(tarefa) {
  const dona = posicoesDa(tarefa.equipe).find((p) => p.id === tarefa.posicao)
  const atual = tarefa.status === "em_revisao" ? tarefa.etapa : null
  const comExecutora = tarefa.status === "a_fazer" || tarefa.status === "em_andamento"
  const passos = [{ texto: `${dona?.personaNome ?? dona?.titulo ?? tarefa.posicao} executa`, atual: comExecutora, passada: atual !== null }]
  descreverPolitica(tarefa.politica, tarefa.equipe).forEach((texto, i) =>
    passos.push({
      texto,
      atual: atual === i,
      passada: tarefa.status === "concluida" || (atual !== null ? i < atual : comExecutora && tarefa.retorno !== null && i < tarefa.retorno),
    }),
  )
  if (tarefa.status === "concluida") passos[0].passada = true
  const div = document.createElement("div")
  div.className = "trilha-politica"
  div.innerHTML = passos
    .map((p) => `<span class="${p.atual ? "atual" : p.passada ? "passada" : ""}">${p.passada && !p.atual ? "✓ " : ""}${escapar(p.texto)}</span>`)
    .join(" → ")
  return div
}

const esperaDecisaoDoUeslei = (tarefa) =>
  tarefa.status === "em_revisao" && tarefa.etapa != null && tarefa.politica[tarefa.etapa]?.por.ueslei === true

const planoPendente = (registros) => {
  const plano = registros.findLastIndex((r) => r.tipo === "plano")
  return plano >= 0 && registros.findLastIndex((r) => r.tipo === "plano-aprovado") < plano
}

function seletorDeEquipe(valor, aoMudar) {
  const select = document.createElement("select")
  select.className = "seletor-equipe"
  select.setAttribute("aria-label", "equipe")
  for (const e of estado.equipes) {
    const op = document.createElement("option")
    op.value = e.id
    op.textContent = e.nome
    op.selected = e.id === valor
    select.appendChild(op)
  }
  select.onchange = () => aoMudar(select.value)
  return select
}

function voltarParaTarefas() {
  estado.tarefaId = null
  estado.detalhe = null
  estado.log = null
  refletirComposerDeTarefas()
  definirCabecalho("tarefas", tituloDasTarefas())
  renderTarefas()
}

function formNovaTarefa() {
  const form = document.createElement("form")
  form.className = "nova-tarefa"
  const opcoes = posicoesDa(estado.equipeDasTarefas)
    .map((p) => `<option value="${escapar(p.id)}">${escapar(rotuloDaPosicao(p.id))}</option>`)
    .join("")
  form.innerHTML =
    `<select name="posicao" aria-label="posição que fica com a tarefa">${opcoes}</select>` +
    `<input name="titulo" placeholder="O que precisa ser feito" maxlength="200" required />` +
    `<input name="porque" placeholder="Por quê (o objetivo que a persona recebe junto)" />` +
    `<button type="submit">Criar tarefa</button>`
  form.onsubmit = (ev) => {
    ev.preventDefault()
    const dados = new FormData(form)
    const titulo = String(dados.get("titulo") ?? "").trim()
    if (!titulo) return
    enviar({
      tipo: "tarefa-criar",
      tarefa: { equipe: estado.equipeDasTarefas, posicao: dados.get("posicao"), titulo, porque: String(dados.get("porque") ?? "") },
    })
    form.reset()
  }
  return form
}

function renderTarefas() {
  if (estado.modo !== "tarefas" || estado.tarefaId) return
  limparTela()
  definirCabecalho("tarefas", tituloDasTarefas())
  el.mensagens.appendChild(barraDePausa())
  if (estado.equipes.length > 1) {
    el.mensagens.appendChild(
      seletorDeEquipe(estado.equipeDasTarefas, (id) => {
        estado.equipeDasTarefas = id
        renderTarefas()
      }),
    )
  }
  el.mensagens.appendChild(formNovaTarefa())
  const daEquipe = estado.tarefas.filter((t) => t.equipe === estado.equipeDasTarefas)
  if (!daEquipe.length) adicionarMensagem("aviso", "Nenhuma tarefa ainda.")
  for (const status of ORDEM_STATUS) {
    const doStatus = daEquipe.filter((t) => t.status === status)
    if (!doStatus.length) continue
    const titulo = document.createElement("h3")
    titulo.className = "grupo-tarefas"
    titulo.textContent = `${NOMES_STATUS[status]} · ${doStatus.length}`
    el.mensagens.appendChild(titulo)
    const ul = document.createElement("ul")
    ul.className = "lista-decisoes"
    for (const t of doStatus) {
      const li = document.createElement("li")
      li.innerHTML =
        `<span class="status ${t.status}">#${t.id}</span>${escapar(t.titulo)}` +
        (t.rodando ? ` <span class="rodando">● rodando</span>` : "") +
        `<small>${escapar(rotuloDaPosicao(t.posicao))}${t.comQuem ? ` · ${escapar(t.comQuem)}` : ""} · ${quando(t.atualizadaEm)}</small>`
      li.onclick = () => enviar({ tipo: "tarefa", id: t.id })
      ul.appendChild(li)
    }
    el.mensagens.appendChild(ul)
  }
}

function dinheiro(usd) {
  return usd ? `US$ ${usd.toFixed(usd < 0.1 ? 3 : 2)}` : "US$ 0"
}

function duracao(e) {
  if (!e.inicio) return ""
  const ms = (e.fim ? Date.parse(e.fim) : Date.now()) - Date.parse(e.inicio)
  const s = Math.round(ms / 1000)
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}min ${s % 60}s`
}

function linhaDeEvento(ev) {
  const div = document.createElement("div")
  div.className = `evento ${ev.tipo}`
  div.innerHTML = `<time>${quando(ev.em)}</time> ${ev.tipo === "texto" ? formatar(ev.conteudo) : `<code>${escapar(ev.conteudo)}</code>`}`
  return div
}

function renderLog() {
  const alvo = document.getElementById("log-execucao")
  if (!alvo) return
  alvo.innerHTML = ""
  const log = estado.log
  if (!log) return
  const titulo = document.createElement("h3")
  titulo.className = "grupo-tarefas"
  titulo.textContent = `Log da execução ${log.execucaoId}`
  alvo.appendChild(titulo)
  if (!log.eventos.length) alvo.appendChild(Object.assign(document.createElement("small"), { textContent: "Sem eventos ainda." }))
  for (const ev of log.eventos) alvo.appendChild(linhaDeEvento(ev))
}

function pedirLogSePreciso() {
  const ultima = estado.detalhe?.execucoes.filter((e) => e.inicio).at(-1)
  if (ultima && estado.log?.execucaoId !== ultima.id) enviar({ tipo: "execucao", id: ultima.id })
}

function nomeDaRotina(criadaPor) {
  const [equipe, id] = criadaPor.slice("rotina:".length).split("/")
  return estado.rotinas.find((r) => r.equipe === equipe && r.id === id)?.nome ?? id
}

function renderTarefa() {
  const { tarefa, registros, execucoes = [], custoUSD = 0 } = estado.detalhe
  estado.tarefaId = tarefa.id
  estado.equipeDasTarefas = tarefa.equipe
  refletirComposerDeTarefas()
  definirCabecalho("tarefas", `#${tarefa.id} — ${tarefa.titulo}`)
  limparTela()
  const voltar = adicionarMensagem("aviso", "← voltar para as tarefas")
  voltar.style.cursor = "pointer"
  voltar.onclick = voltarParaTarefas
  const linhas = [
    `**${tarefa.titulo}**`,
    `Status: ${NOMES_STATUS[tarefa.status]} · ${rotuloDaPosicao(tarefa.posicao)}${tarefa.rodando ? " · rodando agora" : ""} · custo ${dinheiro(custoUSD)}`,
    tarefa.porque ? `Por quê: ${tarefa.porque}` : "",
    tarefa.dependeDe.length ? `Depende de: ${tarefa.dependeDe.map((d) => `#${d}`).join(", ")}` : "",
    tarefa.pai ? `Parte da tarefa #${tarefa.pai}` : "",
    tarefa.criadaPor?.startsWith("rotina:") ? `Criada pela rotina ${nomeDaRotina(tarefa.criadaPor)}` : "",
    tarefa.descricao,
  ]
  adicionarMensagem("perfil-msg documento", formatar(linhas.filter(Boolean).join("\n\n")))
  if (tarefa.politica?.length) el.mensagens.appendChild(trilhaDaTarefa(tarefa))
  const acoes = document.createElement("div")
  acoes.className = "acoes-tarefa"
  for (const para of TRANSICOES_TAREFA[tarefa.status] ?? []) {
    const botao = document.createElement("button")
    botao.textContent = `→ ${NOMES_STATUS[para]}`
    botao.onclick = () => enviar({ tipo: "tarefa-status", id: tarefa.id, status: para })
    acoes.appendChild(botao)
  }
  if (tarefa.status === "em_revisao" && planoPendente(registros)) {
    const aprovar = document.createElement("button")
    aprovar.className = "aprovar-plano"
    aprovar.textContent = "Aprovar plano"
    aprovar.onclick = () => enviar({ tipo: "tarefa-aprovar-plano", id: tarefa.id })
    acoes.prepend(aprovar)
  }
  if (esperaDecisaoDoUeslei(tarefa)) {
    const mudanca = document.createElement("button")
    mudanca.className = "pedir-mudanca"
    mudanca.textContent = "Pedir mudança"
    mudanca.onclick = () => {
      const texto = prompt("O que precisa mudar?")?.trim()
      if (texto) enviar({ tipo: "tarefa-decidir", id: tarefa.id, decisao: "mudanca", texto })
    }
    const aprovar = document.createElement("button")
    aprovar.className = "aprovar-plano"
    aprovar.textContent = "Aprovar"
    aprovar.onclick = () => enviar({ tipo: "tarefa-decidir", id: tarefa.id, decisao: "aprovar" })
    acoes.prepend(aprovar, mudanca)
  }
  el.mensagens.appendChild(acoes)
  for (const r of registros) {
    if (r.tipo === "comentario") {
      if (r.autor === "ueslei") mensagemDoUsuario(r.texto, null, r.em)
      else adicionarMensagem("perfil-msg", `<strong>${escapar(r.autor)}</strong><br>${formatar(r.texto)}`, r.em)
    } else if (["entrega", "ajuda", "plano", "aprovado", "mudanca"].includes(r.tipo)) {
      const rotulo = { entrega: "entregou", ajuda: "pediu ajuda", plano: "propôs um plano", aprovado: "aprovou", mudanca: "pediu mudança" }[r.tipo]
      adicionarMensagem(`perfil-msg ${r.tipo}`, `<strong>${escapar(r.autor)} ${rotulo}</strong><br>${formatar(r.texto)}`, r.em)
    } else {
      adicionarMensagem("aviso", `${escapar(r.autor)}: ${escapar(r.texto)} · ${quando(r.em)}`)
    }
  }
  if (execucoes.length) {
    const titulo = document.createElement("h3")
    titulo.className = "grupo-tarefas"
    titulo.textContent = `Execuções · ${execucoes.length}`
    el.mensagens.appendChild(titulo)
    const ul = document.createElement("ul")
    ul.className = "lista-decisoes"
    for (const e of [...execucoes].reverse()) {
      const li = document.createElement("li")
      const detalhes = [e.persona, NOMES_GATILHO[e.gatilho] ?? e.gatilho, duracao(e), e.custoUSD != null ? dinheiro(e.custoUSD) : "", e.erro ?? ""]
      li.innerHTML =
        `<span class="status execucao ${e.status}">${e.id}</span>${NOMES_EXECUCAO[e.status] ?? e.status}` +
        `<small>${escapar(detalhes.filter(Boolean).join(" · "))}</small>`
      if (e.inicio) li.onclick = () => enviar({ tipo: "execucao", id: e.id })
      ul.appendChild(li)
    }
    el.mensagens.appendChild(ul)
  }
  const log = document.createElement("div")
  log.id = "log-execucao"
  el.mensagens.appendChild(log)
  renderLog()
  for (const pedido of estado.pedidosDeTarefa.values()) {
    if (pedido.tarefaId === tarefa.id) cartaoDePermissao(pedido)
  }
  pedirLogSePreciso()
  rolarAoFim()
}

// ── personas e equipes ─────────────────────────────────────────────

function renderPersonas() {
  const lista = document.getElementById("lista-personas")
  lista.innerHTML = ""
  const visiveis = estado.personas.filter((p) => p.conversa).sort((a, b) => Number(a.executor) - Number(b.executor))
  for (const p of visiveis) {
    const botao = document.createElement("button")
    botao.className = "perfil"
    botao.dataset.perfil = p.id
    botao.innerHTML =
      `<span class="avatar ${p.id}">${escapar(p.inicial)}</span>` +
      `<span class="nome">${escapar(p.nome)}<small>${escapar(p.titulo ?? "")}</small></span>`
    botao.onclick = () => abrirPerfil(p.id)
    if (estado.modo === "chat" && estado.perfil === p.id) botao.classList.add("ativo")
    lista.appendChild(botao)
  }
  let estilo = document.getElementById("cores-personas")
  if (!estilo) {
    estilo = document.createElement("style")
    estilo.id = "cores-personas"
    document.head.appendChild(estilo)
  }
  estilo.textContent = estado.personas
    .map((p) => `.avatar.${p.id}{background:${p.cor}}.autor.${p.id}{color:${p.cor}}`)
    .join("\n")
}

const LARGURA_NO = 220
const ALTURA_NO = 78
const TOPO_DO_ORGANOGRAMA = 30
const NOMES_CAPACIDADE = { arquivos: "arquivos", comandos: "comandos", ticktask: "TickTask", memoria: "memória", board: "board" }

// ── painel ─────────────────────────────────────────────────────────

const NOMES_ESTADO_PERSONA = { rodando: "rodando", na_fila: "na fila", ocioso: "ociosa", pausada: "pausada", sem_orcamento: "sem orçamento" }
const NOMES_PAPEL = { executa: "executa", revisa: "revisa", board: "board" }
const NOMES_TIPO_ATIVIDADE = {
  entrega: "entregas",
  plano: "planos",
  ajuda: "pedidos de ajuda",
  decisao: "decisões",
  comentario: "comentários",
  auditoria: "auditoria",
  disparo: "rotinas",
}
const ROTULO_ACAO = {
  aprovar: "Aprovar",
  negar: "Negar",
  "pedir-mudanca": "Pedir mudança",
  "aprovar-plano": "Aprovar plano",
  concluir: "Concluir",
  liberar: "Liberar",
  abrir: "Abrir",
}

function abrirPainel() {
  estado.modo = "painel"
  estado.perfil = null
  estado.conversaId = null
  estado.tarefaId = null
  ajustarAoModo()
  selecionarBotao("#botao-painel")
  definirCabecalho("painel", "Painel")
  irParaConversa()
  informarVisivel()
  enviar({ tipo: "equipes" })
  enviar({ tipo: "personas" })
  renderPainel()
}

function abrirTarefaDoPainel(id, equipe) {
  if (equipe) estado.equipeDasTarefas = equipe
  abrirTarefas()
  enviar({ tipo: "tarefa", id })
}

function agirNoPainel(item, acao) {
  switch (acao) {
    case "aprovar":
      if (item.tipo === "comando") enviar({ tipo: "permissao-resposta", id: item.permissaoId, permitido: true })
      else enviar({ tipo: "tarefa-decidir", id: item.tarefaId, decisao: "aprovar" })
      return
    case "negar":
      enviar({ tipo: "permissao-resposta", id: item.permissaoId, permitido: false })
      return
    case "pedir-mudanca": {
      const texto = prompt("O que precisa mudar?")?.trim()
      if (texto) enviar({ tipo: "tarefa-decidir", id: item.tarefaId, decisao: "mudanca", texto })
      return
    }
    case "aprovar-plano":
      enviar({ tipo: "tarefa-aprovar-plano", id: item.tarefaId })
      return
    case "concluir":
      enviar({ tipo: "tarefa-status", id: item.tarefaId, status: "concluida" })
      return
    case "liberar":
      enviar({ tipo: "tarefa-status", id: item.tarefaId, status: "a_fazer" })
      return
    case "abrir":
      if (item.tarefaId) abrirTarefaDoPainel(item.tarefaId, item.equipe)
      else {
        if (item.equipe) estado.equipeVista = item.equipe
        abrirEquipes()
      }
  }
}

function tituloDeSecao(texto) {
  const h = document.createElement("h3")
  h.className = "grupo-tarefas"
  h.textContent = texto
  return h
}

function vazio(texto) {
  return Object.assign(document.createElement("small"), { className: "painel-vazio", textContent: texto })
}

function secaoDeAtencao(itens) {
  const secao = document.createElement("section")
  secao.appendChild(tituloDeSecao(itens.length ? `Precisa de você · ${itens.length}` : "Precisa de você"))
  if (!itens.length) secao.appendChild(vazio("Nada esperando você."))
  for (const item of itens) {
    const div = document.createElement("div")
    div.className = `msg perfil-msg item-atencao ${item.tipo}`
    div.innerHTML = `<strong>${escapar(item.titulo)}</strong> <small>${quando(item.desde)}</small><br>${escapar(item.detalhe)}`
    const acoes = document.createElement("div")
    acoes.className = "acoes-tarefa"
    for (const acao of item.acoes) {
      const botao = document.createElement("button")
      botao.textContent = ROTULO_ACAO[acao] ?? acao
      if (acao === "aprovar" || acao === "aprovar-plano") botao.className = "aprovar-plano"
      botao.onclick = () => agirNoPainel(item, acao)
      acoes.appendChild(botao)
    }
    div.appendChild(acoes)
    secao.appendChild(div)
  }
  return secao
}

function secaoAgora({ rodando, naFila }) {
  const secao = document.createElement("section")
  secao.appendChild(tituloDeSecao("Agora"))
  if (!rodando.length && !naFila.length) secao.appendChild(vazio("Nenhuma persona trabalhando."))
  const ul = document.createElement("ul")
  ul.className = "lista-decisoes"
  for (const e of rodando) {
    const li = document.createElement("li")
    const evento = e.ultimoEvento ? `<br>${escapar(e.ultimoEvento.conteudo)}` : ""
    li.innerHTML =
      `<span class="status em_andamento">#${e.tarefaId}</span>${escapar(e.titulo)} <span class="rodando">● ${escapar(NOMES_PAPEL[e.papel] ?? e.papel)}</span>` +
      `<small>${escapar(e.persona ?? "board")} · desde ${quando(e.inicio)}${evento}</small>`
    li.onclick = () => abrirTarefaDoPainel(e.tarefaId, e.equipe)
    ul.appendChild(li)
  }
  for (const e of naFila) {
    const li = document.createElement("li")
    li.innerHTML =
      `<span class="status a_fazer">#${e.tarefaId}</span>${escapar(e.titulo)}` +
      `<small>${escapar(e.persona ?? "sem persona")} · na fila: ${escapar(e.motivo)}</small>`
    li.onclick = () => abrirTarefaDoPainel(e.tarefaId)
    ul.appendChild(li)
  }
  if (ul.children.length) secao.appendChild(ul)
  return secao
}

function secaoDeCartoes(personas) {
  const secao = document.createElement("section")
  secao.appendChild(tituloDeSecao("Personas"))
  const grade = document.createElement("div")
  grade.className = "cartoes-persona"
  for (const p of personas) {
    const limite = [
      p.limiteUSD != null ? `${dinheiro(p.gastoMesUSD)} de ${dinheiro(p.limiteUSD)}` : dinheiro(p.gastoMesUSD),
      p.limiteTokens != null ? `${formatarTokens(p.tokensMes)} de ${formatarTokens(p.limiteTokens)}` : formatarTokens(p.tokensMes),
    ].join(" · ")
    const cartao = document.createElement("div")
    cartao.className = `cartao-persona ${p.estado}`
    cartao.style.borderLeftColor = p.cor
    cartao.innerHTML =
      `<strong>${escapar(p.nome)}</strong> <small>${NOMES_ESTADO_PERSONA[p.estado] ?? p.estado}${p.tarefaId ? ` · #${p.tarefaId}` : ""}</small>` +
      `<br><small>${escapar(limite)} · ${p.abertas} aberta(s)</small>`
    if (p.tarefaId) cartao.onclick = () => abrirTarefaDoPainel(p.tarefaId)
    grade.appendChild(cartao)
  }
  secao.appendChild(grade)
  return secao
}

function secaoDeContagem(tarefas) {
  const secao = document.createElement("section")
  secao.appendChild(tituloDeSecao("Tarefas"))
  if (estado.equipes.length > 1) {
    secao.appendChild(
      seletorDeEquipe(estado.equipeDoPainel, (id) => {
        estado.equipeDoPainel = id
        renderPainel()
      }),
    )
  }
  const contagem = tarefas[estado.equipeDoPainel] ?? {}
  const linha = document.createElement("div")
  linha.className = "acoes-tarefa"
  for (const status of ORDEM_STATUS) {
    if (!contagem[status]) continue
    const botao = document.createElement("button")
    botao.textContent = `${NOMES_STATUS[status]} · ${contagem[status]}`
    botao.onclick = () => {
      estado.equipeDasTarefas = estado.equipeDoPainel
      abrirTarefas()
    }
    linha.appendChild(botao)
  }
  secao.appendChild(linha.children.length ? linha : vazio("Nenhuma tarefa nesta equipe."))
  return secao
}

function secaoDeProximas(rotinas) {
  const secao = document.createElement("section")
  secao.appendChild(tituloDeSecao("Próximas rotinas"))
  if (!rotinas.length) secao.appendChild(vazio("Nenhuma rotina agendada."))
  const ul = document.createElement("ul")
  ul.className = "lista-atividade"
  for (const r of rotinas) {
    const li = document.createElement("li")
    li.innerHTML = `<time>${quando(r.proximo)}</time> <strong>${escapar(r.nome)}</strong> · ${escapar(equipeDe(r.equipe)?.nome ?? r.equipe)}`
    ul.appendChild(li)
  }
  if (rotinas.length) secao.appendChild(ul)
  return secao
}

function secaoDeAtividadeDoPainel(itens) {
  const secao = document.createElement("section")
  secao.appendChild(tituloDeSecao("Atividade"))
  const filtros = document.createElement("div")
  filtros.className = "acoes-tarefa"
  const quem = document.createElement("select")
  quem.setAttribute("aria-label", "filtrar por persona")
  quem.innerHTML =
    `<option value="">todas as personas</option><option value="ueslei">Ueslei</option>` +
    estado.personas.map((p) => `<option value="${escapar(p.id)}">${escapar(p.nome)}</option>`).join("")
  quem.value = estado.filtroPersona
  quem.onchange = () => {
    estado.filtroPersona = quem.value
    renderPainel()
  }
  const tipo = document.createElement("select")
  tipo.setAttribute("aria-label", "filtrar por tipo")
  tipo.innerHTML =
    `<option value="">tudo</option>` +
    Object.entries(NOMES_TIPO_ATIVIDADE).map(([v, n]) => `<option value="${v}">${n}</option>`).join("")
  tipo.value = estado.filtroTipo
  tipo.onchange = () => {
    estado.filtroTipo = tipo.value
    renderPainel()
  }
  filtros.append(quem, tipo)
  secao.appendChild(filtros)
  const filtrados = itens.filter(
    (a) => (!estado.filtroPersona || a.quem === estado.filtroPersona) && (!estado.filtroTipo || a.tipo === estado.filtroTipo),
  )
  if (!filtrados.length) secao.appendChild(vazio("Nada por aqui."))
  const ul = document.createElement("ul")
  ul.className = "lista-atividade"
  for (const a of filtrados) {
    const li = document.createElement("li")
    const nome = estado.personas.find((p) => p.id === a.quem)?.nome ?? (a.quem === "ueslei" ? "Ueslei" : a.quem)
    li.innerHTML =
      `<time>${quando(a.em)}</time> <strong>${escapar(nome)}</strong>${a.tarefaId ? ` · #${a.tarefaId}` : ""} · ${escapar(a.texto)}`
    if (a.tarefaId) {
      li.style.cursor = "pointer"
      li.onclick = () => abrirTarefaDoPainel(a.tarefaId, a.equipe)
    }
    ul.appendChild(li)
  }
  if (filtrados.length) secao.appendChild(ul)
  return secao
}

function renderPainel() {
  if (estado.modo !== "painel") return
  limparTela()
  definirCabecalho("painel", "Painel")
  el.mensagens.appendChild(barraDePausa())
  const r = estado.painel
  if (!r) {
    adicionarMensagem("aviso", "Carregando o painel…")
    return
  }
  const gasto = `Mês ${r.gasto.mes}: ${dinheiro(r.gasto.tarefasUSD)} em tarefas · ${dinheiro(r.gasto.totalUSD)} no total · ${formatarTokens(r.gasto.tokensTotal)}`
  el.mensagens.append(
    secaoDeAtencao(r.atencao),
    secaoAgora(r.agora),
    secaoDeCartoes(r.personas),
    Object.assign(document.createElement("small"), { className: "painel-vazio", textContent: gasto }),
    secaoDeContagem(r.tarefas),
    secaoDeProximas(r.proximasRotinas),
    secaoDeAtividadeDoPainel(r.atividade),
  )
}

function abrirEquipes() {
  estado.modo = "equipes"
  estado.perfil = null
  estado.conversaId = null
  estado.posicaoVista = null
  ajustarAoModo()
  selecionarBotao("#botao-equipes")
  definirCabecalho("equipes", "Equipes")
  irParaConversa()
  informarVisivel()
  enviar({ tipo: "equipes" })
  enviar({ tipo: "personas" })
  enviar({ tipo: "tarefas" })
  enviar({ tipo: "rotinas" })
  renderEquipes()
}

function svgDoOrganograma(equipe) {
  const ponto = (p) => equipe.layout[p.id] ?? { x: 0, y: 0 }
  const xs = equipe.posicoes.map((p) => ponto(p).x)
  const ys = equipe.posicoes.map((p) => ponto(p).y)
  const minX = Math.min(...xs)
  const maxX = Math.max(...xs) + LARGURA_NO
  const maxY = Math.max(...ys) + ALTURA_NO
  const desloca = 20 - minX
  const no = (p) => ({ x: ponto(p).x + desloca, y: ponto(p).y + TOPO_DO_ORGANOGRAMA })
  const largura = maxX - minX + 40
  const altura = maxY + TOPO_DO_ORGANOGRAMA + 20
  const linhas = equipe.posicoes.map((p) => {
    const chefe = equipe.posicoes.find((c) => c.id === p.respondeA)
    if (!chefe) return ""
    const de = no(p)
    const x1 = de.x + LARGURA_NO / 2
    const [x2, y2] = [no(chefe).x + LARGURA_NO / 2, no(chefe).y + ALTURA_NO]
    const meio = (de.y + y2) / 2
    return `<path class="ligacao" d="M${x1} ${de.y} V${meio} H${x2} V${y2}" />`
  })
  const nos = equipe.posicoes.map((p) => {
    const { x, y } = no(p)
    const persona = p.persona ? personaDe(p.persona) : null
    const capacidades = p.capacidades.map((c) => NOMES_CAPACIDADE[c] ?? c).join(" · ")
    return (
      `<g class="no-org${estado.posicaoVista === p.id ? " escolhido" : ""}" data-posicao="${escapar(p.id)}" tabindex="0">` +
      `<rect x="${x}" y="${y}" width="${LARGURA_NO}" height="${ALTURA_NO}" rx="10" />` +
      `<circle cx="${x + 22}" cy="${y + 26}" r="12" fill="${persona?.cor ?? "var(--borda)"}" />` +
      `<text class="inicial" x="${x + 22}" y="${y + 30}">${escapar(persona?.inicial ?? "?")}</text>` +
      `<text class="titulo-no" x="${x + 42}" y="${y + 24}">${escapar(p.titulo)}</text>` +
      `<text class="persona-no" x="${x + 42}" y="${y + 42}">${escapar(p.personaNome ?? "vaga")}</text>` +
      `<text class="capacidades-no" x="${x + 12}" y="${y + 66}">${escapar(capacidades)}</text>` +
      `</g>`
    )
  })
  return (
    `<svg class="organograma" viewBox="0 0 ${largura} ${altura}" width="${largura}" height="${altura}" role="img" aria-label="organograma da equipe ${escapar(equipe.nome)}">` +
    linhas.join("") +
    nos.join("") +
    `</svg>`
  )
}

function detalheDaPosicao(equipe, p) {
  const div = document.createElement("div")
  div.className = "msg perfil-msg documento detalhe-posicao"
  const chefe = equipe.posicoes.find((c) => c.id === p.respondeA)
  const abertas = estado.tarefas.filter(
    (t) => t.equipe === equipe.id && t.posicao === p.id && t.status !== "concluida" && t.status !== "cancelada",
  )
  const linhas = [
    `<strong>${escapar(p.titulo)}</strong> <small>(${escapar(p.id)})</small>`,
    `Persona: ${escapar(p.personaNome ?? "vaga")}`,
    `Responde a: ${escapar(chefe ? chefe.titulo : "ninguém (solta, responde a você)")}`,
    `Capacidades: ${escapar(p.capacidades.map((c) => NOMES_CAPACIDADE[c] ?? c).join(", ") || "nenhuma")}`,
    p.capacidades.includes("comandos") ? `Aprovação de comando: ${escapar(p.aprovacao)}` : "",
    p.diretorio ? `Diretório: <code>${escapar(p.diretorio)}</code>` : "",
    p.politica?.length ? `Depois da entrega: ${escapar(descreverPolitica(p.politica, equipe.id).join(" → "))}` : "",
  ]
  div.innerHTML = linhas.filter(Boolean).join("<br>")
  if (abertas.length) {
    const ul = document.createElement("ul")
    ul.className = "lista-decisoes"
    for (const t of abertas) {
      const li = document.createElement("li")
      li.innerHTML = `<span class="status ${t.status}">#${t.id}</span>${escapar(t.titulo)}`
      li.onclick = () => {
        estado.equipeDasTarefas = t.equipe
        abrirTarefas()
        enviar({ tipo: "tarefa", id: t.id })
      }
      ul.appendChild(li)
    }
    div.appendChild(ul)
  }
  return div
}

let formDePersona = null

function formNovaPersona() {
  if (formDePersona) return formDePersona
  const form = document.createElement("form")
  form.className = "nova-tarefa nova-persona"
  form.innerHTML =
    `<input name="nome" placeholder="Nome da persona" maxlength="40" required />` +
    `<input name="titulo" placeholder="Papel curto (aparece na lista)" maxlength="60" />` +
    `<textarea name="base" rows="4" maxlength="4000" required placeholder="Quem é, que papel tem com você e qual é o jeito dela"></textarea>` +
    `<select name="modelo" aria-label="modelo"><option value="">modelo padrão</option><option value="sonnet">Sonnet</option><option value="opus">Opus</option></select>` +
    `<label class="cor-persona">cor <input name="cor" type="color" value="#5b8def" /></label>` +
    `<button type="submit">Criar persona</button>`
  let corEscolhida = false
  form.querySelector('[name="cor"]').addEventListener("input", () => (corEscolhida = true))
  form.onsubmit = (ev) => {
    ev.preventDefault()
    const dados = new FormData(form)
    const persona = {
      nome: String(dados.get("nome") ?? "").trim(),
      titulo: String(dados.get("titulo") ?? "").trim(),
      base: String(dados.get("base") ?? "").trim(),
      modelo: String(dados.get("modelo") ?? "") || undefined,
      cor: corEscolhida ? String(dados.get("cor")) : undefined,
    }
    if (!persona.nome || !persona.base) return
    enviar({ tipo: "persona-criar", persona })
    form.reset()
    corEscolhida = false
  }
  formDePersona = form
  return form
}

function secaoDePersonas() {
  const secao = document.createElement("section")
  secao.className = "secao-personas"
  const titulo = document.createElement("h3")
  titulo.className = "grupo-tarefas"
  titulo.textContent = `Personas · ${estado.personas.length}`
  secao.appendChild(titulo)
  const ul = document.createElement("ul")
  ul.className = "lista-decisoes"
  for (const p of estado.personas) {
    const li = document.createElement("li")
    li.className = "persona-item"
    const MOTIVOS = { ueslei: "pausada", tudo: "tudo pausado", orcamento: "orçamento estourado" }
    const limite = p.orcamentoMensalUSD
    const limiteTokens = p.orcamentoMensalTokens
    const fracao = (gasto, teto) => (teto == null ? 0 : teto <= 0 ? 1 : Math.min(1, gasto / teto))
    const proporcao = Math.max(fracao(p.gastoMesUSD ?? 0, limite), fracao(p.tokensMes ?? 0, limiteTokens))
    li.innerHTML =
      `<span class="avatar avatar-balao ${p.id}">${escapar(p.inicial)}</span>` +
      `<span class="persona-dados">${escapar(p.nome)}` +
      `<small>${escapar([p.titulo, p.modelo, p.gerandoPerfil ? "gerando perfil…" : "", p.pausa ? MOTIVOS[p.pausa.motivo] : ""].filter(Boolean).join(" · "))}</small>` +
      `<small>tarefas no mês: US$ ${(p.gastoMesUSD ?? 0).toFixed(2)}${limite != null ? ` de US$ ${limite.toFixed(2)}` : " · sem limite"} · total US$ ${(p.gastoTotalMesUSD ?? 0).toFixed(2)}</small>` +
      `<small>tokens no mês: ${formatarTokens(p.tokensMes ?? 0)}${limiteTokens != null ? ` de ${formatarTokens(limiteTokens)}` : " · sem limite"} · total ${formatarTokens(p.tokensTotalMes ?? 0)}</small>` +
      (limite != null || limiteTokens != null ? `<span class="barra-orcamento${proporcao >= 1 ? " estourado" : proporcao >= 0.8 ? " alerta" : ""}"><span style="width:${Math.round(proporcao * 100)}%"></span></span>` : "") +
      `</span>`
    const orcamento = document.createElement("input")
    orcamento.type = "number"
    orcamento.min = "0"
    orcamento.step = "0.5"
    orcamento.placeholder = "limite US$"
    orcamento.className = "orcamento-persona"
    orcamento.value = limite != null ? String(limite) : ""
    orcamento.title = "orçamento mensal das tarefas (vazio = sem limite)"
    orcamento.onchange = () =>
      enviar({ tipo: "persona-salvar", persona: { id: p.id, orcamentoMensalUSD: orcamento.value === "" ? null : Number(orcamento.value) } })
    li.appendChild(orcamento)
    const tokens = document.createElement("input")
    tokens.type = "number"
    tokens.min = "0"
    tokens.step = "100000"
    tokens.placeholder = "limite tokens"
    tokens.className = "orcamento-persona tokens"
    tokens.value = limiteTokens != null ? String(limiteTokens) : ""
    tokens.title = "limite mensal de tokens das tarefas (vazio = sem limite)"
    tokens.onchange = () =>
      enviar({
        tipo: "persona-salvar",
        persona: { id: p.id, orcamentoMensalTokens: tokens.value === "" ? null : Math.round(Number(tokens.value)) },
      })
    li.appendChild(tokens)
    const pausa = document.createElement("button")
    pausa.className = "pausar-persona"
    const pausadaPeloUeslei = p.pausa?.motivo === "ueslei"
    pausa.textContent = pausadaPeloUeslei ? "Retomar" : "Pausar"
    pausa.onclick = () => enviar(pausadaPeloUeslei ? { tipo: "retomar", alvo: p.id } : { tipo: "pausar", alvo: p.id })
    li.appendChild(pausa)
    if (p.excluivel) {
      const excluir = document.createElement("button")
      excluir.className = "excluir-persona"
      excluir.textContent = "Excluir"
      excluir.onclick = () => {
        const confirmacao = prompt(
          `Excluir ${p.nome}? As posições dela ficam vagas e as conversas viram só leitura. Digite ${p.nome} para confirmar.`,
        )
        if (confirmacao !== null) enviar({ tipo: "persona-excluir", id: p.id, confirmacao })
      }
      li.appendChild(excluir)
    }
    ul.appendChild(li)
  }
  secao.appendChild(ul)
  secao.appendChild(formNovaPersona())
  return secao
}

const NOMES_RESULTADO = { criada: "criou a tarefa", pulada: "pulou", falhou: "falhou" }

function linhaDoDisparo(d) {
  if (!d) return "nunca disparou"
  const tarefa = d.tarefa ? ` #${d.tarefa}` : ""
  return `${quando(d.em)} · ${NOMES_RESULTADO[d.resultado] ?? d.resultado}${tarefa}${d.motivo ? ` (${d.motivo})` : ""}`
}

function secaoDeRotinas(equipe) {
  const secao = document.createElement("section")
  const titulo = document.createElement("h3")
  titulo.className = "grupo-tarefas"
  titulo.textContent = "Rotinas"
  secao.appendChild(titulo)
  const lista = estado.rotinas.filter((r) => r.equipe === equipe.id || r.sistema)
  if (!lista.length) {
    secao.appendChild(Object.assign(document.createElement("small"), { textContent: "Nenhuma rotina. Crie pelo app desktop." }))
    return secao
  }
  const ul = document.createElement("ul")
  ul.className = "lista-decisoes lista-rotinas"
  for (const r of lista) {
    const li = document.createElement("li")
    const gatilhos = [r.cron ? `cron ${r.cron}` : "", r.webhook ? "webhook" : ""].filter(Boolean).join(" · ") || "só manual"
    const proximo = r.ativa && r.proximo ? ` · próximo ${quando(r.proximo)}` : ""
    li.innerHTML =
      `<span class="status ${r.ativa ? "a_fazer" : "cancelada"}">${r.ativa ? "ativa" : "parada"}</span>${escapar(r.nome)}` +
      `<small>${escapar(gatilhos)}${proximo}<br>último: ${escapar(linhaDoDisparo(r.ultimoDisparo))}</small>`
    if (!r.sistema) {
      const acoes = document.createElement("div")
      acoes.className = "acoes-tarefa"
      const disparar = document.createElement("button")
      disparar.textContent = "Disparar agora"
      disparar.onclick = () => enviar({ tipo: "rotina-disparar", equipe: r.equipe, id: r.id })
      const ativar = document.createElement("button")
      ativar.textContent = r.ativa ? "Desativar" : "Ativar"
      ativar.onclick = () => enviar({ tipo: "rotina-ativar", equipe: r.equipe, id: r.id, ativa: !r.ativa })
      acoes.append(disparar, ativar)
      li.appendChild(acoes)
    }
    ul.appendChild(li)
  }
  secao.appendChild(ul)
  return secao
}

function renderEquipes() {
  if (estado.modo !== "equipes") return
  limparTela()
  el.mensagens.appendChild(barraDePausa())
  const equipe = equipeDe(estado.equipeVista) ?? estado.equipes[0]
  if (equipe) {
    estado.equipeVista = equipe.id
    definirCabecalho("equipes", `Equipes — ${equipe.nome}`)
    if (estado.equipes.length > 1) {
      el.mensagens.appendChild(
        seletorDeEquipe(equipe.id, (id) => {
          estado.equipeVista = id
          estado.posicaoVista = null
          renderEquipes()
        }),
      )
    }
    const rolagem = document.createElement("div")
    rolagem.className = "organograma-rolagem"
    rolagem.innerHTML = equipe.posicoes.length ? svgDoOrganograma(equipe) : "<p>Equipe sem posições.</p>"
    rolagem.onclick = (ev) => {
      const no = ev.target.closest("[data-posicao]")
      if (!no) return
      estado.posicaoVista = estado.posicaoVista === no.dataset.posicao ? null : no.dataset.posicao
      renderEquipes()
    }
    el.mensagens.appendChild(rolagem)
    const vista = equipe.posicoes.find((p) => p.id === estado.posicaoVista)
    if (vista) el.mensagens.appendChild(detalheDaPosicao(equipe, vista))
    el.mensagens.appendChild(secaoDeRotinas(equipe))
  }
  el.mensagens.appendChild(secaoDePersonas())
}

// ── envio ──────────────────────────────────────────────────────────

function submeter() {
  const texto = el.entrada.value.trim()
  const anexos = estado.anexos
  const noChat = estado.modo === "chat"
  if (estado.respostaEmCurso) return
  if (!texto && !(noChat && anexos.length)) return
  if (estado.modo === "tarefas" && !estado.tarefaId) return
  if (estado.modo === "equipes" || estado.modo === "painel") return
  el.entrada.value = ""
  ajustarEntrada()

  if (estado.modo === "tarefas") {
    enviar({ tipo: "tarefa-comentar", id: estado.tarefaId, texto })
    return
  }

  if (estado.modo === "board") {
    mensagemDoUsuario(texto, null, new Date())
    definirEmCurso("board")
    adicionarMensagem("aviso", "Board convocado — colhendo pareceres…")
    enviar({ tipo: "board", pauta: texto })
    return
  }

  if (noChat && estado.perfil) {
    const citacao = estado.citacao ?? undefined
    const ids = anexos.map((a) => a.id)
    mensagemDoUsuario(texto, citacao, new Date(), anexos)
    limparCitacao()
    limparAnexos()
    definirEmCurso("chat")
    const comum = {
      texto,
      citacao,
      anexos: ids,
      modelo: el.modelo.value,
      auto: estado.auto,
      foco: ehExecutor(estado.perfil) ? (estado.foco ?? "") : undefined,
    }
    if (estado.conversaId) {
      enviar({ tipo: "mensagem", conversaId: estado.conversaId, ...comum })
    } else {
      enviar({ tipo: "nova", perfil: estado.perfil, ...comum })
    }
    mostrarDigitando(estado.perfil)
  }
}

// ── recepção ───────────────────────────────────────────────────────

let textoStreaming = ""
let partesRenderizadas = 0
let perfilStreaming = null
let indicadorDigitando = null

function mostrarDigitando(perfil) {
  if (!indicadorDigitando) {
    indicadorDigitando = document.createElement("div")
    indicadorDigitando.className = "msg digitando"
    indicadorDigitando.innerHTML =
      `<span class="avatar avatar-balao ${perfil}">${inicialDe(perfil)}</span>` +
      `<span class="autor ${perfil}">${escapar(nomeDe(perfil))}</span>` +
      `<span class="pontos"><i></i><i></i><i></i></span>`
  }
  el.mensagens.appendChild(indicadorDigitando)
  el.mensagens.scrollTop = el.mensagens.scrollHeight
}

function esconderDigitando() {
  indicadorDigitando?.remove()
  indicadorDigitando = null
}

function renderizarBlocosFechados(partes) {
  while (partesRenderizadas < partes.length) {
    const parte = partes[partesRenderizadas].trim()
    if (parte) mensagemDoPerfil(perfilStreaming, parte, partesRenderizadas === 0)
    partesRenderizadas++
  }
}

function encerrarStreaming() {
  esconderDigitando()
  textoStreaming = ""
  partesRenderizadas = 0
  perfilStreaming = null
}

function tratar(msg) {
  switch (msg.tipo) {
    case "permissao": {
      if (msg.tarefaId) {
        estado.pedidosDeTarefa.set(msg.id, msg)
        if (estado.modo === "tarefas" && estado.tarefaId === msg.tarefaId) cartaoDePermissao(msg)
        break
      }
      cartaoDePermissao(msg)
      break
    }
    case "comando": {
      adicionarMensagem("comando", `▸ ${escapar(msg.comando)}`)
      break
    }
    case "permissao-resolvida": {
      estado.pedidosDeTarefa.delete(msg.id)
      const acoes = document.querySelector(`[data-permissao="${CSS.escape(msg.id)}"] .acoes`)
      if (acoes?.querySelector("button")) acoes.innerHTML = `<small>${ROTULOS_PERMISSAO[msg.como] ?? msg.como}</small>`
      break
    }
    case "atalhos": {
      estado.atalhos = msg.lista
      renderAtalhos()
      break
    }
    case "conversas": {
      el.listaConversas.innerHTML = ""
      for (const meta of msg.lista) {
        const li = document.createElement("li")
        li.innerHTML =
          `<span class="avatar ${meta.perfil}">${inicialDe(meta.perfil)}</span>` +
          `<span class="linha"><span class="titulo">${escapar(meta.titulo)}</span>` +
          `<time>${quando(meta.criadaEm)}</time></span>`
        li.onclick = () => {
          irParaConversa()
          enviar({ tipo: "abrir", conversaId: meta.id })
        }
        li.dataset.id = meta.id
        el.listaConversas.appendChild(li)
      }
      break
    }
    case "excluida": {
      if (estado.conversaId === msg.id) {
        estado.conversaId = null
        estado.perfil = null
        estado.foco = null
        limparTela()
        selecionarBotao(null)
        definirCabecalho(null, "Escolha um perfil para começar")
        irParaLista()
        informarVisivel()
      }
      break
    }
    case "criada": {
      estado.conversaId = msg.meta.id
      definirCabecalho(msg.meta.perfil, `${nomeDe(msg.meta.perfil)} — ${msg.meta.titulo}`)
      enviar({ tipo: "listar" })
      informarVisivel()
      break
    }
    case "conversa": {
      estado.modo = "chat"
      estado.perfil = msg.meta.perfil
      estado.conversaId = msg.meta.id
      estado.auto = msg.meta.auto === true
      estado.foco = msg.meta.foco ?? null
      ajustarAoModo()
      selecionarBotao(`[data-perfil="${msg.meta.perfil}"]`)
      definirCabecalho(msg.meta.perfil, `${nomeDe(msg.meta.perfil)} — ${msg.meta.titulo}`)
      el.modelo.value = msg.meta.modelo ?? "haiku"
      irParaConversa()
      informarVisivel()
      limparTela()
      for (const m of msg.mensagens) {
        if (m.role === "user") {
          mensagemDoUsuario(m.texto, m.citacao, m.ts, m.anexos)
        } else {
          balcoesDoPerfil(m.perfil, m.texto, m.ts)
        }
      }
      break
    }
    case "chunk": {
      perfilStreaming = msg.perfil
      textoStreaming += msg.texto
      const partes = textoStreaming.split(SEPARADOR_BALAO)
      renderizarBlocosFechados(partes.slice(0, -1))
      mostrarDigitando(msg.perfil)
      break
    }
    case "fim": {
      if (perfilStreaming) renderizarBlocosFechados(textoStreaming.split(SEPARADOR_BALAO))
      encerrarStreaming()
      definirEmCurso(null)
      break
    }
    case "board-status":
    case "aviso": {
      adicionarMensagem("aviso", escapar(msg.texto))
      break
    }
    case "board-sintese": {
      mensagemDoPerfil("board", msg.texto)
      adicionarMensagem("aviso", `Ata completa: ${msg.ata}`)
      definirEmCurso(null)
      break
    }
    case "decisoes": {
      limparTela()
      const ul = document.createElement("ul")
      ul.className = "lista-decisoes"
      if (!msg.lista.length) adicionarMensagem("aviso", "Nenhuma decisão registrada ainda.")
      for (const d of msg.lista) {
        const li = document.createElement("li")
        li.innerHTML = `<span class="status ${d.status}">${d.status}</span>${escapar(d.title)} <small>· ${d.date} · ${d.tags.join(", ")}</small>`
        li.onclick = () => enviar({ tipo: "decisao", id: d.id })
        ul.appendChild(li)
      }
      el.mensagens.appendChild(ul)
      break
    }
    case "decisao": {
      limparTela()
      adicionarMensagem("perfil-msg documento", formatar(msg.conteudo))
      const voltar = adicionarMensagem("aviso", "← voltar para a lista")
      voltar.style.cursor = "pointer"
      voltar.onclick = () => enviar({ tipo: "decisoes" })
      break
    }
    case "equipes": {
      estado.equipes = msg.lista
      renderTarefas()
      renderEquipes()
      break
    }
    case "personas": {
      estado.personas = msg.lista
      renderPersonas()
      renderEquipes()
      break
    }
    case "orquestra": {
      estado.pausadoTudo = msg.pausadoTudo === true
      renderEquipes()
      renderTarefas()
      break
    }
    case "painel": {
      estado.painel = msg.retrato
      renderPainel()
      break
    }
    case "rotinas": {
      estado.rotinas = msg.lista
      renderEquipes()
      if (estado.modo === "tarefas" && estado.detalhe) renderTarefa()
      break
    }
    case "tarefas": {
      estado.tarefas = msg.lista
      renderTarefas()
      renderEquipes()
      break
    }
    case "tarefa": {
      const i = estado.tarefas.findIndex((t) => t.id === msg.tarefa.id)
      if (i >= 0) estado.tarefas[i] = msg.tarefa
      else estado.tarefas.unshift(msg.tarefa)
      if (estado.modo !== "tarefas") break
      if ((estado.tarefaId === null && msg.pedida) || estado.tarefaId === msg.tarefa.id) {
        if (estado.tarefaId !== msg.tarefa.id) estado.log = null
        estado.detalhe = msg
        renderTarefa()
      } else renderTarefas()
      break
    }
    case "execucao": {
      const d = estado.detalhe
      if (!d || d.tarefa.id !== msg.execucao.tarefa) break
      const i = d.execucoes.findIndex((e) => e.id === msg.execucao.id)
      if (i >= 0) d.execucoes[i] = msg.execucao
      else d.execucoes.push(msg.execucao)
      if (msg.eventos) {
        estado.log = { execucaoId: msg.execucao.id, eventos: msg.eventos }
        renderLog()
      } else if (msg.execucao.status === "rodando") {
        pedirLogSePreciso()
      }
      break
    }
    case "execucao-evento": {
      if (estado.log?.execucaoId !== msg.execucaoId) break
      estado.log.eventos.push(msg.evento)
      const alvo = document.getElementById("log-execucao")
      if (alvo) {
        alvo.querySelector("small")?.remove()
        alvo.appendChild(linhaDeEvento(msg.evento))
        rolarAoFim()
      }
      break
    }
    case "erro": {
      adicionarMensagem("erro", escapar(msg.mensagem))
      encerrarStreaming()
      definirEmCurso(null)
      break
    }
  }
}

// ── ligação da UI ──────────────────────────────────────────────────

el.auto.onclick = () => {
  estado.auto = !estado.auto
  refletirAuto()
}
el.ticktask.onclick = () => {
  estado.foco = estado.foco === "ticktask" ? null : "ticktask"
  refletirFoco()
  adicionarMensagem(
    "aviso",
    estado.foco
      ? "TickTask ligado: o Alfred registra direto no app."
      : "TickTask desligado: o Alfred volta a executar comandos.",
  )
}
document.getElementById("botao-board").onclick = abrirBoard
document.getElementById("botao-decisoes").onclick = abrirDecisoes
document.getElementById("botao-painel").onclick = abrirPainel
document.getElementById("botao-tarefas").onclick = abrirTarefas
document.getElementById("botao-equipes").onclick = abrirEquipes
document.getElementById("citacao-fechar").onclick = limparCitacao
el.voltar.onclick = irParaLista
el.fab.onclick = () => (document.body.dataset.folha === "aberta" ? fecharFolha() : abrirFolha())
el.veu.onclick = fecharFolha

document.body.dataset.tela = "lista"
history.replaceState({ tela: "lista" }, "")
window.addEventListener("popstate", () => {
  if (!history.state?.folha) ocultarFolha()
  mostrarTela(history.state?.tela === "conversa" ? "conversa" : "lista")
})
document.addEventListener("visibilitychange", informarVisivel)

// ── menu do balão: toque longo no celular, clique direito no desktop ──

const menu = document.getElementById("menu-balao")
const menuConversa = document.getElementById("menu-conversa")
let balaoDoMenu = null
let conversaDoMenu = null

const textoDoBalao = (balao) => balao?.querySelector(".corpo")?.textContent.trim() ?? ""

function abrirMenu(balao, x, y) {
  if (!textoDoBalao(balao)) return
  fecharMenu()
  balaoDoMenu = balao
  balao.classList.add("pressionado")
  menu.querySelector('[data-acao="responder"]').hidden = estado.modo !== "chat"
  menu.hidden = false
  posicionarMenu(menu, x, y)
}

function fecharMenu() {
  balaoDoMenu?.classList.remove("pressionado")
  balaoDoMenu = null
  menu.hidden = true
}

function fecharMenuConversa() {
  document.querySelector("#lista-conversas li.pressionado")?.classList.remove("pressionado")
  conversaDoMenu = null
  menuConversa.hidden = true
}

function fecharMenus() {
  fecharMenu()
  fecharMenuConversa()
}

function posicionarMenu(alvo, x, y) {
  const limite = (v, tamanho, total) => Math.min(Math.max(8, v), total - tamanho - 8)
  alvo.style.left = `${limite(x, alvo.offsetWidth, window.innerWidth)}px`
  alvo.style.top = `${limite(y, alvo.offsetHeight, window.innerHeight)}px`
}

// Mesmo gesto do balão servindo a lista: toque longo no celular, clique direito
// no desktop.
function ligarToqueLongo(container, achar, aoAbrir) {
  let timer = null
  let inicio = null
  const cancelar = () => {
    clearTimeout(timer)
    timer = null
    inicio = null
  }
  container.addEventListener("pointerdown", (ev) => {
    if (ev.pointerType === "mouse" && ev.button !== 0) return
    const alvo = achar(ev)
    if (!alvo) return
    inicio = { x: ev.clientX, y: ev.clientY }
    timer = setTimeout(() => {
      timer = null
      aoAbrir(alvo, ev.clientX, ev.clientY)
    }, 450)
  })
  container.addEventListener("pointermove", (ev) => {
    if (!timer || !inicio) return
    if (Math.hypot(ev.clientX - inicio.x, ev.clientY - inicio.y) > 10) cancelar()
  })
  container.addEventListener("pointerup", cancelar)
  container.addEventListener("pointercancel", cancelar)
  container.addEventListener("scroll", () => {
    cancelar()
    fecharMenus()
  })
  container.addEventListener("contextmenu", (ev) => {
    const alvo = achar(ev)
    if (!alvo) return
    ev.preventDefault()
    aoAbrir(alvo, ev.clientX, ev.clientY)
  })
}

// Fora de contexto seguro navigator.clipboard não existe, e este app roda em
// http na rede local — daí o caminho pelo textarea.
async function copiar(texto) {
  if (window.isSecureContext && navigator.clipboard) {
    try {
      await navigator.clipboard.writeText(texto)
      return
    } catch {
      /* cai no caminho abaixo */
    }
  }
  const area = document.createElement("textarea")
  area.value = texto
  area.setAttribute("readonly", "")
  area.style.cssText = "position: fixed; top: 0; opacity: 0;"
  document.body.appendChild(area)
  area.select()
  area.setSelectionRange(0, texto.length)
  const copiou = document.execCommand("copy")
  area.remove()
  if (!copiou) adicionarMensagem("aviso", "Não consegui copiar para a área de transferência.")
}

ligarToqueLongo(
  el.mensagens,
  (ev) => ev.target.closest(".msg.perfil-msg:not(.documento)"),
  abrirMenu,
)

menu.addEventListener("click", (ev) => {
  const acao = ev.target.closest("button")?.dataset.acao
  const texto = textoDoBalao(balaoDoMenu)
  fecharMenu()
  if (!texto) return
  if (acao === "responder") definirCitacao(texto)
  if (acao === "copiar") copiar(texto)
})

// ── menu da conversa e confirmação ─────────────────────────────────

const confirmacao = document.getElementById("confirmacao")
const confirmacaoTexto = document.getElementById("confirmacao-texto")
let responderConfirmacao = null

function fecharConfirmacao(resposta) {
  if (!responderConfirmacao) return
  const responder = responderConfirmacao
  responderConfirmacao = null
  confirmacao.hidden = true
  responder(resposta)
}

function confirmar(texto) {
  fecharConfirmacao(false)
  confirmacaoTexto.textContent = texto
  confirmacao.hidden = false
  return new Promise((resolve) => {
    responderConfirmacao = resolve
  })
}

document.getElementById("confirmacao-sim").onclick = () => fecharConfirmacao(true)
document.getElementById("confirmacao-nao").onclick = () => fecharConfirmacao(false)
confirmacao.addEventListener("click", (ev) => {
  if (ev.target === confirmacao) fecharConfirmacao(false)
})

function abrirMenuConversa(li, x, y) {
  if (!li.dataset.id) return
  fecharMenus()
  conversaDoMenu = { id: li.dataset.id, titulo: li.querySelector(".titulo")?.textContent ?? "" }
  li.classList.add("pressionado")
  menuConversa.hidden = false
  posicionarMenu(menuConversa, x, y)
}

ligarToqueLongo(
  document.getElementById("conversas"),
  (ev) => ev.target.closest("#lista-conversas li"),
  abrirMenuConversa,
)

menuConversa.addEventListener("click", async (ev) => {
  const acao = ev.target.closest("button")?.dataset.acao
  const alvo = conversaDoMenu
  fecharMenuConversa()
  if (acao !== "excluir" || !alvo) return
  const apagar = await confirmar(
    `Excluir "${alvo.titulo}"? Somem a transcrição e os anexos desta conversa. ` +
      "A memória do perfil não é afetada.",
  )
  if (apagar) enviar({ tipo: "excluir", conversaId: alvo.id })
})

// ── menu do clipe ──────────────────────────────────────────────────

const menuAnexo = document.getElementById("menu-anexo")
const fontes = {
  camera: document.getElementById("fonte-camera"),
  galeria: document.getElementById("fonte-galeria"),
  arquivo: document.getElementById("fonte-arquivo"),
}

function fecharMenuAnexo() {
  menuAnexo.hidden = true
}

function alternarMenuAnexo() {
  if (!menuAnexo.hidden) {
    fecharMenuAnexo()
    return
  }
  menuAnexo.hidden = false
  const alvo = el.clipe.getBoundingClientRect()
  menuAnexo.style.left = `${Math.max(8, alvo.left)}px`
  menuAnexo.style.top = `${Math.max(8, alvo.top - menuAnexo.offsetHeight - 8)}px`
}

el.clipe.onclick = alternarMenuAnexo

menuAnexo.addEventListener("click", (ev) => {
  const fonte = ev.target.closest("button")?.dataset.fonte
  fecharMenuAnexo()
  fontes[fonte]?.click()
})

for (const entrada of Object.values(fontes)) {
  // Zerar o value faz o change disparar ao escolher o mesmo arquivo de novo.
  entrada.addEventListener("change", () => {
    const escolhidos = [...entrada.files]
    entrada.value = ""
    anexarArquivos(escolhidos)
  })
}

document.addEventListener(
  "pointerdown",
  (ev) => {
    if (!menu.hidden && !menu.contains(ev.target)) fecharMenu()
    if (!menuConversa.hidden && !menuConversa.contains(ev.target)) fecharMenuConversa()
    if (!menuAnexo.hidden && !menuAnexo.contains(ev.target) && !el.clipe.contains(ev.target)) {
      fecharMenuAnexo()
    }
  },
  true,
)
document.addEventListener("keydown", (ev) => {
  if (ev.key !== "Escape") return
  fecharMenus()
  fecharMenuAnexo()
  fecharConfirmacao(false)
  fecharFolha()
})

el.enviar.onclick = submeter

// O scrollHeight de uma caixa border-box não conta a borda; sem os 2px o campo
// cresce um pixel a cada tecla.
function ajustarEntrada() {
  el.entrada.style.height = "auto"
  el.entrada.style.height = `${el.entrada.scrollHeight + 2}px`
  renderAtalhos()
}

el.entrada.addEventListener("input", ajustarEntrada)
ajustarEntrada()

// No celular não existe Shift+Enter, então Enter quebra linha e o envio é só
// pelo botão.
el.entrada.addEventListener("keydown", (ev) => {
  if (ev.key === "Enter" && !ev.shiftKey && !compacto()) {
    ev.preventDefault()
    submeter()
  }
})

// interactive-widget=resizes-content resolve o teclado no Chrome do Android; isto
// cobre navegador que ignora a chave e só encolhe a viewport visual.
const viewport = window.visualViewport
if (viewport) {
  const ajustarAltura = () => {
    document.documentElement.style.setProperty("--altura-app", `${viewport.height}px`)
  }
  viewport.addEventListener("resize", ajustarAltura)
  ajustarAltura()
}

el.entrada.addEventListener("focus", () => {
  setTimeout(() => {
    el.mensagens.scrollTop = el.mensagens.scrollHeight
  }, 300)
})

conectar()
