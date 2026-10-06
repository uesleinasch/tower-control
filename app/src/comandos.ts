const SEPARADOR = String.raw`[;&|(\n\`{]`
const PREFIXO = String.raw`(?:(?:sudo|nohup|time|exec|nice|xargs|env|command|timeout)(?:\s+(?:-\S+|\w+=\S*|\d+\w*))*\s+)*`
const INICIO = String.raw`(?:^|${SEPARADOR})\s*${PREFIXO}`
const emPosicaoDeComando = (nomes: string) => new RegExp(`${INICIO}(?:${nomes})\\b`)

const GIT = String.raw`\bgit(?:\s+(?:-[Cc]\s+\S+|--?[\w-]+(?:=\S+)?))*\s+`
const git = (subcomando: string) => new RegExp(`${GIT}${subcomando}`)

const SENSIVEIS: RegExp[] = [
  /\bsudo\b/,
  /\brm\b[^;&|\n]*\s(?:-\w*[rR]\w*|--recursive)\b/,
  emPosicaoDeComando("mkfs(?:\\.\\w+)?|fdisk|parted|wipefs"),
  /\bdd\b[^|;&]*\bof=/,
  emPosicaoDeComando("shutdown|reboot|poweroff|halt"),
  git(String.raw`push\b`),
  git(String.raw`reset\s+--hard\b`),
  git(String.raw`clean\s+-\w*f`),
  git(String.raw`branch\s+-D\b`),
  /\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(ba|z)?sh\b/,
  emPosicaoDeComando("kill|pkill|killall"),
  /\bsystemctl\s+(--user\s+)?(stop|disable|mask|kill)\b/,
  /\bch(?:mod|own|grp)\b[^;&|\n]*\s(?:-\w*R\w*|--recursive)\b/,
  /\bfind\b[^;&|\n]*\s-delete\b/,
  /\b(apt|apt-get|dpkg|snap)\s+(remove|purge|-r|-P)\b/,
  /\bdocker\s+(rm|rmi|system\s+prune|volume\s+rm)\b/,
  />\s*\/dev\/(sd|nvme|disk)/,
  /:\(\)\s*\{/,
]

export function exigeAprovacaoSempre(comando: string): boolean {
  return SENSIVEIS.some((padrao) => padrao.test(comando))
}
