// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/TransferHelper.sol";
import "../security/OnlySelf.sol";
import "../interfaces/IFeeManager.sol";
import "../interfaces/ITradingOpen.sol";
import "../interfaces/ITradingChecker.sol";
import "../interfaces/IOrderAndTradeHistory.sol";
import "../libraries/LibTrading.sol";

contract TradingOpenFacet is ITradingOpen, OnlySelf {

    using TransferHelper for address;

    function limitOrderDeal(LimitOrder memory order, uint256 marketPrice) external onlySelf override {
        LibTrading.TradingStorage storage ts = LibTrading.tradingStorage();

        LibTrading.increaseOpenTradeAmount(ts, order.tokenIn, order.margin);
        // update fundingFee
        int256 longAccFundingFeePerShare = ITradingCore(address(this)).updatePairPositionInfo(order.pairBase, order.entryPrice, marketPrice, order.qty, order.isLong, true);

        bytes32[] storage tradeHashes = ts.userOpenTradeHashes[order.user];
        uint24 broker = IFeeManager(address(this)).chargeOpenFee(order.tokenIn, order.openFee, order.broker);
        OpenTrade memory ot = OpenTrade(
            order.user, uint32(tradeHashes.length), order.entryPrice, order.pairBase, order.tokenIn,
            order.margin, order.stopLoss, order.takeProfit, broker, order.isLong, order.openFee,
            longAccFundingFeePerShare, order.executionFee, uint40(block.timestamp), order.qty,
            IPairsManager(address(this)).getPairHoldingFeeRate(order.pairBase, order.isLong), block.number
        );
        ts.openTrades[order.orderHash] = ot;
        tradeHashes.push(order.orderHash);
        _limitTrade(order.orderHash, ot);
        emit OpenMarketTrade(ot.user, order.orderHash, ot);
    }

    function _limitTrade(bytes32 tradeHash, OpenTrade memory ot) private {
        IOrderAndTradeHistory(address(this)).limitTrade(
            tradeHash,
            IOrderAndTradeHistory.TradeInfo(ot.margin, ot.openFee, ot.executionFee, uint40(block.timestamp))
        );
    }

    function _marketTrade(bytes32 tradeHash, OpenTrade memory ot) private {
        IOrderAndTradeHistory(address(this)).marketTrade(
            tradeHash,
            IOrderAndTradeHistory.OrderInfo(ot.user, ot.margin + ot.openFee + ot.executionFee, ot.tokenIn, ot.qty, ot.isLong, ot.pairBase, ot.entryPrice),
            IOrderAndTradeHistory.TradeInfo(ot.margin, ot.openFee, ot.executionFee, uint40(block.timestamp))
        );
    }

    function marketTradeCallback(bytes32 tradeHash, uint upperPrice, uint lowerPrice) external onlySelf override {
        LibTrading.TradingStorage storage ts = LibTrading.tradingStorage();
        ITrading.PendingTrade memory pt = ts.pendingTrades[tradeHash];
        uint256 marketPrice = pt.isLong ? upperPrice : lowerPrice;
        (bool result, uint96 openFee, uint96 executionFee, uint256 entryPrice, ITradingChecker.Refund refund) = ITradingChecker(address(this)).marketTradeCallbackCheck(pt, marketPrice);
        if (!result) {
            (address tokenIn, address user, uint256 amountIn) = (pt.tokenIn, pt.user, pt.amountIn);
            // clear pending data
            ts.pendingTradeAmountIns[tokenIn] -= amountIn;
            delete ts.pendingTrades[tradeHash];

            tokenIn.transfer(user, amountIn);
            emit PendingTradeRefund(user, tradeHash, refund);
        } else {
            _marketTradeDeal(ts, pt, tradeHash, openFee, executionFee, marketPrice, entryPrice);
            // clear pending data
            ts.pendingTradeAmountIns[pt.tokenIn] -= pt.amountIn;
            address tokenIn = pt.tokenIn;
            delete ts.pendingTrades[tradeHash];

            tokenIn.transfer(tx.origin, executionFee);
        }
    }

    function _marketTradeDeal(
        LibTrading.TradingStorage storage ts, ITrading.PendingTrade memory pt,
        bytes32 tradeHash, uint96 openFee, uint96 executionFee, uint256 marketPrice, uint256 entryPrice
    ) private {
        uint96 margin = uint96(pt.amountIn) - openFee - executionFee;
        LibTrading.increaseOpenTradeAmount(ts, pt.tokenIn, margin);
        // update fundingFee
        int256 longAccFundingFeePerShare = ITradingCore(address(this)).updatePairPositionInfo(pt.pairBase, entryPrice, marketPrice, pt.qty, pt.isLong, true);

        uint24 broker = IFeeManager(address(this)).chargeOpenFee(pt.tokenIn, openFee, pt.broker);
        bytes32[] storage tradeHashes = ts.userOpenTradeHashes[pt.user];
        OpenTrade memory ot = OpenTrade(
            pt.user, uint32(tradeHashes.length), uint64(entryPrice), pt.pairBase, pt.tokenIn, margin, pt.stopLoss,
            pt.takeProfit, broker, pt.isLong, openFee, longAccFundingFeePerShare, executionFee, uint40(block.timestamp),
            pt.qty, IPairsManager(address(this)).getPairHoldingFeeRate(pt.pairBase, pt.isLong), block.number
        );
        ts.openTrades[tradeHash] = ot;
        tradeHashes.push(tradeHash);
        _marketTrade(tradeHash, ot);
        emit OpenMarketTrade(pt.user, tradeHash, ot);
    }
}
