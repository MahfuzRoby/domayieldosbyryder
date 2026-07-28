"use client"

import { WalletProvider, useWallet } from "@/components/wallet-provider"
import { SiteHeader } from "@/components/site-header"
import { Overview } from "@/components/overview"
import { FaucetCard } from "@/components/faucet-card"
import { EarnVaultCard } from "@/components/earn-vault-card"
import { BorrowCard } from "@/components/borrow-card"
import { ActivityLog } from "@/components/activity-log"
import { Button } from "@/components/ui-bits"
import { ADDRESSES, DOMA } from "@/lib/contracts"
import { Wallet, AlertTriangle } from "lucide-react"

function ConnectBanner() {
  const { address, isCorrectChain, connect, connecting, switchNetwork } = useWallet()
  if (address && isCorrectChain) return null

  return (
    <div className="flex flex-col items-center gap-3 rounded-[var(--radius)] border border-primary/25 bg-primary-dim/20 px-6 py-5 text-center sm:flex-row sm:justify-between sm:text-left">
      <div className="flex items-center gap-3">
        {address && !isCorrectChain ? (
          <AlertTriangle className="size-5 shrink-0 text-warning" aria-hidden />
        ) : (
          <Wallet className="size-5 shrink-0 text-primary" aria-hidden />
        )}
        <p className="text-sm text-foreground">
          {address && !isCorrectChain
            ? `You're on the wrong network. Switch to ${DOMA.chainName} to use the protocol.`
            : "Connect your wallet to deposit, borrow, and manage positions."}
        </p>
      </div>
      {address && !isCorrectChain ? (
        <Button onClick={switchNetwork}>Switch Network</Button>
      ) : (
        <Button onClick={connect} loading={connecting}>
          <Wallet className="size-4" aria-hidden />
          Connect Wallet
        </Button>
      )}
    </div>
  )
}

function Dashboard() {
  return (
    <div className="min-h-dvh">
      <SiteHeader />
      <main className="mx-auto max-w-6xl space-y-5 px-4 py-6 sm:px-6 sm:py-8">
        <Overview />
        <ConnectBanner />
        <FaucetCard />
        <div className="grid gap-5 lg:grid-cols-2">
          <EarnVaultCard />
          <BorrowCard />
        </div>
        <ActivityLog />
        <ContractFooter />
      </main>
    </div>
  )
}

function ContractFooter() {
  const rows = [
    { label: "dUSDC Vault", addr: ADDRESSES.vault },
    { label: "Domain Vault", addr: ADDRESSES.domainVault },
    { label: "USDC.e", addr: ADDRESSES.usdc },
    { label: "Domain NFT", addr: ADDRESSES.domainNFT },
  ]
  return (
    <footer className="rounded-[var(--radius)] border border-border bg-card p-5 sm:p-6">
      <h2 className="mb-4 text-[13px] font-semibold uppercase tracking-[0.08em] text-muted">
        Deployed Contracts · {DOMA.chainName}
      </h2>
      <div className="grid gap-2 sm:grid-cols-2">
        {rows.map((r) => (
          <a
            key={r.label}
            href={`${DOMA.explorer}/address/${r.addr}`}
            target="_blank"
            rel="noreferrer noopener"
            className="flex items-center justify-between gap-3 rounded-lg border border-border bg-input px-3 py-2.5 text-sm transition-colors hover:border-primary/40"
          >
            <span className="font-medium text-foreground">{r.label}</span>
            <span className="truncate font-mono text-xs text-muted">
              {r.addr.slice(0, 8)}…{r.addr.slice(-6)}
            </span>
          </a>
        ))}
      </div>
      <p className="mt-4 text-[11px] leading-relaxed text-muted">
        Testnet software, unaudited. Do not use with real funds. Contracts hold user deposits and
        carry bridging / oracle trust assumptions described in the protocol README.
      </p>
    </footer>
  )
}

export default function Page() {
  return (
    <WalletProvider>
      <Dashboard />
    </WalletProvider>
  )
}
