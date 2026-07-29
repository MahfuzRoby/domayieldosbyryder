// Live Doma Testnet deployment (chain 97476).
// Addresses sourced from broadcast/Deploy.s.sol/97476/run-latest.json

export const DOMA = {
  chainIdHex: "0x17cc4",
  chainIdDec: 97476,
  chainName: "Doma Testnet",
  rpcUrl: "https://rpc-testnet.doma.xyz",
  explorer: "https://explorer-testnet.doma.xyz",
  nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
} as const

export const ADDRESSES = {
  usdc: "0x283BF87BF58339633c231C546aC665946F279E0A",
  vault: "0x66B4739Ccf3Acf66eAe286940878DEE223Cb26fa", // DUSDCVault (ERC-4626 pool)
  domainVault: "0xCDBe72Cd064ACFD2ebA98Cc49479dac3cbcb0FC4", // DomainVault (lending)
  domainNFT: "0xd000000000009E6bEa0bA0c5D964AE98d59ED318", // Doma Ownership Token
} as const

export const ERC20_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function allowance(address,address) view returns (uint256)",
  "function mint(address,uint256)",
] as const

export const VAULT_ABI = [
  "function asset() view returns (address)",
  "function totalAssets() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function convertToAssets(uint256) view returns (uint256)",
  "function convertToShares(uint256) view returns (uint256)",
  "function maxWithdraw(address) view returns (uint256)",
  "function deposit(uint256,address) returns (uint256)",
  "function withdraw(uint256,address,address) returns (uint256)",
] as const

export const DOMAIN_VAULT_ABI = [
  "function domainNFT() view returns (address)",
  "function loanToValueBps() view returns (uint256)",
  "function liquidationThresholdBps() view returns (uint256)",
  "function positions(uint256) view returns (address borrower, uint256 principal, uint256 accruedInterest, uint256 lastAccrualTimestamp, bool active)",
  "function debtOf(uint256) view returns (uint256)",
  "function borrowRateBps() view returns (uint256)",
  "function collateralValue(uint256) view returns (uint256)",
  "function healthFactorBps(uint256) view returns (uint256)",
  "function depositCollateral(uint256)",
  "function borrow(uint256,uint256)",
  "function repay(uint256,uint256)",
  "function withdrawCollateral(uint256)",
  "function liquidate(uint256)",
] as const

export const NFT_ABI = [
  "function ownerOf(uint256) view returns (address)",
  "function approve(address,uint256)",
  "function getApproved(uint256) view returns (address)",
  "function expirationOf(uint256) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function tokenOfOwnerByIndex(address,uint256) view returns (uint256)",
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
] as const
