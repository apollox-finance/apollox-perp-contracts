// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../interfaces/IApxReward.sol";
import "../libraries/LibApxReward.sol";
import "../libraries/LibAccessControlEnumerable.sol";

// calculate apx award
contract ApxRewardFacet is IApxReward {

    function initializeApxRewardFacet(address _rewardsToken, uint256 _apxPerBlock, uint256 _startBlock) external {
        require(_rewardsToken != address(0), "Invalid _rewardsToken");
        require(_apxPerBlock > 0, "apxPerBlock greater than 0");

        LibAccessControlEnumerable.checkRole(Constants.DEPLOYER_ROLE);
        LibApxReward.initialize(_rewardsToken, _apxPerBlock, _startBlock);
    }

    function updateApxPerBlock(uint256 _apxPerBlock) external override {
        LibAccessControlEnumerable.checkRole(Constants.STAKE_OPERATOR_ROLE);
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
