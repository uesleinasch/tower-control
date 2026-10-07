"use strict"

const NOMES = { poe: "Poe", nati: "Nati", lucas: "Lucas", pami: "Pami", alfred: "Alfred", board: "Board" }
const INICIAIS = { poe: "P", nati: "N", lucas: "L", pami: "P", alfred: "A", board: "B", decisoes: "D", tarefas: "T" }

const EXECUTORES = ["alfred"]
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
  equipes: [],
  tarefas: [],
  tarefaId: null,
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
    el.avatar.textContent = INICIAIS[perfil] ?? "?"
  }
}

function focarEntrada() {
  if (!compacto()) el.entrada.focus()
}

function refletirAuto() {
  const ligado = estado.auto && EXECUTORES.includes(estado.perfil)
  el.auto.setAttribute("aria-pressed", String(estado.auto))
  el.auto.textContent = ligado ? "auto · Opus 5.5" : "auto"
  el.modelo.disabled = ligado
  el.modelo.title = ligado ? "no modo auto o Alfred usa Opus 5.5" : "modelo usado nas respostas desta conversa"
}

function refletirFoco() {
  const ligado = estado.foco === "ticktask"
  el.ticktask.setAttribute("aria-pressed", String(ligado))
  if (estado.modo === "chat" && estado.perfil) {
    el.entrada.placeholder = ligado ? "O que registrar no TickTask…" : `Mensagem para ${NOMES[estado.perfil]}…`
  }
}

function ajustarAoModo() {
  const executor = estado.modo === "chat" && EXECUTORES.includes(estado.perfil)
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
  const cartao = adicionarMensagem(
    "permissao",
    `<span class="autor alfred">Alfred quer rodar um comando</span>` +
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
    ? `<span class="avatar avatar-balao ${perfil}">${INICIAIS[perfil] ?? "?"}</span>` +
      `<span class="autor ${perfil}">${NOMES[perfil] ?? perfil}</span>`
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
  definirCabecalho(perfil, `Nova conversa com ${NOMES[perfil]}`)
  limparTela()
  adicionarMensagem("aviso", `Você está falando com ${NOMES[perfil]}. A conversa é criada na primeira mensagem.`)
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
    "Apresente a pauta. Os quatro perfis vão deliberar em paralelo e você recebe a síntese; a ata completa fica em board/minutes/.",
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
  em_revisao: ["concluida", "em_andamento", "cancelada"],
  bloqueada: ["a_fazer", "cancelada"],
  concluida: ["a_fazer"],
  cancelada: ["backlog"],
}
const ORDEM_STATUS = ["em_andamento", "em_revisao", "a_fazer", "bloqueada", "backlog", "concluida", "cancelada"]

function posicoesDaCasa() {
  return estado.equipes.find((e) => e.id === "casa")?.posicoes ?? []
}

function rotuloDaPosicao(id) {
  const p = posicoesDaCasa().find((x) => x.id === id)
  if (!p) return id
  return p.personaNome ? `${p.personaNome} · ${p.titulo}` : `${p.titulo} (vaga)`
}

function refletirComposerDeTarefas() {
  const listando = estado.modo === "tarefas" && !estado.tarefaId
  el.entrada.disabled = listando
  if (estado.modo === "tarefas") {
    el.entrada.placeholder = listando ? "Abra uma tarefa para comentar" : "Comentar na tarefa…"
  }
}

function abrirTarefas() {
  estado.modo = "tarefas"
  estado.perfil = null
  estado.conversaId = null
  estado.tarefaId = null
  ajustarAoModo()
  selecionarBotao("#botao-tarefas")
  definirCabecalho("tarefas", "Tarefas — Casa")
  limparTela()
  irParaConversa()
  informarVisivel()
  enviar({ tipo: "equipes" })
  enviar({ tipo: "tarefas", equipe: "casa" })
}

function voltarParaTarefas() {
  estado.tarefaId = null
  refletirComposerDeTarefas()
  definirCabecalho("tarefas", "Tarefas — Casa")
  renderTarefas()
}

function formNovaTarefa() {
  const form = document.createElement("form")
  form.className = "nova-tarefa"
  const opcoes = posicoesDaCasa()
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
      tarefa: { equipe: "casa", posicao: dados.get("posicao"), titulo, porque: String(dados.get("porque") ?? "") },
    })
    form.reset()
  }
  return form
}

