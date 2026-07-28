"use client"

import { parseUnits } from "ethers"
import { useWallet } from "@/components/wallet-provider"
import { useTx } from "@/components/use-tx"
import { Button } from "@/components/ui-bits"
import { fmtEth, fmtUsdc } from "@/lib/format"
import { DOMA } from "@/lib/contracts"
import { Droplets, ExternalLink } from "lucide-react"

export function FaucetCard() {
  const { contracts, address, balances } = useWallet()
  const { run, pending } = useTx()

  async function mint() {
    if (!contracts || !address) return
    await run("Mint 10,000 test USDC.e", () =>
      contracts.usdc.mint(address, parseUnits("10000", 6)),
    )
  }

  return (
    <div className="rounded-[var(--radius)] border border-border bg-card p-5 sm:p-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-start gap-3">
          <div className="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-lg border border-border bg-card-elevated text-primary">
            <Droplets className="size-4" aria-hidden />
          </div>
          <div>
            <h2 className="text-[15px] font-semibold">Testnet Faucet</h2>
            <p className="mt-1 text-[13px] leading-relaxed text-muted">
              Mint mock USDC.e to try the protocol. You&apos;ll also need Doma testnet ETH for gas.
            </p>
            <div className="mt-2 flex flex-wrap gap-x-5 gap-y-1 font-mono text-xs text-muted">
              <span>
                USDC.e: <span className="text-foreground">{fmtUsdc(balances.usdc)}</span>
              </span>
              <span>
                ETH: <span className="text-foreground">{fmtEth(balances.eth)}</span>
              </span>
            </div>
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <a
            href={DOMA.explorer}
            target="_blank"
            rel="noreferrer noopener"
            className="inline-flex items-center gap-1.5 rounded-lg border border-border bg-card-elevated px-3 py-2.5 text-sm font-medium text-foreground hover:bg-border/60"
          >
            Explorer
            <ExternalLink className="size-3.5" aria-hidden />
          </a>
          <Button onClick={mint} loading={pending} disabled={!contracts || !address}>
            <Droplets className="size-4" aria-hidden />
            Mint 10,000
          </Button>
        </div>
      </div>
    </div>
  )
}
