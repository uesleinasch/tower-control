const INICIO = String.raw`(?:^|[;&|(]\s*|\bsudo\s+)`
const emPosicaoDeComando = (nomes: string) => new RegExp(`${INICIO}(?:${nomes})\\b`)

const SENSIVEIS: RegExp[] = [
  /\bsudo\b/,
  /\brm\s+(-\w+\s+)*-\w*[rR]/,
  emPosicaoDeComando("mkfs(?:\\.\\w+)?|fdisk|parted|wipefs"),
  /\bdd\b[^|;&]*\bof=/,
  emPosicaoDeComando("shutdown|reboot|poweroff|halt"),
  /\bgit\s+push\b/,
  /\bgit\s+reset\s+--hard\b/,
  /\bgit\s+clean\s+-\w*f/,
  /\bgit\s+branch\s+-D\b/,
  /\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(ba|z)?sh\b/,
  emPosicaoDeComando("kill|pkill|killall"),
  /\bsystemctl\s+(--user\s+)?(stop|disable|mask|kill)\b/,
  /\bch(mod|own)\s+-R\b/,
  /\b(apt|apt-get|dpkg|snap)\s+(remove|purge|-r|-P)\b/,
  /\bdocker\s+(rm|rmi|system\s+prune|volume\s+rm)\b/,
  />\s*\/dev\/(sd|nvme|disk)/,
  /:\(\)\s*\{/,
]

export function exigeAprovacaoSempre(comando: string): boolean {
  return SENSIVEIS.some((padrao) => padrao.test(comando))
}
