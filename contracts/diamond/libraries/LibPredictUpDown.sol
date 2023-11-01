// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Period} from  "../interfaces/IPredictionManager.sol";
import {PendingPrediction, OpenPrediction, PredictionMarket} from  "../interfaces/IPredictUpDown.sol";

library LibPredictUpDown {

    bytes32 constant PREDICT_UP_DOWN_STORAGE_POSITION = keccak256("apollox.predict.up.down.storage");

    struct PredictionUpDownStorage {
        uint256 id;
        //--------------- pending ---------------
        mapping(uint256 id => PendingPrediction) pendingPredictions;
        mapping(address tokenIn => uint256) pendingPredictionAmountIns;
        //--------------- open ---------------
        mapping(uint256 id => OpenPrediction) openPredictions;
        // user => id[]
        mapping(address user => uint256[]) userOpenPredictionIds;
        mapping(address tokenIn => uint256) openPredictionAmountIns;
        // predictionPairBase => period => PredictionMarket
        mapping(address predictionPairBase => mapping(Period => PredictionMarket)) pairPeriodPredictionMarkets;
    }

    function predictionUpDownStorage() internal pure returns (PredictionUpDownStorage storage puds) {
        bytes32 position = PREDICT_UP_DOWN_STORAGE_POSITION;
        assembly {
            puds.slot := position
        }
    }
}
