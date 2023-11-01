// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/TransferHelper.sol";
import "../security/OnlySelf.sol";
import "../interfaces/IVault.sol";
import "../interfaces/ITradingPortal.sol";
import {RequestType, IPriceFacade} from "../interfaces/IPriceFacade.sol";
import "../interfaces/IPairsManager.sol";
import "../interfaces/ITradingConfig.sol";
import "../interfaces/ITradingChecker.sol";
import "../libraries/LibTrading.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract TradingPortalFacet is ITradingPortal, OnlySelf {

    using TransferHelper for address;

    function _check(ITrading.OpenTrade storage ot) internal view {
        require(ot.margin > 0, "TradingPortalFacet: Trade information does not exist");
        require(ot.user == msg.sender, "TradingPortalFacet: Can only be updated by yourself");
    }

    function openMarketTrade(OpenDataInput memory data) external override {
        _openMarketTrade(data);
    }

    function openMarketTradeBNB(OpenDataInput memory data) external payable override {
        data.tokenIn = TransferHelper.nativeWrapped();
        data.amountIn = uint96(msg.value);
        _openMarketTrade(data);
    }

    function _openMarketTrade(OpenDataInput memory data) private {
        ITradingChecker(address(this)).openMarketTradeCheck(data);

        LibTrading.TradingStorage storage ts = LibTrading.tradingStorage();
        address user = msg.sender;
        ITrading.PendingTrade memory pt = ITrading.PendingTrade(
            user, data.broker, data.isLong, data.price, data.pairBase, data.amountIn,
            data.tokenIn, data.qty, data.stopLoss, data.takeProfit, uint128(block.number)
        );
        bytes32 tradeHash = keccak256(abi.encode(pt, ts.salt, "trade"));
        ts.salt++;
        ts.pendingTrades[tradeHash] = pt;
        data.tokenIn.transferFrom(user, data.amountIn);
        ts.pendingTradeAmountIns[data.tokenIn] += data.amountIn;
        IPriceFacade(address(this)).requestPrice(tradeHash, data.pairBase, RequestType.OPEN);
        emit MarketPendingTrade(user, tradeHash, data);
    }

    function updateTradeTp(bytes32 tradeHash, uint64 takeProfit) public override {
        OpenTrade storage ot = LibTrading.tradingStorage().openTrades[tradeHash];
        _check(ot);
        uint256 oldTp = ot.takeProfit;
        ot.takeProfit = takeProfit;
        ITradingChecker(address(this)).checkMarketTradeTp(ot);

        emit UpdateTradeTp(msg.sender, tradeHash, oldTp, takeProfit);
    }

    function updateTradeSl(bytes32 tradeHash, uint64 stopLoss) public override {
        OpenTrade storage ot = LibTrading.tradingStorage().openTrades[tradeHash];
        _check(ot);
        require(ITradingChecker(address(this)).checkSl(ot.isLong, stopLoss, ot.entryPrice), "TradingPortalFacet: stopLoss is not in the valid range");

        uint256 oldSl = ot.stopLoss;
        ot.stopLoss = stopLoss;
        emit UpdateTradeSl(msg.sender, tradeHash, oldSl, stopLoss);
    }

    // stopLoss is allowed to be equal to 0, which means the sl setting is removed.
    // takeProfit must be greater than 0
    function updateTradeTpAndSl(bytes32 tradeHash, uint64 takeProfit, uint64 stopLoss) external override {
        updateTradeTp(tradeHash, takeProfit);
        updateTradeSl(tradeHash, stopLoss);
    }

    /*
       token   balance     balanceUsd
       USDT     80000        80012
       USDC     60000        59946
       BUSD     200           200

       totalBalanceUsd = 80012 + 59946 + 200 = 140158

       points
       USDC = 59946 * 10000 / 140158 = 4277
       BUSD = 200 * 10000 / 140158 = 14
       USDT = 10000 - 4277 - 14 = 5709
   */
    function settleLpFundingFee(uint256 lpReceiveFundingFeeUsd) external onlySelf override {
        LibTrading.TradingStorage storage ts = LibTrading.tradingStorage();
        address[] memory tokenIns = ts.openTradeTokenIns;

        if (tokenIns.length == 1) {
            IVault.MarginToken memory mt = IVault(address(this)).getTokenForTrading(tokenIns[0]);
            MarginBalance memory mb = MarginBalance(tokenIns[0], mt.price, mt.decimals, 0);
            _transferFundingFeeToVault(ts, mb, lpReceiveFundingFeeUsd, 1e4);
        } else {
            MarginBalance[] memory balances = new MarginBalance[](tokenIns.length);
            uint256 totalBalanceUsd;
            UC index = ZERO;
            for (UC i = ZERO; i < uc(tokenIns.length); i = i + ONE) {
                IVault.MarginToken memory mt = IVault(address(this)).getTokenForTrading(tokenIns[i.into()]);
                if (mt.switchOn && ts.openTradeAmountIns[tokenIns[i.into()]] > 0) {
                    uint balanceUsd = mt.price * ts.openTradeAmountIns[tokenIns[i.into()]] * 1e10 / (10 ** mt.decimals);
                    balances[index.into()] = MarginBalance(tokenIns[i.into()], mt.price, mt.decimals, balanceUsd);
                    totalBalanceUsd += balanceUsd;
                    index = index + ONE;
                }
            }
            uint points = 1e4;
            for (UC i = ONE; i < index; i = i + uc(1)) {
                MarginBalance memory mb = balances[i.into()];
                uint share = mb.balanceUsd * 1e4 / totalBalanceUsd;
                points -= share;
                _transferFundingFeeToVault(ts, mb, lpReceiveFundingFeeUsd, share);
            }
            _transferFundingFeeToVault(ts, balances[0], lpReceiveFundingFeeUsd, points);
        }
    }

    function _transferFundingFeeToVault(
        LibTrading.TradingStorage storage ts,
        ITrading.MarginBalance memory mb,
        uint256 lpReceiveFundingFeeUsd,
        uint256 share
    ) private {
        uint lpFundingFee = lpReceiveFundingFeeUsd * share * (10 ** mb.decimals) / (1e4 * 1e10 * mb.price);
        ts.openTradeAmountIns[mb.token] -= lpFundingFee;
        IVault(address(this)).increase(mb.token, lpFundingFee);
        emit FundingFeeAddLiquidity(mb.token, lpFundingFee);
    }

    function closeTrade(bytes32 tradeHash) external override {
        OpenTrade storage ot = LibTrading.tradingStorage().openTrades[tradeHash];
        _check(ot);
        ITradingConfig.TradingConfig memory tc = ITradingConfig(address(this)).getTradingConfig();
        require(tc.userCloseTrading, "TradingPortalFacet: This feature is temporarily disabled");
        require(
            IPairsManager(address(this)).getPairForTrading(ot.pairBase).status != IPairsManager.PairStatus.CLOSE,
            "TradingPortalFacet: pair does not support close position"
        );
        IPriceFacade(address(this)).requestPrice(tradeHash, ot.pairBase, RequestType.CLOSE);
    }

    function addMargin(bytes32 tradeHash, uint96 amount) external payable override {
        require(amount > 0, "TradingPortalFacet: amount must be greater than 0");
        LibTrading.TradingStorage storage ts = LibTrading.tradingStorage();
        OpenTrade storage ot = ts.openTrades[tradeHash];
        _check(ot);
        uint96 beforeMargin = ot.margin;
        ot.margin += amount;
        ts.openTradeAmountIns[ot.tokenIn] += amount;
        IOrderAndTradeHistory(address(this)).updateMargin(tradeHash, ot.margin);
        ot.tokenIn.transferFrom(msg.sender, amount);
        emit UpdateMargin(msg.sender, tradeHash, beforeMargin, ot.margin);
    }
}
