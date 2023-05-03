// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../security/OnlySelf.sol";
import "../interfaces/IDiamondCut.sol";
import "../libraries/LibDiamond.sol";

contract DiamondCutFacet is IDiamondCut, OnlySelf {

    /**
     * diamondCut((address,uint8,bytes4[])[],address,bytes)
     */
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external onlySelf override {
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
