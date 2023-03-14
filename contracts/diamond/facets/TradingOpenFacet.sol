// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../security/OnlySelf.sol";
import "../interfaces/IFeeManager.sol";
import "../interfaces/ITradingOpen.sol";
import "../interfaces/ITradingChecker.sol";
import "../interfaces/IOrderAndTradeHistory.sol";
import "../libraries/LibTrading.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TradingOpenFacet is ITradingOpen, OnlySelf {

    using SafeERC20 for IERC20;

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
            longAccFundingFeePerShare, order.executionFee, uint40(block.timestamp), order.qty
        );
        ts.openTrades[order.orderHash] = ot;
        tradeHashes.push(order.orderHash);
        _limitTrade(order.orderHash, ot);
        emit OpenMarketTrade(ot.user, order.orderHash, ot);
    }

    function _limitTrade(bytes32 tradeHash, OpenTrade memory ot) private {
        IOrderAndTradeHistory(address(this)).limitTrade(
            tradeHash,
            IOrderAndTradeHistory.TradeInfo(ot.margin, ot.openFee, ot.executionFee)
        );
    }

    function _marketTrade(bytes32 tradeHash, OpenTrade memory ot) private {
        IOrderAndTradeHistory(address(this)).marketTrade(
            tradeHash,
            IOrderAndTradeHistory.OrderInfo(ot.user, ot.margin + ot.openFee, ot.tokenIn, ot.qty, ot.isLong, ot.pairBase, ot.entryPrice),
            IOrderAndTradeHistory.TradeInfo(ot.margin, ot.openFee, ot.executionFee)
        );
    }

    function marketTradeCallback(bytes32 tradeHash, uint upperPrice, uint lowerPrice) external onlySelf override {
        LibTrading.TradingStorage storage ts = LibTrading.tradingStorage();
        ITrading.PendingTrade memory pt = ts.pendingTrades[tradeHash];
        uint256 marketPrice = pt.isLong ? upperPrice : lowerPrice;
        (bool result, uint256 entryPrice, ITradingChecker.Refund refund) = ITradingChecker(address(this)).marketTradeCallbackCheck(pt, marketPrice);
        if (!result) {
            IERC20(pt.tokenIn).safeTransfer(pt.user, pt.amountIn);
            emit PendingTradeRefund(pt.user, tradeHash, refund);
        } else {
            _marketTradeDeal(ts, pt, tradeHash, marketPrice, entryPrice);
        }
        // clear pending data
        ts.pendingTradeAmountIns[pt.tokenIn] -= pt.amountIn;
        delete ts.pendingTrades[tradeHash];
    }

    function _marketTradeDeal(
        LibTrading.TradingStorage storage ts, ITrading.PendingTrade memory pt,
        bytes32 tradeHash, uint256 marketPrice, uint256 entryPrice
    ) private {
        uint notionalUsd = entryPrice * pt.qty;
        IVault.MarginToken memory token = IVault(address(this)).getTokenForTrading(pt.tokenIn);
        uint openFee = notionalUsd * IPairsManager(address(this)).getPairFeeConfig(pt.pairBase).openFeeP * (10 ** token.decimals) / (1e4 * 1e10 * token.price);
        uint margin = pt.amountIn - openFee;

        LibTrading.increaseOpenTradeAmount(ts, pt.tokenIn, margin);
        // update fundingFee
        int256 longAccFundingFeePerShare = ITradingCore(address(this)).updatePairPositionInfo(pt.pairBase, entryPrice, marketPrice, pt.qty, pt.isLong, true);

        uint24 broker = IFeeManager(address(this)).chargeOpenFee(pt.tokenIn, openFee, pt.broker);
        bytes32[] storage tradeHashes = ts.userOpenTradeHashes[pt.user];
        OpenTrade memory ot = OpenTrade(
            pt.user, uint32(tradeHashes.length), uint64(entryPrice), pt.pairBase, pt.tokenIn, uint96(margin), pt.stopLoss,
            pt.takeProfit, broker, pt.isLong, uint96(openFee), longAccFundingFeePerShare, 0, uint40(block.timestamp), pt.qty
        );
        ts.openTrades[tradeHash] = ot;
        tradeHashes.push(tradeHash);
        _marketTrade(tradeHash, ot);
        emit OpenMarketTrade(pt.user, tradeHash, ot);
    }
}
