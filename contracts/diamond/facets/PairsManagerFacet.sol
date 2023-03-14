// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../interfaces/IPairsManager.sol";
import "../libraries/LibPairsManager.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract PairsManagerFacet is IPairsManager {

    function addSlippageConfig(
        string calldata name, uint16 index, SlippageType slippageType,
        uint256 onePercentDepthAboveUsd, uint256 onePercentDepthBelowUsd, // Allowed to be 0
        uint16 slippageLongP, uint16 slippageShortP  // Allowed to be 0
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(slippageLongP < 1e4 && slippageShortP < 1e4,
            "PairsManagerFacet: Invalid parameters");
        LibPairsManager.addSlippageConfig(index, name, slippageType,
            onePercentDepthAboveUsd, onePercentDepthBelowUsd, slippageLongP, slippageShortP);
    }

    function removeSlippageConfig(uint16 index) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        LibPairsManager.removeSlippageConfig(index);
    }

    function updateSlippageConfig(
        uint16 index, SlippageType slippageType,
        uint256 onePercentDepthAboveUsd, uint256 onePercentDepthBelowUsd, // Allowed to be 0
        uint16 slippageLongP, uint16 slippageShortP  // Allowed to be 0
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(slippageLongP < 1e4 && slippageShortP < 1e4,
            "PairsManagerFacet: Invalid parameters");
        LibPairsManager.SlippageConfig memory config = LibPairsManager.SlippageConfig(
            "", onePercentDepthAboveUsd, onePercentDepthBelowUsd, slippageLongP, slippageShortP, index, slippageType, true
        );
        LibPairsManager.updateSlippageConfig(config);
    }

    function getSlippageConfigByIndex(uint16 index) external view override returns (LibPairsManager.SlippageConfig memory, PairSimple[] memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        LibPairsManager.SlippageConfig memory config = pms.slippageConfigs[index];
        address[] memory slippagePairs = pms.slippageConfigPairs[index];
        PairSimple[] memory pairSimples = new PairSimple[](slippagePairs.length);
        if (slippagePairs.length > 0) {
            mapping(address => LibPairsManager.Pair) storage _pairs = LibPairsManager.pairsManagerStorage().pairs;
            for (uint i; i < slippagePairs.length; i++) {
                LibPairsManager. Pair storage pair = _pairs[slippagePairs[i]];
                pairSimples[i] = PairSimple(pair.name, pair.base, pair.pairType, pair.status);
            }
        }
        return (config, pairSimples);
    }

    function addPair(
        address base, string calldata name,
        PairType pairType, PairStatus status,
        PairMaxOiAndFundingFeeConfig memory pairConfig,
        uint16 slippageConfigIndex, uint16 feeConfigIndex,
        LibPairsManager.LeverageMargin[] memory leverageMargins
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        _leverageMarginsCheck(leverageMargins);
        PairSimple memory ps = PairSimple(name, base, pairType, status);
        LibPairsManager.addPair(ps, slippageConfigIndex, feeConfigIndex, leverageMargins);
        LibPairsManager.updatePairMaxOi(base, pairConfig.maxLongOiUsd, pairConfig.maxShortOiUsd);
        LibPairsManager.updatePairFundingFeeConfig(
            base, pairConfig.fundingFeePerBlockP, pairConfig.minFundingFeeR, pairConfig.maxFundingFeeR
        );
    }

    function updatePairMaxOi(address base, uint256 maxLongOiUsd, uint256 maxShortOiUsd) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.updatePairMaxOi(base, maxLongOiUsd, maxShortOiUsd);
    }

    function updatePairFundingFeeConfig(
        address base, uint256 fundingFeePerBlockP, uint256 minFundingFeeR, uint256 maxFundingFeeR
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.updatePairFundingFeeConfig(base, fundingFeePerBlockP, minFundingFeeR, maxFundingFeeR);
    }

    function removePair(address base) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.removePair(base);
    }

    function updatePairStatus(address base, PairStatus status) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.updatePairStatus(base, status);
    }

    function updatePairSlippage(address base, uint16 slippageConfigIndex) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.updatePairSlippage(base, slippageConfigIndex);
    }

    function updatePairFee(address base, uint16 feeConfigIndex) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.updatePairFee(base, feeConfigIndex);
    }

    function updatePairLeverageMargin(address base, LibPairsManager.LeverageMargin[] memory leverageMargins) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        _leverageMarginsCheck(leverageMargins);
        LibPairsManager.updatePairLeverageMargin(base, leverageMargins);
    }

    function _leverageMarginsCheck(LibPairsManager.LeverageMargin[] memory leverageMargins) private pure {
        require(leverageMargins.length > 0, "PairsManagerFacet: Must specify leverage and margin allocation");
        if (leverageMargins.length == 1) {
            LibPairsManager.LeverageMargin memory lm = leverageMargins[0];
            require(lm.tier == 1 && lm.maxLeverage <= 1e3 &&
            lm.liqLostP < 1e4 && lm.initialLostP < lm.liqLostP,
                "PairsManagerFacet: leverageMargins parameter is invalid");
        } else {
            LibPairsManager.LeverageMargin memory lm;
            LibPairsManager.LeverageMargin memory nextLm;
            for (UC i = ZERO; i < uc(leverageMargins.length - 1); i = i + ONE) {
                lm = leverageMargins[i.into()];
                if (lm.tier != (i + ONE).into() || lm.maxLeverage > 1e3
                || lm.liqLostP >= 1e4
                || lm.initialLostP >= lm.liqLostP
                || lm.tier >= (nextLm = leverageMargins[(i + ONE).into()]).tier
                || lm.notionalUsd >= nextLm.notionalUsd
                || lm.maxLeverage <= nextLm.maxLeverage
                    || lm.liqLostP <= nextLm.liqLostP) {
                    revert("PairsManagerFacet: leverageMargins parameter is invalid");
                }
            }
            LibPairsManager.LeverageMargin memory lastLm = leverageMargins[leverageMargins.length - 1];
            require(lastLm.tier == leverageMargins.length && lastLm.maxLeverage <= 1e3 &&
            lastLm.liqLostP < 1e4 && lastLm.initialLostP < lastLm.liqLostP,
                "PairsManagerFacet: leverageMargins parameter is invalid");
        }
    }

    function pairs() external view override returns (PairView[] memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        address[] memory bases = pms.pairBases;
        PairView[] memory pairViews = new PairView[](bases.length);
        for (uint i; i < bases.length; i++) {
            LibPairsManager.Pair storage pair = pms.pairs[bases[i]];
            pairViews[i] = _pairToView(pair, pms.slippageConfigs[pair.slippageConfigIndex]);
        }
        return pairViews;
    }

    function getPairByBase(address base) external view override returns (PairView memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        LibPairsManager.Pair storage pair = pms.pairs[base];
        return _pairToView(pair, pms.slippageConfigs[pair.slippageConfigIndex]);
    }

    function _pairToView(
        LibPairsManager.Pair storage pair, LibPairsManager.SlippageConfig memory slippageConfig
    ) private view returns (IPairsManager.PairView memory) {
        LibPairsManager.LeverageMargin[] memory leverageMargins = new LibPairsManager.LeverageMargin[](pair.maxTier);
        for (uint16 i = 0; i < pair.maxTier; i++) {
            leverageMargins[i] = pair.leverageMargins[i + 1];
        }
        (LibFeeManager.FeeConfig memory feeConfig,) = LibFeeManager.getFeeConfigByIndex(pair.feeConfigIndex);
        IPairsManager.PairView memory pv = IPairsManager.PairView(
            pair.name, pair.base, pair.basePosition, pair.pairType, pair.status, pair.maxLongOiUsd, pair.maxShortOiUsd,
            pair.fundingFeePerBlockP, pair.minFundingFeeR, pair.maxFundingFeeR, leverageMargins,
            pair.slippageConfigIndex, pair.slippagePosition, slippageConfig,
            pair.feeConfigIndex, pair.feePosition, feeConfig
        );
        return pv;
    }

    function getPairForTrading(address base) external view override returns (TradingPair memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        LibPairsManager.Pair storage pair = pms.pairs[base];
        LeverageMargin[] memory lms = new LeverageMargin[](pair.maxTier);
        for (uint16 i = 0; i < pair.maxTier; i++) {
            LibPairsManager.LeverageMargin memory lm = pair.leverageMargins[i + 1];
            lms[i] = LeverageMargin(lm.notionalUsd, lm.maxLeverage, lm.initialLostP, lm.liqLostP);
        }
        return TradingPair(
            pair.base, pair.name, pair.pairType, pair.status,
            PairMaxOiAndFundingFeeConfig(pair.maxLongOiUsd, pair.maxShortOiUsd, pair.fundingFeePerBlockP, pair.minFundingFeeR, pair.maxFundingFeeR),
            lms,
            _convertSlippage(pms.slippageConfigs[pair.slippageConfigIndex]),
            _convertFeeRate(pair.feeConfigIndex)
        );
    }

    function _convertFeeRate(uint16 feeIndex) private view returns (FeeConfig memory) {
        (LibFeeManager.FeeConfig memory fc,) = LibFeeManager.getFeeConfigByIndex(feeIndex);
        return FeeConfig(fc.openFeeP, fc.closeFeeP);
    }

    function _convertSlippage(LibPairsManager.SlippageConfig memory sc) private pure returns (SlippageConfig memory) {
        return SlippageConfig(
            sc.onePercentDepthAboveUsd, sc.onePercentDepthBelowUsd,
            sc.slippageLongP, sc.slippageShortP, sc.slippageType
        );
    }

    function getPairConfig(address base) external view override returns (PairMaxOiAndFundingFeeConfig memory) {
        LibPairsManager.Pair storage pair = LibPairsManager.pairsManagerStorage().pairs[base];
        return PairMaxOiAndFundingFeeConfig(pair.maxLongOiUsd, pair.maxShortOiUsd, pair.fundingFeePerBlockP, pair.minFundingFeeR, pair.maxFundingFeeR);
    }

    function getPairFeeConfig(address base) external view override returns (FeeConfig memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        LibPairsManager.Pair storage pair = pms.pairs[base];
        return _convertFeeRate(pair.feeConfigIndex);
    }

    function getPairSlippageConfig(address base) external view override returns (SlippageConfig memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        LibPairsManager.Pair storage pair = pms.pairs[base];
        return _convertSlippage(pms.slippageConfigs[pair.slippageConfigIndex]);
    }
}
