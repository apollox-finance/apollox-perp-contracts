// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Bits.sol";
import "../../utils/Constants.sol";
import "../interfaces/IPairsManager.sol";
import "../interfaces/ITradingConfig.sol";
import "../libraries/LibTradingConfig.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract TradingConfigFacet is ITradingConfig {

    using Bits for uint;

    function initTradingConfigFacet(
        uint256 executionFeeUsd, uint256 minNotionalUsd, uint24 maxTakeProfitP, uint256 minBetUsd
    ) external {
        require(minNotionalUsd > 0 && maxTakeProfitP > 0 && minBetUsd > 0, "TradingConfigFacet: Invalid parameter");
        LibAccessControlEnumerable.checkRole(Constants.DEPLOYER_ROLE);
        LibTradingConfig.initialize(executionFeeUsd, minNotionalUsd, maxTakeProfitP, minBetUsd);
    }

    function getTradingConfig() external view override returns (TradingConfig memory) {
        LibTradingConfig.TradingConfigStorage storage tcs = LibTradingConfig.tradingConfigStorage();
        uint switches = tcs.tradingSwitches;
        return TradingConfig(
            tcs.executionFeeUsd, tcs.minNotionalUsd, tcs.maxTakeProfitP,
            switches.bitSet(uint8(TradingSwitch.LIMIT_ORDER)), switches.bitSet(uint8(TradingSwitch.EXECUTE_LIMIT_ORDER)),
            switches.bitSet(uint8(TradingSwitch.MARKET_TRADING)), switches.bitSet(uint8(TradingSwitch.USER_CLOSE_TRADING)),
            switches.bitSet(uint8(TradingSwitch.TP_SL_CLOSE_TRADING)), switches.bitSet(uint8(TradingSwitch.LIQUIDATE_TRADING))
        );
    }

    function getPredictionConfig() external view returns (PredictionConfig memory) {
        LibTradingConfig.TradingConfigStorage storage tcs = LibTradingConfig.tradingConfigStorage();
        uint switches = tcs.tradingSwitches;
        return PredictionConfig(
            tcs.minBetUsd,
            switches.bitSet(uint8(TradingSwitch.PREDICTION_BET)),
            switches.bitSet(uint8(TradingSwitch.PREDICTION_SETTLE))
        );
    }

    function setTradingSwitches(
        bool limitOrder, bool executeLimitOrder, bool marketTrade,
        bool userCloseTrade, bool tpSlCloseTrade, bool liquidateTradeSwitch,
        bool predictBet, bool predictSettle
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.MONITOR_ROLE);
        uint tradeSwitches = 0;
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.LIMIT_ORDER), limitOrder);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.EXECUTE_LIMIT_ORDER), executeLimitOrder);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.MARKET_TRADING), marketTrade);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.USER_CLOSE_TRADING), userCloseTrade);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.TP_SL_CLOSE_TRADING), tpSlCloseTrade);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.LIQUIDATE_TRADING), liquidateTradeSwitch);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.PREDICTION_BET), predictBet);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.PREDICTION_SETTLE), predictSettle);
        LibTradingConfig.setTradingSwitches(uint16(tradeSwitches));
    }

    function setExecutionFeeUsd(uint256 executionFeeUsd) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        LibTradingConfig.setExecutionFeeUsd(executionFeeUsd);
    }

    function setMinNotionalUsd(uint256 minNotionalUsd) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        LibTradingConfig.setMinNotionalUsd(minNotionalUsd);
    }

    function setMinBetUsd(uint256 minBetUsd) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        LibTradingConfig.setMinBetUsd(minBetUsd);
    }

    function setMaxTakeProfitP(uint24 maxTakeProfitP) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        LibTradingConfig.setMaxTakeProfitP(maxTakeProfitP);
    }

    function setMaxTpRatioForLeverage(address pairBase, MaxTpRatioForLeverage[] calldata maxTpRatios) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        require(
            pairBase != address(0) && IPairsManager(address(this)).getPairByBaseV3(pairBase).base != address(0),
            "TradingConfigFacet: pair does not exist"
        );
        LibTradingConfig.setMaxTpRatioForLeverage(pairBase, maxTpRatios);
    }

    function getPairMaxTpRatios(address pairBase) external view override returns (MaxTpRatioForLeverage[] memory) {
        return LibTradingConfig.tradingConfigStorage().maxTpRatios[pairBase];
    }

    function getPairMaxTpRatio(address pairBase, uint256 leverage_10000) external view override returns (uint24) {
        LibTradingConfig.TradingConfigStorage storage tcs = LibTradingConfig.tradingConfigStorage();
        MaxTpRatioForLeverage[] storage tpRatios = tcs.maxTpRatios[pairBase];
        if (tpRatios.length == 0) {
            return tcs.maxTakeProfitP;
        } else {
            for (UC i = ZERO; i < uc(tpRatios.length); i = i + ONE) {
                MaxTpRatioForLeverage storage tpRatio = tpRatios[i.into()];
                if (leverage_10000 < tpRatio.leverage * uint256(1e4)) {
                    return tpRatio.maxTakeProfitP;
                }
            }
            return tpRatios[tpRatios.length - 1].maxTakeProfitP;
        }
    }
}
