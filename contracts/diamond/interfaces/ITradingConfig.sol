// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITradingConfig {

    event SetTradeSwitches(uint16 indexed oldTradeSwitches, uint16 indexed tradeSwitches);
    event SetExecutionFeeUsd(uint256 oldExecutionFeeUsd, uint256 executionFeeUsd);
    event SetMinNotionalUsd(uint256 oldMinNotionalUsd, uint256 minNotionalUsd);
    event SetMaxTakeProfitP(uint24 oldMaxTakeProfitP, uint24 maxTakeProfitP);
    event UpdateProtectionPrice(address indexed pairBase, uint64 upperPrice, uint64 lowerPrice);

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

    struct PriceProtection {
        uint40 updatedAt;
        uint64 upperPrice;  // 1e8
        uint64 lowerPrice;  // 1e8
    }

    struct PriceConfig {
        address pairBase;
        uint64 upperPrice;  // 1e8
        uint64 lowerPrice;  // 1e8
    }

    function getTradingConfig() external view returns (TradingConfig memory);

    function setTradingSwitches(
        bool limitOrder, bool executeLimitOrder, bool marketTrade,
        bool userCloseTrade, bool tpSlCloseTrade, bool liquidateTrade
    ) external;

    function setExecutionFeeUsd(uint256 executionFeeUsd) external;

    function setMinNotionalUsd(uint256 minNotionalUsd) external;

    function setMaxTakeProfitP(uint24 maxTakeProfitP) external;

    function updateProtectionPrice(PriceConfig[] calldata priceConfigs) external;

    function getProtectionPrice(address pairBase) external view returns (PriceProtection memory);
}
