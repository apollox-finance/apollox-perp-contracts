// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Bits.sol";
import "../../utils/Constants.sol";
import "../interfaces/ITradingConfig.sol";
import "../libraries/LibTradingConfig.sol";
import "../libraries/LibAccessControlEnumerable.sol";

contract TradingConfigFacet is ITradingConfig {

    using Bits for uint;

    function initTradingConfigFacet(uint256 executionFeeUsd, uint256 minNotionalUsd, uint24 maxTakeProfitP) external {
        require(minNotionalUsd > 0 && maxTakeProfitP > 0, "TradingConfigFacet: Invalid parameter");
        LibAccessControlEnumerable.checkRole(Constants.DEPLOYER_ROLE);
        LibTradingConfig.initialize(executionFeeUsd, minNotionalUsd, maxTakeProfitP);
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

    function setTradingSwitches(
        bool limitOrder, bool executeLimitOrder, bool marketTrade,
        bool userCloseTrade, bool tpSlCloseTrade, bool liquidateTradeSwitch
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        uint tradeSwitches = 0;
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.LIMIT_ORDER), limitOrder);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.EXECUTE_LIMIT_ORDER), executeLimitOrder);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.MARKET_TRADING), marketTrade);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.USER_CLOSE_TRADING), userCloseTrade);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.TP_SL_CLOSE_TRADING), tpSlCloseTrade);
        tradeSwitches = tradeSwitches.setOrClearBit(uint8(TradingSwitch.LIQUIDATE_TRADING), liquidateTradeSwitch);
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

    function setMaxTakeProfitP(uint24 maxTakeProfitP) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        LibTradingConfig.setMaxTakeProfitP(maxTakeProfitP);
    }
}
