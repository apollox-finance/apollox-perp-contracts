// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IApxReward.sol";
import "../libraries/LibApxReward.sol";
import "../libraries/LibAccessControlEnumerable.sol";

// calculate apx award
contract ApxRewardFacet is IApxReward {

    bytes32 public constant STAKE_OPERATOR_ROLE = keccak256("STAKE_OPERATOR");

    function initializeApxRewardFacet(address _rewardsToken, uint256 _apxPerBlock, uint256 _startBlock) external {
        require(_rewardsToken != address(0), "Invalid _rewardsToken");
        require(_apxPerBlock >= 0, "Invalid _apxPerBlock");
        require(_startBlock >= 0, "Invalid _startBlock");

        LibAccessControlEnumerable.checkRole(LibAccessControlEnumerable.DEPLOYER_ROLE);
        LibApxReward.initialize(_rewardsToken, _apxPerBlock, _startBlock);
    }

    function updateApxPerBlock(uint256 _apxPerBlock) external override {
        LibAccessControlEnumerable.checkRole(STAKE_OPERATOR_ROLE);
        LibApxReward.updateApxPerBlock(_apxPerBlock);
    }

    function addReserves(uint256 amount) external override {
        require(amount > 0, "ApxRewardFacet: amount must be greater than 0");
        LibApxReward.addReserves(amount);
    }

    function apxPoolInfo() external view returns (ApxPoolInfo memory) {
        return LibApxReward.apxPoolInfo();
    }

    function pendingApx(address _account) external view override returns (uint256) {
        return LibApxReward.pendingApx(_account);
    }
}
