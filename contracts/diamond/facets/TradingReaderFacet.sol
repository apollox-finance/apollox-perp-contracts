// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPriceFacade.sol";
import "../interfaces/ITradingCore.sol";
import "../interfaces/ITradingReader.sol";
import "../libraries/LibTrading.sol";
import "../libraries/LibLimitOrder.sol";
import "../libraries/LibTradingCore.sol";

contract TradingReaderFacet is ITradingReader {

    function getMarketInfo(address pairBase) public view override returns (MarketInfo memory) {
        ITradingCore.PairPositionInfo memory ppi = LibTradingCore.tradingCoreStorage().pairPositionInfos[pairBase];
        return MarketInfo(pairBase, ppi.longQty, ppi.shortQty, ppi.lpLongAvgPrice, ppi.lpShortAvgPrice, LibTradingCore.fundingFeeRate(ppi, pairBase));
    }

    function getMarketInfos(address[] calldata pairBases) external view override returns (MarketInfo[] memory) {
        MarketInfo[] memory marketInfos = new MarketInfo[](pairBases.length);
        for (uint i; i < pairBases.length; i++) {
            marketInfos[i] = getMarketInfo(pairBases[i]);
        }
        return marketInfos;
    }

    function getPendingTrade(bytes32 tradeHash) external view override returns (PendingTrade memory) {
        return LibTrading.tradingStorage().pendingTrades[tradeHash];
    }

    function getPositionByHash(bytes32 tradeHash) public view override returns (Position memory) {
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

    function getPositions(address user, address pairBase) external view override returns (Position[] memory){
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

    function traderAssets(address[] memory tokens) external view override returns (TraderAsset[] memory) {
        TraderAsset[] memory assets = new TraderAsset[](tokens.length * 3);
        if (tokens.length > 0) {
            for (uint i; i < tokens.length; i++) {
                address token = tokens[i];
                assets[i * 3] = TraderAsset(AssetPurpose.LIMIT, token, LibLimitOrder.limitOrderStorage().limitOrderAmountIns[token]);
                assets[i * 3 + 1] = TraderAsset(AssetPurpose.PENDING, token, LibTrading.tradingStorage().pendingTradeAmountIns[token]);
                assets[i * 3 + 2] = TraderAsset(AssetPurpose.POSITION, token, LibTrading.tradingStorage().openTradeAmountIns[token]);
            }
        }
        return assets;
    }
}
