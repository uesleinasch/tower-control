"use strict"

const NOMES = { poe: "Poe", nati: "Nati", lucas: "Lucas", pami: "Pami", board: "Board" }
const INICIAIS = { poe: "P", nati: "N", lucas: "L", pami: "P", board: "B", decisoes: "D" }

const estado = {
  ws: null,
  modo: "chat", // chat | board | decisoes
  perfil: null,
  conversaId: null,
  respostaEmCurso: null,
  citacao: null,
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
}

// ── telas ──────────────────────────────────────────────────────────

const compacto = () => window.matchMedia("(max-width: 899px)").matches

function irParaConversa() {
  if (document.body.dataset.tela === "conversa") return
  document.body.dataset.tela = "conversa"
  if (compacto()) history.pushState({ tela: "conversa" }, "")
}

function irParaLista() {
  document.body.dataset.tela = "lista"
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

function adicionarMensagem(classe, html, ts) {
  const div = document.createElement("div")
  const marca = ts ? hora(ts) : ""
  div.className = marca ? `msg ${classe} com-hora` : `msg ${classe}`
  div.innerHTML = marca ? `${html}<time class="hora">${marca}</time>` : html
  el.mensagens.appendChild(div)
  el.mensagens.scrollTop = el.mensagens.scrollHeight
  return div
}

function mensagemDoUsuario(texto, citacao, ts) {
  const cabeca = citacao ? blocoCitacao(citacao) : ""
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
  selecionarBotao(`[data-perfil="${perfil}"]`)
  definirCabecalho(perfil, `Nova conversa com ${NOMES[perfil]}`)
  limparTela()
  adicionarMensagem("aviso", `Você está falando com ${NOMES[perfil]}. A conversa é criada na primeira mensagem.`)
  el.entrada.placeholder = `Mensagem para ${NOMES[perfil]}…`
  irParaConversa()
  focarEntrada()
}

function abrirBoard() {
  estado.modo = "board"
  estado.perfil = null
  estado.conversaId = null
  selecionarBotao("#botao-board")
  definirCabecalho("board", "Board — deliberação em conselho")
  limparTela()
  adicionarMensagem(
    "aviso",
    "Apresente a pauta. Os quatro perfis vão deliberar em paralelo e você recebe a síntese; a ata completa fica em board/minutes/.",
  )
  el.entrada.placeholder = "Pauta para o board…"
  irParaConversa()
  focarEntrada()
}

function abrirDecisoes() {
  estado.modo = "decisoes"
  selecionarBotao("#botao-decisoes")
  definirCabecalho("decisoes", "Decisões registradas")
  limparTela()
  irParaConversa()
  enviar({ tipo: "decisoes" })
}

// ── envio ──────────────────────────────────────────────────────────

function submeter() {
  const texto = el.entrada.value.trim()
  if (!texto || estado.respostaEmCurso) return
  el.entrada.value = ""
  ajustarEntrada()

  if (estado.modo === "board") {
    mensagemDoUsuario(texto, null, new Date())
    estado.respostaEmCurso = "board"
    el.enviar.disabled = true
    adicionarMensagem("aviso", "Board convocado — colhendo pareceres…")
    enviar({ tipo: "board", pauta: texto })
    return
  }

  if (estado.modo === "chat" && estado.perfil) {
    const citacao = estado.citacao ?? undefined
    mensagemDoUsuario(texto, citacao, new Date())
    limparCitacao()
    estado.respostaEmCurso = "chat"
    el.enviar.disabled = true
    if (estado.conversaId) {
      enviar({ tipo: "mensagem", conversaId: estado.conversaId, texto, citacao, modelo: el.modelo.value })
    } else {
      enviar({ tipo: "nova", perfil: estado.perfil, texto, citacao, modelo: el.modelo.value })
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
    case "conversas": {
      el.listaConversas.innerHTML = ""
      for (const meta of msg.lista) {
        const li = document.createElement("li")
        li.innerHTML = `<span class="ponto" style="background: var(--${meta.perfil})"></span>${escapar(meta.titulo)}`
        li.onclick = () => {
          irParaConversa()
          enviar({ tipo: "abrir", conversaId: meta.id })
        }
        li.dataset.id = meta.id
        el.listaConversas.appendChild(li)
      }
      break
    }
    case "criada": {
      estado.conversaId = msg.meta.id
      definirCabecalho(msg.meta.perfil, `${NOMES[msg.meta.perfil]} — ${msg.meta.titulo}`)
      enviar({ tipo: "listar" })
      break
    }
    case "conversa": {
      estado.modo = "chat"
      estado.perfil = msg.meta.perfil
      estado.conversaId = msg.meta.id
      selecionarBotao(`[data-perfil="${msg.meta.perfil}"]`)
      definirCabecalho(msg.meta.perfil, `${NOMES[msg.meta.perfil]} — ${msg.meta.titulo}`)
      el.modelo.value = msg.meta.modelo ?? ""
      irParaConversa()
      limparTela()
      for (const m of msg.mensagens) {
        if (m.role === "user") {
          mensagemDoUsuario(m.texto, m.citacao, m.ts)
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
      estado.respostaEmCurso = null
      el.enviar.disabled = false
      break
    }
    case "board-status": {
      adicionarMensagem("aviso", msg.texto)
      break
    }
    case "board-sintese": {
      mensagemDoPerfil("board", msg.texto)
      adicionarMensagem("aviso", `Ata completa: ${msg.ata}`)
      estado.respostaEmCurso = null
      el.enviar.disabled = false
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
    case "erro": {
      adicionarMensagem("erro", escapar(msg.mensagem))
      encerrarStreaming()
      estado.respostaEmCurso = null
      el.enviar.disabled = false
      break
    }
  }
}

// ── ligação da UI ──────────────────────────────────────────────────

document.querySelectorAll(".perfil").forEach((b) => {
  b.onclick = () => abrirPerfil(b.dataset.perfil)
})
document.getElementById("botao-board").onclick = abrirBoard
document.getElementById("botao-decisoes").onclick = abrirDecisoes
document.getElementById("citacao-fechar").onclick = limparCitacao
el.voltar.onclick = irParaLista

document.body.dataset.tela = "lista"
history.replaceState({ tela: "lista" }, "")
window.addEventListener("popstate", () => {
  document.body.dataset.tela = history.state?.tela === "conversa" ? "conversa" : "lista"
})

// ── menu do balão: toque longo no celular, clique direito no desktop ──

const menu = document.getElementById("menu-balao")
let balaoDoMenu = null
let toqueLongo = null
let inicioToque = null

const textoDoBalao = (balao) => balao?.querySelector(".corpo")?.textContent.trim() ?? ""

function abrirMenu(balao, x, y) {
  if (!textoDoBalao(balao)) return
  fecharMenu()
  balaoDoMenu = balao
  balao.classList.add("pressionado")
  menu.querySelector('[data-acao="responder"]').hidden = estado.modo !== "chat"
  menu.hidden = false
  const limite = (v, tamanho, total) => Math.min(Math.max(8, v), total - tamanho - 8)
  menu.style.left = `${limite(x, menu.offsetWidth, window.innerWidth)}px`
  menu.style.top = `${limite(y, menu.offsetHeight, window.innerHeight)}px`
}

function fecharMenu() {
  balaoDoMenu?.classList.remove("pressionado")
  balaoDoMenu = null
  menu.hidden = true
}

function cancelarToque() {
  clearTimeout(toqueLongo)
  toqueLongo = null
  inicioToque = null
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

const balaoAlvo = (ev) => ev.target.closest(".msg.perfil-msg:not(.documento)")

el.mensagens.addEventListener("pointerdown", (ev) => {
  if (ev.pointerType === "mouse" && ev.button !== 0) return
  const balao = balaoAlvo(ev)
  if (!balao) return
  inicioToque = { x: ev.clientX, y: ev.clientY }
  toqueLongo = setTimeout(() => {
    toqueLongo = null
    abrirMenu(balao, ev.clientX, ev.clientY)
  }, 450)
})

el.mensagens.addEventListener("pointermove", (ev) => {
  if (!toqueLongo || !inicioToque) return
  if (Math.hypot(ev.clientX - inicioToque.x, ev.clientY - inicioToque.y) > 10) cancelarToque()
})

el.mensagens.addEventListener("pointerup", cancelarToque)
el.mensagens.addEventListener("pointercancel", cancelarToque)
el.mensagens.addEventListener("scroll", () => {
  cancelarToque()
  fecharMenu()
})

el.mensagens.addEventListener("contextmenu", (ev) => {
  const balao = balaoAlvo(ev)
  if (!balao) return
  ev.preventDefault()
  abrirMenu(balao, ev.clientX, ev.clientY)
})

menu.addEventListener("click", (ev) => {
  const acao = ev.target.closest("button")?.dataset.acao
  const texto = textoDoBalao(balaoDoMenu)
  fecharMenu()
  if (!texto) return
  if (acao === "responder") definirCitacao(texto)
  if (acao === "copiar") copiar(texto)
})

document.addEventListener(
  "pointerdown",
  (ev) => {
    if (!menu.hidden && !menu.contains(ev.target)) fecharMenu()
  },
  true,
)
document.addEventListener("keydown", (ev) => {
  if (ev.key === "Escape") fecharMenu()
})

el.enviar.onclick = submeter

// O scrollHeight de uma caixa border-box não conta a borda; sem os 2px o campo
// cresce um pixel a cada tecla.
function ajustarEntrada() {
  el.entrada.style.height = "auto"
  el.entrada.style.height = `${el.entrada.scrollHeight + 2}px`
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
