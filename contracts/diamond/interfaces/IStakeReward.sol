// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IStakeReward {

    function stake(uint256 amount) external;

    function unStake(uint256 _amount) external;

    // LibFeeReward.claimFeeReward() & LibApxReward.claimApxReward()
    function claimAllReward() external;

    function totalStaked() external view returns (uint256);

    function stakeOf(address account) external view returns (uint256);

}
