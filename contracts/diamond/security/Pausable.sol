// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../libraries/LibDiamond.sol";

abstract contract Pausable {

    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function _paused() internal view virtual returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.paused;
    }

    function _requireNotPaused() internal view virtual {
        require(!_paused(), "Pausable: paused");
    }

    function _requirePaused() internal view virtual {
        require(_paused(), "Pausable: not paused");
    }

    function _pause() internal virtual whenNotPaused {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal virtual whenPaused {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.paused = false;
        emit Unpaused(msg.sender);
    }
}
