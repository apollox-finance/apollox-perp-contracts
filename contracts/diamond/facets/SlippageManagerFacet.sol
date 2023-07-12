// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ISlippageManager.sol";
import "../libraries/LibAccessControlEnumerable.sol";

contract SlippageManagerFacet is ISlippageManager {

    function addSlippageConfig(
        string calldata name, uint16 index, SlippageType slippageType,
        uint256 onePercentDepthAboveUsd, uint256 onePercentDepthBelowUsd, // Allowed to be 0
        uint16 slippageLongP, uint16 slippageShortP  // Allowed to be 0
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(slippageLongP < 1e4 && slippageShortP < 1e4, "SlippageManagerFacet: Invalid parameters");
        if (slippageType != SlippageType.FIXED) {
            require(onePercentDepthAboveUsd > 0 && onePercentDepthBelowUsd > 0, "SlippageManagerFacet: Invalid dynamic slippage parameter configuration");
        }

        LibPairsManager.SlippageConfig storage config = LibPairsManager.pairsManagerStorage().slippageConfigs[index];
        require(!config.enable, "SlippageManagerFacet: Configuration already exists");
        config.index = index;
        config.name = name;
        config.enable = true;
        config.slippageType = slippageType;
        config.onePercentDepthAboveUsd = onePercentDepthAboveUsd;
        config.onePercentDepthBelowUsd = onePercentDepthBelowUsd;
        config.slippageLongP = slippageLongP;
        config.slippageShortP = slippageShortP;
        emit AddSlippageConfig(index, slippageType, onePercentDepthAboveUsd,
            onePercentDepthBelowUsd, slippageLongP, slippageShortP, name);
    }

    function removeSlippageConfig(uint16 index) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        LibPairsManager.SlippageConfig storage config = pms.slippageConfigs[index];
        require(config.enable, "SlippageManagerFacet: Configuration not enabled");
        require(pms.slippageConfigPairs[index].length == 0, "SlippageManagerFacet: Cannot remove a configuration that is still in use");
        delete pms.slippageConfigs[index];
        emit RemoveSlippageConfig(index);
    }

    function updateSlippageConfig(
        uint16 index, SlippageType slippageType,
        uint256 onePercentDepthAboveUsd, uint256 onePercentDepthBelowUsd, // Allowed to be 0
        uint16 slippageLongP, uint16 slippageShortP  // Allowed to be 0
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.MONITOR_ROLE);
        require(slippageLongP < 1e4 && slippageShortP < 1e4, "SlippageManagerFacet: Invalid parameters");
        if (slippageType != SlippageType.FIXED) {
            require(onePercentDepthAboveUsd > 0 && onePercentDepthBelowUsd > 0, "SlippageManagerFacet: Invalid dynamic slippage parameter configuration");
        }

        LibPairsManager.SlippageConfig storage config = LibPairsManager.pairsManagerStorage().slippageConfigs[index];
        require(config.enable, "SlippageManagerFacet: Configuration not enabled");
        config.slippageType = slippageType;
        config.onePercentDepthAboveUsd = onePercentDepthAboveUsd;
        config.onePercentDepthBelowUsd = onePercentDepthBelowUsd;
        config.slippageLongP = slippageLongP;
        config.slippageShortP = slippageShortP;
        emit UpdateSlippageConfig(
            index, slippageType, onePercentDepthAboveUsd, onePercentDepthBelowUsd, slippageLongP, slippageShortP
        );
    }

    function getSlippageConfigByIndex(uint16 index) external view override returns (LibPairsManager.SlippageConfig memory, IPairsManager.PairSimple[] memory) {
        LibPairsManager.PairsManagerStorage storage pms = LibPairsManager.pairsManagerStorage();
        LibPairsManager.SlippageConfig memory config = pms.slippageConfigs[index];
        address[] memory slippagePairs = pms.slippageConfigPairs[index];
        IPairsManager.PairSimple[] memory pairSimples = new IPairsManager.PairSimple[](slippagePairs.length);
        if (slippagePairs.length > 0) {
            mapping(address => LibPairsManager.Pair) storage _pairs = LibPairsManager.pairsManagerStorage().pairs;
            for (uint i; i < slippagePairs.length; i++) {
                LibPairsManager. Pair storage pair = _pairs[slippagePairs[i]];
                pairSimples[i] = IPairsManager.PairSimple(pair.name, pair.base, pair.pairType, pair.status);
            }
        }
        return (config, pairSimples);
    }
}
