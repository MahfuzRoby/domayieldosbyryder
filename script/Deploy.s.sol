// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DUSDCVault} from "../contracts/DUSDCVault.sol";
import {DomainVault} from "../contracts/DomainVault.sol";

/// @notice Minimal mintable test stablecoin, used only if no real USDC.e
/// address is provided via USDC_ADDRESS in .env.
contract DeployMockUSDCe is ERC20 {
    constructor() ERC20("Bridged USDC (test)", "USDC.e") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address ownershipToken = vm.envAddress("DOMA_OWNERSHIP_TOKEN");
        address usdcAddress = vm.envOr("USDC_ADDRESS", address(0));

        require(ownershipToken != address(0), "DOMA_OWNERSHIP_TOKEN not set in .env");

        console.log("Deploying as:", deployer);
        console.log("Ownership Token:", ownershipToken);

        vm.startBroadcast(deployerKey);

        // Deploy or reuse the USDC.e asset.
        if (usdcAddress == address(0)) {
            DeployMockUSDCe mock = new DeployMockUSDCe();
            usdcAddress = address(mock);
            console.log("No USDC_ADDRESS set -- deployed MockUSDCe at:", usdcAddress);

            // Mint the deployer some test liquidity to seed the pool with, for demo purposes.
            mock.mint(deployer, 1_000_000 * 1e6);
        } else {
            console.log("Using existing USDC.e at:", usdcAddress);
        }

        // Deploy the lending pool.
        DUSDCVault pool = new DUSDCVault(
            IERC20(usdcAddress),
            "Doma USDC Vault",
            "dUSDC",
            deployer
        );
        console.log("DUSDCVault deployed at:", address(pool));

        // Deploy the domain-collateralized borrowing vault, pointed at the pool.
        DomainVault domainVault = new DomainVault(
            ownershipToken,
            payable(address(pool)),
            deployer
        );
        console.log("DomainVault deployed at:", address(domainVault));

        // Wire DomainVault as an allocator so it can draw/return liquidity from the pool.
        pool.grantRole(pool.ALLOCATOR_ROLE(), address(domainVault));
        console.log("Granted ALLOCATOR_ROLE to DomainVault");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("USDC.e:      ", usdcAddress);
        console.log("DUSDCVault:  ", address(pool));
        console.log("DomainVault: ", address(domainVault));
    }
}
