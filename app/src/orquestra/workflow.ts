import { slugValido, type Equipe, type Etapa } from "./equipe"
import { membrosDoBoard } from "./politica"

export type TipoDeValor = "texto" | "numero" | "booleano" | { escolha: string[] }
export type Saidas = Record<string, TipoDeValor>
export type Valor = string | number | boolean
export type OpDeRegra = "igual" | "diferente" | "contem" | "maior" | "menor" | "vazio" | "preenchido"

export interface Regra {
  campo: string
  op: OpDeRegra
  valor?: Valor
}

interface Base {
  id: string
  titulo?: string
  prazo?: string
}

export type No =
  | (Base & { tipo: "executar"; posicao: string; instrucao: string; criterio?: string; saidas?: Saidas })
  | (Base & { tipo: "revisar"; de: string; por: { posicao: string } | { board: true } })
  | (Base & { tipo: "aprovar"; de: string; por: { posicao: string } | { ueslei: true } })
  | (Base & { tipo: "decisao_humana"; pergunta: string; opcoes: string[] })
  | (Base & { tipo: "condicao"; regras: (Regra & { saida: string })[] })
  | (Base & { tipo: "paralelo" })
  | (Base & { tipo: "juncao" })
  | (Base & { tipo: "laco"; maxVoltas: number; enquanto: Regra })
  | (Base & { tipo: "espera"; duracao?: string; ate?: string; sinal?: string })
  | (Base & { tipo: "board"; pauta: string; opcoes?: string[] })
  | (Base & { tipo: "fim"; resultado?: string })

export type TipoDeNo = No["tipo"]

export interface Aresta {
  de: string
  para: string
  quando?: string
}

export interface Workflow {
  id: string
  nome: string
  versao: number
  entrada: Saidas
  inicio: string
  nos: No[]
  arestas: Aresta[]
  layout: Record<string, { x: number; y: number }>
}

export const TIPOS_DE_NO: readonly TipoDeNo[] = [
  "executar",
  "revisar",
  "aprovar",
  "decisao_humana",
  "condicao",
  "paralelo",
  "juncao",
  "laco",
  "espera",
  "board",
  "fim",
]
export const OPS: readonly OpDeRegra[] = ["igual", "diferente", "contem", "maior", "menor", "vazio", "preenchido"]
export const MAX_VOLTAS_DO_LACO = 20
export const QUANDO_SENAO = "senao"

