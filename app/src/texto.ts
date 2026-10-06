export function slug(texto: string): string {
  return texto
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60)
}

const doisDigitos = (n: number) => String(n).padStart(2, "0")

export function dataLocal(quando: Date = new Date()): string {
  return `${quando.getFullYear()}-${doisDigitos(quando.getMonth() + 1)}-${doisDigitos(quando.getDate())}`
}

export function dataHoraLocal(quando: Date): string {
  return `${dataLocal(quando)} ${doisDigitos(quando.getHours())}:${doisDigitos(quando.getMinutes())}`
}
