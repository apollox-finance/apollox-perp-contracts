// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ITradingCore.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";

library LibTradingCore {

    using SignedMath for int256;

    bytes32 constant TRADING_CORE_POSITION = keccak256("apollox.trading.core.storage");

    struct TradingCoreStorage {
        // pair.pairBase =>
        mapping(address => ITradingCore.PairPositionInfo) pairPositionInfos;
        // pair.base[]
        address[] hasPositionPairs;
    }

    function tradingCoreStorage() internal pure returns (TradingCoreStorage storage tcs) {
        bytes32 position = TRADING_CORE_POSITION;
        assembly {
            tcs.slot := position
        }
    }

    function updateFundingFee(
        ITradingCore.PairPositionInfo storage ppi, address pairBase, uint256 marketPrice
    ) internal returns (uint256 lpReceiveFundingFeeUsd){
        int256 oldLongAccFundingFeePerShare = ppi.longAccFundingFeePerShare;
        bool needTransfer = _updateAccFundingFeePerShare(ppi, pairBase);
        if (needTransfer) {
            int256 longReceiveFundingFeeUsd = int256(ppi.longQty * marketPrice) * (ppi.longAccFundingFeePerShare - oldLongAccFundingFeePerShare) / 1e18;
            int256 shortReceiveFundingFeeUsd = int256(ppi.shortQty * marketPrice) * (ppi.longAccFundingFeePerShare - oldLongAccFundingFeePerShare) * (- 1) / 1e18;
            if (ppi.longQty > ppi.shortQty) {
                require(
                    (shortReceiveFundingFeeUsd == 0 && longReceiveFundingFeeUsd == 0) ||
                    longReceiveFundingFeeUsd < 0 && shortReceiveFundingFeeUsd >= 0 && longReceiveFundingFeeUsd.abs() > shortReceiveFundingFeeUsd.abs(),
                    "LibTrading: Funding fee calculation error. [LONG]"
                );
                lpReceiveFundingFeeUsd = (longReceiveFundingFeeUsd + shortReceiveFundingFeeUsd).abs();
            } else {
                require(
                    (shortReceiveFundingFeeUsd == 0 && longReceiveFundingFeeUsd == 0) ||
                    (shortReceiveFundingFeeUsd < 0 && longReceiveFundingFeeUsd >= 0 && shortReceiveFundingFeeUsd.abs() > longReceiveFundingFeeUsd.abs()),
                    "LibTrading: Funding fee calculation error. [SHORT]"
                );
                lpReceiveFundingFeeUsd = (shortReceiveFundingFeeUsd + longReceiveFundingFeeUsd).abs();
            }
        }
        return lpReceiveFundingFeeUsd;
    }

    function _updateAccFundingFeePerShare(
        ITradingCore.PairPositionInfo storage ppi, address pairBase
    ) private returns (bool){
        if (block.number <= ppi.lastFundingFeeBlock) {
            return false;
        }
        int256 fundingFeeR = fundingFeeRate(ppi, pairBase);
        // (ppi.longQty > ppi.shortQty) & (fundingFeeRate > 0) & (Long - money <==> Short + money) & (longAcc < 0)
        // (ppi.longQty < ppi.shortQty) & (fundingFeeRate < 0) & (Long + money <==> Short - money) & (longAcc > 0)
        // (ppi.longQty == ppi.shortQty) & (fundingFeeRate == 0)
        ppi.longAccFundingFeePerShare += fundingFeeR * (- 1) * int256(block.number - ppi.lastFundingFeeBlock);
        ppi.lastFundingFeeBlock = block.number;
        return true;
    }

    function fundingFeeRate(
        ITradingCore.PairPositionInfo memory ppi, address pairBase
    ) internal view returns (int256) {
        IPairsManager.PairMaxOiAndFundingFeeConfig memory pairConfig = IPairsManager(address(this)).getPairConfig(pairBase);
        int256 fundingFeeR;
        if (ppi.longQty != ppi.shortQty) {
            fundingFeeR = int256((int256(ppi.longQty) - int256(ppi.shortQty)).abs() * pairConfig.fundingFeePerBlockP) / (int256(ppi.longQty).max(int256(ppi.shortQty)));
            fundingFeeR = int256(pairConfig.maxFundingFeeR).min(int256(pairConfig.minFundingFeeR).max(fundingFeeR));
            if (ppi.longQty < ppi.shortQty) {
                fundingFeeR *= (- 1);
            }
        }
        return fundingFeeR;
    }

    function updatePairQtyAndAvgPrice(
        TradingCoreStorage storage tcs,
        ITradingCore.PairPositionInfo storage ppi,
        address pairBase, uint256 qty,
        uint256 userPrice, bool isOpen, bool isLong
    ) internal {
        if (isOpen) {
            if (ppi.longQty == 0 && ppi.shortQty == 0) {
                ppi.pairBase = pairBase;
                ppi.pairIndex = uint16(tcs.hasPositionPairs.length);
                tcs.hasPositionPairs.push(pairBase);
            }
            if (isLong) {
                // LP Increase position
                if (ppi.longQty >= ppi.shortQty) {
                    ppi.lpAveragePrice = uint64((ppi.lpAveragePrice * (ppi.longQty - ppi.shortQty) + userPrice * qty) / (ppi.longQty + qty - ppi.shortQty));
                }
                // LP Reverse open position
                else if (ppi.longQty < ppi.shortQty && ppi.longQty + qty > ppi.shortQty) {
                    ppi.lpAveragePrice = uint64(userPrice);
                }
                // LP position == 0
                else if (ppi.longQty < ppi.shortQty && ppi.longQty + qty == ppi.shortQty) {
                    ppi.lpAveragePrice = 0;
                }
                // LP Reduce position, No change in average price
                ppi.longQty += qty;
            } else {
                // LP Increase position
                if (ppi.shortQty >= ppi.longQty) {
                    ppi.lpAveragePrice = uint64((ppi.lpAveragePrice * (ppi.shortQty - ppi.longQty) + userPrice * qty) / (ppi.shortQty + qty - ppi.longQty));
                }
                // LP Reverse open position
                else if (ppi.shortQty < ppi.longQty && ppi.shortQty + qty > ppi.longQty) {
                    ppi.lpAveragePrice = uint64(userPrice);
                }
                // LP position == 0
                else if (ppi.shortQty < ppi.longQty && ppi.shortQty + qty == ppi.longQty) {
                    ppi.lpAveragePrice = 0;
                }
                // LP Reduce position, No change in average price
                ppi.shortQty += qty;
            }
        } else {
            if (isLong) {
                // LP Reduce position, No change in average price
                // if (ppi.longQty > ppi.shortQty && ppi.longQty - qty > ppi.shortQty)
                // LP position == 0
                if (ppi.longQty > ppi.shortQty && ppi.longQty - qty == ppi.shortQty) {
                    ppi.lpAveragePrice = 0;
                }
                // LP Reverse open position
                else if (ppi.longQty > ppi.shortQty && ppi.longQty - qty < ppi.shortQty) {
                    ppi.lpAveragePrice = uint64(userPrice);
                }
                // LP Increase position
                else if (ppi.longQty <= ppi.shortQty) {
                    ppi.lpAveragePrice = uint64((ppi.lpAveragePrice * (ppi.shortQty - ppi.longQty) + userPrice * qty) / (ppi.shortQty - ppi.longQty + qty));
                }
                ppi.longQty -= qty;
            } else {
                // LP Reduce position, No change in average price
                // if (ppi.longQty > ppi.shortQty && ppi.longQty - qty > ppi.shortQty)
                // LP position == 0
                if (ppi.shortQty > ppi.longQty && ppi.shortQty - qty == ppi.longQty) {
                    ppi.lpAveragePrice = 0;
                }
                // LP Reverse open position
                else if (ppi.shortQty > ppi.longQty && ppi.shortQty - qty < ppi.longQty) {
                    ppi.lpAveragePrice = uint64(userPrice);
                }
                // LP Increase position
                else if (ppi.shortQty <= ppi.longQty) {
                    ppi.lpAveragePrice = uint64((ppi.lpAveragePrice * (ppi.longQty - ppi.shortQty) + userPrice * qty) / (ppi.longQty - ppi.shortQty + qty));
                }
                ppi.shortQty -= qty;
            }
            if (ppi.longQty == 0 && ppi.shortQty == 0) {
                address[] storage pairs = tcs.hasPositionPairs;
                uint lastIndex = pairs.length - 1;
                uint removeIndex = ppi.pairIndex;
                if (lastIndex != removeIndex) {
                    address lastPair = pairs[lastIndex];
                    pairs[removeIndex] = lastPair;
                    tcs.pairPositionInfos[lastPair].pairIndex = uint16(removeIndex);
                }
                pairs.pop();
                delete tcs.pairPositionInfos[pairBase];
            }
        }
    }
}
