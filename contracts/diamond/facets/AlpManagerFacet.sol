// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/TransferHelper.sol";
import "../security/Pausable.sol";
import "../interfaces/IAlpManager.sol";
import "../libraries/LibAlpManager.sol";
import "../libraries/LibStakeReward.sol";
import "../security/ReentrancyGuard.sol";
import "../libraries/LibAccessControlEnumerable.sol";

interface IAlp {
    function mint(address to, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}

contract AlpManagerFacet is ReentrancyGuard, Pausable, IAlpManager {

    using TransferHelper for address;

    function initAlpManagerFacet(address alpToken) external {
        LibAccessControlEnumerable.checkRole(Constants.DEPLOYER_ROLE);
        require(alpToken != address(0), "AlpManagerFacet: Invalid alpToken");
        LibAlpManager.initialize(alpToken);
    }

    function ALP() public view override returns (address) {
        return LibAlpManager.alpManagerStorage().alp;
    }

    function coolingDuration() external view override returns (uint256) {
        return LibAlpManager.alpManagerStorage().coolingDuration;
    }

    function setCoolingDuration(uint256 coolingDuration_) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        LibAlpManager.AlpManagerStorage storage ams = LibAlpManager.alpManagerStorage();
        ams.coolingDuration = coolingDuration_;
    }

    function mintAlp(address tokenIn, uint256 amount, uint256 minAlp, bool stake) external whenNotPaused nonReentrant override {
        _mintAlp(tokenIn, amount, minAlp, stake);
    }

    function mintAlpBNB(uint256 minAlp, bool stake) external payable whenNotPaused nonReentrant override {
        _mintAlp(TransferHelper.nativeWrapped(), msg.value, minAlp, stake);
    }

    function _mintAlp(address tokenIn, uint256 amount, uint256 minAlp, bool stake) private {
        require(amount > 0, "AlpManagerFacet: invalid amount");
        address account = msg.sender;
        uint256 alpAmount = LibAlpManager.mintAlp(account, tokenIn, amount);
        require(alpAmount >= minAlp, "AlpManagerFacet: insufficient ALP output");
        tokenIn.transferFrom(account, amount);
        _mint(account, tokenIn, amount, alpAmount, stake);
    }

    function _mint(address account, address tokenIn, uint256 amount, uint256 alpAmount, bool stake) private {
        IAlp(ALP()).mint(account, alpAmount);
        emit MintAlp(account, tokenIn, amount, alpAmount);
        if (stake) {
            LibStakeReward.stake(alpAmount);
        }
    }

    function burnAlp(address tokenOut, uint256 alpAmount, uint256 minOut, address receiver) external whenNotPaused nonReentrant override {
        _burnAlp(tokenOut, alpAmount, minOut, receiver);
    }

    function burnAlpBNB(uint256 alpAmount, uint256 minOut, address payable receiver) external whenNotPaused nonReentrant override {
        _burnAlp(TransferHelper.nativeWrapped(), alpAmount, minOut, receiver);
    }

    function _burnAlp(address tokenOut, uint256 alpAmount, uint256 minOut, address receiver) private {
        require(alpAmount > 0, "AlpManagerFacet: invalid alpAmount");
        address account = msg.sender;
        uint256 amountOut = LibAlpManager.burnAlp(account, tokenOut, alpAmount);
        require(amountOut >= minOut, "AlpManagerFacet: insufficient token output");
        IAlp(ALP()).burnFrom(account, alpAmount);
        IVault(address(this)).decrease(tokenOut, amountOut);
        tokenOut.transfer(receiver, amountOut);
        emit BurnAlp(account, receiver, tokenOut, alpAmount, amountOut);
    }

    function alpPrice() external view override returns (uint256) {
        return LibAlpManager.alpPrice();
    }

    function lastMintedTimestamp(address account) external view override returns (uint256) {
        return LibAlpManager.alpManagerStorage().lastMintedAt[account];
    }
}