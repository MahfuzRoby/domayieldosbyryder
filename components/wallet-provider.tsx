"use client"

import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  useRef,
  type ReactNode,
} from "react"
import { BrowserProvider, Contract, type Signer } from "ethers"
import {
  DOMA,
  ADDRESSES,
  ERC20_ABI,
  VAULT_ABI,
  DOMAIN_VAULT_ABI,
  NFT_ABI,
} from "@/lib/contracts"

export type LogKind = "info" | "success" | "error" | "pending"
export type LogEntry = { id: number; time: string; kind: LogKind; msg: string }

type Balances = {
  eth?: bigint
  usdc?: bigint
  shares?: bigint // dUSDC shares
  shareValue?: bigint // shares converted to USDC.e
  poolTotal?: bigint
  poolSupply?: bigint
  maxWithdraw?: bigint
  vaultSymbol?: string
}

type Contracts = {
  usdc: Contract
  vault: Contract
  domainVault: Contract
  nft: Contract
}

type WalletCtx = {
  address?: string
  chainId?: number
  isCorrectChain: boolean
  connecting: boolean
  provider?: BrowserProvider
  signer?: Signer
  contracts?: Contracts
  balances: Balances
  log: LogEntry[]
  pushLog: (msg: string, kind?: LogKind) => number
  updateLog: (id: number, msg: string, kind: LogKind) => void
  connect: () => Promise<void>
  disconnect: () => void
  refresh: () => Promise<void>
  switchNetwork: () => Promise<void>
}

const Ctx = createContext<WalletCtx | null>(null)

export function useWallet() {
  const c = useContext(Ctx)
  if (!c) throw new Error("useWallet must be used within WalletProvider")
  return c
}

function getEthereum(): any {
  if (typeof window === "undefined") return null
  return (window as any).ethereum ?? null
}

