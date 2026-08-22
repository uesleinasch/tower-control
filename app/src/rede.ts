import { networkInterfaces } from "node:os"

function ehTailscale(endereco: string): boolean {
  const octetos = endereco.split(".").map(Number)
  return octetos[0] === 100 && octetos[1] >= 64 && octetos[1] <= 127
}

const VIRTUAIS = /^(docker|br-|veth|virbr|lxc|lxd)/

export function enderecos(): { lan?: string; tailscale?: string } {
  const resultado: { lan?: string; tailscale?: string } = {}
  let lanReserva: string | undefined
  for (const [nome, lista] of Object.entries(networkInterfaces())) {
    for (const iface of lista ?? []) {
      if (iface.family !== "IPv4" || iface.internal) continue
      if (ehTailscale(iface.address)) {
        resultado.tailscale ??= iface.address
      } else if (VIRTUAIS.test(nome)) {
        lanReserva ??= iface.address
      } else {
        resultado.lan ??= iface.address
      }
    }
  }
  resultado.lan ??= lanReserva
  return resultado
}
