import { Database } from "bun:sqlite"
import { mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { NOMES_DE_STATUS, exigirMudanca, type NovaTarefa, type Registro, type StatusTarefa, type Tarefa } from "./tarefa"

const VERSAO = 1

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
    if (user_version === 0) {
      this.db.transaction(() => {
        this.db.exec(ESQUEMA)
        this.db.exec(`PRAGMA user_version = ${VERSAO}`)
      })()
    } else if (user_version > VERSAO) {
      throw new Error(`orquestra.db é da versão ${user_version}, mais nova que este servidor (${VERSAO})`)
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

  comentar(id: number, autor: string, texto: string, agora = new Date()): Registro {
    const limpo = texto.trim().slice(0, 20_000)
    if (!limpo) throw new Error("comentário vazio")
    const em = agora.toISOString()
    return this.db.transaction(() => {
      this.exigir(id)
      this.registrar(id, "comentario", autor, limpo, em)
      this.db.query("UPDATE tarefas SET atualizada_em = ? WHERE id = ?").run(em, id)
      return this.db.query("SELECT * FROM registros WHERE tarefa = ? ORDER BY id DESC LIMIT 1").get(id) as Registro
    })()
  }
}