export function WalletProvider({ children }: { children: ReactNode }) {
  const [address, setAddress] = useState<string>()
  const [chainId, setChainId] = useState<number>()
  const [connecting, setConnecting] = useState(false)
  const [balances, setBalances] = useState<Balances>({})
  const [log, setLog] = useState<LogEntry[]>([])

  const providerRef = useRef<BrowserProvider>()
  const signerRef = useRef<Signer>()
  const contractsRef = useRef<Contracts>()
  const logId = useRef(0)

  const isCorrectChain = chainId === DOMA.chainIdDec

  const pushLog = useCallback((msg: string, kind: LogKind = "info") => {
    const id = ++logId.current
    setLog((prev) =>
      [{ id, time: new Date().toLocaleTimeString(), kind, msg }, ...prev].slice(0, 60),
    )
    return id
  }, [])

  const updateLog = useCallback((id: number, msg: string, kind: LogKind) => {
    setLog((prev) =>
      prev.map((e) => (e.id === id ? { ...e, msg, kind, time: new Date().toLocaleTimeString() } : e)),
    )
  }, [])

  const buildContracts = useCallback(async (signer: Signer): Promise<Contracts> => {
    const usdc = new Contract(ADDRESSES.usdc, ERC20_ABI, signer)
    const vault = new Contract(ADDRESSES.vault, VAULT_ABI, signer)
    const domainVault = new Contract(ADDRESSES.domainVault, DOMAIN_VAULT_ABI, signer)
    let nftAddr = ADDRESSES.domainNFT
    try {
      nftAddr = await domainVault.domainNFT()
    } catch {
      /* fall back to configured address */
    }
    const nft = new Contract(nftAddr, NFT_ABI, signer)
    return { usdc, vault, domainVault, nft }
  }, [])

  const refresh = useCallback(async () => {
    const c = contractsRef.current
    const p = providerRef.current
    if (!c || !p || !address) return
    try {
      const [eth, usdc, shares, poolTotal, poolSupply, maxW] = await Promise.all([
        p.getBalance(address),
        c.usdc.balanceOf(address),
        c.vault.balanceOf(address),
        c.vault.totalAssets(),
        c.vault.totalSupply().catch(() => 0n),
        c.vault.maxWithdraw(address).catch(() => 0n),
      ])
      let shareValue = 0n
      try {
        shareValue = await c.vault.convertToAssets(shares)
      } catch {
        shareValue = shares
      }
      setBalances((b) => ({
        ...b,
        eth,
        usdc,
        shares,
        shareValue,
        poolTotal,
        poolSupply,
        maxWithdraw: maxW,
      }))
    } catch (e) {
      console.log("[v0] refresh error:", (e as any)?.message)
    }
  }, [address])

  const switchNetwork = useCallback(async () => {
    const eth = getEthereum()
    if (!eth) return
    try {
      await eth.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: DOMA.chainIdHex }],
      })
    } catch (err: any) {
      if (err.code === 4902) {
        await eth.request({
          method: "wallet_addEthereumChain",
          params: [
            {
              chainId: DOMA.chainIdHex,
              chainName: DOMA.chainName,
              nativeCurrency: DOMA.nativeCurrency,
              rpcUrls: [DOMA.rpcUrl],
              blockExplorerUrls: [DOMA.explorer],
            },
          ],
        })
      } else {
        throw err
      }
    }
  }, [])

  const connect = useCallback(async () => {
    const eth = getEthereum()
    if (!eth) {
      pushLog("No Ethereum wallet detected. Install MetaMask to continue.", "error")
      return
    }
    setConnecting(true)
    try {
      await eth.request({ method: "eth_requestAccounts" })
      try {
        await switchNetwork()
      } catch {
        /* user may reject; we still surface a network warning via chainId */
      }

      const provider = new BrowserProvider(eth)
      const net = await provider.getNetwork()
      const signer = await provider.getSigner()
      const addr = await signer.getAddress()
      const contracts = await buildContracts(signer)

      providerRef.current = provider
      signerRef.current = signer
      contractsRef.current = contracts

      setChainId(Number(net.chainId))
      setAddress(addr)
      setBalances((b) => ({ ...b, vaultSymbol: "dUSDC" }))
      pushLog(`Wallet connected: ${addr.slice(0, 6)}…${addr.slice(-4)}`, "success")
    } catch (e: any) {
      pushLog("Connection failed: " + (e?.shortMessage || e?.message || e), "error")
    } finally {
      setConnecting(false)
    }
  }, [buildContracts, pushLog, switchNetwork])

  const disconnect = useCallback(() => {
    providerRef.current = undefined
    signerRef.current = undefined
    contractsRef.current = undefined
    setAddress(undefined)
    setChainId(undefined)
    setBalances({})
    pushLog("Wallet disconnected.", "info")
  }, [pushLog])

  // Refresh balances when connected + poll gently.
  useEffect(() => {
    if (!address || !isCorrectChain) return
    refresh()
    const t = setInterval(refresh, 15000)
    return () => clearInterval(t)
  }, [address, isCorrectChain, refresh])

  // React to wallet account / chain changes.
  useEffect(() => {
    const eth = getEthereum()
    if (!eth?.on) return
    const onAccounts = (accs: string[]) => {
      if (!accs.length) disconnect()
      else connect()
    }
    const onChain = (cid: string) => setChainId(Number.parseInt(cid, 16))
    eth.on("accountsChanged", onAccounts)
    eth.on("chainChanged", onChain)
    return () => {
      eth.removeListener?.("accountsChanged", onAccounts)
      eth.removeListener?.("chainChanged", onChain)
    }
  }, [connect, disconnect])

  return (
    <Ctx.Provider
      value={{
        address,
        chainId,
        isCorrectChain,
        connecting,
        provider: providerRef.current,
        signer: signerRef.current,
        contracts: contractsRef.current,
        balances,
        log,
        pushLog,
        updateLog,
        connect,
        disconnect,
        refresh,
        switchNetwork,
      }}
    >
      {children}
    </Ctx.Provider>
  )
}
