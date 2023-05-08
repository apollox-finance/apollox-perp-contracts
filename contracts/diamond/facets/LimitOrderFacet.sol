// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../interfaces/ILimitOrder.sol";
import "../interfaces/IPriceFacade.sol";
import "../interfaces/IPairsManager.sol";
import "../interfaces/ITradingChecker.sol";
import "../libraries/LibLimitOrder.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract LimitOrderFacet is ILimitOrder {

    function openLimitOrder(OpenDataInput calldata data) external override {
        ITradingChecker(address(this)).openLimitOrderCheck(data);
        LibLimitOrder.openLimitOrder(data);
    }

    function updateOrderTp(bytes32 orderHash, uint64 takeProfit) public override {
        LimitOrder storage order = LibLimitOrder.limitOrderStorage().limitOrders[orderHash];
        LibLimitOrder.check(order);
        uint256 oldTp = order.takeProfit;
        order.takeProfit = takeProfit;
        ITradingChecker(address(this)).checkLimitOrderTp(order);

        emit UpdateOrderTp(msg.sender, orderHash, oldTp, takeProfit);
    }

    function updateOrderSl(bytes32 orderHash, uint64 stopLoss) public override {
        LimitOrder storage order = LibLimitOrder.limitOrderStorage().limitOrders[orderHash];
        LibLimitOrder.check(order);
        require(ITradingChecker(address(this)).checkSl(order.isLong, stopLoss, order.limitPrice), "LimitOrderFacet: stopLoss is not in the valid range");
        uint256 oldSl = order.stopLoss;
        order.stopLoss = stopLoss;

        emit UpdateOrderSl(msg.sender, orderHash, oldSl, stopLoss);
    }

    // stopLoss is allowed to be equal to 0, which means the sl setting is removed.
    // takeProfit must be greater than 0
    function updateOrderTpAndSl(bytes32 orderHash, uint64 takeProfit, uint64 stopLoss) external override {
        updateOrderTp(orderHash, takeProfit);
        updateOrderSl(orderHash, stopLoss);
    }

    function executeLimitOrder(KeeperExecution[] memory executeOrders) external override {
        LibAccessControlEnumerable.checkRole(Constants.KEEPER_ROLE);
        require(executeOrders.length > 0, "LimitOrderFacet: Parameters are empty");
        LibLimitOrder.LimitOrderStorage storage los = LibLimitOrder.limitOrderStorage();
        for (UC i = ZERO; i < uc(executeOrders.length); i = i + ONE) {
            KeeperExecution memory ke = executeOrders[i.into()];
            LimitOrder memory order = los.limitOrders[ke.hash];
            require(order.amountIn > 0, "LimitOrderFacet: Order does not exist");
            (bool available, uint64 upper, uint64 lower) = IPriceFacade(address(this)).confirmTriggerPrice(order.pairBase, ke.price);
            if (!available) {
                emit ExecuteLimitOrderRejected(order.user, ke.hash, ITradingChecker.Refund.SYSTEM);
                continue;
            }
            uint64 marketPrice = order.isLong ? upper : lower;

            (bool result, uint96 openFee, uint96 executionFee, ITradingChecker.Refund refund) = ITradingChecker(address(this)).executeLimitOrderCheck(order, marketPrice);
            LibLimitOrder.executeLimitOrder(ke.hash, marketPrice, openFee, executionFee, result, refund);
        }
    }

    function cancelLimitOrder(bytes32 orderHash) external override {
        LibLimitOrder.cancelLimitOrder(orderHash);
    }

    function getLimitOrderByHash(bytes32 orderHash) public view override returns (LimitOrderView memory) {
        LimitOrder memory o = LibLimitOrder.limitOrderStorage().limitOrders[orderHash];
        return LimitOrderView(
            orderHash, IPairsManager(address(this)).getPairByBase(o.pairBase).name, o.pairBase, o.isLong,
            o.tokenIn, o.amountIn, o.qty, o.limitPrice, o.stopLoss, o.takeProfit, o.broker, o.timestamp
        );
    }

    function getLimitOrders(address user, address pairBase) external view override returns (LimitOrderView[] memory) {
        bytes32[] memory orderHashes = LibLimitOrder.limitOrderStorage().userLimitOrderHashes[user];
        // query all
        if (pairBase == address(0)) {
            LimitOrderView[] memory orders = new LimitOrderView[](orderHashes.length);
            for (uint i; i < orderHashes.length; i++) {
                orders[i] = getLimitOrderByHash(orderHashes[i]);
            }
            return orders;
        } else {
            LimitOrderView[] memory _orders = new LimitOrderView[](orderHashes.length);
            UC count = ZERO;
            for (UC i = ZERO; i < uc(orderHashes.length); i = i + ONE) {
                LimitOrderView memory p = getLimitOrderByHash(orderHashes[i.into()]);
                if (p.pairBase == pairBase) {
                    count = count + ONE;
                }
                _orders[i.into()] = p;
            }
            LimitOrderView[] memory orders = new LimitOrderView[](count.into());
            UC index = ZERO;
            for (UC i = ZERO; i < uc(orderHashes.length); i = i + ONE) {
                LimitOrderView memory p = _orders[i.into()];
                if (p.pairBase == pairBase) {
                    orders[index.into()] = p;
                    index = index + ONE;
                }
            }
            return orders;
        }
    }
}
