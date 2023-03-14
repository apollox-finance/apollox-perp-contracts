// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Bits.sol";
import "../interfaces/ITradingConfig.sol";

library LibTradingConfig {

    using Bits for uint;

    bytes32 constant TRADING_CONFIG_POSITION = keccak256("apollox.trading.config.storage");

    struct TradingConfigStorage {
        uint256 executionFeeUsd;
        uint256 minNotionalUsd;
        uint24 maxTakeProfitP;
        // ITradingConfig.TradingSwitch
        uint16 tradingSwitches;
    }

    function tradingConfigStorage() internal pure returns (TradingConfigStorage storage tcs) {
        bytes32 position = TRADING_CONFIG_POSITION;
        assembly {
            tcs.slot := position
        }
    }

    event SetTradeSwitches(uint16 indexed oldTradeSwitches, uint16 indexed tradeSwitches);
    event SetExecutionFeeUsd(uint256 oldExecutionFeeUsd, uint256 executionFeeUsd);
    event SetMinNotionalUsd(uint256 oldMinNotionalUsd, uint256 minNotionalUsd);
    event SetMaxTakeProfitP(uint24 oldMaxTakeProfitP, uint24 maxTakeProfitP);

    function initialize(uint256 executionFeeUsd, uint256 minNotionalUsd, uint24 maxTakeProfitP) internal {
        TradingConfigStorage storage tcs = tradingConfigStorage();
        require(tcs.executionFeeUsd == 0 && tcs.minNotionalUsd == 0 && tcs.maxTakeProfitP == 0, "LibTradingConfig: Already initialized");
        setExecutionFeeUsd(executionFeeUsd);
        setMinNotionalUsd(minNotionalUsd);
        setMaxTakeProfitP(maxTakeProfitP);
        // 1+2+4+8+16+32 = 63
        setTradingSwitches(63);
    }

    function setTradingSwitches(uint16 switches) internal {
        TradingConfigStorage storage tcs = tradingConfigStorage();
        uint16 old = tcs.tradingSwitches;
        require(old != switches, "LibTradingConfig: No switches are updated");
        tcs.tradingSwitches = switches;
        emit SetTradeSwitches(old, switches);
    }

    function setExecutionFeeUsd(uint256 executionFeeUsd) internal {
        TradingConfigStorage storage tcs = tradingConfigStorage();
        uint256 oldExecutionFeeUsd = tcs.executionFeeUsd;
        tcs.executionFeeUsd = executionFeeUsd;
        emit SetExecutionFeeUsd(oldExecutionFeeUsd, executionFeeUsd);
    }

    function setMinNotionalUsd(uint256 minNotionalUsd) internal {
        require(minNotionalUsd > 0, "LibTradingConfig: minNotionalUsd must be greater than 0");
        TradingConfigStorage storage tcs = tradingConfigStorage();
        uint256 old = tcs.minNotionalUsd;
        tcs.minNotionalUsd = minNotionalUsd;
        emit SetMinNotionalUsd(old, minNotionalUsd);
    }

    function setMaxTakeProfitP(uint24 maxTakeProfitP) internal {
        require(maxTakeProfitP > 0, "LibTradingConfig: maxTakeProfitP must be greater than 0");
        TradingConfigStorage storage tcs = tradingConfigStorage();
        uint24 old = tcs.maxTakeProfitP;
        tcs.maxTakeProfitP = maxTakeProfitP;
        emit SetMaxTakeProfitP(old, maxTakeProfitP);
    }

    function checkTradeSwitch(ITradingConfig.TradingSwitch tradingSwitch) internal view {
        require(uint(tradingConfigStorage().tradingSwitches).bitSet(uint8(tradingSwitch)), "LibTradingConfig: This feature is temporarily disabled");
    }
}
