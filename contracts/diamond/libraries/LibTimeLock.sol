// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "@openzeppelin/contracts/utils/Address.sol";

library LibTimeLock {

    using Address for address;

    bytes32 constant TIME_LOCK_POSITION = keccak256("apollox.time.lock.storage");

    struct Transaction {
        string functionSignature;
        bytes data;
        uint40 executeTime;
        uint40 expiryTime;
    }

    struct TimeLockStorage {
        uint256 salt;
        // hash => Transaction
        mapping(bytes32 => Transaction) transactions;
    }

    function timeLockStorage() internal pure returns (TimeLockStorage storage tls) {
        bytes32 position = TIME_LOCK_POSITION;
        assembly {
            tls.slot := position
        }
    }

    event QueueTransaction(bytes32 indexed transactionHash, string functionSignature, bytes data);
    event CancelTransaction(bytes32 indexed transactionHash);
    event ExecuteTransaction(bytes32 indexed transactionHash);

    function queueTransaction(string calldata functionSignature, bytes calldata data) internal {
        TimeLockStorage storage tls = timeLockStorage();
        uint256 executeTime = block.timestamp + Constants.TIME_LOCK_DELAY;
        bytes32 transactionHash = keccak256(abi.encode(functionSignature, data, executeTime, tls.salt));
        require(tls.transactions[transactionHash].executeTime == 0, "LibTimeLock: Transaction already exists");
        tls.salt++;
        tls.transactions[transactionHash] = Transaction(
            functionSignature, data, uint40(executeTime),
            uint40(block.timestamp + Constants.TIME_LOCK_GRACE_PERIOD)
        );
        emit QueueTransaction(transactionHash, functionSignature, data);
    }

    function cancelTransaction(bytes32 transactionHash) internal {
        TimeLockStorage storage tls = timeLockStorage();
        require(tls.transactions[transactionHash].executeTime > 0, "LibTimeLock: Transaction hasn't been queued");
        delete tls.transactions[transactionHash];
        emit CancelTransaction(transactionHash);
    }

    function executeTransaction(bytes32 transactionHash) internal returns (bytes memory) {
        TimeLockStorage storage tls = timeLockStorage();
        require(tls.transactions[transactionHash].executeTime > 0, "LibTimeLock: Transaction hasn't been queued");
        require(block.timestamp >= tls.transactions[transactionHash].executeTime, "LibTimeLock: Transaction hasn't surpassed time lock");
        require(block.timestamp <= tls.transactions[transactionHash].expiryTime, "LibTimeLock: Transaction is stale");

        Transaction storage transaction = tls.transactions[transactionHash];
        bytes memory data;
        if (bytes(transaction.functionSignature).length == 0) {
            data = transaction.data;
        } else {
            data = abi.encodePacked(bytes4(keccak256(bytes(transaction.functionSignature))), transaction.data);
        }
        bytes memory result = address(this).functionCall(data);
        emit ExecuteTransaction(transactionHash);
        delete tls.transactions[transactionHash];
        return result;
    }
}
