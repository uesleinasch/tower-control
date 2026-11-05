export interface Cron {
  minutos: ReadonlySet<number>
  horas: ReadonlySet<number>
  dias: ReadonlySet<number>
  meses: ReadonlySet<number>
  semana: ReadonlySet<number>
  diaRestrito: boolean
  semanaRestrita: boolean
}

const CAMPOS = [
  { nome: "minuto", min: 0, max: 59 },
  { nome: "hora", min: 0, max: 23 },
  { nome: "dia do mês", min: 1, max: 31 },
  { nome: "mês", min: 1, max: 12 },
  { nome: "dia da semana", min: 0, max: 7 },
] as const

function inteiro(texto: string, campo: (typeof CAMPOS)[number]): number {
  if (!/^\d+$/.test(texto)) throw new Error(`${campo.nome}: "${texto}" não é número`)
  const n = Number(texto)
  if (n < campo.min || n > campo.max) throw new Error(`${campo.nome}: ${n} fora de ${campo.min}–${campo.max}`)
  return n
}

function lerCampo(texto: string, campo: (typeof CAMPOS)[number]): Set<number> {
  const valores = new Set<number>()
  for (const parte of texto.split(",")) {
    const [faixa, passoTexto] = parte.split("/")
    if (faixa === undefined || faixa === "" || parte.split("/").length > 2) throw new Error(`${campo.nome}: "${parte}" inválido`)
    const passo = passoTexto === undefined ? 1 : inteiro(passoTexto, { ...campo, min: 1, max: campo.max + 1 } as never)
    let de: number
    let ate: number
    if (faixa === "*") {
      de = campo.min
      ate = campo.max
    } else if (faixa.includes("-")) {
      const [a, b] = faixa.split("-")
      de = inteiro(a ?? "", campo)
      ate = inteiro(b ?? "", campo)
      if (de > ate) throw new Error(`${campo.nome}: faixa ${faixa} invertida`)
    } else {
      de = inteiro(faixa, campo)
      ate = passoTexto === undefined ? de : campo.max
    }
    for (let v = de; v <= ate; v += passo) valores.add(campo.nome === "dia da semana" && v === 7 ? 0 : v)
  }
  return valores
}

export function lerCron(expressao: string): Cron {
  const partes = expressao.trim().split(/\s+/)
  if (partes.length !== 5) throw new Error("use 5 campos: minuto hora dia-do-mês mês dia-da-semana")
  const [minutos, horas, dias, meses, semana] = partes.map((p, i) => lerCampo(p, CAMPOS[i]!))
  return {
    minutos: minutos!,
    horas: horas!,
    dias: dias!,
    meses: meses!,
    semana: semana!,
    diaRestrito: partes[2] !== "*",
    semanaRestrita: partes[4] !== "*",
  }
}

function diaCasa(cron: Cron, d: Date): boolean {
  const dia = cron.dias.has(d.getDate())
  const semana = cron.semana.has(d.getDay())
  if (cron.diaRestrito && cron.semanaRestrita) return dia || semana
  return dia && semana
}

const LIMITE_DE_PASSOS = 200_000

// No fuso local da máquina: o horário "8:30" do cron é 8:30 no relógio de quem roda.
export function proximoHorario(cron: Cron, depois: Date): Date | null {
  const d = new Date(depois)
  d.setSeconds(0, 0)
  d.setMinutes(d.getMinutes() + 1)
  for (let passos = 0; passos < LIMITE_DE_PASSOS; passos++) {
    if (!cron.meses.has(d.getMonth() + 1)) {
      d.setMonth(d.getMonth() + 1, 1)
      d.setHours(0, 0, 0, 0)
    } else if (!diaCasa(cron, d)) {
      d.setDate(d.getDate() + 1)
      d.setHours(0, 0, 0, 0)
    } else if (!cron.horas.has(d.getHours())) {
      d.setHours(d.getHours() + 1, 0, 0, 0)
    } else if (!cron.minutos.has(d.getMinutes())) {
      d.setMinutes(d.getMinutes() + 1, 0, 0)
    } else {
      return d
    }
  }
  return null
}

export function proximosHorarios(cron: Cron, depois: Date, quantos: number): Date[] {
  const saida: Date[] = []
  let atual = depois
  while (saida.length < quantos) {
    const proximo = proximoHorario(cron, atual)
    if (!proximo) break
    saida.push(proximo)
    atual = proximo
  }
  return saida
}

// O último horário do cron em (de, ate]; null se não houver.
export function ultimoHorarioEntre(cron: Cron, de: Date, ate: Date): Date | null {
  let ultimo: Date | null = null
  let atual = de
  for (;;) {
    const proximo = proximoHorario(cron, atual)
    if (!proximo || proximo.getTime() > ate.getTime()) return ultimo
    ultimo = proximo
    atual = proximo
  }
}

// Conservador: olha só hora e minuto, inclusive da virada do dia, mesmo que os dias não sejam seguidos.
export function menorIntervaloEmMinutos(cron: Cron): number {
  const horarios = [...cron.horas].flatMap((h) => [...cron.minutos].map((m) => h * 60 + m)).sort((a, b) => a - b)
  if (horarios.length < 2) return 24 * 60
  let menor = 24 * 60 - horarios.at(-1)! + horarios[0]!
  for (let i = 1; i < horarios.length; i++) menor = Math.min(menor, horarios[i]! - horarios[i - 1]!)
  return menor
}
