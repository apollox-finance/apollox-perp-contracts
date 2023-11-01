// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPriceFacade.sol";
import "../interfaces/ITradingConfig.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

library LibTradingConfig {

    bytes32 constant TRADING_CONFIG_POSITION = keccak256("apollox.trading.config.storage");

    // obsolete
    struct PriceProtection {
        uint40 updatedAt;
        uint64 upperPrice;  // 1e8
        uint64 lowerPrice;  // 1e8
    }

    struct TradingConfigStorage {
        uint256 executionFeeUsd;
        uint256 minNotionalUsd;
        uint24 maxTakeProfitP;
        // ITradingConfig.TradingSwitch
        uint16 tradingSwitches;
        mapping(address pairBase => PriceProtection) priceProtections;  // obsolete
        mapping(address pairBase => ITradingConfig.MaxTpRatioForLeverage[]) maxTpRatios;
        uint256 minBetUsd;
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
    event SetMinBetUsd(uint256 oldMinBetUsd, uint256 minBetUsd);
    event SetMaxTakeProfitP(uint24 oldMaxTakeProfitP, uint24 maxTakeProfitP);
    event SetMaxTpRatioForLeverage(address indexed pairBase, ITradingConfig.MaxTpRatioForLeverage[] maxTpRatios);

    function initialize(
        uint256 executionFeeUsd, uint256 minNotionalUsd, uint24 maxTakeProfitP, uint256 minBetUsd
    ) internal {
        TradingConfigStorage storage tcs = tradingConfigStorage();
        require(tcs.executionFeeUsd == 0 && tcs.minNotionalUsd == 0 && tcs.maxTakeProfitP == 0, "LibTradingConfig: Already initialized");
        setExecutionFeeUsd(executionFeeUsd);
        setMinNotionalUsd(minNotionalUsd);
        setMaxTakeProfitP(maxTakeProfitP);
        setMinBetUsd(minBetUsd);
        // 1+2+4+8+16+32+64+128 = 255
        setTradingSwitches(255);
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

    function setMinBetUsd(uint256 minBetUsd) internal {
        require(minBetUsd > 0, "LibTradingConfig: minBetUsd must be greater than 0");
        TradingConfigStorage storage tcs = tradingConfigStorage();
        uint256 old = tcs.minBetUsd;
        tcs.minBetUsd = minBetUsd;
        emit SetMinBetUsd(old, minBetUsd);
    }

    function setMaxTakeProfitP(uint24 maxTakeProfitP) internal {
        require(maxTakeProfitP > 0, "LibTradingConfig: maxTakeProfitP must be greater than 0");
        TradingConfigStorage storage tcs = tradingConfigStorage();
        uint24 old = tcs.maxTakeProfitP;
        tcs.maxTakeProfitP = maxTakeProfitP;
        emit SetMaxTakeProfitP(old, maxTakeProfitP);
    }

    function setMaxTpRatioForLeverage(address pairBase, ITradingConfig.MaxTpRatioForLeverage[] calldata maxTpRatios) internal {
        delete tradingConfigStorage().maxTpRatios[pairBase];
        ITradingConfig.MaxTpRatioForLeverage[] storage tpRatios = tradingConfigStorage().maxTpRatios[pairBase];
        UC size = uc(maxTpRatios.length);
        for (UC i = ZERO; i < size; i = i + ONE) {
            ITradingConfig.MaxTpRatioForLeverage calldata tpRatio = maxTpRatios[i.into()];
            if (i + ONE < size) {
                ITradingConfig.MaxTpRatioForLeverage calldata nextTpRatio = maxTpRatios[(i + ONE).into()];
                require(tpRatio.leverage < nextTpRatio.leverage, "LibTradingConfig: leverage multipliers need to be in the order from smallest to largest");
            }
            tpRatios.push(tpRatio);
        }
        emit SetMaxTpRatioForLeverage(pairBase, maxTpRatios);
    }
}
