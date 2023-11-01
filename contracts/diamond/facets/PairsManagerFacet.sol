// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../interfaces/IPairsManager.sol";
import "../libraries/LibPairsManager.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract PairsManagerFacet is IPairsManager {

    function addPair(
        address base, string calldata name,
        PairType pairType, PairStatus status,
        PairMaxOiAndFundingFeeConfig calldata pairConfig,
        uint16 slippageConfigIndex, uint16 feeConfigIndex,
        LibPairsManager.LeverageMargin[] calldata leverageMargins,
        uint40 longHoldingFeeRate, uint40 shortHoldingFeeRate
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
        LibPairsManager.updatePairHoldingFeeRate(base, longHoldingFeeRate, shortHoldingFeeRate);
    }

    function updatePairMaxOi(address base, uint256 maxLongOiUsd, uint256 maxShortOiUsd) external override {
        LibAccessControlEnumerable.checkRole(Constants.MONITOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.updatePairMaxOi(base, maxLongOiUsd, maxShortOiUsd);
    }

    function batchUpdatePairMaxOi(UpdatePairMaxOiParam[] calldata params) external override {
        LibAccessControlEnumerable.checkRole(Constants.MONITOR_ROLE);
        for (UC i = ZERO; i < uc(params.length); i = i + ONE) {
            UpdatePairMaxOiParam calldata param = params[i.into()];
            require(param.base != address(0), "PairsManagerFacet: base cannot be 0 address");
            LibPairsManager.updatePairMaxOi(param.base, param.maxLongOiUsd, param.maxShortOiUsd);
        }
    }

    function updatePairHoldingFeeRate(address base, uint40 longHoldingFeeRate, uint40 shortHoldingFeeRate) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.updatePairHoldingFeeRate(base, longHoldingFeeRate, shortHoldingFeeRate);
    }

    function updatePairFundingFeeConfig(
        address base, uint256 fundingFeePerBlockP, uint256 minFundingFeeR, uint256 maxFundingFeeR
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.MONITOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.updatePairFundingFeeConfig(base, fundingFeePerBlockP, minFundingFeeR, maxFundingFeeR);
    }

    function removePair(address base) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.removePair(base);
    }

    function updatePairStatus(address base, PairStatus status) external override {
        LibAccessControlEnumerable.checkRole(Constants.MONITOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        LibPairsManager.updatePairStatus(base, status);
    }

    function batchUpdatePairStatus(PairType pairType, PairStatus status) external override {
        LibAccessControlEnumerable.checkRole(Constants.MONITOR_ROLE);
        LibPairsManager.batchUpdatePairStatus(pairType, status);
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

    function updatePairLeverageMargin(address base, LibPairsManager.LeverageMargin[] calldata leverageMargins) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(base != address(0), "PairsManagerFacet: base cannot be 0 address");
        _leverageMarginsCheck(leverageMargins);
        LibPairsManager.updatePairLeverageMargin(base, leverageMargins);
    }

    function _leverageMarginsCheck(LibPairsManager.LeverageMargin[] calldata leverageMargins) private pure {
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
                nextLm = leverageMargins[(i + ONE).into()];
                require(
                    lm.tier == (i + ONE).into()
                    && lm.maxLeverage <= 1e3
                    && lm.liqLostP < 1e4 && lm.liqLostP > 1e3
                    && lm.initialLostP < lm.liqLostP
                    && lm.notionalUsd < nextLm.notionalUsd
                    && lm.initialLostP > nextLm.initialLostP
                    && lm.maxLeverage > nextLm.maxLeverage
                    && lm.liqLostP > nextLm.liqLostP,
                    "PairsManagerFacet: leverageMargins parameter is invalid"
                );
            }
            LibPairsManager.LeverageMargin memory lastLm = leverageMargins[leverageMargins.length - 1];
            require(
                lastLm.tier == leverageMargins.length
                && lastLm.maxLeverage <= 1e3
                && lastLm.liqLostP < 1e4 && lastLm.liqLostP > 1e3
                && lastLm.initialLostP < lastLm.liqLostP,
                "PairsManagerFacet: leverageMargins parameter is invalid"
            );
        }
    }

    function pairsV3() external view override returns (PairView[] memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        address[] memory bases = pms.pairBases;
        PairView[] memory pairViews = new PairView[](bases.length);
        for (uint i; i < bases.length; i++) {
            LibPairsManager.Pair storage pair = pms.pairs[bases[i]];
            pairViews[i] = _pairToView(pair, pms.slippageConfigs[pair.slippageConfigIndex]);
        }
        return pairViews;
    }

    function getPairByBaseV3(address base) external view override returns (PairView memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        LibPairsManager.Pair storage pair = pms.pairs[base];
        return _pairToView(pair, pms.slippageConfigs[pair.slippageConfigIndex]);
    }

    function _pairToView(
        LibPairsManager.Pair storage pair, LibPairsManager.SlippageConfig memory slippageConfig
    ) private view returns (PairView memory) {
        LibPairsManager.LeverageMargin[] memory leverageMargins = new LibPairsManager.LeverageMargin[](pair.maxTier);
        for (uint16 i = 0; i < pair.maxTier; i++) {
            leverageMargins[i] = pair.leverageMargins[i + 1];
        }
        (LibFeeManager.FeeConfig memory feeConfig,) = LibFeeManager.getFeeConfigByIndex(pair.feeConfigIndex);
        PairView memory pv = PairView(
            pair.name, pair.base, pair.basePosition, pair.pairType, pair.status, pair.maxLongOiUsd, pair.maxShortOiUsd,
            pair.fundingFeePerBlockP, pair.minFundingFeeR, pair.maxFundingFeeR, leverageMargins,
            pair.slippageConfigIndex, pair.slippagePosition, slippageConfig,
            pair.feeConfigIndex, pair.feePosition, feeConfig, pair.longHoldingFeeRate, pair.shortHoldingFeeRate
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
        return FeeConfig(fc.openFeeP, fc.closeFeeP, fc.shareP, fc.minCloseFeeP);
    }

    function _convertSlippage(LibPairsManager.SlippageConfig memory sc) private pure returns (ISlippageManager.SlippageConfig memory) {
        return ISlippageManager.SlippageConfig(
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

    function getPairHoldingFeeRate(address base, bool isLong) external view override returns (uint40 holdingFeeRate) {
        LibPairsManager.Pair storage pair = LibPairsManager.pairsManagerStorage().pairs[base];
        if (isLong) {
            return pair.longHoldingFeeRate;
        } else {
            return pair.shortHoldingFeeRate;
        }
    }

    function getPairSlippageConfig(address base) external view override returns (ISlippageManager.SlippageConfig memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        LibPairsManager.Pair storage pair = pms.pairs[base];
        return _convertSlippage(pms.slippageConfigs[pair.slippageConfigIndex]);
    }
}
