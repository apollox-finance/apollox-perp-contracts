// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ITrading.sol";
import "./ITradingCore.sol";

interface ITradingReader is ITrading {

    struct MarketInfo {
        address pairBase;
        uint256 longQty;              // 1e10
        uint256 shortQty;             // 1e10
        uint64 lpLongAvgPrice;        // 1e8
        uint64 lpShortAvgPrice;       // 1e8
        int256 fundingFeeRate;        // 1e18
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
    enum AssetPurpose {
        LIMIT, PENDING, POSITION
    }
    struct TraderAsset {
        AssetPurpose purpose;
        address token;
        uint256 value;
    }

    function getMarketInfo(address pairBase) external view returns (MarketInfo memory);

    function getMarketInfos(address[] calldata pairBases) external view returns (MarketInfo[] memory);

    function getPendingTrade(bytes32 tradeHash) external view returns (PendingTrade memory);

    function getPositionByHash(bytes32 tradeHash) external view returns (Position memory);

    function getPositions(address user, address pairBase) external view returns (Position[] memory);

    function traderAssets(address[] memory tokens) external view returns (TraderAsset[] memory);
}
