// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPriceFacade.sol";
import {Period, PredictionPairStatus, PredictionPeriod} from  "../interfaces/IPredictionManager.sol";
import {IPredictUpDown, PredictionMarket} from  "../interfaces/IPredictUpDown.sol";

library LibPredictionManager {

    bytes32 constant PREDICTION_MANAGER_STORAGE_POSITION = keccak256("apollox.prediction.manager.storage");

    struct PredictionPair {
        string name;
        address base;
        uint16 basePosition;
        mapping(Period => PredictionPeriod) predictionPeriods;
        Period[] periods;
    }

    struct PredictionManagerStorage {
        mapping(address base => PredictionPair) predictionPairs;
        address[] predictionPairBases;
    }

    function predictionManagerStorage() internal pure returns (PredictionManagerStorage storage pms) {
        bytes32 position = PREDICTION_MANAGER_STORAGE_POSITION;
        assembly {
            pms.slot := position
        }
    }

    event AddPredictionPair(address indexed base, string name, PredictionPeriod[] predictionPeriods);
    event RemovePredictionPair(address indexed base);
    event UpdatePredictionPairStatus(address indexed base, PredictionPairStatus status);
    event UpdatePredictionPairPeriodMaxCap(address indexed base, Period indexed period, uint256 maxUpUsd, uint256 maxDownUsd);
    event UpdatePredictionPairPeriodWinRatio(address indexed base, Period indexed period, uint16 winRatio);
    event UpdatePredictionPairPeriodFee(address indexed base, Period indexed period, uint16 openFeeP, uint16 winCloseFeeP, uint16 loseCloseFeeP);
    event AddPeriodForPredictionPair(address indexed base, PredictionPeriod[] predictionPeriods);
    event ReplacePredictionPairPeriod(address indexed base, PredictionPeriod[] predictionPeriods);

    function requireExists(address base) internal view returns (PredictionPair storage) {
        PredictionManagerStorage storage pms = predictionManagerStorage();
        PredictionPair storage pp = pms.predictionPairs[base];
        require(pp.base != address(0), "LibPredictionManager: Predict pair not exist");
        return pp;
    }

    function addPredictionPair(address base, string calldata name, PredictionPeriod[] calldata predictionPeriods) internal {
        PredictionManagerStorage storage pms = predictionManagerStorage();
        PredictionPair storage pp = pms.predictionPairs[base];
        require(pp.base == address(0), "LibPredictionManager: Predict pair already exists");
        require(IPriceFacade(address(this)).getPrice(base) > 0, "LibPredictionManager: No price feed has been configured for the predict pair");
        pp.base = base;
        pp.name = name;
        pp.basePosition = uint16(pms.predictionPairBases.length);
        pms.predictionPairBases.push(base);
        Period[] memory periods = new Period[](predictionPeriods.length);
        for (uint256 i = 0; i < predictionPeriods.length;) {
            PredictionPeriod memory pi = predictionPeriods[i];
            pp.predictionPeriods[pi.period] = pi;
            periods[i] = pi.period;
            unchecked{++i;}
        }
        pp.periods = periods;
        emit AddPredictionPair(base, name, predictionPeriods);
    }

    function removePredictionPair(address base) internal {
        PredictionPair storage pp = requireExists(base);
        PredictionManagerStorage storage pms = predictionManagerStorage();

        PredictionMarket[] memory markets = IPredictUpDown(address(this)).getPredictionMarket(base, pp.periods);
        for (uint256 i = 0; i < markets.length;) {
            PredictionMarket memory pm = markets[i];
            if (pm.upUsd > 0 || pm.downUsd > 0) {
                revert("LibPredictionManager: There are still unclosed predictions.");
            }
            unchecked{++i;}
        }
        _removeAllPeriodFromPredictionPair(pp);
        uint lastPosition = pms.predictionPairBases.length - 1;
        uint basePosition = pp.basePosition;
        if (basePosition != lastPosition) {
            address lastBase = pms.predictionPairBases[lastPosition];
            pms.predictionPairBases[basePosition] = lastBase;
            pms.predictionPairs[lastBase].basePosition = uint16(basePosition);
        }
        pms.predictionPairBases.pop();
        delete pms.predictionPairs[base];
        emit RemovePredictionPair(base);
    }

    function updatePredictionPairStatus(address base, PredictionPairStatus status) internal {
        PredictionPair storage pp = requireExists(base);
        for (uint256 i = 0; i < pp.periods.length;) {
            pp.predictionPeriods[pp.periods[i]].status = status;
            unchecked{++i;}
        }
        emit UpdatePredictionPairStatus(base, status);
    }

    function _requireExistsPeriod(PredictionPair storage pp, Period period) private view returns (PredictionPeriod storage){
        PredictionPeriod storage pi = pp.predictionPeriods[period];
        require(pi.winRatio > 0, "LibPredictionManager: The period does not exist.");
        return pi;
    }

    function updatePredictionPairPeriodMaxCap(
        PredictionPair storage pp, Period period, uint256 maxUpUsd, uint256 maxDownUsd
    ) internal {
        PredictionPeriod storage pi = _requireExistsPeriod(pp, period);
        pi.maxUpUsd = maxUpUsd;
        pi.maxDownUsd = maxDownUsd;
        emit UpdatePredictionPairPeriodMaxCap(pp.base, period, maxUpUsd, maxDownUsd);
    }

    function updatePredictionPairPeriodWinRatio(PredictionPair storage pp, Period period, uint16 winRatio) internal {
        PredictionPeriod storage pi = _requireExistsPeriod(pp, period);
        pi.winRatio = winRatio;
        emit UpdatePredictionPairPeriodWinRatio(pp.base, period, winRatio);
    }

    function updatePredictionPairPeriodFee(
        PredictionPair storage pp, Period period, uint16 openFeeP, uint16 winCloseFeeP, uint16 loseCloseFeeP
    ) internal {
        PredictionPeriod storage pi = _requireExistsPeriod(pp, period);
        pi.openFeeP = openFeeP;
        pi.winCloseFeeP = winCloseFeeP;
        pi.loseCloseFeeP = loseCloseFeeP;
        emit UpdatePredictionPairPeriodFee(pp.base, period, openFeeP, winCloseFeeP, loseCloseFeeP);
    }

    function addPeriodForPredictionPair(PredictionPair storage pp, PredictionPeriod[] calldata predictionPeriods) internal {
        for (uint256 i = 0; i < predictionPeriods.length;) {
            PredictionPeriod calldata pi = predictionPeriods[i];
            require(pp.predictionPeriods[pi.period].winRatio == 0, "LibPredictionManager: The period already exists");
            pp.predictionPeriods[pi.period] = pi;
            pp.periods.push(pi.period);
            unchecked{++i;}
        }
        emit AddPeriodForPredictionPair(pp.base, predictionPeriods);
    }

    function replacePredictionPairPeriod(PredictionPair storage pp, PredictionPeriod[] calldata predictionPeriods) internal {
        _removeAllPeriodFromPredictionPair(pp);
        for (uint256 i = 0; i < predictionPeriods.length;) {
            PredictionPeriod calldata pi = predictionPeriods[i];
            pp.predictionPeriods[pi.period] = pi;
            pp.periods.push(pi.period);
            unchecked{++i;}
        }
        emit ReplacePredictionPairPeriod(pp.base, predictionPeriods);
    }

    function _removeAllPeriodFromPredictionPair(PredictionPair storage pp) private {
        uint oldCount = pp.periods.length;
        for (uint256 i = 0; i < oldCount;) {
            Period period = pp.periods[i];
            delete pp.predictionPeriods[period];
            unchecked{++i;}
        }
        for (uint256 i = 0; i < oldCount;) {
            pp.periods.pop();
            unchecked{++i;}
        }
    }
}
