// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../libraries/LibVault.sol";
import "../interfaces/IVault.sol";

// In order to be compatible with the front-end call before the release,
// temporary use, front-end all updated, this Facet can be removed.
contract TransitionFacet {
    struct Token {
        address tokenAddress;
        uint16 weight;
        uint16 feeBasisPoints;
        uint16 taxBasisPoints;
        bool stable;
        bool dynamicFee;
    }

    function tokens() external view returns (Token[] memory _tokens) {
        LibVault.VaultStorage storage vs = LibVault.vaultStorage();
        _tokens = new Token[](vs.tokenAddresses.length);
        for (uint256 i; i < vs.tokenAddresses.length; i++) {
            LibVault.AvailableToken memory at = LibVault.getTokenByAddress(vs.tokenAddresses[i]);
            _tokens[i] = Token(
                at.tokenAddress, at.weight, at.feeBasisPoints,
                at.taxBasisPoints, at.stable, at.dynamicFee
            );
        }
    }

    function totalCexValue() external view returns (IVault.LpItem[] memory lpItems) {
        LibVault.VaultStorage storage vs = LibVault.vaultStorage();
        address[] storage tokenAddresses = vs.tokenAddresses;
        lpItems = new IVault.LpItem[](tokenAddresses.length);
        for (uint256 i; i < tokenAddresses.length; i++) {
            LibVault.AvailableToken storage at = vs.tokens[tokenAddresses[i]];
            lpItems[i] = _itemValue(at, vs.treasury[tokenAddresses[i]]);
        }
    }

    function _itemValue(LibVault.AvailableToken storage at, uint256 tokenValue) private view returns (IVault.LpItem memory lpItem) {
        address tokenAddress = at.tokenAddress;
        uint256 price = LibPriceFacade.getPrice(tokenAddress);
        uint256 valueUsd = price * tokenValue * 1e10 / (10 ** at.decimals);
        lpItem = IVault.LpItem(
            tokenAddress, int256(tokenValue), at.decimals, int256(valueUsd),
            at.weight, at.feeBasisPoints, at.taxBasisPoints, at.dynamicFee
        );
    }
}
