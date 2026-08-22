"use strict"

const NOMES = { poe: "Poe", nati: "Nati", lucas: "Lucas", pami: "Pami", board: "Board" }

const estado = {
  ws: null,
  modo: "chat", // chat | board | decisoes
  perfil: null,
  conversaId: null,
  respostaEmCurso: null,
}

const el = {
  mensagens: document.getElementById("mensagens"),
  entrada: document.getElementById("entrada"),
  enviar: document.getElementById("enviar"),
  titulo: document.getElementById("titulo-conversa"),
  conexao: document.getElementById("estado-conexao"),
  listaConversas: document.getElementById("lista-conversas"),
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

function adicionarMensagem(classe, html) {
  const div = document.createElement("div")
  div.className = `msg ${classe}`
  div.innerHTML = html
  el.mensagens.appendChild(div)
  el.mensagens.scrollTop = el.mensagens.scrollHeight
  return div
}

function mensagemDoPerfil(perfil, texto, comAutor = true) {
  const autor = comAutor
    ? `<span class="autor ${perfil}">${NOMES[perfil] ?? perfil}</span>`
    : ""
  const div = adicionarMensagem(
    "perfil-msg",
    `${autor}<span class="corpo">${formatar(texto)}</span>`,
  )
  return div.querySelector(".corpo")
}

const SEPARADOR_BALAO = /\n\s*-{3,}\s*\n/

function balcoesDoPerfil(perfil, texto) {
  const partes = texto.split(SEPARADOR_BALAO).map((p) => p.trim()).filter(Boolean)
  partes.forEach((parte, i) => mensagemDoPerfil(perfil, parte, i === 0))
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
  el.titulo.textContent = `Nova conversa com ${NOMES[perfil]}`
  limparTela()
  adicionarMensagem("aviso", `Você está falando com ${NOMES[perfil]}. A conversa é criada na primeira mensagem.`)
  el.entrada.placeholder = `Mensagem para ${NOMES[perfil]}…`
  el.entrada.focus()
}

function abrirBoard() {
  estado.modo = "board"
  estado.perfil = null
  estado.conversaId = null
  selecionarBotao("#botao-board")
  el.titulo.textContent = "Board — deliberação em conselho"
  limparTela()
  adicionarMensagem(
    "aviso",
    "Apresente a pauta. Os quatro perfis vão deliberar em paralelo e você recebe a síntese; a ata completa fica em board/minutes/.",
  )
  el.entrada.placeholder = "Pauta para o board…"
  el.entrada.focus()
}

function abrirDecisoes() {
  estado.modo = "decisoes"
  selecionarBotao("#botao-decisoes")
  el.titulo.textContent = "Decisões registradas"
  limparTela()
  enviar({ tipo: "decisoes" })
}

// ── envio ──────────────────────────────────────────────────────────

function submeter() {
  const texto = el.entrada.value.trim()
  if (!texto || estado.respostaEmCurso) return
  el.entrada.value = ""

  if (estado.modo === "board") {
    adicionarMensagem("usuario", escapar(texto))
    estado.respostaEmCurso = "board"
    el.enviar.disabled = true
    adicionarMensagem("aviso", "Board convocado — colhendo pareceres…")
    enviar({ tipo: "board", pauta: texto })
    return
  }

  if (estado.modo === "chat" && estado.perfil) {
    adicionarMensagem("usuario", escapar(texto))
    estado.respostaEmCurso = "chat"
    el.enviar.disabled = true
    if (estado.conversaId) {
      enviar({ tipo: "mensagem", conversaId: estado.conversaId, texto })
    } else {
      enviar({ tipo: "nova", perfil: estado.perfil, texto })
    }
  }
}

// ── recepção ───────────────────────────────────────────────────────

let bolhasStreaming = []
let textoStreaming = ""

function tratar(msg) {
  switch (msg.tipo) {
    case "conversas": {
      el.listaConversas.innerHTML = ""
      for (const meta of msg.lista) {
        const li = document.createElement("li")
        li.innerHTML = `<span class="ponto" style="background: var(--${meta.perfil})"></span>${escapar(meta.titulo)}`
        li.onclick = () => enviar({ tipo: "abrir", conversaId: meta.id })
        li.dataset.id = meta.id
        el.listaConversas.appendChild(li)
      }
      break
    }
    case "criada": {
      estado.conversaId = msg.meta.id
      el.titulo.textContent = `${NOMES[msg.meta.perfil]} — ${msg.meta.titulo}`
      enviar({ tipo: "listar" })
      break
    }
    case "conversa": {
      estado.modo = "chat"
      estado.perfil = msg.meta.perfil
      estado.conversaId = msg.meta.id
      selecionarBotao(`[data-perfil="${msg.meta.perfil}"]`)
      el.titulo.textContent = `${NOMES[msg.meta.perfil]} — ${msg.meta.titulo}`
      limparTela()
      for (const m of msg.mensagens) {
        if (m.role === "user") adicionarMensagem("usuario", escapar(m.texto))
        else balcoesDoPerfil(m.perfil, m.texto)
      }
      break
    }
    case "chunk": {
      if (!bolhasStreaming.length) textoStreaming = ""
      textoStreaming += msg.texto
      const partes = textoStreaming.split(SEPARADOR_BALAO)
      partes.forEach((parte, i) => {
        if (!bolhasStreaming[i]) bolhasStreaming[i] = mensagemDoPerfil(msg.perfil, "", i === 0)
        bolhasStreaming[i].innerHTML = formatar(parte.trim())
      })
      el.mensagens.scrollTop = el.mensagens.scrollHeight
      break
    }
    case "fim": {
      bolhasStreaming = []
      textoStreaming = ""
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
      adicionarMensagem("perfil-msg", formatar(msg.conteudo))
      const voltar = adicionarMensagem("aviso", "← voltar para a lista")
      voltar.style.cursor = "pointer"
      voltar.onclick = () => enviar({ tipo: "decisoes" })
      break
    }
    case "erro": {
      adicionarMensagem("erro", escapar(msg.mensagem))
      bolhasStreaming = []
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

el.enviar.onclick = submeter
el.entrada.addEventListener("keydown", (ev) => {
  if (ev.key === "Enter" && !ev.shiftKey) {
    ev.preventDefault()
    submeter()
  }
})

conectar()
