// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../interfaces/ITimeLock.sol";
import "../libraries/LibTimeLock.sol";
import "../libraries/LibAccessControlEnumerable.sol";

contract TimeLockFacet is ITimeLock {

    function queueTransaction(string calldata functionSignature, bytes calldata data) external override {
        require(
            LibAccessControlEnumerable.hasRole(Constants.ADMIN_ROLE, msg.sender) ||
            LibAccessControlEnumerable.hasRole(Constants.DEPLOYER_ROLE, msg.sender),
            "TimeLockFacet: missing role."
        );
        LibTimeLock.queueTransaction(functionSignature, data);
    }

    function cancelTransaction(bytes32 transactionHash) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        LibTimeLock.cancelTransaction(transactionHash);
    }

    function executeTransaction(bytes32 transactionHash) external override returns (bytes memory) {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        return LibTimeLock.executeTransaction(transactionHash);
    }
}
