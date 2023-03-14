// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IDiamondCut.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibAccessControlEnumerable.sol";

contract DiamondCutFacet is IDiamondCut {

    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external override {
        LibAccessControlEnumerable.checkRole(LibAccessControlEnumerable.DEPLOYER_ROLE);
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
