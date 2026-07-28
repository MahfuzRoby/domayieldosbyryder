"use client"

import { useWallet } from "@/components/wallet-provider"
import { fmtUsdc } from "@/lib/format"
import { TrendingUp, Vault, Coins, ArrowUpRight } from "lucide-react"

export function Overview() {
  const { balances, address, isCorrectChain } = useWallet()
  const connected = !!address && isCorrectChain

  return (
    <section className="relative overflow-hidden rounded-[var(--radius)] border border-border bg-card">
      <div className="grid-backdrop absolute inset-0 opacity-60" aria-hidden />
      <div className="relative p-6 sm:p-8">
        <div className="flex items-center gap-2 text-xs font-medium text-primary">
          <span className="inline-flex items-center gap-1.5 rounded-full border border-primary/30 bg-primary-dim/30 px-2.5 py-1">
            <span className="size-1.5 rounded-full bg-primary" aria-hidden />
            Live on Doma Testnet
          </span>
        </div>

        <h1 className="mt-4 max-w-2xl text-balance text-3xl font-bold leading-tight tracking-tight sm:text-4xl">
          Put idle USDC.e to work, or borrow against your{" "}
          <span className="text-primary">tokenized domains</span>.
        </h1>
        <p className="mt-3 max-w-xl text-pretty text-sm leading-relaxed text-muted">
          Domayield is a lending protocol on the Doma chain. Lenders deposit USDC.e into a
          yield-bearing vault; borrowers lock a tokenized Doma domain as collateral and draw
          liquidity against it.
        </p>

        <div className="mt-7 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <HeroStat
            icon={<Vault className="size-4" aria-hidden />}
            label="Pool Liquidity (TVL)"
            value={connected ? `$${fmtUsdc(balances.poolTotal)}` : "—"}
            hint="Total assets in the vault"
          />
          <HeroStat
            icon={<Coins className="size-4" aria-hidden />}
            label="Your Deposit"
            value={connected ? `$${fmtUsdc(balances.shareValue)}` : "—"}
            hint="Redeemable value of your dUSDC"
          />
          <HeroStat
            icon={<TrendingUp className="size-4" aria-hidden />}
            label="Your dUSDC"
            value={connected ? fmtUsdc(balances.shares) : "—"}
            hint="Vault shares held"
          />
          <HeroStat
            icon={<ArrowUpRight className="size-4" aria-hidden />}
            label="Wallet USDC.e"
            value={connected ? fmtUsdc(balances.usdc) : "—"}
            hint="Available to deposit or repay"
          />
        </div>
      </div>
    </section>
  )
}

function HeroStat({
  icon,
  label,
  value,
  hint,
}: {
  icon: React.ReactNode
  label: string
  value: string
  hint: string
}) {
  return (
    <div className="rounded-xl border border-border bg-background/60 p-4">
      <div className="flex items-center gap-2 text-muted">
        <span className="text-primary">{icon}</span>
        <span className="text-[10px] font-medium uppercase tracking-[0.08em]">{label}</span>
      </div>
      <div className="mt-2 font-mono text-xl font-bold text-foreground">{value}</div>
      <div className="mt-0.5 text-[11px] text-muted">{hint}</div>
    </div>
  )
}
