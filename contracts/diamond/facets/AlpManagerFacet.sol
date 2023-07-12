// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../security/Pausable.sol";
import "../libraries/LibVault.sol";
import "../interfaces/IAlpManager.sol";
import "../libraries/LibAlpManager.sol";
import "../libraries/LibStakeReward.sol";
import "../security/ReentrancyGuard.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IAlp {
    function mint(address to, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}

contract AlpManagerFacet is ReentrancyGuard, Pausable, IAlpManager {

    using Address for address;

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
        require(amount > 0, "AlpManagerFacet: invalid amount");
        address account = msg.sender;
        uint256 alpAmount = LibAlpManager.mintAlp(account, tokenIn, amount);
        require(alpAmount >= minAlp, "AlpManagerFacet: insufficient ALP output");
        _mint(account, tokenIn, amount, alpAmount, stake);
    }

    function mintAlpBNB(uint256 minAlp, bool stake) external payable whenNotPaused nonReentrant override {
        uint amount = msg.value;
        require(amount > 0, "AlpManagerFacet: invalid msg.value");
        address account = msg.sender;
        uint256 alpAmount = LibAlpManager.mintAlpBNB(account, amount);
        require(alpAmount >= minAlp, "AlpManagerFacet: insufficient ALP output");
        _mint(account, LibVault.WBNB(), amount, alpAmount, stake);
    }

    function _mint(address account, address tokenIn, uint256 amount, uint256 alpAmount, bool stake) private {
        IAlp(ALP()).mint(account, alpAmount);
        emit MintAlp(account, tokenIn, amount, alpAmount);
        if (stake) {
            LibStakeReward.stake(alpAmount);
        }
    }

    function burnAlp(address tokenOut, uint256 alpAmount, uint256 minOut, address receiver) external whenNotPaused nonReentrant override {
        require(alpAmount > 0, "AlpManagerFacet: invalid alpAmount");
        address account = msg.sender;
        uint256 amountOut = LibAlpManager.burnAlp(account, tokenOut, alpAmount, receiver);
        require(amountOut >= minOut, "AlpManagerFacet: insufficient token output");
        IAlp(ALP()).burnFrom(account, alpAmount);
        emit BurnAlp(account, receiver, tokenOut, alpAmount, amountOut);
    }

    function burnAlpBNB(uint256 alpAmount, uint256 minOut, address payable receiver) external whenNotPaused nonReentrant override {
        require(alpAmount > 0, "AlpManagerFacet: invalid alpAmount");
        address account = msg.sender;
        uint256 amountOut = LibAlpManager.burnAlpBNB(account, alpAmount, receiver);
        require(amountOut >= minOut, "AlpManagerFacet: insufficient BNB output");
        IAlp(ALP()).burnFrom(account, alpAmount);
        emit BurnAlp(account, receiver, LibVault.WBNB(), alpAmount, amountOut);
    }

    function alpPrice() external view override returns (uint256){
        return LibAlpManager.alpPrice();
    }

    function lastMintedTimestamp(address account) external view override returns (uint256) {
        return LibAlpManager.alpManagerStorage().lastMintedAt[account];
    }
}