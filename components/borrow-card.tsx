"use client"

import { useState, useCallback } from "react"
import { parseUnits } from "ethers"
import { useWallet } from "@/components/wallet-provider"
import { useTx } from "@/components/use-tx"
import { Card, CardHeader, Stat, Button, Field } from "@/components/ui-bits"
import { fmtUsdc, fmtUsd18, errMsg } from "@/lib/format"
import { ADDRESSES } from "@/lib/contracts"
import { Landmark, Search, PackagePlus, HandCoins, Undo2, PackageMinus, Zap } from "lucide-react"

type Position = {
  borrower: string
  debt: bigint
  active: boolean
  collateral: bigint // 1e18 USD
  healthBps: bigint
  expiry: bigint
}

const MAX_UINT = (1n << 256n) - 1n

export function BorrowCard() {
  const { contracts, address, pushLog } = useWallet()
  const { run, pending } = useTx()

  const [tokenId, setTokenId] = useState("")
  const [borrowAmt, setBorrowAmt] = useState("")
  const [repayAmt, setRepayAmt] = useState("")
  const [pos, setPos] = useState<Position | null>(null)
  const [loading, setLoading] = useState(false)

  const disabled = !contracts || !address

  const loadPosition = useCallback(async () => {
    if (!contracts || !tokenId) return
    setLoading(true)
    try {
      const [p, collat, hf] = await Promise.all([
        contracts.domainVault.positions(tokenId),
        contracts.domainVault.collateralValue(tokenId),
        contracts.domainVault.healthFactorBps(tokenId),
      ])
      let expiry = 0n
      try {
        expiry = await contracts.nft.expirationOf(tokenId)
      } catch {
        /* NFT may not expose expiration for this id */
      }
      setPos({
        borrower: p.borrower ?? p[0],
        debt: p.debt ?? p[1],
        active: p.active ?? p[2],
        collateral: collat,
        healthBps: hf,
        expiry,
      })
      pushLog(`Loaded domain #${tokenId}.`, "info")
    } catch (e) {
      pushLog(`Could not load domain #${tokenId}: ${errMsg(e)}`, "error")
      setPos(null)
    } finally {
      setLoading(false)
    }
  }, [contracts, tokenId, pushLog])

  async function onDepositCollateral() {
    if (!contracts || !tokenId) return
    const approved: string = await contracts.nft.getApproved(tokenId).catch(() => "")
    if (approved.toLowerCase() !== ADDRESSES.domainVault.toLowerCase()) {
      const ok = await run(`Approve domain #${tokenId}`, () =>
        contracts.nft.approve(ADDRESSES.domainVault, tokenId),
      )
      if (!ok) return
    }
    await run(`Deposit domain #${tokenId} as collateral`, () =>
      contracts.domainVault.depositCollateral(tokenId),
    { onDone: loadPosition })
  }

  async function onBorrow() {
    if (!contracts || !tokenId || !borrowAmt) return
    const amt = parseUnits(borrowAmt, 6)
    await run(`Borrow ${borrowAmt} USDC.e`, () => contracts.domainVault.borrow(tokenId, amt), {
      onDone: () => {
        setBorrowAmt("")
        return loadPosition()
      },
    })
  }

  async function onRepay() {
    if (!contracts || !address || !tokenId || !repayAmt) return
    const amt = parseUnits(repayAmt, 6)
    const allowance: bigint = await contracts.usdc.allowance(address, ADDRESSES.domainVault)
    if (allowance < amt) {
      const ok = await run(`Approve ${repayAmt} USDC.e`, () =>
        contracts.usdc.approve(ADDRESSES.domainVault, amt),
      )
      if (!ok) return
    }
    await run(`Repay ${repayAmt} USDC.e`, () => contracts.domainVault.repay(tokenId, amt), {
      onDone: () => {
        setRepayAmt("")
        return loadPosition()
      },
    })
  }

  async function onWithdrawCollateral() {
    if (!contracts || !tokenId) return
    await run(`Withdraw domain #${tokenId}`, () =>
      contracts.domainVault.withdrawCollateral(tokenId),
    { onDone: loadPosition })
  }

  async function onLiquidate() {
    if (!contracts || !address || !tokenId || !pos) return
    if (pos.debt > 0n) {
      const allowance: bigint = await contracts.usdc.allowance(address, ADDRESSES.domainVault)
      if (allowance < pos.debt) {
        const ok = await run("Approve debt repayment", () =>
          contracts.usdc.approve(ADDRESSES.domainVault, pos.debt),
        )
        if (!ok) return
      }
    }
    await run(`Liquidate domain #${tokenId}`, () => contracts.domainVault.liquidate(tokenId), {
      onDone: loadPosition,
    })
  }

  const hasDebt = pos && pos.debt > 0n
  const healthy = pos ? pos.healthBps >= 10_000n || pos.healthBps === MAX_UINT : false
  const noDebt = pos ? pos.debt === 0n : true

  function healthDisplay() {
    if (!pos || pos.debt === 0n) return { text: "No debt", tone: "positive" as const }
    if (pos.healthBps === MAX_UINT) return { text: "∞", tone: "positive" as const }
    const pct = Number(pos.healthBps) / 100
    const tone = pct < 100 ? "negative" : pct < 130 ? "warning" : "positive"
    return { text: `${pct.toFixed(0)}%`, tone: tone as "negative" | "warning" | "positive" }
  }
  const health = healthDisplay()

  return (
    <Card>
      <CardHeader
        icon={<Landmark className="size-4" aria-hidden />}
        title="Borrow — Domain Collateral"
        subtitle="Lock a tokenized Doma domain (Ownership Token ID) as collateral, then borrow USDC.e against its appraised value."
      />

      <div className="mb-4 flex flex-col gap-2 sm:flex-row">
        <Field
          value={tokenId}
          onChange={setTokenId}
          placeholder="Domain Token ID"
          disabled={disabled}
        />
        <Button
          variant="secondary"
          onClick={loadPosition}
          loading={loading}
          disabled={disabled || !tokenId}
        >
          <Search className="size-4" aria-hidden />
          Load
        </Button>
      </div>

      {pos ? (
        <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Stat label="Collateral" value={pos.collateral > 0n ? `$${fmtUsd18(pos.collateral)}` : "No price"} />
          <Stat label="Debt" value={`${fmtUsdc(pos.debt)}`} tone={hasDebt ? "warning" : "default"} />
          <Stat label="Health" value={health.text} tone={health.tone} />
          <Stat
            label="Status"
            value={pos.active ? "Active" : "Inactive"}
            tone={pos.active ? "primary" : "default"}
            mono={false}
          />
        </div>
      ) : (
        <div className="mb-5 rounded-xl border border-dashed border-border bg-input/50 px-4 py-6 text-center text-[13px] text-muted">
          Enter a domain token ID and press Load to view its position.
        </div>
      )}

      <div className="space-y-4">
        <Button
          variant="secondary"
          fullWidth
          onClick={onDepositCollateral}
          loading={pending}
          disabled={disabled || !tokenId}
        >
          <PackagePlus className="size-4" aria-hidden />
          Approve &amp; Deposit Domain
        </Button>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-2">
            <Field
              value={borrowAmt}
              onChange={setBorrowAmt}
              placeholder="Borrow amount"
              suffix="USDC.e"
              disabled={disabled}
            />
            <Button onClick={onBorrow} loading={pending} disabled={disabled || !borrowAmt}>
              <HandCoins className="size-4" aria-hidden />
              Borrow
            </Button>
          </div>
          <div className="flex flex-col gap-2">
            <Field
              value={repayAmt}
              onChange={setRepayAmt}
              placeholder="Repay amount"
              suffix="USDC.e"
              disabled={disabled}
            />
            <Button
              variant="secondary"
              onClick={onRepay}
              loading={pending}
              disabled={disabled || !repayAmt}
            >
              <Undo2 className="size-4" aria-hidden />
              Approve &amp; Repay
            </Button>
          </div>
        </div>

        <div className="h-px bg-border" />

        <div className="grid gap-3 sm:grid-cols-2">
          <Button
            variant="secondary"
            onClick={onWithdrawCollateral}
            loading={pending}
            disabled={disabled || !tokenId || !noDebt}
            title={!noDebt ? "Repay all debt before withdrawing" : undefined}
          >
            <PackageMinus className="size-4" aria-hidden />
            Withdraw Domain
          </Button>
          <Button
            variant="danger"
            onClick={onLiquidate}
            loading={pending}
            disabled={disabled || !tokenId || (!!pos && healthy && noDebt)}
            title={pos && healthy ? "Position is healthy" : undefined}
          >
            <Zap className="size-4" aria-hidden />
            Liquidate
          </Button>
        </div>
        <p className="text-[11px] leading-relaxed text-muted">
          Withdrawing requires zero outstanding debt. Liquidation repays a position&apos;s debt
          in exchange for the collateral domain — only possible when the position is unhealthy or
          near expiry.
        </p>
      </div>
    </Card>
  )
}
