// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../security/OnlySelf.sol";
import "../../utils/Constants.sol";
import "../interfaces/IFeeManager.sol";
import "../interfaces/IPairsManager.sol";
import "../libraries/LibFeeManager.sol";
import "../libraries/LibPairsManager.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract FeeManagerFacet is IFeeManager, OnlySelf {

    function initFeeManagerFacet(address daoRepurchase, uint16 daoShareP) external {
        LibAccessControlEnumerable.checkRole(Constants.DEPLOYER_ROLE);
        require(daoRepurchase != address(0), "FeeManagerFacet: daoRepurchase cannot be 0 address");
        LibFeeManager.initialize(daoRepurchase, daoShareP);
    }

    function addFeeConfig(uint16 index, string calldata name, uint16 openFeeP, uint16 closeFeeP) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(openFeeP < 1e4 && closeFeeP < 1e4, "FeeManagerFacet: Invalid parameters");
        LibFeeManager.addFeeConfig(index, name, openFeeP, closeFeeP);
    }

    function removeFeeConfig(uint16 index) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        LibFeeManager.removeFeeConfig(index);
    }

    function updateFeeConfig(uint16 index, uint16 openFeeP, uint16 closeFeeP) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(openFeeP < 1e4 && closeFeeP < 1e4, "FeeManagerFacet: Invalid parameters");
        LibFeeManager.updateFeeConfig(index, openFeeP, closeFeeP);
    }

    function setDaoRepurchase(address daoRepurchase) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        require(daoRepurchase != address(0), "FeeManagerFacet: daoRepurchase cannot be 0 address");
        LibFeeManager.setDaoRepurchase(daoRepurchase);
    }

    function setDaoShareP(uint16 daoShareP) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        LibFeeManager.setDaoShareP(daoShareP);
    }

    function getFeeConfigByIndex(uint16 index) external view override returns (LibFeeManager.FeeConfig memory, IPairsManager.PairSimple[] memory) {
        (LibFeeManager.FeeConfig memory feeConfig, address[] memory feePairs) = LibFeeManager.getFeeConfigByIndex(index);
        IPairsManager.PairSimple[] memory pairSimples = new IPairsManager.PairSimple[](feePairs.length);
        if (feePairs.length > 0) {
            mapping(address => LibPairsManager.Pair) storage pairs = LibPairsManager.pairsManagerStorage().pairs;
            for (uint i; i < feePairs.length; i++) {
                LibPairsManager.Pair storage pair = pairs[feePairs[i]];
                pairSimples[i] = IPairsManager.PairSimple(pair.name, pair.base, pair.pairType, pair.status);
            }
        }
        return (feeConfig, pairSimples);
    }

    function getFeeDetails(address[] calldata tokens) external view override returns (FeeDetail[] memory) {
        LibFeeManager.FeeManagerStorage storage fms = LibFeeManager.feeManagerStorage();
        FeeDetail[] memory feeDetails = new FeeDetail[](tokens.length);
        for (UC i = ZERO; i < uc(tokens.length); i = i + ONE) {
            feeDetails[i.into()] = fms.feeDetails[tokens[i.into()]];
        }
        return feeDetails;
    }

    function daoConfig() external view override returns (address, uint16) {
        LibFeeManager.FeeManagerStorage storage fms = LibFeeManager.feeManagerStorage();
        return (fms.daoRepurchase, fms.daoShareP);
    }

    function chargeOpenFee(address token, uint256 openFee, uint24 broker) external onlySelf override returns (uint24) {
        return LibFeeManager.chargeOpenFee(token, openFee, broker);
    }

    function chargeCloseFee(address token, uint256 closeFee, uint24 broker) external onlySelf override {
        LibFeeManager.chargeCloseFee(token, closeFee, broker);
    }
}
