// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Mirrors the non-standard methods Doma adds on top of its ERC-721
/// "Domain Ownership Token" (see docs.doma.xyz). Every tokenized domain on
/// Doma exposes these two extra views:
///   - expirationOf: domain's expiry timestamp. After expiry the token
///     becomes non-transferable until renewed.
///   - registrarOf: IANA id of the sponsoring registrar.
interface IDomainOwnershipToken is IERC721 {
    function expirationOf(uint256 tokenId) external view returns (uint256);
    function registrarOf(uint256 tokenId) external view returns (uint256);
}