const DURACAO = /^(\d{1,4})(m|h|d)$/
const HORARIO = /^([01]\d|2[0-3]):[0-5]\d$/
const REFERENCIA = /\{\{\s*([a-z][a-z0-9-]*)\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/g

export function duracaoEmMs(texto: string): number | null {
  const m = DURACAO.exec(texto)
  if (!m) return null
  const n = Number(m[1])
  return n * (m[2] === "m" ? 60_000 : m[2] === "h" ? 3_600_000 : 86_400_000)
}

export function proximoHorarioDoDia(hhmm: string, depois: Date): Date {
  const [h, min] = hhmm.split(":").map(Number)
  const d = new Date(depois)
  d.setHours(h ?? 0, min ?? 0, 0, 0)
  if (d.getTime() <= depois.getTime()) d.setDate(d.getDate() + 1)
  return d
}

export function nomeDoTipo(tipo: TipoDeValor): string {
  return typeof tipo === "string" ? tipo : `uma de: ${tipo.escolha.join(", ")}`
}

export function saidasDoNo(no: No): Saidas {
  switch (no.tipo) {
    case "executar":
      return { devolutiva: "texto", ...(no.saidas ?? {}) }
    case "revisar":
    case "aprovar":
      return { parecer: "texto" }
    case "decisao_humana":
      return { opcao: { escolha: no.opcoes }, comentario: "texto" }
    case "board":
      return { sintese: "texto", decisao: no.opcoes?.length ? { escolha: no.opcoes } : "texto" }
    case "laco":
      return { voltas: "numero" }
    case "espera":
      return { motivo: { escolha: ["pronto", "prazo"] } }
    default:
      return {}
  }
}

export function quandosDoNo(no: No): (string | undefined)[] | "dois-ou-mais" {
  switch (no.tipo) {
    case "executar":
    case "juncao":
      return [undefined]
    case "revisar":
    case "aprovar":
      return ["aprovado"]
    case "decisao_humana":
      return no.opcoes
    case "condicao":
      return [...new Set(no.regras.map((r) => r.saida)), QUANDO_SENAO]
    case "paralelo":
      return "dois-ou-mais"
    case "laco":
      return ["repetir", "sair"]
    case "espera":
      return no.prazo ? ["pronto", "prazo"] : ["pronto"]
    case "board":
      return no.opcoes?.length ? no.opcoes : [undefined]
    case "fim":
      return []
  }
}

export function textosDoNo(no: No): string[] {
  switch (no.tipo) {
    case "executar":
      return [no.instrucao, no.criterio ?? ""]
    case "decisao_humana":
      return [no.pergunta]
    case "board":
      return [no.pauta]
    default:
      return []
  }
}

export function regrasDoNo(no: No): Regra[] {
  if (no.tipo === "condicao") return no.regras
  if (no.tipo === "laco") return [no.enquanto]
  return []
}

export function referencias(texto: string): { no: string; campo: string }[] {
  return [...texto.matchAll(REFERENCIA)].map((m) => ({ no: m[1]!, campo: m[2]! }))
}

export function lerCampo(campo: string): { no: string; campo: string } | null {
  const m = /^([a-z][a-z0-9-]*)\.([a-zA-Z_][a-zA-Z0-9_]*)$/.exec(campo.trim())
  return m ? { no: m[1]!, campo: m[2]! } : null
}

// ── leitura ────────────────────────────────────────────────────────

function objeto(bruto: unknown): Record<string, unknown> {
  return bruto && typeof bruto === "object" && !Array.isArray(bruto) ? (bruto as Record<string, unknown>) : {}
}

function texto(v: unknown): string {
  return typeof v === "string" ? v.trim() : ""
}

function lerTipo(bruto: unknown, onde: string): TipoDeValor {
  if (bruto === "texto" || bruto === "numero" || bruto === "booleano") return bruto
  const e = objeto(bruto).escolha
  if (Array.isArray(e) && e.length >= 2 && e.every((x) => typeof x === "string" && x.trim())) {
    return { escolha: [...new Set(e.map((x: string) => x.trim()))] }
  }
  throw new Error(`${onde}: tipo inválido (use texto, numero, booleano ou { "escolha": [...] } com 2 ou mais opções)`)
}

function lerSaidas(bruto: unknown, onde: string): Saidas {
  const saidas: Saidas = {}
  for (const [nome, tipo] of Object.entries(objeto(bruto))) {
    if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(nome)) throw new Error(`${onde}: nome de campo inválido (${nome})`)
    saidas[nome] = lerTipo(tipo, `${onde}.${nome}`)
  }
  return saidas
}

function lerRegra(bruto: unknown, onde: string): Regra {
  const r = objeto(bruto)
  const op = r.op as OpDeRegra
  if (!OPS.includes(op)) throw new Error(`${onde}: op inválida (${String(r.op)})`)
  const campo = texto(r.campo)
  if (!lerCampo(campo)) throw new Error(`${onde}: campo inválido (${campo || "vazio"}); use no.saida ou entrada.campo`)
  const regra: Regra = { campo, op }
  if (op !== "vazio" && op !== "preenchido") {
    if (!["string", "number", "boolean"].includes(typeof r.valor)) throw new Error(`${onde}: a op ${op} precisa de valor`)
    regra.valor = r.valor as Valor
  }
  return regra
}

function lerOpcoes(bruto: unknown, onde: string): string[] {
  if (!Array.isArray(bruto) || bruto.length < 2) throw new Error(`${onde}: precisa de 2 ou mais opções`)
  const opcoes = [...new Set(bruto.map((o) => texto(o)).filter(Boolean))]
  if (opcoes.length !== bruto.length) throw new Error(`${onde}: opções vazias ou repetidas`)
  return opcoes
}

function lerNo(bruto: unknown): No {
  const n = objeto(bruto)
  if (!slugValido(n.id)) throw new Error(`caixa: id inválido (${String(n.id)})`)
  const onde = `caixa ${n.id}`
  const tipo = n.tipo as TipoDeNo
  if (!TIPOS_DE_NO.includes(tipo)) throw new Error(`${onde}: tipo desconhecido (${String(n.tipo)})`)
  const base: Base = { id: n.id }
  if (texto(n.titulo)) base.titulo = texto(n.titulo)
  if (n.prazo !== undefined) {
    if (duracaoEmMs(texto(n.prazo)) === null) throw new Error(`${onde}: prazo inválido (use 30m, 2h ou 1d)`)
    base.prazo = texto(n.prazo)
  }
  switch (tipo) {
    case "executar": {
      const instrucao = texto(n.instrucao)
      if (!instrucao) throw new Error(`${onde}: instrução obrigatória`)
      const no: No = { ...base, tipo, posicao: texto(n.posicao), instrucao }
      if (texto(n.criterio)) no.criterio = texto(n.criterio)
      if (n.saidas !== undefined) {
        const saidas = lerSaidas(n.saidas, `${onde}: saídas`)
        if ("devolutiva" in saidas) throw new Error(`${onde}: "devolutiva" é reservada`)
        if (Object.keys(saidas).length) no.saidas = saidas
      }
      return no
    }
    case "revisar":
    case "aprovar": {
      const por = objeto(n.por)
      const de = texto(n.de)
      if (typeof por.posicao === "string" && por.posicao.trim()) return { ...base, tipo, de, por: { posicao: por.posicao.trim() } }
      if (tipo === "revisar" && por.board === true) return { ...base, tipo, de, por: { board: true } }
      if (tipo === "aprovar" && por.ueslei === true) return { ...base, tipo, de, por: { ueslei: true } }
      throw new Error(`${onde}: quem decide é inválido`)
    }
    case "decisao_humana": {
      const pergunta = texto(n.pergunta)
      if (!pergunta) throw new Error(`${onde}: pergunta obrigatória`)
      return { ...base, tipo, pergunta, opcoes: lerOpcoes(n.opcoes, onde) }
    }
    case "condicao": {
      if (!Array.isArray(n.regras) || !n.regras.length) throw new Error(`${onde}: precisa de pelo menos uma regra`)
      const regras = n.regras.map((r, i) => {
        const saida = texto(objeto(r).saida)
        if (!saida || saida === QUANDO_SENAO) throw new Error(`${onde}: regra ${i + 1}: saída obrigatória e diferente de "senao"`)
        return { ...lerRegra(r, `${onde}: regra ${i + 1}`), saida }
      })
      return { ...base, tipo, regras }
    }
    case "laco": {
      const max = n.maxVoltas
      if (typeof max !== "number" || !Number.isInteger(max) || max < 1 || max > MAX_VOLTAS_DO_LACO) {
        throw new Error(`${onde}: maxVoltas obrigatório, de 1 a ${MAX_VOLTAS_DO_LACO}`)
      }
      return { ...base, tipo, maxVoltas: max, enquanto: lerRegra(n.enquanto, `${onde}: enquanto`) }
    }
    case "espera": {
      const no: No = { ...base, tipo }
      const formas = [n.duracao, n.ate, n.sinal].filter((v) => v !== undefined)
      if (formas.length !== 1) throw new Error(`${onde}: use exatamente um de duracao, ate e sinal`)
      if (n.duracao !== undefined) {
        if (duracaoEmMs(texto(n.duracao)) === null) throw new Error(`${onde}: duração inválida (use 30m, 2h ou 1d)`)
        no.duracao = texto(n.duracao)
      }
      if (n.ate !== undefined) {
        if (!HORARIO.test(texto(n.ate))) throw new Error(`${onde}: horário inválido (use HH:MM)`)
        no.ate = texto(n.ate)
      }
      if (n.sinal !== undefined) {
        if (!texto(n.sinal)) throw new Error(`${onde}: sinal vazio`)
        no.sinal = texto(n.sinal)
      }
      return no
    }
    case "board": {
      const pauta = texto(n.pauta)
      if (!pauta) throw new Error(`${onde}: pauta obrigatória`)
      const no: No = { ...base, tipo, pauta }
      if (n.opcoes !== undefined) no.opcoes = lerOpcoes(n.opcoes, onde)
      return no
    }
    case "fim": {
      const no: No = { ...base, tipo }
      if (texto(n.resultado)) no.resultado = texto(n.resultado)
      return no
    }
    default:
      return { ...base, tipo } as No
  }
}

// ── validação ──────────────────────────────────────────────────────

function alcancaveis(de: string, saida: Map<string, string[]>, evitar?: string): Set<string> {
  const vistos = new Set<string>()
  const pilha = [de]
  while (pilha.length) {
    const atual = pilha.pop()!
    if (vistos.has(atual) || atual === evitar) continue
    vistos.add(atual)
    pilha.push(...(saida.get(atual) ?? []))
  }
  return vistos
}

function temCiclo(ids: string[], saida: Map<string, string[]>): boolean {
  const estado = new Map<string, 1 | 2>()
  const visitar = (id: string): boolean => {
    if (estado.get(id) === 1) return true
    if (estado.get(id) === 2) return false
    estado.set(id, 1)
    for (const prox of saida.get(id) ?? []) if (visitar(prox)) return true
    estado.set(id, 2)
    return false
  }
  return ids.some((id) => visitar(id))
}

function tipoDoCampo(campo: string, nos: Map<string, No>, entrada: Saidas): TipoDeValor | undefined {
  const ref = lerCampo(campo)
  if (!ref) return undefined
  if (ref.no === "entrada") return entrada[ref.campo]
  const no = nos.get(ref.no)
  return no ? saidasDoNo(no)[ref.campo] : undefined
}

export function corrente(workflow: Pick<Workflow, "nos" | "arestas">, executar: string): No[] {
  const nos = new Map(workflow.nos.map((n) => [n.id, n]))
  const cadeia: No[] = []
  let atual = executar
  for (let i = 0; i < workflow.nos.length; i++) {
    const aresta = workflow.arestas.find((a) => a.de === atual)
    const prox = aresta ? nos.get(aresta.para) : undefined
    if (!prox || (prox.tipo !== "revisar" && prox.tipo !== "aprovar") || prox.de !== executar) break
    cadeia.push(prox)
    atual = prox.id
  }
  return cadeia
}

export function etapasDaCorrente(cadeia: No[]): Etapa[] {
  return cadeia.flatMap((n): Etapa[] =>
    n.tipo === "revisar" ? [{ tipo: "revisao", por: n.por }] : n.tipo === "aprovar" ? [{ tipo: "aprovacao", por: n.por }] : [],
  )
}

export function validarWorkflow(bruto: unknown, equipe: Equipe): Workflow {
  const w = objeto(bruto)
  if (!slugValido(w.id)) throw new Error(`workflow: id inválido (${String(w.id)})`)
  const onde = `workflow ${w.id}`
  const erros: string[] = []
  const nome = texto(w.nome)
  if (!nome) erros.push(`${onde}: nome obrigatório`)
  let entrada: Saidas = {}
  try {
    entrada = lerSaidas(w.entrada, `${onde}: entrada`)
  } catch (erro) {
    erros.push((erro as Error).message)
  }
  const nos: No[] = []
  for (const bruta of Array.isArray(w.nos) ? w.nos : []) {
    try {
      nos.push(lerNo(bruta))
    } catch (erro) {
      erros.push(`${onde}: ${(erro as Error).message}`)
    }
  }
  if (!Array.isArray(w.nos) || !w.nos.length) erros.push(`${onde}: precisa de caixas`)
  const porId = new Map<string, No>()
  for (const n of nos) {
    if (porId.has(n.id) || n.id === "entrada") erros.push(`${onde}: caixa ${n.id}: id repetido ou reservado`)
    porId.set(n.id, n)
  }
  const arestas: Aresta[] = (Array.isArray(w.arestas) ? w.arestas : []).map((a) => {
    const o = objeto(a)
    const aresta: Aresta = { de: texto(o.de), para: texto(o.para) }
    if (texto(o.quando)) aresta.quando = texto(o.quando)
    return aresta
  })
  const inicio = texto(w.inicio)
  if (!porId.has(inicio)) erros.push(`${onde}: início inexistente (${inicio || "vazio"})`)
  for (const a of arestas) {
    if (!porId.has(a.de)) erros.push(`${onde}: ligação de caixa inexistente (${a.de})`)
    if (!porId.has(a.para)) erros.push(`${onde}: ligação para caixa inexistente (${a.para})`)
  }
  const saida = new Map<string, string[]>()
  const entram = new Map<string, number>()
  for (const a of arestas) {
    saida.set(a.de, [...(saida.get(a.de) ?? []), a.para])
    entram.set(a.para, (entram.get(a.para) ?? 0) + 1)
  }

  for (const n of nos) {
    const aqui = `${onde}: caixa ${n.id}`
    const minhas = arestas.filter((a) => a.de === n.id)
    const esperadas = quandosDoNo(n)
    if (esperadas === "dois-ou-mais") {
      if (minhas.length < 2) erros.push(`${aqui}: o paralelo precisa de 2 ou mais ligações`)
      if (minhas.some((a) => a.quando)) erros.push(`${aqui}: ligações do paralelo não têm "quando"`)
    } else {
      const usadas = minhas.map((a) => a.quando)
      for (const q of usadas) {
        if (!esperadas.includes(q)) erros.push(`${aqui}: ligação com "quando" inválido (${q ?? "vazio"})`)
      }
      for (const q of esperadas) {
        const quantas = usadas.filter((u) => u === q).length
        if (quantas === 0) erros.push(`${aqui}: falta a ligação ${q ? `"${q}"` : "de saída"}`)
        if (quantas > 1) erros.push(`${aqui}: ligação ${q ? `"${q}"` : "de saída"} repetida`)
      }
    }
    if (n.tipo === "juncao" && (entram.get(n.id) ?? 0) < 2) erros.push(`${aqui}: a junção precisa de 2 ou mais ligações entrando`)
    if (n.tipo === "executar") {
      const posicao = equipe.posicoes.find((p) => p.id === n.posicao)
      if (!posicao) erros.push(`${aqui}: posição inexistente (${n.posicao || "vazio"})`)
    }
    if (n.tipo === "revisar" || n.tipo === "aprovar") {
      const de = porId.get(n.de)
      if (!de || de.tipo !== "executar") {
        erros.push(`${aqui}: "de" precisa ser uma caixa executar (${n.de || "vazio"})`)
      } else {
        if (!corrente({ nos, arestas }, de.id).some((c) => c.id === n.id)) {
          erros.push(`${aqui}: precisa vir logo depois de ${de.id} (ou de outra revisão dele)`)
        }
        const executora = equipe.posicoes.find((p) => p.id === de.posicao)?.persona ?? null
        if ("posicao" in n.por) {
          const ref = n.por.posicao
          const alvo = equipe.posicoes.find((p) => p.id === ref)
          if (!alvo) erros.push(`${aqui}: posição inexistente (${ref})`)
          else if (alvo.persona !== null && alvo.persona === executora) erros.push(`${aqui}: ${alvo.persona} revisaria o próprio trabalho`)
        }
        if ("board" in n.por && !membrosDoBoard(equipe, executora).length) erros.push(`${aqui}: o board da equipe não tem membros`)
      }
    }
    if (n.tipo === "board" && !membrosDoBoard(equipe, null).length) erros.push(`${aqui}: o board da equipe não tem membros`)
  }
  for (const n of nos) {
    if (n.tipo !== "executar") continue
    const cadeia = corrente({ nos, arestas }, n.id)
    const aprovacoes = cadeia.filter((c) => c.tipo === "aprovar").length
    if (aprovacoes > 1) erros.push(`${onde}: caixa ${n.id}: só pode haver uma aprovação`)
    else if (aprovacoes === 1 && cadeia.at(-1)!.tipo !== "aprovar") erros.push(`${onde}: caixa ${n.id}: a aprovação precisa ser a última`)
  }

  if (porId.has(inicio)) {
    const vistos = alcancaveis(inicio, saida)
    for (const n of nos) if (!vistos.has(n.id)) erros.push(`${onde}: caixa ${n.id}: não é alcançável a partir do início`)
  }
  const semLaco = new Map([...saida].filter(([de]) => porId.get(de)?.tipo !== "laco"))
  if (temCiclo(nos.map((n) => n.id), semLaco)) erros.push(`${onde}: há um ciclo que não passa por um laço`)
  for (const laco of nos.filter((n) => n.tipo === "laco")) {
    const repetir = arestas.find((a) => a.de === laco.id && a.quando === "repetir")
    if (!repetir) continue
    const corpo = [...alcancaveis(repetir.para, saida, laco.id)].filter((id) => alcancaveis(id, saida).has(laco.id))
    for (const id of corpo) {
      const tipo = porId.get(id)?.tipo
      if (tipo === "paralelo" || tipo === "juncao") erros.push(`${onde}: caixa ${id}: paralelo e junção não podem ficar dentro do laço ${laco.id}`)
    }
  }

  for (const n of nos) {
    const aqui = `${onde}: caixa ${n.id}`
    const antes = (ref: string) => ref !== n.id && alcancaveis(ref, saida).has(n.id)
    const conferir = (ref: { no: string; campo: string }, contexto: string) => {
      if (ref.no === "entrada") {
        if (!(ref.campo in entrada)) erros.push(`${aqui}: ${contexto} usa entrada.${ref.campo}, que não existe`)
        return
      }
      const outro = porId.get(ref.no)
      if (!outro) erros.push(`${aqui}: ${contexto} usa a caixa inexistente ${ref.no}`)
      else if (!(ref.campo in saidasDoNo(outro))) erros.push(`${aqui}: ${contexto} usa ${ref.no}.${ref.campo}, que não é saída de ${ref.no}`)
      else if (!antes(ref.no)) erros.push(`${aqui}: ${contexto} usa ${ref.no}, que não vem antes`)
    }
    for (const t of textosDoNo(n)) for (const ref of referencias(t)) conferir(ref, `o texto`)
    for (const regra of regrasDoNo(n)) {
      const ref = lerCampo(regra.campo)!
      conferir(ref, `a regra`)
      const tipo = tipoDoCampo(regra.campo, porId, entrada)
      if (!tipo) continue
      if ((regra.op === "maior" || regra.op === "menor") && tipo !== "numero") erros.push(`${aqui}: ${regra.op} só vale para número`)
      if (tipo === "numero" && regra.valor !== undefined && typeof regra.valor !== "number") erros.push(`${aqui}: o valor precisa ser número`)
      if (tipo === "booleano" && regra.valor !== undefined && typeof regra.valor !== "boolean") erros.push(`${aqui}: o valor precisa ser sim ou não`)
      if (typeof tipo === "object" && regra.op === "igual" && !tipo.escolha.includes(String(regra.valor))) {
        erros.push(`${aqui}: ${String(regra.valor)} não é uma das escolhas de ${regra.campo}`)
      }
    }
  }

  if (erros.length) throw new Error(erros.join("; "))
  const versao = typeof w.versao === "number" && Number.isInteger(w.versao) && w.versao > 0 ? w.versao : 1
  const layout: Workflow["layout"] = {}
  for (const [id, ponto] of Object.entries(objeto(w.layout))) {
    const xy = objeto(ponto)
    if (porId.has(id) && typeof xy.x === "number" && typeof xy.y === "number") layout[id] = { x: xy.x, y: xy.y }
  }
  return { id: w.id, nome, versao, entrada, inicio, nos, arestas, layout }
}

// ── valores ────────────────────────────────────────────────────────

export type Contexto = Record<string, Record<string, Valor>>

export function formatarValor(v: Valor | undefined): string {
  if (v === undefined) return ""
  if (typeof v === "boolean") return v ? "sim" : "não"
  return String(v)
}

export function interpolar(texto: string, contexto: Contexto): string {
  return texto.replace(REFERENCIA, (_, no: string, campo: string) => formatarValor(contexto[no]?.[campo]))
}

export function valorDoCampo(campo: string, contexto: Contexto): Valor | undefined {
  const ref = lerCampo(campo)
  return ref ? contexto[ref.no]?.[ref.campo] : undefined
}

export function avaliar(regra: Regra, contexto: Contexto): boolean {
  const v = valorDoCampo(regra.campo, contexto)
  const vazio = v === undefined || v === ""
  switch (regra.op) {
    case "vazio":
      return vazio
    case "preenchido":
      return !vazio
    case "igual":
      return !vazio && String(v) === String(regra.valor)
    case "diferente":
      return vazio || String(v) !== String(regra.valor)
    case "contem":
      return !vazio && String(v).toLowerCase().includes(String(regra.valor).toLowerCase())
    case "maior":
      return typeof v === "number" && v > Number(regra.valor)
    case "menor":
      return typeof v === "number" && v < Number(regra.valor)
  }
}

export function validarValores(saidas: Saidas, bruto: unknown): Record<string, Valor> {
  const dados = objeto(bruto)
  const valores: Record<string, Valor> = {}
  const erros: string[] = []
  for (const [campo, tipo] of Object.entries(saidas)) {
    const v = dados[campo]
    if (tipo === "texto" && typeof v === "string") valores[campo] = v.trim().slice(0, 20_000)
    else if (tipo === "numero" && typeof v === "number" && Number.isFinite(v)) valores[campo] = v
    else if (tipo === "booleano" && typeof v === "boolean") valores[campo] = v
    else if (typeof tipo === "object" && typeof v === "string" && tipo.escolha.includes(v)) valores[campo] = v
    else erros.push(`${campo} precisa ser ${nomeDoTipo(tipo)}`)
  }
  if (erros.length) throw new Error(erros.join("; "))
  return valores
}
