// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IOrderAndTradeHistory.sol";

// The use of storage here may be removed in the future.
// SubGraph-based data query function
// https://thegraph.com/hosted-service/dashboard
library LibOrderAndTradeHistory {

    bytes32 constant ORDER_TRADE_HISTORY_POSITION = keccak256("apollox.order.trade.history.storage");

    struct OrderAndTradeHistoryStorage {
        // orderHash/tradeHash =>
        mapping(bytes32 => IOrderAndTradeHistory.OrderInfo) orderInfos;
        mapping(bytes32 => IOrderAndTradeHistory.TradeInfo) tradeInfos;
        mapping(bytes32 => IOrderAndTradeHistory.CloseInfo) closeInfos;
        // user =>
        mapping(address => IOrderAndTradeHistory.ActionInfo[]) actionInfos;
    }

    function historyStorage() internal pure returns (OrderAndTradeHistoryStorage storage hs) {
        bytes32 position = ORDER_TRADE_HISTORY_POSITION;
        assembly {
            hs.slot := position
        }
    }
}
