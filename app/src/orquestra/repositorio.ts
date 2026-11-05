import { Database } from "bun:sqlite"
import { mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { NOMES_DE_STATUS, exigirMudanca, type NovaTarefa, type Registro, type StatusTarefa, type Tarefa } from "./tarefa"
import type { Etapa } from "./equipe"
import type { Disparo } from "./rotinas"
import type { Valor, Workflow } from "./workflow"
import type { AcaoDoEspelho, EstadoDaLinha, LinhaDoEspelho } from "./espelho"
import {
  exigirMudancaDeExecucao,
  truncar,
  type Evento,
  type Execucao,
  type Gatilho,
  type StatusExecucao,
  type TipoDeEvento,
} from "./execucao"

const VERSAO = 7

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

const ESQUEMA_4 = `
ALTER TABLE tarefas ADD COLUMN politica TEXT NOT NULL DEFAULT '[]';
ALTER TABLE tarefas ADD COLUMN etapa INTEGER;
ALTER TABLE tarefas ADD COLUMN retorno INTEGER;
ALTER TABLE tarefas ADD COLUMN voltas INTEGER NOT NULL DEFAULT 0;
ALTER TABLE execucoes ADD COLUMN etapa INTEGER;
`

const ESQUEMA_5 = `
CREATE TABLE rotinas_estado (
  equipe TEXT NOT NULL,
  rotina TEXT NOT NULL,
  marca TEXT NOT NULL,
  token TEXT,
  PRIMARY KEY (equipe, rotina)
);
CREATE TABLE disparos (
  id INTEGER PRIMARY KEY,
  equipe TEXT NOT NULL,
  rotina TEXT NOT NULL,
  origem TEXT NOT NULL,
  horario TEXT,
  em TEXT NOT NULL,
  resultado TEXT NOT NULL,
  motivo TEXT NOT NULL DEFAULT '',
  tarefa INTEGER
);
CREATE INDEX disparos_por_rotina ON disparos(equipe, rotina, id);
`

const ESQUEMA_6 = `
CREATE TABLE fluxos (
  id INTEGER PRIMARY KEY,
  equipe TEXT NOT NULL,
  workflow TEXT NOT NULL,
  versao INTEGER NOT NULL,
  definicao TEXT NOT NULL,
  entrada TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL,
  resultado TEXT,
  criado_por TEXT NOT NULL,
  depois_de INTEGER,
  criado_em TEXT NOT NULL,
  atualizado_em TEXT NOT NULL,
  erro TEXT
);
CREATE INDEX fluxos_por_status ON fluxos(status, id);
CREATE TABLE fichas (
  id INTEGER PRIMARY KEY,
  fluxo INTEGER NOT NULL REFERENCES fluxos(id),
  no TEXT NOT NULL,
  status TEXT NOT NULL,
  tarefa INTEGER,
  veio_de INTEGER,
  chegadas TEXT NOT NULL DEFAULT '[]',
  saidas TEXT NOT NULL DEFAULT '{}',
  acorda_em TEXT,
  prazo_em TEXT,
  avisada INTEGER NOT NULL DEFAULT 0,
  criada_em TEXT NOT NULL,
  concluida_em TEXT
);
CREATE INDEX fichas_por_fluxo ON fichas(fluxo, id);
ALTER TABLE tarefas ADD COLUMN fluxo INTEGER;
ALTER TABLE tarefas ADD COLUMN ficha INTEGER;
`

const ESQUEMA_7 = `
CREATE TABLE espelho (
  id INTEGER PRIMARY KEY,
  chave TEXT NOT NULL,
  tipo TEXT NOT NULL,
  titulo TEXT NOT NULL,
  ticktask INTEGER,
  opcoes TEXT NOT NULL DEFAULT '{}',
  estado TEXT NOT NULL,
  acao TEXT NOT NULL,
  criado_em TEXT NOT NULL,
  atualizado_em TEXT NOT NULL,
  erro TEXT
);
CREATE UNIQUE INDEX espelho_um_por_chave ON espelho(chave) WHERE estado IN ('criar', 'aberto', 'dispensado');
CREATE INDEX espelho_por_estado ON espelho(estado, id);
`

export interface Fluxo {
  id: number
  equipe: string
  workflow: string
  versao: number
  definicao: Workflow
  entrada: Record<string, Valor>
  status: "esperando" | "rodando" | "concluido" | "falhou" | "cancelado"
  resultado: string | null
  criadoPor: string
  depoisDe: number | null
  criadoEm: string
  atualizadoEm: string
  erro: string | null
}

export interface Ficha {
  id: number
  fluxo: number
  no: string
  status: "esperando" | "concluida" | "cancelada"
  tarefa: number | null
  veioDe: number | null
  chegadas: string[]
  saidas: Record<string, Valor>
  acordaEm: string | null
  prazoEm: string | null
  avisada: boolean
  criadaEm: string
  concluidaEm: string | null
}

interface LinhaFluxo {
  id: number
  equipe: string
  workflow: string
  versao: number
  definicao: string
  entrada: string
  status: Fluxo["status"]
  resultado: string | null
  criado_por: string
  depois_de: number | null
  criado_em: string
  atualizado_em: string
  erro: string | null
}

interface LinhaFicha {
  id: number
  fluxo: number
  no: string
  status: Ficha["status"]
  tarefa: number | null
  veio_de: number | null
  chegadas: string
  saidas: string
  acorda_em: string | null
  prazo_em: string | null
  avisada: number
  criada_em: string
  concluida_em: string | null
}

function montarFluxo(l: LinhaFluxo): Fluxo {
  return {
    id: l.id,
    equipe: l.equipe,
    workflow: l.workflow,
    versao: l.versao,
    definicao: JSON.parse(l.definicao) as Workflow,
    entrada: JSON.parse(l.entrada) as Record<string, Valor>,
    status: l.status,
    resultado: l.resultado,
    criadoPor: l.criado_por,
    depoisDe: l.depois_de,
    criadoEm: l.criado_em,
    atualizadoEm: l.atualizado_em,
    erro: l.erro,
  }
}

function montarFicha(l: LinhaFicha): Ficha {
  return {
    id: l.id,
    fluxo: l.fluxo,
    no: l.no,
    status: l.status,
    tarefa: l.tarefa,
    veioDe: l.veio_de,
    chegadas: JSON.parse(l.chegadas) as string[],
    saidas: JSON.parse(l.saidas) as Record<string, Valor>,
    acordaEm: l.acorda_em,
    prazoEm: l.prazo_em,
    avisada: l.avisada === 1,
    criadaEm: l.criada_em,
    concluidaEm: l.concluida_em,
  }
}

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
  etapa: number | null
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
    etapa: l.etapa,
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
  politica: string
  etapa: number | null
  retorno: number | null
  voltas: number
  fluxo: number | null
  ficha: number | null
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
        if (user_version < 4) this.db.exec(ESQUEMA_4)
        if (user_version < 5) this.db.exec(ESQUEMA_5)
        if (user_version < 6) this.db.exec(ESQUEMA_6)
        if (user_version < 7) this.db.exec(ESQUEMA_7)
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
      politica: JSON.parse(linha.politica) as Etapa[],
      etapa: linha.etapa,
      retorno: linha.retorno,
      voltas: linha.voltas,
      fluxo: linha.fluxo,
      ficha: linha.ficha,
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
          `INSERT INTO tarefas (equipe, posicao, titulo, descricao, porque, pai, status, criada_por, criada_em, atualizada_em, politica, fluxo, ficha)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id`,
        )
        .get(
          nova.equipe,
          nova.posicao,
          nova.titulo,
          nova.descricao,
          nova.porque,
          nova.pai,
          nova.status,
          autor,
          em,
          em,
          JSON.stringify(nova.politica ?? []),
          nova.fluxo ?? null,
          nova.ficha ?? null,
        ) as {
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
      const etapa = para === "em_revisao" ? tarefa.etapa : null
      this.db.query("UPDATE tarefas SET status = ?, dono = ?, etapa = ?, atualizada_em = ? WHERE id = ?").run(para, dono, etapa, em, id)
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

  checkoutDeEtapa(id: number, etapa: number, dono: string, agora = new Date()): Tarefa {
    const mudou = this.db
      .query("UPDATE tarefas SET dono = ?, atualizada_em = ? WHERE id = ? AND status = 'em_revisao' AND etapa = ? AND dono IS NULL")
      .run(dono, agora.toISOString(), id, etapa)
    if (mudou.changes !== 1) throw new Error(`tarefa ${id} não está esperando a etapa ${etapa + 1}`)
    return this.exigir(id)
  }

  // Só solta se a etapa ainda é desta execução: o Ueslei pode ter movido a tarefa no meio.
  soltarEtapa(execucao: number, agora = new Date()): Tarefa | undefined {
    const { tarefa, etapa } = this.exigirExecucao(execucao)
    const mudou = this.db
      .query("UPDATE tarefas SET dono = NULL, atualizada_em = ? WHERE id = ? AND status = 'em_revisao' AND etapa IS ? AND dono = ?")
      .run(agora.toISOString(), tarefa, etapa, donoDaExecucao(execucao))
    return mudou.changes === 1 ? this.exigir(tarefa) : undefined
  }

  irParaEtapa(id: number, etapa: number, autor: string, texto: string, agora = new Date()): Tarefa {
    const em = agora.toISOString()
    return this.db.transaction(() => {
      const tarefa = this.exigir(id)
      if (tarefa.status !== "em_revisao") exigirMudanca(tarefa, "em_revisao", [])
      if (!tarefa.politica[etapa]) throw new Error(`tarefa ${id}: a política não tem a etapa ${etapa + 1}`)
      this.db
        .query("UPDATE tarefas SET status = 'em_revisao', etapa = ?, dono = NULL, atualizada_em = ? WHERE id = ?")
        .run(etapa, em, id)
      this.registrar(id, "status", autor, texto, em)
      return this.exigir(id)
    })()
  }

  definirPolitica(id: number, politica: Etapa[]): Tarefa {
    this.db.query("UPDATE tarefas SET politica = ? WHERE id = ?").run(JSON.stringify(politica), id)
    return this.exigir(id)
  }

  ligarFicha(tarefa: number, ficha: number): void {
    this.db.query("UPDATE tarefas SET ficha = ? WHERE id = ?").run(ficha, tarefa)
    this.db.query("UPDATE fichas SET tarefa = ? WHERE id = ?").run(tarefa, ficha)
  }

  criarFluxo(f: Omit<Fluxo, "id" | "atualizadoEm" | "resultado" | "erro">): Fluxo {
    const { id } = this.db
      .query(
        `INSERT INTO fluxos (equipe, workflow, versao, definicao, entrada, status, criado_por, depois_de, criado_em, atualizado_em)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id`,
      )
      .get(
        f.equipe,
        f.workflow,
        f.versao,
        JSON.stringify(f.definicao),
        JSON.stringify(f.entrada),
        f.status,
        f.criadoPor,
        f.depoisDe,
        f.criadoEm,
        f.criadoEm,
      ) as { id: number }
    return this.exigirFluxo(id)
  }

  fluxo(id: number): Fluxo | undefined {
    const linha = this.db.query("SELECT * FROM fluxos WHERE id = ?").get(id) as LinhaFluxo | null
    return linha ? montarFluxo(linha) : undefined
  }

  exigirFluxo(id: number): Fluxo {
    const fluxo = this.fluxo(id)
    if (!fluxo) throw new Error(`execução de workflow ${id} não existe`)
    return fluxo
  }

  fluxosAbertos(): Fluxo[] {
    return (this.db.query("SELECT * FROM fluxos WHERE status IN ('esperando', 'rodando') ORDER BY id").all() as LinhaFluxo[]).map(montarFluxo)
  }

  fluxosRecentes(limite = 20): Fluxo[] {
    return (
      this.db.query("SELECT * FROM fluxos WHERE status NOT IN ('esperando', 'rodando') ORDER BY id DESC LIMIT ?").all(limite) as LinhaFluxo[]
    ).map(montarFluxo)
  }

  fluxoAbertoDe(criadoPor: string): Fluxo | undefined {
    const linha = this.db
      .query("SELECT * FROM fluxos WHERE criado_por = ? AND status IN ('esperando', 'rodando') ORDER BY id DESC LIMIT 1")
      .get(criadoPor) as LinhaFluxo | null
    return linha ? montarFluxo(linha) : undefined
  }

  fluxosEsperandoPor(id: number): Fluxo[] {
    return (this.db.query("SELECT * FROM fluxos WHERE status = 'esperando' AND depois_de = ? ORDER BY id").all(id) as LinhaFluxo[]).map(
      montarFluxo,
    )
  }

  mudarFluxo(id: number, campos: { status?: Fluxo["status"]; resultado?: string | null; erro?: string | null }, agora = new Date()): Fluxo {
    const atual = this.exigirFluxo(id)
    this.db
      .query("UPDATE fluxos SET status = ?, resultado = ?, erro = ?, atualizado_em = ? WHERE id = ?")
      .run(
        campos.status ?? atual.status,
        campos.resultado !== undefined ? campos.resultado : atual.resultado,
        campos.erro !== undefined ? campos.erro : atual.erro,
        agora.toISOString(),
        id,
      )
    return this.exigirFluxo(id)
  }

  criarFicha(f: { fluxo: number; no: string; veioDe: number | null; chegadas?: string[]; acordaEm?: string | null; prazoEm?: string | null }, agora = new Date()): Ficha {
    const { id } = this.db
      .query(
        `INSERT INTO fichas (fluxo, no, status, veio_de, chegadas, acorda_em, prazo_em, criada_em)
         VALUES (?, ?, 'esperando', ?, ?, ?, ?, ?) RETURNING id`,
      )
      .get(f.fluxo, f.no, f.veioDe, JSON.stringify(f.chegadas ?? []), f.acordaEm ?? null, f.prazoEm ?? null, agora.toISOString()) as { id: number }
    return this.exigirFicha(id)
  }

  ficha(id: number): Ficha | undefined {
    const linha = this.db.query("SELECT * FROM fichas WHERE id = ?").get(id) as LinhaFicha | null
    return linha ? montarFicha(linha) : undefined
  }

  exigirFicha(id: number): Ficha {
    const ficha = this.ficha(id)
    if (!ficha) throw new Error(`ficha ${id} não existe`)
    return ficha
  }

  fichasDo(fluxo: number): Ficha[] {
    return (this.db.query("SELECT * FROM fichas WHERE fluxo = ? ORDER BY id").all(fluxo) as LinhaFicha[]).map(montarFicha)
  }

  fichasEsperando(): Ficha[] {
    return (this.db.query("SELECT * FROM fichas WHERE status = 'esperando' ORDER BY id").all() as LinhaFicha[]).map(montarFicha)
  }

  mudarFicha(
    id: number,
    campos: Partial<Pick<Ficha, "status" | "chegadas" | "saidas" | "acordaEm" | "prazoEm" | "avisada">>,
    agora = new Date(),
  ): Ficha {
    const f = { ...this.exigirFicha(id), ...campos }
    this.db
      .query(
        `UPDATE fichas SET status = ?, chegadas = ?, saidas = ?, acorda_em = ?, prazo_em = ?, avisada = ?,
         concluida_em = CASE WHEN ? = 'esperando' THEN NULL ELSE COALESCE(concluida_em, ?) END WHERE id = ?`,
      )
      .run(
        f.status,
        JSON.stringify(f.chegadas),
        JSON.stringify(f.saidas),
        f.acordaEm,
        f.prazoEm,
        f.avisada ? 1 : 0,
        f.status,
        agora.toISOString(),
        id,
      )
    return this.exigirFicha(id)
  }

  marcarRetorno(id: number, retorno: number | null, voltas: number): Tarefa {
    this.db.query("UPDATE tarefas SET retorno = ?, voltas = ? WHERE id = ?").run(retorno, voltas, id)
    return this.exigir(id)
  }

  estadoDaRotina(equipe: string, rotina: string): { marca: string; token: string | null } | undefined {
    return (this.db.query("SELECT marca, token FROM rotinas_estado WHERE equipe = ? AND rotina = ?").get(equipe, rotina) ?? undefined) as
      | { marca: string; token: string | null }
      | undefined
  }

  marcarRotina(equipe: string, rotina: string, marca: Date): void {
    this.db
      .query(
        `INSERT INTO rotinas_estado (equipe, rotina, marca) VALUES (?, ?, ?)
         ON CONFLICT (equipe, rotina) DO UPDATE SET marca = excluded.marca`,
      )
      .run(equipe, rotina, marca.toISOString())
  }

  trocarToken(equipe: string, rotina: string, token: string | null, agora = new Date()): void {
    this.db
      .query(
        `INSERT INTO rotinas_estado (equipe, rotina, marca, token) VALUES (?, ?, ?, ?)
         ON CONFLICT (equipe, rotina) DO UPDATE SET token = excluded.token`,
      )
      .run(equipe, rotina, agora.toISOString(), token)
  }

  esquecerRotina(equipe: string, rotina: string): void {
    this.db.query("DELETE FROM rotinas_estado WHERE equipe = ? AND rotina = ?").run(equipe, rotina)
  }

  registrarDisparo(d: Omit<Disparo, "id">): Disparo {
    const { id } = this.db
      .query(
        `INSERT INTO disparos (equipe, rotina, origem, horario, em, resultado, motivo, tarefa)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING id`,
      )
      .get(d.equipe, d.rotina, d.origem, d.horario, d.em, d.resultado, d.motivo, d.tarefa) as { id: number }
    return { ...d, id }
  }

  disparos(equipe: string, rotina: string, limite = 10): Disparo[] {
    return this.db
      .query("SELECT * FROM disparos WHERE equipe = ? AND rotina = ? ORDER BY id DESC LIMIT ?")
      .all(equipe, rotina, limite) as Disparo[]
  }

  tarefaAbertaDe(criadaPor: string): number | null {
    const linha = this.db
      .query("SELECT id FROM tarefas WHERE criada_por = ? AND status NOT IN ('concluida', 'cancelada') ORDER BY id DESC LIMIT 1")
      .get(criadaPor) as { id: number } | null
    return linha?.id ?? null
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
    extra: { tentativa?: number; naoAntes?: Date; etapa?: number; posicao?: string } = {},
  ): { execucao: Execucao; juntada: boolean } {
    const em = agora.toISOString()
    return this.db.transaction(() => {
      const alvo = this.exigir(tarefa)
      const existente = this.naFilaDa(tarefa)
      if (existente) return { execucao: existente, juntada: true }
      const { id } = this.db
        .query(
          `INSERT INTO execucoes (tarefa, posicao, gatilho, status, tentativa, nao_antes, criada_em, etapa)
           VALUES (?, ?, ?, 'na_fila', ?, ?, ?, ?) RETURNING id`,
        )
        .get(
          alvo.id,
          extra.posicao ?? alvo.posicao,
          gatilho,
          extra.tentativa ?? 1,
          extra.naoAntes?.toISOString() ?? null,
          em,
          extra.etapa ?? null,
        ) as { id: number }
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

  comecar(id: number, persona: string | null, modelo: string, agora = new Date()): Execucao {
    const em = agora.toISOString()
    return this.db.transaction(() => {
      const execucao = this.exigirExecucao(id)
      exigirMudancaDeExecucao(execucao, "rodando")
      if (execucao.etapa === null) this.checkout(execucao.tarefa, donoDaExecucao(id), agora)
      else this.checkoutDeEtapa(execucao.tarefa, execucao.etapa, donoDaExecucao(id), agora)
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
        if (e.etapa === null) this.devolver(e.id, "a_fazer", "orquestra", agora)
        else this.soltarEtapa(e.id, agora)
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

  ultimoEvento(execucao: number): Evento | undefined {
    return (this.db.query("SELECT * FROM eventos WHERE execucao = ? ORDER BY id DESC LIMIT 1").get(execucao) ?? undefined) as
      | Evento
      | undefined
  }

  registrosRecentes(tipos: readonly Registro["tipo"][], limite = 100): (Registro & { equipe: string })[] {
    const marcas = tipos.map(() => "?").join(", ")
    return this.db
      .query(
        `SELECT r.*, t.equipe FROM registros r JOIN tarefas t ON t.id = r.tarefa
         WHERE r.tipo IN (${marcas}) ORDER BY r.id DESC LIMIT ?`,
      )
      .all(...tipos, limite) as (Registro & { equipe: string })[]
  }

  disparosRecentes(limite = 100): Disparo[] {
    return this.db.query("SELECT * FROM disparos ORDER BY id DESC LIMIT ?").all(limite) as Disparo[]
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

  linhasDoEspelho(): LinhaDoEspelho[] {
    const linhas = this.db
      .query("SELECT * FROM espelho WHERE estado IN ('criar', 'aberto', 'fechar', 'dispensado') ORDER BY id")
      .all() as Record<string, unknown>[]
    return linhas.map((l) => ({
      id: l.id as number,
      chave: l.chave as string,
      tipo: l.tipo as string,
      titulo: l.titulo as string,
      ticktask: (l.ticktask as number | null) ?? null,
      opcoes: JSON.parse(l.opcoes as string) as Record<string, number>,
      estado: l.estado as EstadoDaLinha,
      acao: JSON.parse(l.acao as string) as AcaoDoEspelho,
      criadoEm: l.criado_em as string,
      atualizadoEm: l.atualizado_em as string,
      erro: (l.erro as string | null) ?? null,
    }))
  }

  criarLinha(l: { chave: string; tipo: string; titulo: string; acao: AcaoDoEspelho }, agora = new Date()): LinhaDoEspelho {
    const em = agora.toISOString()
    const { id } = this.db
      .query(
        "INSERT INTO espelho (chave, tipo, titulo, estado, acao, criado_em, atualizado_em) VALUES (?, ?, ?, 'criar', ?, ?, ?) RETURNING id",
      )
      .get(l.chave, l.tipo, l.titulo, JSON.stringify(l.acao), em, em) as { id: number }
    return { id, ...l, ticktask: null, opcoes: {}, estado: "criar", criadoEm: em, atualizadoEm: em, erro: null }
  }

  mudarLinha(id: number, mudanca: Partial<Pick<LinhaDoEspelho, "estado" | "ticktask" | "opcoes" | "erro">>, agora = new Date()): void {
    const campos: string[] = ["atualizado_em = ?"]
    const valores: (string | number | null)[] = [agora.toISOString()]
    if (mudanca.estado !== undefined) campos.push("estado = ?"), valores.push(mudanca.estado)
    if (mudanca.ticktask !== undefined) campos.push("ticktask = ?"), valores.push(mudanca.ticktask)
    if (mudanca.opcoes !== undefined) campos.push("opcoes = ?"), valores.push(JSON.stringify(mudanca.opcoes))
    if (mudanca.erro !== undefined) campos.push("erro = ?"), valores.push(mudanca.erro)
    this.db.query(`UPDATE espelho SET ${campos.join(", ")} WHERE id = ?`).run(...valores, id)
  }
}
