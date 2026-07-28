"use client"

import { useWallet } from "@/components/wallet-provider"
import { Button } from "@/components/ui-bits"
import { shortAddr } from "@/lib/format"
import { DOMA } from "@/lib/contracts"
import { Layers, Wallet, AlertTriangle, LogOut } from "lucide-react"

export function SiteHeader() {
  const { address, isCorrectChain, chainId, connecting, connect, disconnect, switchNetwork } =
    useWallet()

  return (
    <header className="sticky top-0 z-30 border-b border-border bg-background/80 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
        <div className="flex items-center gap-2.5">
          <div className="flex size-9 items-center justify-center rounded-lg bg-primary text-primary-foreground">
            <Layers className="size-5" aria-hidden />
          </div>
          <div className="leading-tight">
            <div className="text-[15px] font-bold tracking-tight">
              Doma<span className="text-primary">yield</span>
            </div>
            <div className="text-[11px] text-muted">Domain-collateralized lending</div>
          </div>
        </div>

        <div className="flex items-center gap-2.5">
          {address ? (
            <>
              {isCorrectChain ? (
                <span className="hidden items-center gap-1.5 rounded-full border border-border bg-card px-3 py-1.5 text-xs text-muted sm:inline-flex">
                  <span className="size-1.5 rounded-full bg-positive pulse-dot" aria-hidden />
                  {DOMA.chainName}
                </span>
              ) : (
                <button
                  onClick={switchNetwork}
                  className="inline-flex items-center gap-1.5 rounded-full border border-warning/40 bg-warning/10 px-3 py-1.5 text-xs font-medium text-warning"
                >
                  <AlertTriangle className="size-3.5" aria-hidden />
                  Wrong network — switch
                </button>
              )}
              <span className="inline-flex items-center gap-2 rounded-lg border border-border bg-card px-3 py-2 font-mono text-xs">
                <Wallet className="size-3.5 text-primary" aria-hidden />
                {shortAddr(address)}
              </span>
              <Button variant="secondary" onClick={disconnect} aria-label="Disconnect wallet">
                <LogOut className="size-4" aria-hidden />
                <span className="sr-only sm:not-sr-only">Disconnect</span>
              </Button>
            </>
          ) : (
            <Button onClick={connect} loading={connecting}>
              <Wallet className="size-4" aria-hidden />
              {connecting ? "Connecting" : "Connect Wallet"}
            </Button>
          )}
        </div>
      </div>
    </header>
  )
}
