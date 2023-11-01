// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITradingConfig {

    event SetTradeSwitches(uint16 indexed oldTradeSwitches, uint16 indexed tradeSwitches);
    event SetExecutionFeeUsd(uint256 oldExecutionFeeUsd, uint256 executionFeeUsd);
    event SetMinNotionalUsd(uint256 oldMinNotionalUsd, uint256 minNotionalUsd);
    event SetMaxTakeProfitP(uint24 oldMaxTakeProfitP, uint24 maxTakeProfitP);
    event SetMaxTpRatioForLeverage(address indexed pairBase, MaxTpRatioForLeverage[] maxTpRatios);

    /*
    |-----------> 8 bit <-----------|
    |---|---|---|---|---|---|---|---|
    | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
    |---|---|---|---|---|---|---|---|
    */
    enum TradingSwitch {
        LIMIT_ORDER,
        EXECUTE_LIMIT_ORDER,
        MARKET_TRADING,
        USER_CLOSE_TRADING,
        TP_SL_CLOSE_TRADING,
        LIQUIDATE_TRADING,
        PREDICTION_BET,
        PREDICTION_SETTLE
    }

    struct TradingConfig {
        uint256 executionFeeUsd;
        uint256 minNotionalUsd;
        uint24 maxTakeProfitP;
        bool limitOrder;
        bool executeLimitOrder;
        bool marketTrading;
        bool userCloseTrading;
        bool tpSlCloseTrading;
        bool liquidateTrading;
    }

    struct PriceConfig {
        address pairBase;
        uint64 upperPrice;  // 1e8
        uint64 lowerPrice;  // 1e8
    }

    struct MaxTpRatioForLeverage {
        uint16 leverage;
        uint24 maxTakeProfitP;
    }

    struct PredictionConfig {
        uint256 minBetUsd;
        bool predictionBet;
        bool predictionSettle;
    }

    function getTradingConfig() external view returns (TradingConfig memory);

    function getPredictionConfig() external view returns (PredictionConfig memory);

    function setTradingSwitches(
        bool limitOrder, bool executeLimitOrder, bool marketTrade,
        bool userCloseTrade, bool tpSlCloseTrade, bool liquidateTrade,
        bool predictBet, bool predictSettle
    ) external;

    function setExecutionFeeUsd(uint256 executionFeeUsd) external;

    function setMinNotionalUsd(uint256 minNotionalUsd) external;

    function setMinBetUsd(uint256 minBetUsd) external;

    function setMaxTakeProfitP(uint24 maxTakeProfitP) external;

    function setMaxTpRatioForLeverage(address pairBase, MaxTpRatioForLeverage[] calldata maxTpRatios) external;

    function getPairMaxTpRatios(address pairBase) external view returns (MaxTpRatioForLeverage[] memory);

    function getPairMaxTpRatio(address pairBase, uint256 leverage_10000) external view returns (uint24);
}
