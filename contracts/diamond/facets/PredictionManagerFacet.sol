// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import {ZeroAddress} from "../../utils/Errors.sol";
import "../interfaces/IPredictionManager.sol";
import "../libraries/LibPredictionManager.sol";
import "../libraries/LibAccessControlEnumerable.sol";

contract PredictionManagerFacet is IPredictionManager {

    function addPredictionPair(
        address base, string calldata name, PredictionPeriod[] calldata predictionPeriods
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        _isBaseNonZero(base);
        _predictionPeriodsCheck(predictionPeriods);
        LibPredictionManager.addPredictionPair(base, name, predictionPeriods);
    }

    function removePredictionPair(address base) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        _isBaseNonZero(base);
        LibPredictionManager.removePredictionPair(base);
    }

    function updatePredictionPairStatus(address base, PredictionPairStatus status) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        _isBaseNonZero(base);
        LibPredictionManager.updatePredictionPairStatus(base, status);
    }

    function updatePredictionPairMaxCap(address base, PeriodCap[] calldata periodCaps) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        _isBaseNonZero(base);
        LibPredictionManager.PredictionPair storage pp = LibPredictionManager.requireExists(base);
        for (uint256 i = 0; i < periodCaps.length;) {
            PeriodCap memory ic = periodCaps[i];
            LibPredictionManager.updatePredictionPairPeriodMaxCap(pp, ic.period, ic.maxUpUsd, ic.maxDownUsd);
            unchecked{++i;}
        }
    }

    function updatePredictionPairWinRatio(address base, PeriodWinRatio[] calldata periodWinRatios) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        _isBaseNonZero(base);
        LibPredictionManager.PredictionPair storage pp = LibPredictionManager.requireExists(base);
        for (uint256 i = 0; i < periodWinRatios.length;) {
            PeriodWinRatio memory iwr = periodWinRatios[i];
            LibPredictionManager.updatePredictionPairPeriodWinRatio(pp, iwr.period, iwr.winRatio);
            unchecked{++i;}
        }
    }

    function updatePredictionPairFee(address base, PeriodFee[] calldata periodFees) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        _isBaseNonZero(base);
        LibPredictionManager.PredictionPair storage pp = LibPredictionManager.requireExists(base);
        for (uint256 i = 0; i < periodFees.length;) {
            PeriodFee memory iFee = periodFees[i];
            LibPredictionManager.updatePredictionPairPeriodFee(pp, iFee.period, iFee.openFeeP, iFee.winCloseFeeP, iFee.loseCloseFeeP);
            unchecked{++i;}
        }
    }

    function addPeriodForPredictionPair(address base, PredictionPeriod[] calldata predictionPeriods) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        _isBaseNonZero(base);
        _predictionPeriodsCheck(predictionPeriods);
        LibPredictionManager.PredictionPair storage pp = LibPredictionManager.requireExists(base);
        LibPredictionManager.addPeriodForPredictionPair(pp, predictionPeriods);
    }

    function replacePredictionPairPeriod(address base, PredictionPeriod[] calldata predictionPeriods) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        _isBaseNonZero(base);
        _predictionPeriodsCheck(predictionPeriods);
        LibPredictionManager.PredictionPair storage pp = LibPredictionManager.requireExists(base);
        LibPredictionManager.replacePredictionPairPeriod(pp, predictionPeriods);
    }

    function _isBaseNonZero(address base) private pure {
        if (base == address(0)) revert ZeroAddress();
    }

    function _predictionPeriodsCheck(PredictionPeriod[] calldata predictionPeriods) private pure {
        require(predictionPeriods.length > 0, "PredictionManagerFacet: contains at least one period");
        for (uint256 i = 0; i < predictionPeriods.length;) {
            PredictionPeriod memory pi = predictionPeriods[i];
            require(pi.winRatio > 5000 && pi.winRatio < 1e4, "PredictionManagerFacet: invalid winRatio");
            require(
                pi.openFeeP < 1e4 && pi.winCloseFeeP < 1e4 && pi.loseCloseFeeP < 1e4,
                "PredictionManagerFacet: invalid openFeeP or closeFeeP"
            );
            unchecked{++i;}
        }
    }

    function getPredictionPairByBase(address base) public view override returns (PredictionPairView memory) {
        LibPredictionManager.PredictionPair storage pp = LibPredictionManager.predictionManagerStorage().predictionPairs[base];
        PredictionPeriod[] memory predictionPeriods = new PredictionPeriod[](pp.periods.length);
        for (uint256 i = 0; i < pp.periods.length;) {
            predictionPeriods[i] = pp.predictionPeriods[pp.periods[i]];
            unchecked{++i;}
        }
        return PredictionPairView(pp.name, pp.base, predictionPeriods);
    }

    function predictionPairs(uint start, uint8 size) external view override returns (PredictionPairView[] memory predictPairViews) {
        LibPredictionManager.PredictionManagerStorage storage pms = LibPredictionManager.predictionManagerStorage();
        if (start >= pms.predictionPairBases.length || size == 0) {
            predictPairViews = new PredictionPairView[](0);
        } else {
            uint count = pms.predictionPairBases.length - start > size ? size : pms.predictionPairBases.length - start;
            predictPairViews = new PredictionPairView[](count);
            for (uint256 i = 0; i < count;) {
                uint256 index;
                unchecked{index = i + start;}
                predictPairViews[i] = getPredictionPairByBase(pms.predictionPairBases[index]);
                unchecked{++i;}
            }
        }
        return predictPairViews;
    }

    function getPredictionPeriod(address base, Period period) external view override returns (PredictionPeriod memory) {
        return LibPredictionManager.predictionManagerStorage().predictionPairs[base].predictionPeriods[period];
    }
}
