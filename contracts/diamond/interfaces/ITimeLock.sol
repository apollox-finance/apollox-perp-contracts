// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITimeLock {

    event QueueTransaction(bytes32 indexed transactionHash, string functionSignature, bytes data);
    event CancelTransaction(bytes32 indexed transactionHash);
    event ExecuteTransaction(bytes32 indexed transactionHash);

    function queueTransaction(string calldata functionSignature, bytes calldata data) external;

    function cancelTransaction(bytes32 transactionHash) external;

    function executeTransaction(bytes32 transactionHash) external returns (bytes memory);
}
