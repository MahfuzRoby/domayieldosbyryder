# dUSDC Vault — Idle-USDC.e Yield Layer for Doma Traders

`DUSDCVault.sol` is an ERC-4626 vault deployed **on Doma chain**. Traders deposit
USDC.e and receive `dUSDC` shares, whose value grows as yield is earned on Base via
a Morpho vault. `dUSDC` is designed to be usable directly as a Doma Marketplace
payment currency, so sellers can receive it (and keep earning yield) without a
separate withdrawal step.

This repo currently contains **only the vault contract** — the piece explicitly
requested first. See "Not built yet" below for what's still needed to make the
full protocol work end-to-end.

## Why the design looks like this

Doma chain doesn't have Aave/Morpho deployed on it; those live on Base (Doma's
current bridging partner). So this vault's shares live on one chain while a
portion of the backing assets live on another. That split creates two problems
the contract deliberately isolates and constrains:

1. **How does the vault know what the Base-side position is worth?**
   `remoteReportedValue` is written by `NAV_REPORTER_ROLE` (expect a multisig or
   an oracle/relayer contract — not a single EOA in production), gated by:
   - a **timelock** (`navReportDelay`, default 6h) before a report takes effect, and
   - a **max deviation cap** (`maxNavDeviationBps`, default 5%) per report.

   This bounds — but does not eliminate — the trust placed in the reporter. See
   "Upgrade path" below for removing this trust assumption later.

2. **What happens when someone wants to redeem more than the local USDC.e
   balance covers?** `withdraw`/`redeem` only succeed instantly up to
   `localLiquidity()`. Beyond that, depositors call `requestRedeem`, which
   escrows (not burns) their shares — so they keep earning yield while queued —
   and an `ALLOCATOR_ROLE` keeper later calls `fulfillQueuedRedemptions` once
   it's bridged enough back.

## Roles

| Role | Expected holder | Powers |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Protocol multisig / timelock | Grant roles, tune buffer/NAV params, set deposit cap, rescue stray tokens |
| `ALLOCATOR_ROLE` | Keeper automation (see "Not built yet") | `allocate()` funds out, `reclaim()` + `fulfillQueuedRedemptions()` funds back in |
| `NAV_REPORTER_ROLE` | Multisig or oracle/relayer contract | `reportRemoteValue()` |
| `GUARDIAN_ROLE` | Incident-response multisig | `pause()` / `unpause()` |

## Not built yet (next pieces, in the order I'd build them)

1. **Off-chain keeper (TypeScript)** — decides how much idle USDC.e to sweep
   toward `targetBufferBps`, calls `allocate()`, bridges to Base, deposits into
   the chosen Morpho vault, and later reverses the flow to fund
   `fulfillQueuedRedemptions()`. This is a natural extension of the
   `doma-sdk` package built earlier (reuses `resolveNetworkConfig`,
   `DomaApiClient`, viem clients).
2. **NAV reporter** — starts as a simple signed-message relayer posting into
   `reportRemoteValue()`; the "Upgrade path" below describes replacing it.
3. **Marketplace integration** — construct Doma Orderbook listings/offers
   denominated in the `dUSDC` token address (via `orderbookApiClient`/the
   official Orderbook SDK from `doma-sdk`).
4. **Base-side adapter** — holds the Morpho vault position, and (once you
   move past the simple relayer) emits the verified cross-chain value message.

## Upgrade path for NAV reporting

v1 as shipped here trusts `NAV_REPORTER_ROLE`, bounded by the timelock +
deviation cap. To remove that trust assumption later without changing the
public interface: replace whatever address holds `NAV_REPORTER_ROLE` with a
contract that only accepts a verified cross-chain message (e.g. Chainlink CCIP
or a LayerZero receiver reading the Morpho vault's `convertToAssets` on Base)
and calls `reportRemoteValue()` itself. `DUSDCVault` doesn't need to change.

## Testing

`test/DUSDCVault.t.sol` is a Foundry test suite covering: deposit/instant
withdraw, the buffer-floor check on `allocate`, allocate/reclaim accounting,
NAV timelock + deviation cap, and the async redemption queue.

**I was not able to actually run these tests or compile the contract** in the
sandbox this was generated in (no network access to fetch `forge-std` or
`openzeppelin-contracts`). Before deploying or relying on this:

```bash
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts
forge test -vvv
```

I've manually traced through the test expectations against the contract logic
(buffer math, NAV deviation math, share accounting), but treat that as a
starting point for review, not a substitute for actually running it — and get
this professionally audited before it touches real funds, given it holds
user deposits and has bridging/allocator trust assumptions baked in.
