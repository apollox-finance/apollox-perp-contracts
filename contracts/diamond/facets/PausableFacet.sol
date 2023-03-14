// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPausable.sol";
import "../security/Pausable.sol";
import "../libraries/LibAccessControlEnumerable.sol";

contract PausableFacet is Pausable, IPausable {

    function paused() external view override returns (bool) {
        return _paused();
    }

    function pause() external override {
        LibAccessControlEnumerable.checkRole(ADMIN_ROLE);
        _pause();
    }

    function unpause() external override {
        LibAccessControlEnumerable.checkRole(ADMIN_ROLE);
        _unpause();
    }
}
