import { formatUnits } from "ethers"

export function fmtUsdc(x: bigint | undefined | null, maxFrac = 2): string {
  if (x === undefined || x === null) return "-"
  return Number(formatUnits(x, 6)).toLocaleString(undefined, {
    maximumFractionDigits: maxFrac,
  })
}

// Collateral values are 1e18-scaled USD in the contract.
export function fmtUsd18(x: bigint | undefined | null, maxFrac = 2): string {
  if (x === undefined || x === null) return "-"
  return Number(formatUnits(x, 18)).toLocaleString(undefined, {
    maximumFractionDigits: maxFrac,
  })
}

export function fmtEth(x: bigint | undefined | null): string {
  if (x === undefined || x === null) return "-"
  return Number(formatUnits(x, 18)).toFixed(4)
}

export function shortAddr(a?: string | null): string {
  if (!a) return "-"
  return a.slice(0, 6) + "…" + a.slice(-4)
}

export function errMsg(e: any): string {
  return e?.shortMessage || e?.reason || e?.info?.error?.message || e?.message || String(e)
}
