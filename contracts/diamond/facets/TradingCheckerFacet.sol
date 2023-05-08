// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../interfaces/IVault.sol";
import "../interfaces/ILimitOrder.sol";
import "../interfaces/IPriceFacade.sol";
import "../interfaces/ITradingCore.sol";
import "../interfaces/IPairsManager.sol";
import "../interfaces/ITradingConfig.sol";
import "../interfaces/ITradingChecker.sol";
import "../libraries/LibTrading.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract TradingCheckerFacet is ITradingChecker {

    function checkTp(
        bool isLong, uint takeProfit, uint entryPrice, uint leverage_10000, uint maxTakeProfitP
    ) public pure returns (bool) {
        if (isLong) {
            // The takeProfit price must be set and the percentage of profit must not exceed the maximum allowed
            return takeProfit > entryPrice && (takeProfit - entryPrice) * leverage_10000 <= maxTakeProfitP * entryPrice;
        } else {
            // The takeProfit price must be set and the percentage of profit must not exceed the maximum allowed
            return takeProfit > 0 && takeProfit < entryPrice && (entryPrice - takeProfit) * leverage_10000 <= maxTakeProfitP * entryPrice;
        }
    }

    function checkSl(bool isLong, uint stopLoss, uint entryPrice) public pure returns (bool) {
        if (isLong) {
            // stopLoss price below the liquidation price is meaningless
            // But no check is done here and is intercepted by the front-end.
            // (entryPrice - stopLoss) * qty < marginUsd * liqLostP / Constants.1e4
            return stopLoss == 0 || stopLoss < entryPrice;
        } else {
            // stopLoss price below the liquidation price is meaningless
            // But no check is done here and is intercepted by the front-end.
            // (stopLoss - entryPrice) * qty * 1e4 < marginUsd * liqLostP
            return stopLoss == 0 || stopLoss > entryPrice;
        }
    }

    function checkLimitOrderTp(ILimitOrder.LimitOrder calldata order) external view override {
        IVault.MarginToken memory token = IVault(address(this)).getTokenForTrading(order.tokenIn);

        // notionalUsd = price * qty
        uint notionalUsd = order.limitPrice * order.qty;

        // openFeeUsd = notionalUsd * openFeeP
        uint openFeeUsd = notionalUsd * IPairsManager(address(this)).getPairFeeConfig(order.pairBase).openFeeP / 1e4;

        // marginUsd = amountInUsd - openFeeUsd - executionFeeUsd
        uint marginUsd = order.amountIn * token.price * 1e10 / (10 ** token.decimals) - openFeeUsd - ITradingConfig(address(this)).getTradingConfig().executionFeeUsd;

        // leverage_10000 = notionalUsd * 10000 / marginUsd
        uint leverage_10000 = notionalUsd * 1e4 / marginUsd;

        require(
            checkTp(order.isLong, order.takeProfit, order.limitPrice, leverage_10000, ITradingConfig(address(this)).getTradingConfig().maxTakeProfitP),
            "TradingCheckerFacet: takeProfit is not in the valid range"
        );
    }

    function _checkParameters(IBook.OpenDataInput calldata data) private pure {
        require(
            data.qty > 0 && data.amountIn > 0 && data.price > 0
            && data.pairBase != address(0) && data.tokenIn != address(0),
            "TradingCheckerFacet: Invalid parameters"
        );
    }

    function openLimitOrderCheck(IBook.OpenDataInput calldata data) external view override {
        _checkParameters(data);

        IVault.MarginToken memory token = IVault(address(this)).getTokenForTrading(data.tokenIn);
        require(token.asMargin, "TradingCheckerFacet: This token is not supported as margin");

        IPairsManager.TradingPair memory pair = IPairsManager(address(this)).getPairForTrading(data.pairBase);
        require(pair.status == IPairsManager.PairStatus.AVAILABLE, "TradingCheckerFacet: The pair is temporarily unavailable for trading");

        ITradingConfig.TradingConfig memory tc = ITradingConfig(address(this)).getTradingConfig();
        require(tc.limitOrder, "TradingCheckerFacet: This feature is temporarily disabled");

        (uint marketPrice,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(data.pairBase);
        require(marketPrice > 0, "TradingCheckerFacet: No access to current market effective prices");

        uint triggerPrice = ITradingCore(address(this)).triggerPrice(data.pairBase, data.price, data.qty, data.isLong);
        require(
            (data.isLong && triggerPrice < marketPrice) || (!data.isLong && triggerPrice > marketPrice),
            "TradingCheckerFacet: This price will open a position immediately"
        );

        // price * qty * 10^18 / 10^(8+10) = price * qty
        uint notionalUsd = data.price * data.qty;
        // The notional value must be greater than or equal to the minimum notional value allowed
        require(notionalUsd >= tc.minNotionalUsd, "TradingCheckerFacet: Position is too small");

        IPairsManager.LeverageMargin[] memory lms = pair.leverageMargins;
        // The notional value of the position must be less than or equal to the maximum notional value allowed by pair
        require(notionalUsd <= lms[lms.length - 1].notionalUsd, "TradingCheckerFacet: Position is too large");

        IPairsManager.LeverageMargin memory lm = marginLeverage(lms, notionalUsd);
        uint openFeeUsd = notionalUsd * pair.feeConfig.openFeeP / 1e4;
        uint amountInUsd = data.amountIn * token.price * 1e10 / (10 ** token.decimals);
        require(amountInUsd > openFeeUsd + tc.executionFeeUsd, "TradingCheckerFacet: The amount is too small");

        // marginUsd = amountInUsd - openFeeUsd - executionFeeUsd
        uint marginUsd = amountInUsd - openFeeUsd - tc.executionFeeUsd;
        // leverage = notionalUsd / marginUsd
        uint leverage_10000 = notionalUsd * 1e4 / marginUsd;
        require(
            leverage_10000 <= uint(1e4) * lm.maxLeverage,
            "TradingCheckerFacet: Exceeds the maximum leverage allowed for the position"
        );
        require(
            checkTp(data.isLong, data.takeProfit, data.price, leverage_10000, tc.maxTakeProfitP),
            "TradingCheckerFacet: takeProfit is not in the valid range"
        );
        require(
            checkSl(data.isLong, data.stopLoss, data.price),
            "TradingCheckerFacet: stopLoss is not in the valid range"
        );
    }

    struct ExecuteLimitOrderCheckTuple {
        IPairsManager.TradingPair pair;
        ITradingConfig.TradingConfig tc;
        IVault.MarginToken token;
        ITradingCore.PairQty pairQty;
        uint notionalUsd;
        uint triggerPrice;
    }

    function _buildExecuteLimitOrderCheckTuple(
        ILimitOrder.LimitOrder memory order
    ) private view returns (ExecuteLimitOrderCheckTuple memory) {
        IPairsManager.TradingPair memory pair = IPairsManager(address(this)).getPairForTrading(order.pairBase);
        ITradingCore.PairQty memory pairQty = ITradingCore(address(this)).getPairQty(order.pairBase);
        return ExecuteLimitOrderCheckTuple(
            pair,
            ITradingConfig(address(this)).getTradingConfig(),
            IVault(address(this)).getTokenForTrading(order.tokenIn),
            pairQty,
            order.limitPrice * order.qty,
            ITradingCore(address(this)).triggerPrice(pairQty, pair.slippageConfig, order.limitPrice, order.qty, order.isLong)
        );
    }

    function executeLimitOrderCheck(
        ILimitOrder.LimitOrder memory order,
        uint256 marketPrice
    ) external view override returns (bool result, uint96 openFee, uint96 executionFee, Refund refund) {
        ExecuteLimitOrderCheckTuple memory tuple = _buildExecuteLimitOrderCheckTuple(order);
        if (!tuple.tc.executeLimitOrder) {
            return (false, 0, 0, Refund.SWITCH);
        }

        if (tuple.pair.base == address(0) || tuple.pair.status != IPairsManager.PairStatus.AVAILABLE) {
            return (false, 0, 0, Refund.PAIR_STATUS);
        }

        if (tuple.notionalUsd < tuple.tc.minNotionalUsd) {
            return (false, 0, 0, Refund.MIN_NOTIONAL_USD);
        }

        IPairsManager.LeverageMargin[] memory lms = tuple.pair.leverageMargins;
        if (tuple.notionalUsd > lms[lms.length - 1].notionalUsd) {
            return (false, 0, 0, Refund.MAX_NOTIONAL_USD);
        }

        IPairsManager.LeverageMargin memory lm = marginLeverage(lms, tuple.notionalUsd);
        uint openFeeUsd = tuple.notionalUsd * tuple.pair.feeConfig.openFeeP / 1e4;
        uint amountInUsd = order.amountIn * tuple.token.price * 1e10 / (10 ** tuple.token.decimals);
        if (amountInUsd <= openFeeUsd + tuple.tc.executionFeeUsd) {
            return (false, 0, 0, Refund.AMOUNT_IN);
        }

        // marginUsd = amountInUsd - openFeeUsd - executionFeeUsd
        uint marginUsd = amountInUsd - openFeeUsd - tuple.tc.executionFeeUsd;
        // leverage_10000 = notionalUsd * 10000 / marginUsd
        uint leverage_10000 = tuple.notionalUsd * 1e4 / marginUsd;
        if (leverage_10000 > uint(1e4) * lm.maxLeverage) {
            return (false, 0, 0, Refund.MAX_LEVERAGE);
        }

        if (order.isLong) {
            if (marketPrice > tuple.triggerPrice) {
                return (false, 0, 0, Refund.USER_PRICE);
            }
            // Whether the Stop Loss will be triggered immediately at the current price
            if (marketPrice <= order.stopLoss) {
                return (false, 0, 0, Refund.SL);
            }
            // pair OI check
            if (tuple.notionalUsd + tuple.pairQty.longQty * marketPrice > tuple.pair.pairConfig.maxLongOiUsd) {
                return (false, 0, 0, Refund.PAIR_OI);
            }
            // open lost check
            if ((order.limitPrice - marketPrice) * order.qty * 1e4 >= marginUsd * lm.initialLostP) {
                return (false, 0, 0, Refund.OPEN_LOST);
            }
        } else {
            // Comparison of the values of price and limitPrice + slippage
            if (marketPrice < tuple.triggerPrice) {
                return (false, 0, 0, Refund.USER_PRICE);
            }
            // 4. Whether the Stop Loss will be triggered immediately at the current price
            if (order.stopLoss > 0 && marketPrice >= order.stopLoss) {
                return (false, 0, 0, Refund.SL);
            }
            // pair OI check
            if (tuple.notionalUsd + tuple.pairQty.shortQty * marketPrice > tuple.pair.pairConfig.maxShortOiUsd) {
                return (false, 0, 0, Refund.PAIR_OI);
            }
            // open lost check
            if ((marketPrice - order.limitPrice) * order.qty * 1e4 >= marginUsd * lm.initialLostP) {
                return (false, 0, 0, Refund.OPEN_LOST);
            }
        }
        return (true,
        uint96(openFeeUsd * (10 ** tuple.token.decimals) / (1e10 * tuple.token.price)),
        uint96(tuple.tc.executionFeeUsd * (10 ** tuple.token.decimals) / (1e10 * tuple.token.price)),
        Refund.NO
        );
    }

    function checkMarketTradeTp(ITrading.OpenTrade calldata ot) external view {
        IVault.MarginToken memory token = IVault(address(this)).getTokenForTrading(ot.tokenIn);

        // notionalUsd = price * qty
        uint notionalUsd = ot.entryPrice * ot.qty;

        // marginUsd = margin * token.price
        uint marginUsd = ot.margin * token.price * 1e10 / (10 ** token.decimals);

        // leverage_10000 = notionalUsd * 10000 / marginUsd
        uint leverage_10000 = notionalUsd * 1e4 / marginUsd;

        require(
            checkTp(ot.isLong, ot.takeProfit, ot.entryPrice, leverage_10000, ITradingConfig(address(this)).getTradingConfig().maxTakeProfitP),
            "TradingCheckerFacet: takeProfit is not in the valid range"
        );
    }

    function openMarketTradeCheck(IBook.OpenDataInput calldata data) external view override {
        _checkParameters(data);

        IVault.MarginToken memory token = IVault(address(this)).getTokenForTrading(data.tokenIn);
        require(token.asMargin, "TradingCheckerFacet: This token is not supported as margin");

        IPairsManager.TradingPair memory pair = IPairsManager(address(this)).getPairForTrading(data.pairBase);
        require(pair.status == IPairsManager.PairStatus.AVAILABLE, "TradingCheckerFacet: The pair is temporarily unavailable for trading");

        ITradingConfig.TradingConfig memory tc = ITradingConfig(address(this)).getTradingConfig();
        require(tc.marketTrading, "TradingCheckerFacet: This feature is temporarily disabled");

        (uint marketPrice,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(data.pairBase);
        require(marketPrice > 0, "TradingCheckerFacet: No access to current market effective prices");

        ITradingCore.PairQty memory pairQty = ITradingCore(address(this)).getPairQty(data.pairBase);
        uint trialPrice = ITradingCore(address(this)).slippagePrice(pairQty, pair.slippageConfig, marketPrice, data.qty, data.isLong);
        require(
            (data.isLong && trialPrice <= data.price) || (!data.isLong && trialPrice >= data.price),
            "TradingCheckerFacet: Unable to trading at a price acceptable to the user"
        );

        // price * qty * 10^18 / 10^(8+10) = price * qty
        uint notionalUsd = trialPrice * data.qty;
        // The notional value must be greater than or equal to the minimum notional value allowed
        require(notionalUsd >= tc.minNotionalUsd, "TradingCheckerFacet: Position is too small");

        IPairsManager.LeverageMargin[] memory lms = pair.leverageMargins;
        // The notional value of the position must be less than or equal to the maximum notional value allowed by pair
        require(notionalUsd <= lms[lms.length - 1].notionalUsd, "TradingCheckerFacet: Position is too large");

        IPairsManager.LeverageMargin memory lm = marginLeverage(lms, notionalUsd);
        uint openFeeUsd = notionalUsd * pair.feeConfig.openFeeP / 1e4;
        uint amountInUsd = data.amountIn * token.price * 1e10 / (10 ** token.decimals);
        require(amountInUsd > openFeeUsd + tc.executionFeeUsd, "TradingCheckerFacet: The amount is too small");

        // marginUsd = amountInUsd - openFeeUsd - executionFeeUsd
        uint marginUsd = amountInUsd - openFeeUsd - tc.executionFeeUsd;
        // leverage = notionalUsd / marginUsd
        uint leverage_10000 = notionalUsd * 1e4 / marginUsd;
        require(
            leverage_10000 <= uint(1e4) * lm.maxLeverage,
            "TradingCheckerFacet: Exceeds the maximum leverage allowed for the position"
        );
        require(
            checkTp(data.isLong, data.takeProfit, trialPrice, leverage_10000, tc.maxTakeProfitP),
            "TradingCheckerFacet: takeProfit is not in the valid range"
        );
        require(
            checkSl(data.isLong, data.stopLoss, trialPrice),
            "TradingCheckerFacet: stopLoss is not in the valid range"
        );

        if (data.isLong) {
            // It is prohibited to open positions with excessive losses. Avoid opening positions that are liquidated
            require(
                (trialPrice - marketPrice) * data.qty * 1e4 < marginUsd * lm.initialLostP,
                "TradingCheckerFacet: Too much initial loss"
            );
            // The total position must be less than or equal to the maximum position allowed for the trading pair
            require(notionalUsd + pairQty.longQty * trialPrice <= pair.pairConfig.maxLongOiUsd, "TradingCheckerFacet: Long positions have exceeded the maximum allowed");
        } else {
            // It is prohibited to open positions with excessive losses. Avoid opening positions that are liquidated
            require(
                (marketPrice - trialPrice) * data.qty * 1e4 < marginUsd * lm.initialLostP,
                "TradingCheckerFacet: Too much initial loss"
            );
            // The total position must be less than or equal to the maximum position allowed for the trading pair
            require(notionalUsd + pairQty.shortQty * trialPrice <= pair.pairConfig.maxShortOiUsd, "TradingCheckerFacet: Short positions have exceeded the maximum allowed");
        }
    }

    struct MarketTradeCallbackCheckTuple {
        IPairsManager.TradingPair pair;
        ITradingConfig.TradingConfig tc;
        IVault.MarginToken token;
        ITradingCore.PairQty pairQty;
        uint notionalUsd;
        uint entryPrice;
    }

    function _buildMarketTradeCallbackCheckTuple(
        ITrading.PendingTrade memory pt, uint256 marketPrice
    ) private view returns (MarketTradeCallbackCheckTuple memory) {
        IPairsManager.TradingPair memory pair = IPairsManager(address(this)).getPairForTrading(pt.pairBase);
        ITradingCore.PairQty memory pairQty = ITradingCore(address(this)).getPairQty(pt.pairBase);
        uint entryPrice = ITradingCore(address(this)).slippagePrice(pairQty, pair.slippageConfig, marketPrice, pt.qty, pt.isLong);
        return MarketTradeCallbackCheckTuple(
            pair,
            ITradingConfig(address(this)).getTradingConfig(),
            IVault(address(this)).getTokenForTrading(pt.tokenIn),
            pairQty,
            entryPrice * pt.qty,
            entryPrice
        );
    }

    function marginLeverage(
        IPairsManager.LeverageMargin[] memory lms, uint256 notionalUsd
    ) private pure returns (IPairsManager.LeverageMargin memory) {
        for (UC i = ZERO; i < uc(lms.length); i = i + ONE) {
            if (notionalUsd <= lms[i.into()].notionalUsd) {
                return lms[i.into()];
            }
        }
        return lms[lms.length - 1];
    }

    function marketTradeCallbackCheck(
        ITrading.PendingTrade calldata pt, uint256 marketPrice
    ) external view returns (bool result, uint96 openFee, uint96 executionFee, uint256 entryPrice, Refund refund) {
        if (pt.blockNumber + Constants.FEED_DELAY_BLOCK < block.number) {
            return (false, 0, 0, 0, Refund.FEED_DELAY);
        }

        MarketTradeCallbackCheckTuple memory tuple = _buildMarketTradeCallbackCheckTuple(pt, marketPrice);
        if ((pt.isLong && tuple.entryPrice > pt.price) || (!pt.isLong && tuple.entryPrice < pt.price)) {
            return (false, 0, 0, tuple.entryPrice, Refund.USER_PRICE);
        }

        if (tuple.notionalUsd < tuple.tc.minNotionalUsd) {
            return (false, 0, 0, tuple.entryPrice, Refund.MIN_NOTIONAL_USD);
        }

        IPairsManager.LeverageMargin[] memory lms = tuple.pair.leverageMargins;
        if (tuple.notionalUsd > lms[lms.length - 1].notionalUsd) {
            return (false, 0, 0, tuple.entryPrice, Refund.MAX_NOTIONAL_USD);
        }

        IPairsManager.LeverageMargin memory lm = marginLeverage(lms, tuple.notionalUsd);
        uint openFeeUsd = tuple.notionalUsd * tuple.pair.feeConfig.openFeeP / 1e4;
        uint amountInUsd = pt.amountIn * tuple.token.price * 1e10 / (10 ** tuple.token.decimals);
        if (amountInUsd <= openFeeUsd + tuple.tc.executionFeeUsd) {
            return (false, 0, 0, tuple.entryPrice, Refund.AMOUNT_IN);
        }

        // marginUsd = amountInUsd - openFeeUsd - executionFeeUsd
        uint marginUsd = amountInUsd - openFeeUsd - tuple.tc.executionFeeUsd;
        // leverage_10000 = notionalUsd * 10000 / marginUsd
        uint leverage_10000 = tuple.notionalUsd * 1e4 / marginUsd;
        if (leverage_10000 > uint(1e4) * lm.maxLeverage) {
            return (false, 0, 0, tuple.entryPrice, Refund.MAX_LEVERAGE);
        }

        if (!checkTp(pt.isLong, pt.takeProfit, tuple.entryPrice, leverage_10000, tuple.tc.maxTakeProfitP)) {
            return (false, 0, 0, tuple.entryPrice, Refund.TP);
        }

        if (!checkSl(pt.isLong, pt.stopLoss, tuple.entryPrice)) {
            return (false, 0, 0, tuple.entryPrice, Refund.SL);
        }

        if (pt.isLong) {
            // pair OI check
            if (tuple.notionalUsd + tuple.pairQty.longQty * tuple.entryPrice > tuple.pair.pairConfig.maxLongOiUsd) {
                return (false, 0, 0, tuple.entryPrice, Refund.PAIR_OI);
            }
            // open lost check
            if ((tuple.entryPrice - marketPrice) * pt.qty * 1e4 >= marginUsd * lm.initialLostP) {
                return (false, 0, 0, tuple.entryPrice, Refund.OPEN_LOST);
            }
        } else {
            // pair OI check
            if (tuple.notionalUsd + tuple.pairQty.shortQty * tuple.entryPrice > tuple.pair.pairConfig.maxShortOiUsd) {
                return (false, 0, 0, tuple.entryPrice, Refund.PAIR_OI);
            }
            // open lost check
            if ((marketPrice - tuple.entryPrice) * pt.qty * 1e4 >= marginUsd * lm.initialLostP) {
                return (false, 0, 0, tuple.entryPrice, Refund.OPEN_LOST);
            }
        }
        return (
        true,
        uint96(openFeeUsd * (10 ** tuple.token.decimals) / (1e10 * tuple.token.price)),
        uint96(tuple.tc.executionFeeUsd * (10 ** tuple.token.decimals) / (1e10 * tuple.token.price)),
        tuple.entryPrice, Refund.NO
        );
    }

    function executeLiquidateCheck(
        ITrading.OpenTrade calldata ot, uint256 marketPrice, uint256 closePrice
    ) external view returns (bool needLiq, int256 pnl, int256 fundingFee, uint256 closeFee) {
        IVault.MarginToken memory mt = IVault(address(this)).getTokenForTrading(ot.tokenIn);
        IPairsManager.TradingPair memory pair = IPairsManager(address(this)).getPairForTrading(ot.pairBase);

        fundingFee = LibTrading.calcFundingFee(ot, mt, marketPrice);

        uint256 closeNotionalUsd = closePrice * ot.qty;
        closeFee = closeNotionalUsd * pair.feeConfig.closeFeeP * (10 ** mt.decimals) / (1e4 * 1e10 * mt.price);
        IPairsManager.LeverageMargin memory lm = marginLeverage(pair.leverageMargins, ot.entryPrice * ot.qty);

        if (ot.isLong) {
            pnl = (int256(closeNotionalUsd) - int256(uint256(ot.entryPrice * ot.qty))) * int256(10 ** mt.decimals) / int256(1e10 * mt.price);
        } else {
            pnl = (int256(uint256(ot.entryPrice * ot.qty)) - int256(closeNotionalUsd)) * int256(10 ** mt.decimals) / int256(1e10 * mt.price);
        }
        int256 loss = int256(closeFee) - fundingFee - pnl;
        return (loss > 0 && uint256(loss) * 1e4 >= lm.liqLostP * ot.margin, pnl, fundingFee, closeFee);
    }
}
