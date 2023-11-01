// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Bits.sol";
import "../libraries/LibVault.sol";
import {FeatureSwitches} from "../interfaces/IVault.sol";

// In order to be compatible with the front-end call before the release,
// temporary use, front-end all updated, this Facet can be removed.
contract TransitionFacet {

    using Bits for uint;

//    struct FeeConfig {
//        string name;
//        uint16 index;
//        uint16 openFeeP;     // 1e4
//        uint16 closeFeeP;    // 1e4
//        bool enable;
//    }
//
//    struct PairView {
//        // BTC/USD
//        string name;
//        // BTC address
//        address base;
//        uint16 basePosition;
//        IPairsManager.PairType pairType;
//        IPairsManager.PairStatus status;
//        uint256 maxLongOiUsd;
//        uint256 maxShortOiUsd;
//        uint256 fundingFeePerBlockP;  // 1e18
//        uint256 minFundingFeeR;       // 1e18
//        uint256 maxFundingFeeR;       // 1e18
//
//        LibPairsManager.LeverageMargin[] leverageMargins;
//
//        uint16 slippageConfigIndex;
//        uint16 slippagePosition;
//        LibPairsManager.SlippageConfig slippageConfig;
//
//        uint16 feeConfigIndex;
//        uint16 feePosition;
//        FeeConfig feeConfig;
//
//        uint40 longHoldingFeeRate;    // 1e12
//        uint40 shortHoldingFeeRate;   // 1e12
//    }
//
//    function pairsV2() external view returns (PairView[] memory) {
//        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
//        address[] memory bases = pms.pairBases;
//        PairView[] memory pairViews = new PairView[](bases.length);
//        for (uint i; i < bases.length; i++) {
//            LibPairsManager.Pair storage pair = pms.pairs[bases[i]];
//            pairViews[i] = _pairToView(pair, pms.slippageConfigs[pair.slippageConfigIndex]);
//        }
//        return pairViews;
//    }
//
//    function getPairByBaseV2(address base) external view returns (PairView memory) {
//        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
//        LibPairsManager.Pair storage pair = pms.pairs[base];
//        return _pairToView(pair, pms.slippageConfigs[pair.slippageConfigIndex]);
//    }
//
//    function _pairToView(
//        LibPairsManager.Pair storage pair, LibPairsManager.SlippageConfig memory slippageConfig
//    ) private view returns (PairView memory) {
//        LibPairsManager.LeverageMargin[] memory leverageMargins = new LibPairsManager.LeverageMargin[](pair.maxTier);
//        for (uint16 i = 0; i < pair.maxTier; i++) {
//            leverageMargins[i] = pair.leverageMargins[i + 1];
//        }
//        (LibFeeManager.FeeConfig memory fc,) = LibFeeManager.getFeeConfigByIndex(pair.feeConfigIndex);
//        FeeConfig memory feeConfig = FeeConfig(fc.name, fc.index, fc.openFeeP, fc.closeFeeP, fc.enable);
//        PairView memory pv = PairView(
//            pair.name, pair.base, pair.basePosition, pair.pairType, pair.status, pair.maxLongOiUsd, pair.maxShortOiUsd,
//            pair.fundingFeePerBlockP, pair.minFundingFeeR, pair.maxFundingFeeR, leverageMargins,
//            pair.slippageConfigIndex, pair.slippagePosition, slippageConfig,
//            pair.feeConfigIndex, pair.feePosition, feeConfig, pair.longHoldingFeeRate, pair.shortHoldingFeeRate
//        );
//        return pv;
//    }

    struct Token {
        address tokenAddress;
        uint16 weight;
        uint16 feeBasisPoints;
        uint16 taxBasisPoints;
        bool stable;
        bool dynamicFee;
        bool asMargin;
    }

    function tokensV2() external view returns (Token[] memory) {
        LibVault.VaultStorage storage vs = LibVault.vaultStorage();
        Token[] memory tokens = new Token[](vs.tokenAddresses.length);
        for (uint256 i; i < vs.tokenAddresses.length; i++) {
            tokens[i] = _getTokenByAddress(vs.tokenAddresses[i]);
        }
        return tokens;
    }

    function _getTokenByAddress(address tokenAddress) private view returns (Token memory) {
        LibVault.AvailableToken memory at = LibVault.getTokenByAddress(tokenAddress);
        return Token(
            at.tokenAddress, at.weight, at.feeBasisPoints,
            at.taxBasisPoints, at.stable, at.dynamicFee,
            uint(at.featureSwitches).bitSet(uint8(FeatureSwitches.AS_MARGIN))
        );
    }
}
