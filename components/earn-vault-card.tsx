"use client"

import { useState } from "react"
import { parseUnits, formatUnits } from "ethers"
import { useWallet } from "@/components/wallet-provider"
import { useTx } from "@/components/use-tx"
import { Card, CardHeader, Stat, Button, Field } from "@/components/ui-bits"
import { fmtUsdc } from "@/lib/format"
import { ADDRESSES } from "@/lib/contracts"
import { PiggyBank, ArrowDownToLine, ArrowUpFromLine } from "lucide-react"

export function EarnVaultCard() {
  const { contracts, address, balances } = useWallet()
  const { run, pending } = useTx()
  const [depositAmt, setDepositAmt] = useState("")
  const [withdrawAmt, setWithdrawAmt] = useState("")

  const disabled = !contracts || !address

  async function onDeposit() {
    if (!contracts || !address || !depositAmt) return
    const amt = parseUnits(depositAmt, 6)
    if (amt <= 0n) return

    const allowance: bigint = await contracts.usdc.allowance(address, ADDRESSES.vault)
    if (allowance < amt) {
      const ok = await run(`Approve ${depositAmt} USDC.e`, () =>
        contracts.usdc.approve(ADDRESSES.vault, amt),
      )
      if (!ok) return
    }
    await run(`Deposit ${depositAmt} USDC.e`, () => contracts.vault.deposit(amt, address), {
      onDone: () => setDepositAmt(""),
    })
  }

  async function onWithdraw() {
    if (!contracts || !address || !withdrawAmt) return
    const amt = parseUnits(withdrawAmt, 6)
    if (amt <= 0n) return
    await run(`Withdraw ${withdrawAmt} USDC.e`, () =>
      contracts.vault.withdraw(amt, address, address),
    { onDone: () => setWithdrawAmt("") })
  }

  return (
    <Card>
      <CardHeader
        icon={<PiggyBank className="size-4" aria-hidden />}
        title="Earn — dUSDC Vault"
        subtitle="Deposit USDC.e to receive yield-bearing dUSDC shares. This liquidity is what borrowers draw against."
      />

      <div className="mb-5 grid grid-cols-2 gap-3">
        <Stat label="Your dUSDC" value={fmtUsdc(balances.shares)} tone="primary" />
        <Stat label="Redeemable" value={`$${fmtUsdc(balances.shareValue)}`} tone="positive" />
      </div>

      <div className="space-y-4">
        <div>
          <label className="mb-1.5 block text-xs font-medium text-muted">Deposit</label>
          <div className="flex flex-col gap-2 sm:flex-row">
            <Field
              value={depositAmt}
              onChange={setDepositAmt}
              placeholder="0.00"
              suffix="USDC.e"
              onMax={
                balances.usdc
                  ? () => setDepositAmt(formatUnits(balances.usdc!, 6))
                  : undefined
              }
              disabled={disabled}
            />
            <Button onClick={onDeposit} loading={pending} disabled={disabled || !depositAmt}>
              <ArrowDownToLine className="size-4" aria-hidden />
              Deposit
            </Button>
          </div>
          <p className="mt-1.5 text-[11px] text-muted">
            Wallet balance: <span className="font-mono">{fmtUsdc(balances.usdc)}</span> USDC.e
          </p>
        </div>

        <div className="h-px bg-border" />

        <div>
          <label className="mb-1.5 block text-xs font-medium text-muted">Withdraw</label>
          <div className="flex flex-col gap-2 sm:flex-row">
            <Field
              value={withdrawAmt}
              onChange={setWithdrawAmt}
              placeholder="0.00"
              suffix="USDC.e"
              onMax={
                balances.maxWithdraw
                  ? () => setWithdrawAmt(formatUnits(balances.maxWithdraw!, 6))
                  : undefined
              }
              disabled={disabled}
            />
            <Button
              variant="secondary"
              onClick={onWithdraw}
              loading={pending}
              disabled={disabled || !withdrawAmt}
            >
              <ArrowUpFromLine className="size-4" aria-hidden />
              Withdraw
            </Button>
          </div>
          <p className="mt-1.5 text-[11px] text-muted">
            Instantly available:{" "}
            <span className="font-mono">{fmtUsdc(balances.maxWithdraw)}</span> USDC.e
          </p>
        </div>
      </div>
    </Card>
  )
}
