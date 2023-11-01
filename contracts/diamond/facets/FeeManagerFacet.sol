// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../security/OnlySelf.sol";
import "../../utils/Constants.sol";
import "../../utils/TransferHelper.sol";
import "../interfaces/IFeeManager.sol";
import "../interfaces/IPairsManager.sol";
import "../libraries/LibFeeManager.sol";
import "../libraries/LibPairsManager.sol";
import "../libraries/LibBrokerManager.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract FeeManagerFacet is IFeeManager, OnlySelf {

    using TransferHelper for address;

    function initFeeManagerFacet(address daoRepurchase, address revenueAddress) external {
        LibAccessControlEnumerable.checkRole(Constants.DEPLOYER_ROLE);
        LibFeeManager.initialize(daoRepurchase, revenueAddress);
    }

    function addFeeConfig(
        uint16 index, string calldata name, uint16 openFeeP, uint16 closeFeeP, uint24 shareP, uint24 minCloseFeeP
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(
            openFeeP < 1e4 && closeFeeP < 1e4 && shareP < 1e5 && minCloseFeeP < 1e5, "FeeManagerFacet: Invalid parameters"
        );
        LibFeeManager.addFeeConfig(index, name, openFeeP, closeFeeP, shareP, minCloseFeeP);
    }

    function removeFeeConfig(uint16 index) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        LibFeeManager.removeFeeConfig(index);
    }

    function updateFeeConfig(uint16 index, uint16 openFeeP, uint16 closeFeeP, uint24 shareP, uint24 minCloseFeeP) external override {
        LibAccessControlEnumerable.checkRole(Constants.PAIR_OPERATOR_ROLE);
        require(openFeeP < 1e4 && closeFeeP < 1e4 && shareP < 1e5 && minCloseFeeP < 1e5, "FeeManagerFacet: Invalid parameters");
        LibFeeManager.updateFeeConfig(index, openFeeP, closeFeeP, shareP, minCloseFeeP);
    }

    function setDaoRepurchase(address daoRepurchase) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        LibFeeManager.setDaoRepurchase(daoRepurchase);
    }

    function setRevenueAddress(address revenueAddress) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        LibFeeManager.setRevenueAddress(revenueAddress);
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

    function feeAddress() external view override returns (address daoRepurchase, address revenueAddress) {
        LibFeeManager.FeeManagerStorage storage fms = LibFeeManager.feeManagerStorage();
        return (fms.daoRepurchase, fms.revenueAddress);
    }

    function revenues(address[] calldata tokens) external view override returns (CommissionInfo[] memory) {
        LibFeeManager.FeeManagerStorage storage fms = LibFeeManager.feeManagerStorage();
        CommissionInfo[] memory protocolRevenues = new CommissionInfo[](tokens.length);
        for (UC i = ZERO; i < uc(tokens.length); i = i + ONE) {
            address token = tokens[i.into()];
            LibBrokerManager.Commission storage revenue = fms.revenues[token];
            protocolRevenues[i.into()] = CommissionInfo(token, revenue.total, revenue.pending);
        }
        return protocolRevenues;
    }

    function chargeOpenFee(address token, uint256 openFee, uint24 broker) external onlySelf override returns (uint24) {
        (uint24 brokerId, uint256 brokerAmount, uint256 daoAmount, uint256 alpPoolAmount) = LibFeeManager.chargeFee(token, openFee, broker);
        emit OpenFee(token, openFee, daoAmount, brokerId, brokerAmount, alpPoolAmount);
        return brokerId;
    }

    function chargePredictionOpenFee(address token, uint256 openFee, uint24 broker) external onlySelf override returns (uint24) {
        (uint24 brokerId, uint256 brokerAmount, uint256 daoAmount, uint256 alpPoolAmount) = LibFeeManager.chargeFee(token, openFee, broker);
        emit PredictionOpenFee(token, openFee, daoAmount, brokerId, brokerAmount, alpPoolAmount);
        return brokerId;
    }

    function chargeCloseFee(address token, uint256 closeFee, uint24 broker) external onlySelf override {
        (uint24 brokerId, uint256 brokerAmount, uint256 daoAmount, uint256 alpPoolAmount) = LibFeeManager.chargeFee(token, closeFee, broker);
        emit CloseFee(token, closeFee, daoAmount, brokerId, brokerAmount, alpPoolAmount);
    }

    function chargePredictionCloseFee(address token, uint256 closeFee, uint24 broker) external onlySelf override {
        (uint24 brokerId, uint256 brokerAmount, uint256 daoAmount, uint256 alpPoolAmount) = LibFeeManager.chargeFee(token, closeFee, broker);
        emit PredictionCloseFee(token, closeFee, daoAmount, brokerId, brokerAmount, alpPoolAmount);
    }

    function withdrawRevenue(address[] calldata tokens) external override {
        LibFeeManager.FeeManagerStorage storage fms = LibFeeManager.feeManagerStorage();
        for (UC i = ZERO; i < uc(tokens.length); i = i + ONE) {
            address token = tokens[i.into()];
            LibBrokerManager.Commission storage revenue = fms.revenues[token];
            if (revenue.pending > 0) {
                uint256 r = revenue.pending;
                revenue.pending = 0;
                token.transfer(fms.revenueAddress, r);

                emit WithdrawRevenue(token, msg.sender, r);
            }
        }
    }
}
