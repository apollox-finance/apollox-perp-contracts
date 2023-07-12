// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../security/OnlySelf.sol";
import "../interfaces/IPairsManager.sol";
import "../interfaces/IOrderAndTradeHistory.sol";
import "../libraries/LibOrderAndTradeHistory.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract OrderAndTradeHistoryFacet is IOrderAndTradeHistory, OnlySelf {

    function _saveActionInfo(
        LibOrderAndTradeHistory.OrderAndTradeHistoryStorage storage hs, address user, bytes32 hash, ActionType aType
    ) private {
        ActionInfo[] storage actionInfos = hs.actionInfos[user];
        actionInfos.push(ActionInfo(hash, uint40(block.timestamp), aType));
    }

    function createLimitOrder(bytes32 orderHash, OrderInfo calldata order) external onlySelf override {
        LibOrderAndTradeHistory.OrderAndTradeHistoryStorage storage hs = LibOrderAndTradeHistory.historyStorage();

        hs.orderInfos[orderHash] = order;
        _saveActionInfo(hs, order.user, orderHash, ActionType.LIMIT);
    }

    function cancelLimitOrder(bytes32 orderHash, ActionType aType) external onlySelf override {
        LibOrderAndTradeHistory.OrderAndTradeHistoryStorage storage hs = LibOrderAndTradeHistory.historyStorage();

        _saveActionInfo(hs, hs.orderInfos[orderHash].user, orderHash, aType);
    }

    function limitTrade(bytes32 tradeHash, TradeInfo calldata trade) external onlySelf override {
        LibOrderAndTradeHistory.OrderAndTradeHistoryStorage storage hs = LibOrderAndTradeHistory.historyStorage();

        hs.tradeInfos[tradeHash] = trade;
        _saveActionInfo(hs, hs.orderInfos[tradeHash].user, tradeHash, ActionType.OPEN);
    }

    function marketTrade(bytes32 tradeHash, OrderInfo calldata order, TradeInfo calldata trade) external onlySelf override {
        LibOrderAndTradeHistory.OrderAndTradeHistoryStorage storage hs = LibOrderAndTradeHistory.historyStorage();

        hs.orderInfos[tradeHash] = order;
        hs.tradeInfos[tradeHash] = trade;
        _saveActionInfo(hs, order.user, tradeHash, ActionType.OPEN);
    }

    function closeTrade(bytes32 tradeHash, CloseInfo calldata data, ActionType aType) external onlySelf override {
        LibOrderAndTradeHistory.OrderAndTradeHistoryStorage storage hs = LibOrderAndTradeHistory.historyStorage();

        hs.closeInfos[tradeHash] = data;
        _saveActionInfo(hs, hs.orderInfos[tradeHash].user, tradeHash, aType);
    }

    function updateMargin(bytes32 tradeHash, uint96 newMargin) external onlySelf override {
        TradeInfo storage trade = LibOrderAndTradeHistory.historyStorage().tradeInfos[tradeHash];
        trade.margin = newMargin;
    }

    function getOrderAndTradeHistoryV2(
        address user, uint start, uint8 size
    ) external view override returns (OrderAndTradeHistory[] memory datas) {
        LibOrderAndTradeHistory.OrderAndTradeHistoryStorage storage hs = LibOrderAndTradeHistory.historyStorage();

        if (start >= hs.actionInfos[user].length || size == 0) {
            datas = new OrderAndTradeHistory[](0);
        } else {
            uint count = hs.actionInfos[user].length - start > size ? size : hs.actionInfos[user].length - start;
            datas = new OrderAndTradeHistory[](count);
            for (UC i = ZERO; i < uc(count); i = i + ONE) {
                uint oldest = hs.actionInfos[user].length - (uc(start) + i + ONE).into();
                ActionInfo memory ai = hs.actionInfos[user][oldest];
                OrderInfo memory oi = hs.orderInfos[ai.hash];
                string memory name = IPairsManager(address(this)).getPairForTrading(oi.pairBase).name;
                if (ai.actionType == ActionType.LIMIT || ai.actionType == ActionType.CANCEL_LIMIT || ai.actionType == ActionType.SYSTEM_CANCEL) {
                    datas[i.into()] = OrderAndTradeHistory(
                        ai.hash, ai.timestamp, name, ai.actionType, oi.tokenIn, oi.isLong, oi.amountIn, oi.qty,
                        oi.entryPrice, 0, 0, 0, 0, 0, 0, 0, 0, 0
                    );
                } else if (ai.actionType == ActionType.OPEN) {
                    TradeInfo memory ti = hs.tradeInfos[ai.hash];
                    datas[i.into()] = OrderAndTradeHistory(
                        ai.hash, ai.timestamp, name, ai.actionType, oi.tokenIn, oi.isLong, oi.amountIn,
                        oi.qty, oi.entryPrice, ti.margin, ti.openFee, ti.executionFee, 0, 0, 0, 0, 0, 0
                    );
                } else {
                    TradeInfo memory ti = hs.tradeInfos[ai.hash];
                    CloseInfo memory ci = hs.closeInfos[ai.hash];
                    datas[i.into()] = OrderAndTradeHistory(
                        ai.hash, ai.timestamp, name, ai.actionType, oi.tokenIn, oi.isLong, oi.amountIn,
                        oi.qty, oi.entryPrice, ti.margin, ti.openFee, ti.executionFee,
                        ci.closePrice, ci.fundingFee, ci.closeFee, ci.pnl, ci.holdingFee, ti.openTimestamp
                    );
                }
            }
        }
        return datas;
    }
}