function renderTarefas() {
  if (estado.modo !== "tarefas" || estado.tarefaId) return
  limparTela()
  el.mensagens.appendChild(formNovaTarefa())
  if (!estado.tarefas.length) adicionarMensagem("aviso", "Nenhuma tarefa ainda.")
  for (const status of ORDEM_STATUS) {
    const doStatus = estado.tarefas.filter((t) => t.status === status)
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
        `<small>${escapar(rotuloDaPosicao(t.posicao))} · ${quando(t.atualizadaEm)}</small>`
      li.onclick = () => enviar({ tipo: "tarefa", id: t.id })
      ul.appendChild(li)
    }
    el.mensagens.appendChild(ul)
  }
}

function renderTarefa(tarefa, registros) {
  estado.tarefaId = tarefa.id
  refletirComposerDeTarefas()
  definirCabecalho("tarefas", `#${tarefa.id} — ${tarefa.titulo}`)
  limparTela()
  const voltar = adicionarMensagem("aviso", "← voltar para as tarefas")
  voltar.style.cursor = "pointer"
  voltar.onclick = voltarParaTarefas
  const linhas = [
    `**${tarefa.titulo}**`,
    `Status: ${NOMES_STATUS[tarefa.status]} · ${rotuloDaPosicao(tarefa.posicao)}${tarefa.dono ? ` · com ${tarefa.dono}` : ""}`,
    tarefa.porque ? `Por quê: ${tarefa.porque}` : "",
    tarefa.dependeDe.length ? `Depende de: ${tarefa.dependeDe.map((d) => `#${d}`).join(", ")}` : "",
    tarefa.pai ? `Parte da tarefa #${tarefa.pai}` : "",
    tarefa.descricao,
  ]
  adicionarMensagem("perfil-msg documento", formatar(linhas.filter(Boolean).join("\n\n")))
  const acoes = document.createElement("div")
  acoes.className = "acoes-tarefa"
  for (const para of TRANSICOES_TAREFA[tarefa.status] ?? []) {
    const botao = document.createElement("button")
    botao.textContent = `→ ${NOMES_STATUS[para]}`
    botao.onclick = () => enviar({ tipo: "tarefa-status", id: tarefa.id, status: para })
    acoes.appendChild(botao)
  }
  el.mensagens.appendChild(acoes)
  for (const r of registros) {
    if (r.tipo === "comentario") {
      if (r.autor === "ueslei") mensagemDoUsuario(r.texto, null, r.em)
      else adicionarMensagem("perfil-msg", `<strong>${escapar(r.autor)}</strong><br>${formatar(r.texto)}`, r.em)
    } else {
      adicionarMensagem("aviso", `${escapar(r.autor)}: ${escapar(r.texto)} · ${quando(r.em)}`)
    }
  }
  rolarAoFim()
}

// ── envio ──────────────────────────────────────────────────────────

function submeter() {
  const texto = el.entrada.value.trim()
  const anexos = estado.anexos
  const noChat = estado.modo === "chat"
  if (estado.respostaEmCurso) return
  if (!texto && !(noChat && anexos.length)) return
  if (estado.modo === "tarefas" && !estado.tarefaId) return
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
      foco: EXECUTORES.includes(estado.perfil) ? (estado.foco ?? "") : undefined,
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
      `<span class="avatar avatar-balao ${perfil}">${INICIAIS[perfil] ?? "?"}</span>` +
      `<span class="autor ${perfil}">${NOMES[perfil] ?? ""}</span>` +
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
      cartaoDePermissao(msg)
      break
    }
    case "comando": {
      adicionarMensagem("comando", `▸ ${escapar(msg.comando)}`)
      break
    }
    case "permissao-resolvida": {
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
          `<span class="avatar ${meta.perfil}">${INICIAIS[meta.perfil] ?? "?"}</span>` +
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
      definirCabecalho(msg.meta.perfil, `${NOMES[msg.meta.perfil]} — ${msg.meta.titulo}`)
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
      definirCabecalho(msg.meta.perfil, `${NOMES[msg.meta.perfil]} — ${msg.meta.titulo}`)
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
      break
    }
    case "tarefas": {
      estado.tarefas = msg.lista
      renderTarefas()
      break
    }
    case "tarefa": {
      const i = estado.tarefas.findIndex((t) => t.id === msg.tarefa.id)
      if (i >= 0) estado.tarefas[i] = msg.tarefa
      else estado.tarefas.unshift(msg.tarefa)
      if (estado.modo !== "tarefas") break
      if (estado.tarefaId === null && msg.pedida) renderTarefa(msg.tarefa, msg.registros)
      else if (estado.tarefaId === msg.tarefa.id) renderTarefa(msg.tarefa, msg.registros)
      else renderTarefas()
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

document.querySelectorAll(".perfil").forEach((b) => {
  b.onclick = () => abrirPerfil(b.dataset.perfil)
})

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
document.getElementById("botao-tarefas").onclick = abrirTarefas
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
