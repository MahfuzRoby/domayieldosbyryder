// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IDomainOwnershipToken} from "../interfaces/IDomainOwnershipToken.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Stand-in for Doma's real Domain Ownership Token, for local testing.
/// On real Doma testnet/mainnet, DomainVault points at the actual Ownership
/// Token contract instead of this mock.
contract MockDomainNFT is ERC721, IDomainOwnershipToken {
    uint256 private _nextId = 1;
    mapping(uint256 => uint256) public expirationOf;

    constructor() ERC721("Doma Domain Ownership Token", "DOMA-NFT") {}

    function mintDomain(address to, uint256 validityDays) external returns (uint256 tokenId) {
        tokenId = _nextId++;
        _safeMint(to, tokenId);
        expirationOf[tokenId] = block.timestamp + (validityDays * 1 days);
    }

    function renew(uint256 tokenId, uint256 extraDays) external {
        expirationOf[tokenId] += extraDays * 1 days;
    }

    function registrarOf(uint256) external pure returns (uint256) {
        return 1234; // dummy IANA id
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            require(expirationOf[tokenId] > block.timestamp, "MockDomainNFT: expired, non-transferable");
        }
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
