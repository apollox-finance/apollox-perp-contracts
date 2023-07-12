// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPairsManager.sol";
import "../interfaces/IOrderAndTradeHistory.sol";
import "../libraries/LibPairsManager.sol";
import "../libraries/LibOrderAndTradeHistory.sol";
import "../libraries/LibTrading.sol";

// In order to be compatible with the front-end call before the release,
// temporary use, front-end all updated, this Facet can be removed.
contract TransitionFacet {

    struct PairView {
        // BTC/USD
        string name;
        // BTC address
        address base;
        uint16 basePosition;
        IPairsManager.PairType pairType;
        IPairsManager.PairStatus status;
        uint256 maxLongOiUsd;
        uint256 maxShortOiUsd;
        uint256 fundingFeePerBlockP;  // 1e18
        uint256 minFundingFeeR;       // 1e18
        uint256 maxFundingFeeR;       // 1e18

        LibPairsManager.LeverageMargin[] leverageMargins;

        uint16 slippageConfigIndex;
        uint16 slippagePosition;
        LibPairsManager.SlippageConfig slippageConfig;

        uint16 feeConfigIndex;
        uint16 feePosition;
        LibFeeManager.FeeConfig feeConfig;
    }

    struct Position {
        bytes32 positionHash;
        // BTC/USD
        string pair;
        // pair.base
        address pairBase;
        address marginToken;
        bool isLong;
        uint96 margin;       // marginToken decimals
        uint80 qty;          // 1e10
        uint64 entryPrice;   // 1e8
        uint64 stopLoss;     // 1e8
        uint64 takeProfit;   // 1e8
        uint96 openFee;      // marginToken decimals
        uint96 executionFee; // marginToken decimals
        int256 fundingFee;   // marginToken decimals
        uint40 timestamp;
    }

    struct OrderAndTradeHistory {
        bytes32 hash;
        uint40 timestamp;
        string pair;
        IOrderAndTradeHistory.ActionType actionType;
        address tokenIn;
        bool isLong;
        uint96 amountIn;           // tokenIn decimals
        uint80 qty;                // 1e10
        uint64 entryPrice;         // 1e8

        uint96 margin;             // tokenIn decimals
        uint96 openFee;            // tokenIn decimals
        uint96 executionFee;       // tokenIn decimals

        uint64 closePrice;         // 1e8
        int96 fundingFee;          // tokenIn decimals
        uint96 closeFee;           // tokenIn decimals
        int96 pnl;                 // tokenIn decimals
    }

    function getPairByBase(address base) external view returns (PairView memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        LibPairsManager.Pair storage pair = pms.pairs[base];
        return _pairToView(pair, pms.slippageConfigs[pair.slippageConfigIndex]);
    }

    function pairs() external view returns (PairView[] memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        address[] memory bases = pms.pairBases;
        PairView[] memory pairViews = new PairView[](bases.length);
        for (uint i; i < bases.length; i++) {
            LibPairsManager.Pair storage pair = pms.pairs[bases[i]];
            pairViews[i] = _pairToView(pair, pms.slippageConfigs[pair.slippageConfigIndex]);
        }
        return pairViews;
    }

    function _pairToView(
        LibPairsManager.Pair storage pair, LibPairsManager.SlippageConfig memory slippageConfig
    ) private view returns (PairView memory) {
        LibPairsManager.LeverageMargin[] memory leverageMargins = new LibPairsManager.LeverageMargin[](pair.maxTier);
        for (uint16 i = 0; i < pair.maxTier; i++) {
            leverageMargins[i] = pair.leverageMargins[i + 1];
        }
        (LibFeeManager.FeeConfig memory feeConfig,) = LibFeeManager.getFeeConfigByIndex(pair.feeConfigIndex);
        PairView memory pv = PairView(
            pair.name, pair.base, pair.basePosition, pair.pairType, pair.status, pair.maxLongOiUsd, pair.maxShortOiUsd,
            pair.fundingFeePerBlockP, pair.minFundingFeeR, pair.maxFundingFeeR, leverageMargins,
            pair.slippageConfigIndex, pair.slippagePosition, slippageConfig,
            pair.feeConfigIndex, pair.feePosition, feeConfig
        );
        return pv;
    }

    function getPositionByHash(bytes32 tradeHash) public view returns (Position memory) {
        LibTrading.TradingStorage storage ts = LibTrading.tradingStorage();
        ITrading.OpenTrade memory ot = ts.openTrades[tradeHash];
        int256 fundingFee;
        if (ot.margin > 0) {
            (uint marketPrice,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(ot.pairBase);
            IVault.MarginToken memory mt = IVault(address(this)).getTokenForTrading(ot.tokenIn);
            fundingFee = LibTrading.calcFundingFee(ot, mt, marketPrice);
        }
        return Position(
            tradeHash, IPairsManager(address(this)).getPairForTrading(ot.pairBase).name, ot.pairBase,
            ot.tokenIn, ot.isLong, ot.margin, ot.qty, ot.entryPrice, ot.stopLoss, ot.takeProfit,
            ot.openFee, ot.executionFee, fundingFee, ot.timestamp
        );
    }

    function getPositions(address user, address pairBase) external view returns (Position[] memory){
        bytes32[] memory tradeHashes = LibTrading.tradingStorage().userOpenTradeHashes[user];
        // query all
        if (pairBase == address(0)) {
            Position[] memory positions = new Position[](tradeHashes.length);
            for (uint i; i < tradeHashes.length; i++) {
                positions[i] = getPositionByHash(tradeHashes[i]);
            }
            return positions;
        } else {
            Position[] memory _positions = new Position[](tradeHashes.length);
            uint count;
            for (uint i; i < tradeHashes.length; i++) {
                Position memory p = getPositionByHash(tradeHashes[i]);
                if (p.pairBase == pairBase) {
                    count++;
                }
                _positions[i] = p;
            }
            Position[] memory positions = new Position[](count);
            uint index;
            for (uint i; i < tradeHashes.length; i++) {
                Position memory p = _positions[i];
                if (p.pairBase == pairBase) {
                    positions[index] = p;
                    index++;
                }
            }
            return positions;
        }
    }

    function getOrderAndTradeHistory(
        address user, uint start, uint8 size
    ) external view returns (OrderAndTradeHistory[] memory datas) {
        LibOrderAndTradeHistory.OrderAndTradeHistoryStorage storage hs = LibOrderAndTradeHistory.historyStorage();

        if (start >= hs.actionInfos[user].length || size == 0) {
            datas = new OrderAndTradeHistory[](0);
        } else {
            uint count = hs.actionInfos[user].length - start > size ? size : hs.actionInfos[user].length - start;
            datas = new OrderAndTradeHistory[](count);
            for (UC i = ZERO; i < uc(count); i = i + ONE) {
                uint oldest = hs.actionInfos[user].length - (uc(start) + i + ONE).into();
                IOrderAndTradeHistory.ActionInfo memory ai = hs.actionInfos[user][oldest];
                IOrderAndTradeHistory.OrderInfo memory oi = hs.orderInfos[ai.hash];
                string memory name = IPairsManager(address(this)).getPairForTrading(oi.pairBase).name;
                if (
                    ai.actionType == IOrderAndTradeHistory.ActionType.LIMIT
                    || ai.actionType == IOrderAndTradeHistory.ActionType.CANCEL_LIMIT
                    || ai.actionType == IOrderAndTradeHistory.ActionType.SYSTEM_CANCEL
                ) {
                    datas[i.into()] = OrderAndTradeHistory(
                        ai.hash, ai.timestamp, name, ai.actionType, oi.tokenIn, oi.isLong, oi.amountIn, oi.qty,
                        oi.entryPrice, 0, 0, 0, 0, 0, 0, 0
                    );
                } else if (ai.actionType == IOrderAndTradeHistory.ActionType.OPEN) {
                    IOrderAndTradeHistory.TradeInfo memory ti = hs.tradeInfos[ai.hash];
                    datas[i.into()] = OrderAndTradeHistory(
                        ai.hash, ai.timestamp, name, ai.actionType, oi.tokenIn, oi.isLong, oi.amountIn,
                        oi.qty, oi.entryPrice, ti.margin, ti.openFee, ti.executionFee, 0, 0, 0, 0
                    );
                } else {
                    IOrderAndTradeHistory.TradeInfo memory ti = hs.tradeInfos[ai.hash];
                    IOrderAndTradeHistory.CloseInfo memory ci = hs.closeInfos[ai.hash];
                    datas[i.into()] = OrderAndTradeHistory(
                        ai.hash, ai.timestamp, name, ai.actionType, oi.tokenIn, oi.isLong, oi.amountIn,
                        oi.qty, oi.entryPrice, ti.margin, ti.openFee, ti.executionFee,
                        ci.closePrice, ci.fundingFee, ci.closeFee, ci.pnl
                    );
                }
            }
        }
        return datas;
    }
}
