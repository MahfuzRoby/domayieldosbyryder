"use client"

import { useState, useCallback } from "react"
import { useWallet } from "@/components/wallet-provider"

export type OwnedDomain = {
  tokenId: string
  expiry: bigint
}

/**
 * Finds domain Ownership Tokens held by the connected wallet.
 *
 * Strategy:
 *  1. Try the ERC721Enumerable fast path (balanceOf + tokenOfOwnerByIndex).
 *     Works if Doma's Ownership Token happens to support enumeration.
 *  2. If that's unsupported (most custom ERC-721s aren't enumerable),
 *     fall back to scanning historical Transfer(to: address) events on the
 *     NFT contract via the RPC provider, then re-verify current ownership
 *     with ownerOf() for each candidate token (since some may have since
 *     been transferred away again).
 */
export function useOwnedDomains() {
  const { contracts, address, provider, pushLog } = useWallet()
  const [domains, setDomains] = useState<OwnedDomain[]>([])
  const [scanning, setScanning] = useState(false)

  const scan = useCallback(async () => {
    if (!contracts || !address || !provider) return
    setScanning(true)
    try {
      const found: string[] = []

      // --- Fast path: ERC721Enumerable ---
      try {
        const bal: bigint = await contracts.nft.balanceOf(address)
        if (bal > 0n) {
          const calls = []
          for (let i = 0n; i < bal; i++) {
            calls.push(contracts.nft.tokenOfOwnerByIndex(address, i))
          }
          const ids = await Promise.all(calls)
          found.push(...ids.map((id: bigint) => id.toString()))
        }
      } catch {
        // Not enumerable -- fall through to event scanning below.
      }

      // --- Fallback: scan Transfer events, then re-verify ownership ---
      if (found.length === 0) {
        const filter = contracts.nft.filters.Transfer(null, address)
        const events = await contracts.nft.queryFilter(filter, 0, "latest")
        const candidateIds = Array.from(
          new Set(events.map((e: any) => e.args?.tokenId?.toString()).filter(Boolean)),
        )

        // Re-check current ownership -- a candidate may have since moved on.
        const ownershipChecks = await Promise.all(
          candidateIds.map(async (id) => {
            try {
              const owner: string = await contracts.nft.ownerOf(id)
              return owner.toLowerCase() === address.toLowerCase() ? id : null
            } catch {
              return null // token may have been burned
            }
          }),
        )
        found.push(...ownershipChecks.filter((id): id is string => id !== null))
      }

      // Fetch expiry for display, tolerating any that don't resolve.
      const withExpiry = await Promise.all(
        found.map(async (tokenId) => {
          let expiry = 0n
          try {
            expiry = await contracts.nft.expirationOf(tokenId)
          } catch {
            /* ignore */
          }
          return { tokenId, expiry }
        }),
      )

      setDomains(withExpiry)
      pushLog(`Found ${withExpiry.length} domain(s) in your wallet.`, "info")
    } catch (e: any) {
      pushLog(`Domain scan failed: ${e?.shortMessage || e?.message || e}`, "error")
    } finally {
      setScanning(false)
    }
  }, [contracts, address, provider, pushLog])

  return { domains, scanning, scan }
}
