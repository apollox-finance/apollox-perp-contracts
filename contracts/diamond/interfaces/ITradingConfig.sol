// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITradingConfig {
    /*
    |-----------> 8 bit <-----------|
    |---|---|---|---|---|---|---|---|
    |   |   | 5 | 4 | 3 | 2 | 1 | 0 |
    |---|---|---|---|---|---|---|---|
    */
    enum TradingSwitch {
        LIMIT_ORDER,
        EXECUTE_LIMIT_ORDER,
        MARKET_TRADING,
        USER_CLOSE_TRADING,
        TP_SL_CLOSE_TRADING,
        LIQUIDATE_TRADING
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

    function getTradingConfig() external view returns (TradingConfig memory);

    function setTradingSwitches(
        bool limitOrder, bool executeLimitOrder, bool marketTrade,
        bool userCloseTrade, bool tpSlCloseTrade, bool liquidateTrade
    ) external;

    function setExecutionFeeUsd(uint256 executionFeeUsd) external;

    function setMinNotionalUsd(uint256 minNotionalUsd) external;

    function setMaxTakeProfitP(uint24 maxTakeProfitP) external;
}
