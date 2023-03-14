// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../libraries/LibVault.sol";
import "../libraries/LibPriceFacade.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library LibAlpManager {

    bytes32 constant ALP_MANAGER_STORAGE_POSITION = keccak256("apollox.alp.manager.storage.v2");
    uint8 constant  ALP_DECIMALS = 18;

    struct AlpManagerStorage {
        mapping(address => uint256) lastMintedAt;
        uint256 coolingDuration;
        address alp;
        // blockNumber => ALP Increase in quantity, possibly negative
        mapping(uint256 => int256) alpIncrement;  // obsolete
        uint256 safeguard;  // obsolete
    }

    function alpManagerStorage() internal pure returns (AlpManagerStorage storage ams) {
        bytes32 position = ALP_MANAGER_STORAGE_POSITION;
        assembly {
            ams.slot := position
        }
    }

    function initialize(address alpToken) internal {
        AlpManagerStorage storage ams = alpManagerStorage();
        require(ams.alp == address(0), "LibAlpManager: Already initialized");
        ams.alp = alpToken;
        // default 30 minutes
        ams.coolingDuration = 1800;
    }

    event MintAddLiquidity(address indexed account, address indexed token, uint256 amount);
    event BurnRemoveLiquidity(address indexed account, address indexed token, uint256 amount);

    function alpPrice() internal view returns (uint256) {
        int256 totalValueUsd = LibVault.getTotalValueUsd();
        uint256 totalSupply = IERC20(alpManagerStorage().alp).totalSupply();
        if (totalValueUsd <= 0 && totalSupply > 0) {
            return 0;
        }
        if (totalSupply == 0) {
            return 1e8;
        } else {
            return uint256(totalValueUsd) * 1e8 / totalSupply;
        }
    }

    function mintAlp(address account, address tokenIn, uint256 amount) internal returns (uint256 alpAmount){
        alpAmount = _calculateAlpAmount(tokenIn, amount);
        LibVault.deposit(tokenIn, amount, account, false);
        _addMinted(account);
        emit MintAddLiquidity(account, tokenIn, amount);
    }

    function mintAlpBNB(address account, uint256 amount) internal returns (uint256 alpAmount){
        address tokenIn = LibVault.WBNB();
        alpAmount = _calculateAlpAmount(tokenIn, amount);
        LibVault.depositBNB(amount);
        _addMinted(account);
        emit MintAddLiquidity(account, tokenIn, amount);
    }

    function _calculateAlpAmount(address tokenIn, uint256 amount) private view returns (uint256 alpAmount) {
        LibVault.AvailableToken storage at = LibVault.vaultStorage().tokens[tokenIn];
        require(at.weight > 0, "LibAlpManager: Token does not exist");
        uint256 tokenInPrice = LibPriceFacade.getPrice(tokenIn);
        uint256 amountUsd = tokenInPrice * amount * 1e10 / (10 ** at.decimals);
        uint256 afterTaxAmountUsd = amountUsd * (1e4 - getMintFeePoint(at)) / 1e4;
        uint256 _alpPrice = alpPrice();
        require(_alpPrice > 0, "LibAlpManager: ALP Price is not available");
        alpAmount = afterTaxAmountUsd * 1e8 / _alpPrice;
    }

    function _addMinted(address account) private {
        alpManagerStorage().lastMintedAt[account] = block.timestamp;
    }

    function getMintFeePoint(LibVault.AvailableToken storage at) internal view returns (uint16) {
        // Dynamic rates are not supported in Phase I
        // Soon it will be supported
        require(!at.dynamicFee, "LibAlpManager: Dynamic fee rates are not supported at this time");
        return at.feeBasisPoints;
    }

    function burnAlp(address account, address tokenOut, uint256 alpAmount, address receiver) internal returns (uint256 amountOut) {
        amountOut = _calculateTokenAmount(account, tokenOut, alpAmount);
        LibVault.withdraw(receiver, tokenOut, amountOut);
        emit BurnRemoveLiquidity(account, tokenOut, amountOut);
    }

    function burnAlpBNB(address account, uint256 alpAmount, address payable receiver) internal returns (uint256 amountOut) {
        address tokenOut = LibVault.WBNB();
        amountOut = _calculateTokenAmount(account, tokenOut, alpAmount);
        LibVault.withdrawBNB(receiver, amountOut);
        emit BurnRemoveLiquidity(account, tokenOut, amountOut);
    }

    function _calculateTokenAmount(address account, address tokenOut, uint256 alpAmount) private view returns (uint256 amountOut) {
        LibVault.VaultStorage storage vs = LibVault.vaultStorage();
        LibVault.AvailableToken storage at = vs.tokens[tokenOut];
        require(at.weight > 0, "LibAlpManager: Token does not exist");
        AlpManagerStorage storage ams = alpManagerStorage();
        require(ams.lastMintedAt[account] + ams.coolingDuration <= block.timestamp, "LibAlpManager: Cooling duration not yet passed");
        uint256 tokenOutPrice = LibPriceFacade.getPrice(tokenOut);
        uint256 _alpPrice = alpPrice();
        require(_alpPrice > 0, "LibAlpManager: ALP Price is not available");
        uint256 amountOutUsd = _alpPrice * alpAmount / 1e8;
        uint256 afterTaxAmountOutUsd = amountOutUsd * (1e4 - getBurnFeePoint(at)) / 1e4;

        require(int256(afterTaxAmountOutUsd) <= LibVault.maxWithdrawAbleUsd(), "LibAlpManager: tokenOut balance is insufficient");
        amountOut = afterTaxAmountOutUsd * (10 ** at.decimals) / (tokenOutPrice * 1e10);
        require(amountOut < vs.treasury[tokenOut], "LibAlpManager: tokenOut balance is insufficient");
    }

    function getBurnFeePoint(LibVault.AvailableToken storage at) internal view returns (uint16) {
        // Dynamic rates are not supported in Phase I
        // Soon it will be supported
        require(!at.dynamicFee, "LibAlpManager: Dynamic fee rates are not supported at this time");
        return at.taxBasisPoints;
    }
}