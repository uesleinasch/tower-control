#!/usr/bin/env bun
import { raizDosDados } from "../app/src/caminhos"
import { agregarUso, caminhoDoUso, type Agregado, type RegistroDeUso } from "../app/src/uso"

const indice = process.argv.indexOf("--desde")
const desde = indice > 0 ? process.argv[indice + 1] : undefined
if (indice > 0 && !/^\d{4}-\d{2}-\d{2}$/.test(desde ?? "")) {
  console.error("uso: bun run scripts/relatorio-uso.ts [--desde AAAA-MM-DD]")
  process.exit(1)
}

const arquivo = Bun.file(caminhoDoUso(raizDosDados()))
if (!(await arquivo.exists())) {
  console.log("Nenhum uso registrado ainda.")
  process.exit(0)
}
const registros = (await arquivo.text())
  .split("\n")
  .filter((l) => l.trim())
  .flatMap((l) => {
    try {
      return [JSON.parse(l) as RegistroDeUso]
    } catch {
      return []
    }
  })
  .filter((r) => !desde || r.ts >= desde)

const mil = (n: number) => (n >= 10_000 ? `${Math.round(n / 1000)}k` : n.toLocaleString("pt-BR"))
const linha = (rotulo: string, g: Agregado) =>
  [
    rotulo.padEnd(22),
    String(g.consultas).padStart(6),
    `$${g.custoUSD.toFixed(3)}${g.semCusto ? "*" : " "}`.padStart(10),
    `$${(g.custoUSD / Math.max(1, g.consultas - g.semCusto)).toFixed(4)}`.padStart(9),
    mil(g.entrada).padStart(8),
    mil(g.escritaCache).padStart(8),
    mil(g.leituraCache).padStart(8),
    mil(g.saida).padStart(7),
    `${Math.round(g.acertoCache * 100)}%`.padStart(6),
  ].join(" ")

function tabela(titulo: string, chave: (r: RegistroDeUso) => string): void {
  const grupos = [...agregarUso(registros, chave)].sort((a, b) => b[1].custoUSD - a[1].custoUSD)
  console.log(`\n## ${titulo}\n`)
  console.log(
    ["".padEnd(22), "consul".padStart(6), "custo".padStart(10), "por cons".padStart(9), "entrada".padStart(8), "esc.cache".padStart(8), "leit.cache".padStart(8), "saída".padStart(7), "cache".padStart(6)].join(" "),
  )
  for (const [rotulo, g] of grupos) console.log(linha(rotulo, g))
}

console.log(`${registros.length} consulta(s)${desde ? ` desde ${desde}` : ""} — custo estimado pelo SDK, não é fatura`)
tabela("Por tipo", (r) => r.tipo)
tabela("Por tipo e perfil", (r) => `${r.tipo}:${r.perfil ?? "-"}`)
tabela("Por modelo", (r) => r.modelo ?? "(padrão do SDK)")
if (agregarUso(registros, () => "total").get("total")?.semCusto) {
  console.log("\n* há consultas sem custo conhecido: sessão retomada de antes de o registro existir")
}
