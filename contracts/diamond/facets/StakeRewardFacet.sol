// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IStakeReward.sol";
import "../libraries/LibStakeReward.sol";
import "../security/ReentrancyGuard.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import "../security/Pausable.sol";

//user entry
contract StakeRewardFacet is IStakeReward, Pausable, ReentrancyGuard {

    /* ========== initialize ========== */
    function initializeStakeRewardFacet(address _stakingToken) external {
        LibAccessControlEnumerable.checkRole(Constants.DEPLOYER_ROLE);
        require(_stakingToken != address(0), "Invalid _stakingToken");
        LibStakeReward.initialize(_stakingToken);
    }

    /* ========== VIEWS ========== */
    function totalStaked() external view override returns (uint256) {
        return LibStakeReward.totalStaked();
    }

    function stakeOf(address _user) external view override returns (uint256) {
        return LibStakeReward.stakeOf(_user);
    }

    function stake(uint256 _amount) external nonReentrant whenNotPaused override {
        require(_amount > 0, 'Invalid amount');
        LibStakeReward.checkOncePerBlock(msg.sender);
        LibStakeReward.stake(_amount);
    }

    function unStake(uint256 _amount) external nonReentrant whenNotPaused override {
        LibStakeReward.checkOncePerBlock(msg.sender);
        LibStakeReward.unStake(_amount);
    }

    function claimAllReward() external nonReentrant whenNotPaused override {
        LibStakeReward.checkOncePerBlock(msg.sender);
        LibStakeReward.claimAllReward();
    }
}
