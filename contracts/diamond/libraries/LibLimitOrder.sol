// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/TransferHelper.sol";
import "../interfaces/IBook.sol";
import "../interfaces/ITradingOpen.sol";
import "../interfaces/ILimitOrder.sol";
import "../interfaces/ITradingChecker.sol";
import "../interfaces/IOrderAndTradeHistory.sol";

library LibLimitOrder {

    using TransferHelper for address;

    bytes32 constant LIMIT_ORDER_POSITION = keccak256("apollox.limit.order.storage");

    struct LimitOrderStorage {
        uint256 salt;
        // orderHash =>
        mapping(bytes32 => ILimitOrder.LimitOrder) limitOrders;
        // user =>
        mapping(address => bytes32[]) userLimitOrderHashes;
        // margin.tokenIn => total amount of all open orders
        mapping(address => uint256) limitOrderAmountIns;
    }

    function limitOrderStorage() internal pure returns (LimitOrderStorage storage los) {
        bytes32 position = LIMIT_ORDER_POSITION;
        assembly {
            los.slot := position
        }
    }

    event OpenLimitOrder(address indexed user, bytes32 indexed orderHash, IBook.OpenDataInput data);
    event CancelLimitOrder(address indexed user, bytes32 indexed orderHash);
    event ExecuteLimitOrderRejected(address indexed user, bytes32 indexed orderHash, ITradingChecker.Refund refund);
    event LimitOrderRefund(address indexed user, bytes32 indexed orderHash, ITradingChecker.Refund refund);
    event ExecuteLimitOrderSuccessful(address indexed user, bytes32 indexed orderHash);

    function check(ILimitOrder.LimitOrder storage order) internal view {
        require(order.amountIn > 0, "LibLimitOrder: Order does not exist");
        require(order.user == msg.sender, "LibLimitOrder: Can only be updated by yourself");
    }

    function openLimitOrder(IBook.OpenDataInput memory data) internal {
        LimitOrderStorage storage los = limitOrderStorage();
        address user = msg.sender;
        bytes32[] storage orderHashes = los.userLimitOrderHashes[user];
        ILimitOrder.LimitOrder memory order = ILimitOrder.LimitOrder(
            user, uint32(orderHashes.length), data.price, data.pairBase, data.amountIn,
            data.tokenIn, data.isLong, data.broker, data.stopLoss, data.qty, data.takeProfit, uint40(block.timestamp)
        );
        bytes32 orderHash = keccak256(abi.encode(order, los.salt, "order"));
        los.salt++;
        los.limitOrders[orderHash] = order;
        orderHashes.push(orderHash);
        data.tokenIn.transferFrom(user, data.amountIn);
        los.limitOrderAmountIns[data.tokenIn] += data.amountIn;
        _createLimitOrder(orderHash, order);
        emit OpenLimitOrder(user, orderHash, data);
    }

    function _createLimitOrder(bytes32 orderHash, ILimitOrder.LimitOrder memory o) private {
        IOrderAndTradeHistory(address(this)).createLimitOrder(orderHash, IOrderAndTradeHistory.OrderInfo(
                o.user, o.amountIn, o.tokenIn, o.qty, o.isLong, o.pairBase, o.limitPrice
            )
        );
    }

    function _cancelLimitOrder(bytes32 orderHash, IOrderAndTradeHistory.ActionType aType) private {
        IOrderAndTradeHistory(address(this)).cancelLimitOrder(orderHash, aType);
    }

    function cancelLimitOrder(bytes32 orderHash) internal {
        LimitOrderStorage storage los = limitOrderStorage();
        ILimitOrder.LimitOrder storage order = los.limitOrders[orderHash];
        check(order);

        _cancelLimitOrder(orderHash, IOrderAndTradeHistory.ActionType.CANCEL_LIMIT);
        // After calling the _removeOrder function, the order will no longer be available. Therefore,
        // it is recommended to retrieve the necessary information for the safeTransfer function beforehand.
        (address tokenIn, address user, uint256 amountIn) = (order.tokenIn, order.user, order.amountIn);
        _removeOrder(los, order, orderHash);
        tokenIn.transfer(user, amountIn);
        emit CancelLimitOrder(msg.sender, orderHash);
    }

    function executeLimitOrder(
        bytes32 orderHash, uint64 marketPrice,
        uint96 openFee, uint96 executionFee,
        bool result, ITradingChecker.Refund refund
    ) internal {
        LimitOrderStorage storage los = limitOrderStorage();
        ILimitOrder.LimitOrder memory order = los.limitOrders[orderHash];
        if (!result) {
            if (refund == ITradingChecker.Refund.USER_PRICE || refund == ITradingChecker.Refund.PRICE_PROTECTION) {
                emit ExecuteLimitOrderRejected(order.user, orderHash, refund);
                return;
            } else {
                _cancelLimitOrder(orderHash, IOrderAndTradeHistory.ActionType.SYSTEM_CANCEL);
                (address tokenIn, address user, uint256 amountIn) = (order.tokenIn, order.user, order.amountIn);
                // remove open order
                _removeOrder(los, order, orderHash);

                tokenIn.transfer(user, amountIn);
                emit LimitOrderRefund(user, orderHash, refund);
            }
        } else {
            ITradingOpen(address(this)).limitOrderDeal(
                ITradingOpen.LimitOrder(
                    orderHash, order.user, order.limitPrice, order.pairBase, order.tokenIn,
                    order.amountIn - openFee - executionFee, order.stopLoss, order.takeProfit,
                    order.broker, order.isLong, openFee, executionFee, order.qty
                ),
                marketPrice
            );
            emit ExecuteLimitOrderSuccessful(order.user, orderHash);
            address tokenIn = order.tokenIn;
            // remove open order
            _removeOrder(los, order, orderHash);
            tokenIn.transfer(msg.sender, executionFee);
        }
    }

    function _removeOrder(
        LimitOrderStorage storage los,
        ILimitOrder.LimitOrder memory order,
        bytes32 orderHash
    ) private {
        bytes32[] storage userOrderHashes = los.userLimitOrderHashes[order.user];
        uint256 last = userOrderHashes.length - 1;
        uint256 orderIndex = order.userOpenOrderIndex;
        if (orderIndex != last) {
            bytes32 lastOrderHash = userOrderHashes[last];
            userOrderHashes[orderIndex] = lastOrderHash;
            los.limitOrders[lastOrderHash].userOpenOrderIndex = uint32(orderIndex);
        }
        userOrderHashes.pop();
        los.limitOrderAmountIns[order.tokenIn] -= order.amountIn;
        delete los.limitOrders[orderHash];
    }
}
