// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../security/OnlySelf.sol";
import "../interfaces/ITradingCore.sol";
import "../interfaces/IPairsManager.sol";
import "../interfaces/ITradingPortal.sol";
import "../libraries/LibTradingCore.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract TradingCoreFacet is ITradingCore, OnlySelf {

    function getPairQty(address pairBase) external view override returns (PairQty memory) {
        ITradingCore.PairPositionInfo memory ppi = LibTradingCore.tradingCoreStorage().pairPositionInfos[pairBase];
        return PairQty(ppi.longQty, ppi.shortQty);
    }

    function slippagePrice(address pairBase, uint256 marketPrice, uint256 qty, bool isLong) external view returns (uint256) {
        PairPositionInfo memory ppi = LibTradingCore.tradingCoreStorage().pairPositionInfos[pairBase];
        return slippagePrice(
            PairQty(ppi.longQty, ppi.shortQty), IPairsManager(address(this)).getPairSlippageConfig(pairBase), marketPrice, qty, isLong
        );
    }

    function slippagePrice(
        PairQty memory pairQty,
        IPairsManager.SlippageConfig memory sc,
        uint256 marketPrice, uint256 qty, bool isLong
    ) public pure override returns (uint256) {
        if (isLong) {
            uint slippage = sc.slippageLongP;
            if (sc.slippageType == IPairsManager.SlippageType.ONE_PERCENT_DEPTH) {
                // slippage = (longQty + qty) * price / depthAboveUsd
                slippage = (pairQty.longQty + qty) * marketPrice * 1e4 / sc.onePercentDepthAboveUsd;
            }
            return marketPrice * (1e4 + slippage) / 1e4;
        } else {
            uint slippage = sc.slippageShortP;
            if (sc.slippageType == IPairsManager.SlippageType.ONE_PERCENT_DEPTH) {
                // slippage = (shortQty + qty) * price / depthBelowUsd
                slippage = (pairQty.shortQty + qty) * marketPrice * 1e4 / sc.onePercentDepthBelowUsd;
            }
            return marketPrice * (1e4 - slippage) / 1e4;
        }
    }

    function triggerPrice(address pairBase, uint256 limitPrice, uint256 qty, bool isLong) external view returns (uint256) {
        PairPositionInfo memory ppi = LibTradingCore.tradingCoreStorage().pairPositionInfos[pairBase];
        return triggerPrice(
            PairQty(ppi.longQty, ppi.shortQty), IPairsManager(address(this)).getPairSlippageConfig(pairBase), limitPrice, qty, isLong
        );
    }

    function triggerPrice(
        PairQty memory pairQty,
        IPairsManager.SlippageConfig memory sc,
        uint256 limitPrice, uint256 qty, bool isLong
    ) public pure override returns (uint256) {
        if (isLong) {
            uint slippage = sc.slippageLongP;
            if (sc.slippageType == IPairsManager.SlippageType.ONE_PERCENT_DEPTH) {
                // slippage = (longQty + qty) * price / depthAboveUsd
                slippage = (pairQty.longQty + qty) * limitPrice * 1e4 / sc.onePercentDepthAboveUsd;
            }
            return limitPrice * (1e4 - slippage) / 1e4;
        } else {
            uint slippage = sc.slippageShortP;
            if (sc.slippageType == IPairsManager.SlippageType.ONE_PERCENT_DEPTH) {
                // slippage = (shortQty + qty) * price / depthBelowUsd
                slippage = (pairQty.shortQty + qty) * limitPrice * 1e4 / sc.onePercentDepthBelowUsd;
            }
            return limitPrice * (1e4 + slippage) / 1e4;
        }
    }

    function lastLongAccFundingFeePerShare(address pairBase) external view override returns (int256 longAccFundingFeePerShare) {
        PairPositionInfo memory ppi = LibTradingCore.tradingCoreStorage().pairPositionInfos[pairBase];
        longAccFundingFeePerShare = ppi.longAccFundingFeePerShare;
        if (block.number > ppi.lastFundingFeeBlock) {
            int256 fundingFeeR = LibTradingCore.fundingFeeRate(ppi, pairBase);
            longAccFundingFeePerShare += fundingFeeR * (- 1) * int256(block.number - ppi.lastFundingFeeBlock);
        }
        return longAccFundingFeePerShare;
    }

    function updatePairPositionInfo(
        address pairBase, uint userPrice, uint marketPrice, uint qty, bool isLong, bool isOpen
    ) external onlySelf override returns (int256 longAccFundingFeePerShare){
        LibTradingCore.TradingCoreStorage storage tcs = LibTradingCore.tradingCoreStorage();
        PairPositionInfo storage ppi = tcs.pairPositionInfos[pairBase];
        if (ppi.longQty > 0 || ppi.shortQty > 0) {
            uint256 lpReceiveFundingFeeUsd = LibTradingCore.updateFundingFee(ppi, pairBase, marketPrice);
            if (lpReceiveFundingFeeUsd > 0) {
                ITradingPortal(address(this)).settleLpFundingFee(lpReceiveFundingFeeUsd);
            }
        } else {
            ppi.lastFundingFeeBlock = block.number;
        }
        LibTradingCore.updatePairQtyAndAvgPrice(tcs, ppi, pairBase, qty, userPrice, isOpen, isLong);
        emit UpdatePairPositionInfo(
            pairBase, ppi.lastFundingFeeBlock, ppi.longQty, ppi.shortQty,
            ppi.longAccFundingFeePerShare, ppi.lpAveragePrice
        );
        return ppi.longAccFundingFeePerShare;
    }

    function lpUnrealizedPnlUsd() external view override returns (int256 unrealizedPnlUsd) {
        LibTradingCore.TradingCoreStorage storage tcs = LibTradingCore.tradingCoreStorage();
        address[] memory hasPositionPairs = tcs.hasPositionPairs;
        for (UC i = ZERO; i < uc(hasPositionPairs.length); i = i + ONE) {
            address pairBase = hasPositionPairs[i.into()];
            PairPositionInfo memory ppi = tcs.pairPositionInfos[pairBase];
            (uint256 price,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(pairBase);
            int256 lpAvgPrice = int256(uint256(ppi.lpAveragePrice));
            if (ppi.longQty > ppi.shortQty) {// LP Short
                unrealizedPnlUsd += int256(ppi.longQty - ppi.shortQty) * (lpAvgPrice - int256(price));
            } else {// LP Long
                unrealizedPnlUsd += int256(ppi.shortQty - ppi.longQty) * (int256(price) - lpAvgPrice);
            }
        }
        return unrealizedPnlUsd;
    }

    function lpNotionalUsd() external view override returns (uint256 notionalUsd) {
        LibTradingCore.TradingCoreStorage storage tcs = LibTradingCore.tradingCoreStorage();
        address[] memory hasPositionPairs = tcs.hasPositionPairs;
        for (UC i = ZERO; i < uc(hasPositionPairs.length); i = i + ONE) {
            address pairBase = hasPositionPairs[i.into()];
            PairPositionInfo memory ppi = tcs.pairPositionInfos[pairBase];
            (uint256 price,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(pairBase);
            if (ppi.longQty > ppi.shortQty) {
                notionalUsd += (ppi.longQty - ppi.shortQty) * price;
            } else {
                notionalUsd += (ppi.shortQty - ppi.longQty) * price;
            }
        }
        return notionalUsd;
    }
}
