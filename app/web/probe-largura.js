"use strict"

// TEMPORÁRIO — TickTask #317, item 5: aponta quem cria o scroll horizontal no
// celular. Este arquivo sai inteiro (e a tag no index.html) junto com o conserto.

;(() => {
  const identificar = (nodo) => {
    if (nodo === document.documentElement) return "html"
    if (nodo === document.body) return "body"
    const id = nodo.id ? `#${nodo.id}` : ""
    const classe = nodo.classList.length ? `.${[...nodo.classList].join(".")}` : ""
    return `${nodo.tagName.toLowerCase()}${id}${classe}`.slice(0, 44)
  }

  const painel = document.createElement("pre")
  painel.style.cssText =
    "position:fixed;left:0;right:0;top:0;z-index:9999;margin:0;padding:8px 10px;" +
    "max-height:55vh;overflow:auto;background:#12233b;color:#cfe3ff;" +
    "font:11px/1.45 ui-monospace,monospace;white-space:pre-wrap"
  painel.onclick = () => medir()

  function medir() {
    const raiz = document.documentElement
    const vv = window.visualViewport
    const mobile = window.matchMedia("(max-width: 899px)").matches
    const grosso = window.matchMedia("(hover: none) and (pointer: coarse)").matches
    const fab = document.getElementById("nova-conversa")

    const cab = [
      `layout ${raiz.clientWidth} · innerWidth ${window.innerWidth} · screen ${screen.width}`,
      vv ? `visual ${Math.round(vv.width)} · escala ${vv.scale.toFixed(2)} · offsetLeft ${Math.round(vv.offsetLeft)}` : "sem visualViewport",
      `dpr ${window.devicePixelRatio} · media899 ${mobile ? "SIM" : "NAO"} · toque ${grosso ? "SIM" : "NAO"}`,
      `fab ${fab ? getComputedStyle(fab).display : "ausente"} · tela ${document.body.dataset.tela ?? "?"}`,
      `html ${raiz.scrollWidth}/${raiz.clientWidth} overflow-x ${getComputedStyle(raiz).overflowX}`,
      `body ${document.body.scrollWidth}/${document.body.clientWidth} overflow-x ${getComputedStyle(document.body).overflowX}`,
    ]

    const caixa = (sel) => {
      const nodo = document.querySelector(sel)
      if (!nodo) return `${sel}: ausente`
      const e = getComputedStyle(nodo)
      const r = nodo.getBoundingClientRect()
      return (
        `${sel} ${e.display}/${e.position} ` +
        `x${Math.round(r.left)} y${Math.round(r.top)} ${Math.round(r.width)}x${Math.round(r.height)} ` +
        `t:${e.transform === "none" ? "-" : e.transform.slice(0, 22)}`
      )
    }
    const geo = [
      `body ${getComputedStyle(document.body).display} h${document.body.clientHeight}/${document.body.scrollHeight} ` +
        `--altura-app ${getComputedStyle(raiz).getPropertyValue("--altura-app").trim()}`,
      `html h${raiz.clientHeight}/${raiz.scrollHeight}`,
      caixa("#lateral"),
      caixa("#principal"),
      caixa("#perfis"),
      caixa("#conversas"),
      caixa("#mensagens"),
    ]

    // Só interessa quem de fato rola: overflow-x hidden com ellipsis tem
    // excedente e não é culpado de nada.
    const rolaveis = []
    for (const nodo of [raiz, document.body, ...document.querySelectorAll("body *")]) {
      const excedente = nodo.scrollWidth - nodo.clientWidth
      if (excedente <= 1) continue
      const overflowX = getComputedStyle(nodo).overflowX
      const roladoPeloViewport = nodo === raiz || nodo === document.body
      if (!roladoPeloViewport && overflowX !== "auto" && overflowX !== "scroll") continue
      rolaveis.push(`ROLA ${identificar(nodo)} +${excedente}px (${overflowX})`)
    }

    // Quem passa da borda direita da tela, role ou não.
    const limite = raiz.clientWidth
    const passantes = []
    for (const nodo of document.querySelectorAll("body *")) {
      const r = nodo.getBoundingClientRect()
      if (r.width === 0 || r.right <= limite + 1) continue
      passantes.push(`PASSA ${identificar(nodo)} ${Math.round(r.left)}→${Math.round(r.right)}`)
      if (passantes.length >= 6) break
    }

    painel.textContent =
      `${cab.join("\n")}\n${geo.join("\n")}\n` +
      `${rolaveis.length ? rolaveis.join("\n") : "nenhum elemento rola na horizontal"}\n` +
      `${passantes.length ? passantes.join("\n") : "ninguém passa da borda direita"}\n` +
      `(toque para medir de novo)`
  }

  const agendar = () => setTimeout(medir, 350)

  window.addEventListener("load", () => {
    document.body.appendChild(painel)
    agendar()
    new MutationObserver(agendar).observe(document.body, {
      attributes: true,
      attributeFilter: ["data-tela", "data-folha"],
    })
    window.addEventListener("resize", agendar)
  })

  window.medirLargura = medir
})()
