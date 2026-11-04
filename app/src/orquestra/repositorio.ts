import { Database } from "bun:sqlite"
import { mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { NOMES_DE_STATUS, exigirMudanca, type NovaTarefa, type Registro, type StatusTarefa, type Tarefa } from "./tarefa"
import {
  exigirMudancaDeExecucao,
  truncar,
  type Evento,
  type Execucao,
  type Gatilho,
  type StatusExecucao,
  type TipoDeEvento,
} from "./execucao"

const VERSAO = 3

const ESQUEMA = `
CREATE TABLE tarefas (
  id INTEGER PRIMARY KEY,
  equipe TEXT NOT NULL,
  posicao TEXT NOT NULL,
  titulo TEXT NOT NULL,
  descricao TEXT NOT NULL DEFAULT '',
  porque TEXT NOT NULL DEFAULT '',
  pai INTEGER REFERENCES tarefas(id),
  status TEXT NOT NULL,
  dono TEXT,
  criada_por TEXT NOT NULL,
  criada_em TEXT NOT NULL,
  atualizada_em TEXT NOT NULL
);
CREATE INDEX tarefas_por_equipe ON tarefas(equipe, status);
CREATE TABLE dependencias (
  tarefa INTEGER NOT NULL REFERENCES tarefas(id),
  depende_de INTEGER NOT NULL REFERENCES tarefas(id),
  PRIMARY KEY (tarefa, depende_de)
);
CREATE TABLE registros (
  id INTEGER PRIMARY KEY,
  tarefa INTEGER NOT NULL REFERENCES tarefas(id),
  tipo TEXT NOT NULL,
  autor TEXT NOT NULL,
  texto TEXT NOT NULL,
  em TEXT NOT NULL
);
CREATE INDEX registros_por_tarefa ON registros(tarefa, id);
`

const ESQUEMA_2 = `
CREATE TABLE execucoes (
  id INTEGER PRIMARY KEY,
  tarefa INTEGER NOT NULL REFERENCES tarefas(id),
  posicao TEXT NOT NULL,
  persona TEXT,
  gatilho TEXT NOT NULL,
  status TEXT NOT NULL,
  tentativa INTEGER NOT NULL DEFAULT 1,
  nao_antes TEXT,
  falha INTEGER NOT NULL DEFAULT 0,
  session_id TEXT,
  modelo TEXT,
  criada_em TEXT NOT NULL,
  inicio TEXT,
  fim TEXT,
  resultado TEXT,
  erro TEXT,
  custo_usd REAL,
  custo_acumulado_usd REAL
);
CREATE UNIQUE INDEX uma_na_fila ON execucoes(tarefa) WHERE status = 'na_fila';
CREATE INDEX execucoes_por_status ON execucoes(status, id);
CREATE INDEX execucoes_por_tarefa ON execucoes(tarefa, id);
CREATE TABLE eventos (
  id INTEGER PRIMARY KEY,
  execucao INTEGER NOT NULL REFERENCES execucoes(id),
  tipo TEXT NOT NULL,
  conteudo TEXT NOT NULL,
  em TEXT NOT NULL
);
CREATE INDEX eventos_por_execucao ON eventos(execucao, id);
`

const ESQUEMA_3 = `
CREATE TABLE pausas (
  alvo TEXT PRIMARY KEY,
  motivo TEXT NOT NULL,
  em TEXT NOT NULL
);
CREATE TABLE auditoria (
  id INTEGER PRIMARY KEY,
  em TEXT NOT NULL,
  quem TEXT NOT NULL,
  acao TEXT NOT NULL,
  alvo TEXT NOT NULL,
  detalhe TEXT NOT NULL DEFAULT ''
);
CREATE TABLE avisos_de_orcamento (
  persona TEXT NOT NULL,
  mes TEXT NOT NULL,
  nivel TEXT NOT NULL,
  PRIMARY KEY (persona, mes, nivel)
);
`

export interface LinhaDeAuditoria {
  id: number
  em: string
  quem: string
  acao: string
  alvo: string
  detalhe: string
}

interface LinhaExecucao {
  id: number
  tarefa: number
  posicao: string
  persona: string | null
  gatilho: Gatilho
  status: StatusExecucao
  tentativa: number
  nao_antes: string | null
  falha: number
  session_id: string | null
  modelo: string | null
  criada_em: string
  inicio: string | null
  fim: string | null
  resultado: string | null
  erro: string | null
  custo_usd: number | null
  custo_acumulado_usd: number | null
}

function montarExecucao(l: LinhaExecucao): Execucao {
  return {
    id: l.id,
    tarefa: l.tarefa,
    posicao: l.posicao,
    persona: l.persona,
    gatilho: l.gatilho,
    status: l.status,
    tentativa: l.tentativa,
    naoAntes: l.nao_antes,
    falha: l.falha === 1,
    sessionId: l.session_id,
    modelo: l.modelo,
    criadaEm: l.criada_em,
    inicio: l.inicio,
    fim: l.fim,
    resultado: l.resultado,
    erro: l.erro,
    custoUSD: l.custo_usd,
  }
}

export interface Termino {
  status: "concluida" | "falhou" | "interrompida"
  falha: boolean
  resultado?: string
  erro?: string
  custoUSD?: number | null
  custoAcumuladoUSD?: number | null
}

export const donoDaExecucao = (id: number) => `execucao:${id}`

interface LinhaTarefa {
  id: number
  equipe: string
  posicao: string
  titulo: string
  descricao: string
  porque: string
  pai: number | null
  status: StatusTarefa
  dono: string | null
  criada_por: string
  criada_em: string
  atualizada_em: string
}

const SEM_DONO: readonly StatusTarefa[] = ["backlog", "a_fazer", "bloqueada"]

export function caminhoDoBanco(raiz: string): string {
  return join(raiz, "orquestra", "orquestra.db")
}

export class Repositorio {
  readonly db: Database

  constructor(caminho: string) {
    if (caminho !== ":memory:") mkdirSync(dirname(caminho), { recursive: true })
    this.db = new Database(caminho, { strict: true })
    this.db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;")
    const { user_version } = this.db.query("PRAGMA user_version").get() as { user_version: number }
    if (user_version > VERSAO) {
      throw new Error(`orquestra.db é da versão ${user_version}, mais nova que este servidor (${VERSAO})`)
    }
    if (user_version < VERSAO) {
      this.db.transaction(() => {
        if (user_version < 1) this.db.exec(ESQUEMA)
        if (user_version < 2) this.db.exec(ESQUEMA_2)
        if (user_version < 3) this.db.exec(ESQUEMA_3)
        this.db.exec(`PRAGMA user_version = ${VERSAO}`)
      })()
    }
  }

  fechar(): void {
    this.db.close()
  }

  private dependencias(id: number): number[] {
    return (this.db.query("SELECT depende_de FROM dependencias WHERE tarefa = ? ORDER BY depende_de").all(id) as {
      depende_de: number
    }[]).map((d) => d.depende_de)
  }

  private montar(linha: LinhaTarefa): Tarefa {
    return {
      id: linha.id,
      equipe: linha.equipe,
      posicao: linha.posicao,
      titulo: linha.titulo,
      descricao: linha.descricao,
      porque: linha.porque,
      pai: linha.pai,
      status: linha.status,
      dono: linha.dono,
      criadaPor: linha.criada_por,
      criadaEm: linha.criada_em,
      atualizadaEm: linha.atualizada_em,
      dependeDe: this.dependencias(linha.id),
    }
  }

  private registrar(tarefa: number, tipo: Registro["tipo"], autor: string, texto: string, em: string): void {
    this.db.query("INSERT INTO registros (tarefa, tipo, autor, texto, em) VALUES (?, ?, ?, ?, ?)").run(tarefa, tipo, autor, texto, em)
  }

  ler(id: number): Tarefa | undefined {
    const linha = this.db.query("SELECT * FROM tarefas WHERE id = ?").get(id) as LinhaTarefa | null
    return linha ? this.montar(linha) : undefined
  }

  exigir(id: number): Tarefa {
    const tarefa = this.ler(id)
    if (!tarefa) throw new Error(`tarefa ${id} não existe`)
    return tarefa
  }

  listar(equipe?: string): Tarefa[] {
    const linhas = (
      equipe
        ? this.db.query("SELECT * FROM tarefas WHERE equipe = ? ORDER BY atualizada_em DESC, id DESC").all(equipe)
        : this.db.query("SELECT * FROM tarefas ORDER BY atualizada_em DESC, id DESC").all()
    ) as LinhaTarefa[]
    return linhas.map((l) => this.montar(l))
  }

  registros(id: number): Registro[] {
    return this.db.query("SELECT * FROM registros WHERE tarefa = ? ORDER BY id").all(id) as Registro[]
  }

  criar(nova: NovaTarefa, autor: string, agora = new Date()): Tarefa {
    const em = agora.toISOString()
    return this.db.transaction(() => {
      if (nova.pai !== null) {
        const pai = this.exigir(nova.pai)
        if (pai.equipe !== nova.equipe) throw new Error("a tarefa-pai é de outra equipe")
      }
      for (const dep of nova.dependeDe) this.exigir(dep)
      const { id } = this.db
        .query(
          `INSERT INTO tarefas (equipe, posicao, titulo, descricao, porque, pai, status, criada_por, criada_em, atualizada_em)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id`,
        )
        .get(nova.equipe, nova.posicao, nova.titulo, nova.descricao, nova.porque, nova.pai, nova.status, autor, em, em) as {
        id: number
      }
      for (const dep of nova.dependeDe) {
        this.db.query("INSERT INTO dependencias (tarefa, depende_de) VALUES (?, ?)").run(id, dep)
      }
      this.registrar(id, "status", autor, `criou em ${NOMES_DE_STATUS[nova.status]}`, em)
      return this.exigir(id)
    })()
  }

  mudarStatus(id: number, para: StatusTarefa, autor: string, agora = new Date()): Tarefa {
    const em = agora.toISOString()
    return this.db.transaction(() => {
      const tarefa = this.exigir(id)
      exigirMudanca(tarefa, para, tarefa.dependeDe.map((d) => this.exigir(d).status))
      const dono = SEM_DONO.includes(para) ? null : para === "em_andamento" ? (tarefa.dono ?? autor) : tarefa.dono
      this.db.query("UPDATE tarefas SET status = ?, dono = ?, atualizada_em = ? WHERE id = ?").run(para, dono, em, id)
      this.registrar(id, "status", autor, `${NOMES_DE_STATUS[tarefa.status]} → ${NOMES_DE_STATUS[para]}`, em)
      return this.exigir(id)
    })()
  }

  // O dono único vem do WHERE: duas execuções disputando a mesma tarefa, só uma muda a linha.
  checkout(id: number, dono: string, agora = new Date()): Tarefa {
    const em = agora.toISOString()
    return this.db.transaction(() => {
      const tarefa = this.exigir(id)
      exigirMudanca(tarefa, "em_andamento", tarefa.dependeDe.map((d) => this.exigir(d).status))
      const mudou = this.db
        .query("UPDATE tarefas SET status = 'em_andamento', dono = ?, atualizada_em = ? WHERE id = ? AND status = 'a_fazer' AND dono IS NULL")
        .run(dono, em, id)
      if (mudou.changes !== 1) throw new Error(`tarefa ${id} já tem dono`)
      this.registrar(id, "status", dono, `${NOMES_DE_STATUS[tarefa.status]} → ${NOMES_DE_STATUS.em_andamento}`, em)
      return this.exigir(id)
    })()
  }

  comentar(id: number, autor: string, texto: string, agora = new Date(), tipo: Registro["tipo"] = "comentario"): Registro {
    const limpo = texto.trim().slice(0, 20_000)
    if (!limpo) throw new Error("comentário vazio")
    const em = agora.toISOString()
    return this.db.transaction(() => {
      this.exigir(id)
      this.registrar(id, tipo, autor, limpo, em)
      this.db.query("UPDATE tarefas SET atualizada_em = ? WHERE id = ?").run(em, id)
      return this.db.query("SELECT * FROM registros WHERE tarefa = ? ORDER BY id DESC LIMIT 1").get(id) as Registro
    })()
  }

  cadeiaDePais(id: number): Tarefa[] {
    const pais: Tarefa[] = []
    const vistos = new Set([id])
    for (let pai = this.exigir(id).pai; pai !== null && !vistos.has(pai); ) {
      vistos.add(pai)
      const tarefa = this.exigir(pai)
      pais.push(tarefa)
      pai = tarefa.pai
    }
    return pais
  }

  dependentes(id: number): number[] {
    return (this.db.query("SELECT tarefa FROM dependencias WHERE depende_de = ? ORDER BY tarefa").all(id) as { tarefa: number }[]).map(
      (d) => d.tarefa,
    )
  }

  execucao(id: number): Execucao | undefined {
    const linha = this.db.query("SELECT * FROM execucoes WHERE id = ?").get(id) as LinhaExecucao | null
    return linha ? montarExecucao(linha) : undefined
  }

  exigirExecucao(id: number): Execucao {
    const execucao = this.execucao(id)
    if (!execucao) throw new Error(`execução ${id} não existe`)
    return execucao
  }

  execucoesDaTarefa(tarefa: number): Execucao[] {
    return (this.db.query("SELECT * FROM execucoes WHERE tarefa = ? ORDER BY id").all(tarefa) as LinhaExecucao[]).map(montarExecucao)
  }

  comStatus(status: StatusExecucao): Execucao[] {
    return (this.db.query("SELECT * FROM execucoes WHERE status = ? ORDER BY id").all(status) as LinhaExecucao[]).map(montarExecucao)
  }

  naFilaDa(tarefa: number): Execucao | undefined {
    const linha = this.db.query("SELECT * FROM execucoes WHERE tarefa = ? AND status = 'na_fila'").get(tarefa) as LinhaExecucao | null
    return linha ? montarExecucao(linha) : undefined
  }

  // Devolve a que já estava na fila quando há uma: o índice uma_na_fila não deixa existir duas.
  enfileirar(
    tarefa: number,
    gatilho: Gatilho,
    agora = new Date(),
    extra: { tentativa?: number; naoAntes?: Date } = {},
  ): { execucao: Execucao; juntada: boolean } {
    const em = agora.toISOString()
    return this.db.transaction(() => {
      const alvo = this.exigir(tarefa)
      const existente = this.naFilaDa(tarefa)
      if (existente) return { execucao: existente, juntada: true }
      const { id } = this.db
        .query(
          `INSERT INTO execucoes (tarefa, posicao, gatilho, status, tentativa, nao_antes, criada_em)
           VALUES (?, ?, ?, 'na_fila', ?, ?, ?) RETURNING id`,
        )
        .get(alvo.id, alvo.posicao, gatilho, extra.tentativa ?? 1, extra.naoAntes?.toISOString() ?? null, em) as { id: number }
      return { execucao: this.exigirExecucao(id), juntada: false }
    })()
  }

  descartar(id: number, motivo: string, agora = new Date()): Execucao {
    return this.db.transaction(() => {
      exigirMudancaDeExecucao(this.exigirExecucao(id), "interrompida")
      this.db.query("UPDATE execucoes SET status = 'interrompida', erro = ?, fim = ? WHERE id = ?").run(motivo, agora.toISOString(), id)
      return this.exigirExecucao(id)
    })()
  }

  comecar(id: number, persona: string, modelo: string, agora = new Date()): Execucao {
    const em = agora.toISOString()
    return this.db.transaction(() => {
      const execucao = this.exigirExecucao(id)
      exigirMudancaDeExecucao(execucao, "rodando")
      this.checkout(execucao.tarefa, donoDaExecucao(id), agora)
      this.db
        .query("UPDATE execucoes SET status = 'rodando', persona = ?, modelo = ?, inicio = ? WHERE id = ?")
        .run(persona, modelo, em, id)
      return this.exigirExecucao(id)
    })()
  }

  gravarSessao(id: number, sessionId: string): void {
    this.db.query("UPDATE execucoes SET session_id = ? WHERE id = ?").run(sessionId, id)
  }

  anteriorDoPar(tarefa: number, persona: string, antesDe: number): Execucao | undefined {
    const linha = this.db
      .query("SELECT * FROM execucoes WHERE tarefa = ? AND persona = ? AND id < ? AND inicio IS NOT NULL ORDER BY id DESC LIMIT 1")
      .get(tarefa, persona, antesDe) as LinhaExecucao | null
    return linha ? montarExecucao(linha) : undefined
  }

  sessaoDoPar(tarefa: number, persona: string, antesDe: number): { sessionId: string; custoAcumuladoUSD: number | null } | undefined {
    const linha = this.db
      .query(
        "SELECT session_id, custo_acumulado_usd FROM execucoes WHERE tarefa = ? AND persona = ? AND id < ? AND session_id IS NOT NULL ORDER BY id DESC LIMIT 1",
      )
      .get(tarefa, persona, antesDe) as { session_id: string; custo_acumulado_usd: number | null } | null
    return linha ? { sessionId: linha.session_id, custoAcumuladoUSD: linha.custo_acumulado_usd } : undefined
  }

  terminar(id: number, termino: Termino, agora = new Date()): Execucao {
    return this.db.transaction(() => {
      exigirMudancaDeExecucao(this.exigirExecucao(id), termino.status)
      this.db
        .query(
          `UPDATE execucoes SET status = ?, falha = ?, resultado = ?, erro = ?, custo_usd = ?, custo_acumulado_usd = ?, fim = ?
           WHERE id = ?`,
        )
        .run(
          termino.status,
          termino.falha ? 1 : 0,
          termino.resultado ?? null,
          termino.erro ?? null,
          termino.custoUSD ?? null,
          termino.custoAcumuladoUSD ?? null,
          agora.toISOString(),
          id,
        )
      return this.exigirExecucao(id)
    })()
  }

  // A tarefa só volta para a fazer se ainda é desta execução: o Ueslei pode tê-la movido.
  devolver(execucao: number, para: StatusTarefa, autor: string, agora = new Date()): Tarefa | undefined {
    return this.db.transaction(() => {
      const { tarefa } = this.exigirExecucao(execucao)
      const atual = this.exigir(tarefa)
      if (atual.status !== "em_andamento" || atual.dono !== donoDaExecucao(execucao)) return undefined
      return this.mudarStatus(tarefa, para, autor, agora)
    })()
  }

  interrompidasNaSubida(agora = new Date()): Execucao[] {
    return this.db.transaction(() => {
      const vivas = this.comStatus("rodando")
      for (const e of vivas) {
        this.terminar(e.id, { status: "interrompida", falha: true, erro: "o servidor reiniciou no meio da execução" }, agora)
        this.devolver(e.id, "a_fazer", "orquestra", agora)
      }
      return vivas.map((e) => this.exigirExecucao(e.id))
    })()
  }

  registrarEvento(execucao: number, tipo: TipoDeEvento, conteudo: string, agora = new Date()): Evento {
    const { id } = this.db
      .query("INSERT INTO eventos (execucao, tipo, conteudo, em) VALUES (?, ?, ?, ?) RETURNING id")
      .get(execucao, tipo, truncar(conteudo), agora.toISOString()) as { id: number }
    return this.db.query("SELECT * FROM eventos WHERE id = ?").get(id) as Evento
  }

  eventos(execucao: number): Evento[] {
    return this.db.query("SELECT * FROM eventos WHERE execucao = ? ORDER BY id").all(execucao) as Evento[]
  }

  filhasAbertas(id: number): number {
    const { n } = this.db
      .query("SELECT COUNT(*) AS n FROM tarefas WHERE pai = ? AND status NOT IN ('concluida', 'cancelada')")
      .get(id) as { n: number }
    return n
  }

  pausas(): Map<string, string> {
    const linhas = this.db.query("SELECT alvo, motivo FROM pausas").all() as { alvo: string; motivo: string }[]
    return new Map(linhas.map((l) => [l.alvo, l.motivo]))
  }

  pausar(alvo: string, motivo: string, agora = new Date()): void {
    this.db.query("INSERT OR REPLACE INTO pausas (alvo, motivo, em) VALUES (?, ?, ?)").run(alvo, motivo, agora.toISOString())
  }

  retomar(alvo: string): boolean {
    return this.db.query("DELETE FROM pausas WHERE alvo = ?").run(alvo).changes > 0
  }

  auditar(quem: string, acao: string, alvo: string, detalhe = "", agora = new Date()): void {
    this.db
      .query("INSERT INTO auditoria (em, quem, acao, alvo, detalhe) VALUES (?, ?, ?, ?, ?)")
      .run(agora.toISOString(), quem, acao, alvo, detalhe.slice(0, 2_000))
  }

  auditoria(limite = 200): LinhaDeAuditoria[] {
    return this.db.query("SELECT * FROM auditoria ORDER BY id DESC LIMIT ?").all(limite) as LinhaDeAuditoria[]
  }

  marcarAvisoDeOrcamento(persona: string, mes: string, nivel: string): boolean {
    return (
      this.db.query("INSERT OR IGNORE INTO avisos_de_orcamento (persona, mes, nivel) VALUES (?, ?, ?)").run(persona, mes, nivel)
        .changes > 0
    )
  }
}
