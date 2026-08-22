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
    "max-height:45vh;overflow:auto;background:#3b0d16;color:#ffd9df;" +
    "font:11px/1.45 ui-monospace,monospace;white-space:pre-wrap;display:none"
  painel.onclick = () => (painel.style.display = "none")

  function medir() {
    const linhas = []
    const todos = [document.documentElement, document.body, ...document.querySelectorAll("body *")]

    for (const nodo of todos) {
      const excedente = nodo.scrollWidth - nodo.clientWidth
      if (excedente <= 1) continue
      const overflowX = getComputedStyle(nodo).overflowX
      linhas.push(`ROLA ${identificar(nodo)} +${excedente}px (overflow-x: ${overflowX})`)
      const borda = nodo.getBoundingClientRect().right
      const passantes = [...nodo.querySelectorAll("*")]
        .filter((f) => f.getBoundingClientRect().right > borda + 1)
        .slice(0, 3)
      for (const f of passantes) {
        const r = f.getBoundingClientRect()
        linhas.push(`   └ ${identificar(f)} vai até ${Math.round(r.right)} (borda ${Math.round(borda)})`)
      }
    }

    if (!linhas.length) {
      painel.style.display = "none"
      return
    }
    const largura = document.documentElement.clientWidth
    painel.textContent =
      `viewport ${largura}px · tela=${document.body.dataset.tela ?? "?"}\n` +
      `${linhas.join("\n")}\n(toque para fechar)`
    painel.style.display = "block"
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
