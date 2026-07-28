"use client"

import { useState, useCallback } from "react"
import { useWallet } from "@/components/wallet-provider"
import { errMsg } from "@/lib/format"

/**
 * Runs a sequence of on-chain steps with activity-log feedback.
 * Each step returns a tx-like object exposing `.wait()`, or null to skip.
 */
export function useTx() {
  const { pushLog, updateLog, refresh } = useWallet()
  const [pending, setPending] = useState(false)

  const run = useCallback(
    async (
      label: string,
      fn: () => Promise<any>,
      opts?: { onDone?: () => void | Promise<void> },
    ) => {
      const id = pushLog(`${label}…`, "pending")
      setPending(true)
      try {
        const tx = await fn()
        if (tx && typeof tx.wait === "function") {
          updateLog(id, `${label} — awaiting confirmation…`, "pending")
          await tx.wait()
        }
        updateLog(id, `${label} — confirmed.`, "success")
        await refresh()
        await opts?.onDone?.()
        return true
      } catch (e) {
        updateLog(id, `${label} failed: ${errMsg(e)}`, "error")
        return false
      } finally {
        setPending(false)
      }
    },
    [pushLog, updateLog, refresh],
  )

  return { run, pending }
}
