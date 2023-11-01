// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPriceFacade.sol";
import "../interfaces/ITradingCore.sol";
import "../interfaces/ITradingReader.sol";
import "../libraries/LibTrading.sol";
import "../libraries/LibLimitOrder.sol";
import "../libraries/LibTradingCore.sol";
import "../libraries/LibPredictUpDown.sol";

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

    function getPositionByHashV2(bytes32 tradeHash) public view override returns (Position memory) {
        LibTrading.TradingStorage storage ts = LibTrading.tradingStorage();
        ITrading.OpenTrade storage ot = ts.openTrades[tradeHash];
        int256 fundingFee;
        uint96 holdingFee;
        if (ot.margin > 0) {
            (uint marketPrice,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(ot.pairBase);
            IVault.MarginToken memory mt = IVault(address(this)).getTokenForTrading(ot.tokenIn);
            fundingFee = LibTrading.calcFundingFee(ot, mt, marketPrice);
            holdingFee = uint96(LibTrading.calcHoldingFee(ot, mt));
        }
        return Position(
            tradeHash, IPairsManager(address(this)).getPairForTrading(ot.pairBase).name, ot.pairBase,
            ot.tokenIn, ot.isLong, ot.margin, ot.qty, ot.entryPrice, ot.stopLoss, ot.takeProfit,
            ot.openFee, ot.executionFee, fundingFee, ot.timestamp, holdingFee
        );
    }

    function getPositionsV2(address user, address pairBase) external view override returns (Position[] memory){
        bytes32[] memory tradeHashes = LibTrading.tradingStorage().userOpenTradeHashes[user];
        // query all
        if (pairBase == address(0)) {
            Position[] memory positions = new Position[](tradeHashes.length);
            for (uint i; i < tradeHashes.length; i++) {
                positions[i] = getPositionByHashV2(tradeHashes[i]);
            }
            return positions;
        } else {
            Position[] memory _positions = new Position[](tradeHashes.length);
            uint count;
            for (uint i; i < tradeHashes.length; i++) {
                Position memory p = getPositionByHashV2(tradeHashes[i]);
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
        TraderAsset[] memory assets = new TraderAsset[](tokens.length * 5);
        if (tokens.length > 0) {
            for (uint i; i < tokens.length; i++) {
                address token = tokens[i];
                assets[i * 3] = TraderAsset(AssetPurpose.LIMIT, token, LibLimitOrder.limitOrderStorage().limitOrderAmountIns[token]);
                assets[i * 3 + 1] = TraderAsset(AssetPurpose.PENDING, token, LibTrading.tradingStorage().pendingTradeAmountIns[token]);
                assets[i * 3 + 2] = TraderAsset(AssetPurpose.POSITION, token, LibTrading.tradingStorage().openTradeAmountIns[token]);
                assets[i * 3 + 3] = TraderAsset(AssetPurpose.PREDICTION_PENDING, token, LibPredictUpDown.predictionUpDownStorage().pendingPredictionAmountIns[token]);
                assets[i * 3 + 4] = TraderAsset(AssetPurpose.PREDICTION, token, LibPredictUpDown.predictionUpDownStorage().openPredictionAmountIns[token]);
            }
        }
        return assets;
    }
}
