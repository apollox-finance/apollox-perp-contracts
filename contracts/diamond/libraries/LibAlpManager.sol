// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../libraries/LibVault.sol";
import "../interfaces/IPriceFacade.sol";
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
        ams.coolingDuration = 30 minutes;
    }

    event MintAddLiquidity(address indexed account, address indexed token, uint256 amount);
    event BurnRemoveLiquidity(address indexed account, address indexed token, uint256 amount);

    function alpPrice() internal view returns (uint256) {
        int256 totalValueUsd = LibVault.getTotalValueUsd();
        (int256 lpUnPnlUsd,) = ITradingCore(address(this)).lpUnrealizedPnlUsd();
        return _alpPrice(totalValueUsd + lpUnPnlUsd);
    }

    function _alpPrice(int256 totalValueUsd) private view returns (uint256) {
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
        LibVault.AvailableToken memory at = LibVault.vaultStorage().tokens[tokenIn];
        alpAmount = _calculateAlpAmount(at, amount);
        LibVault.deposit(tokenIn, amount, account, false);
        _addMinted(account);
        emit MintAddLiquidity(account, tokenIn, amount);
    }

    function mintAlpBNB(address account, uint256 amount) internal returns (uint256 alpAmount){
        address tokenIn = LibVault.WBNB();
        LibVault.AvailableToken memory at = LibVault.vaultStorage().tokens[tokenIn];
        alpAmount = _calculateAlpAmount(at, amount);
        LibVault.depositBNB(amount);
        _addMinted(account);
        emit MintAddLiquidity(account, tokenIn, amount);
    }

    function _calculateAlpAmount(LibVault.AvailableToken memory at, uint256 amount) private view returns (uint256 alpAmount) {
        require(at.tokenAddress != address(0), "LibAlpManager: Token does not exist");
        (int256 lpUnPnlUsd, int256 lpTokenUnPnlUsd) = ITradingCore(address(this)).lpUnrealizedPnlUsd(at.tokenAddress);
        uint256 alpPrice_ = _alpPrice(LibVault.getTotalValueUsd() + lpUnPnlUsd);
        require(alpPrice_ > 0, "LibAlpManager: ALP Price is not available");

        (uint256 tokenInPrice,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(at.tokenAddress);
        uint256 amountUsd = tokenInPrice * amount * 1e10 / (10 ** at.decimals);
        int256 poolTokenInUsd = int256(LibVault.vaultStorage().treasury[at.tokenAddress] * tokenInPrice * 1e10 / (10 ** at.decimals)) + lpTokenUnPnlUsd;
        // ∵ alpPrice_ > 0
        // ∴ (LibVault.getTotalValueUsd() + lpUnPnlUsd) > 0
        uint256 afterTaxAmountUsd =
        amountUsd *
        (1e4 - _getFeePoint(at, uint256(LibVault.getTotalValueUsd() + lpUnPnlUsd), poolTokenInUsd, amountUsd, true)) /
        1e4;
        alpAmount = afterTaxAmountUsd * 1e8 / alpPrice_;
    }

    function _addMinted(address account) private {
        alpManagerStorage().lastMintedAt[account] = block.timestamp;
    }

    function burnAlp(address account, address tokenOut, uint256 alpAmount, address receiver) internal returns (uint256 amountOut) {
        AlpManagerStorage storage ams = alpManagerStorage();
        require(ams.lastMintedAt[account] + ams.coolingDuration <= block.timestamp, "LibAlpManager: Cooling duration not yet passed");
        LibVault.AvailableToken memory at = LibVault.vaultStorage().tokens[tokenOut];
        amountOut = _calculateTokenAmount(at, alpAmount);
        LibVault.withdraw(receiver, tokenOut, amountOut);
        emit BurnRemoveLiquidity(account, tokenOut, amountOut);
    }

    function burnAlpBNB(address account, uint256 alpAmount, address payable receiver) internal returns (uint256 amountOut) {
        AlpManagerStorage storage ams = alpManagerStorage();
        require(ams.lastMintedAt[account] + ams.coolingDuration <= block.timestamp, "LibAlpManager: Cooling duration not yet passed");
        address tokenOut = LibVault.WBNB();
        LibVault.AvailableToken memory at = LibVault.vaultStorage().tokens[tokenOut];
        amountOut = _calculateTokenAmount(at, alpAmount);
        LibVault.withdrawBNB(receiver, amountOut);
        emit BurnRemoveLiquidity(account, tokenOut, amountOut);
    }

    function _calculateTokenAmount(LibVault.AvailableToken memory at, uint256 alpAmount) private view returns (uint256 amountOut) {
        require(at.tokenAddress != address(0), "LibAlpManager: Token does not exist");
        (int256 lpUnPnlUsd, int256 lpTokenUnPnlUsd) = ITradingCore(address(this)).lpUnrealizedPnlUsd(at.tokenAddress);
        int256 totalValueUsd = LibVault.getTotalValueUsd() + lpUnPnlUsd;
        uint256 alpPrice_ = _alpPrice(totalValueUsd);
        require(alpPrice_ > 0, "LibAlpManager: ALP Price is not available");
        (uint256 tokenOutPrice,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(at.tokenAddress);
        int256 poolTokenOutUsd = int256(LibVault.vaultStorage().treasury[at.tokenAddress] * tokenOutPrice * 1e10 / (10 ** at.decimals)) + lpTokenUnPnlUsd;
        uint256 amountOutUsd = alpPrice_ * alpAmount / 1e8;
        // It is not allowed for the value of any token in the LP to become negative after burning.
        require(poolTokenOutUsd >= int256(amountOutUsd), "LibAlpManager: tokenOut balance is insufficient");
        // ∵ alpPrice_ > 0
        // ∴ (LibVault.getTotalValueUsd() + lpUnPnlUsd) > 0
        uint256 afterTaxAmountOutUsd = amountOutUsd * (1e4 - _getFeePoint(at, uint256(totalValueUsd), poolTokenOutUsd, amountOutUsd, false)) / 1e4;
        require(int256(afterTaxAmountOutUsd) <= LibVault.maxWithdrawAbleUsd(totalValueUsd), "LibAlpManager: tokenOut balance is insufficient");
        return afterTaxAmountOutUsd * (10 ** at.decimals) / (tokenOutPrice * 1e10);
    }

    function _getFeePoint(
        LibVault.AvailableToken memory at, uint256 totalValueUsd,
        int256 poolTokenUsd, uint256 amountUsd, bool increase
    ) private pure returns (uint256) {
        if (!at.dynamicFee) {
            return increase ? at.feeBasisPoints : at.taxBasisPoints;
        }
        uint256 targetValueUsd = totalValueUsd * at.weight / 1e4;
        int256 nextValueUsd = poolTokenUsd + int256(amountUsd);
        if (!increase) {
            // ∵ poolTokenUsd >= amountUsd && amountUsd > 0
            // ∴ poolTokenUsd > 0
            nextValueUsd = poolTokenUsd - int256(amountUsd);
        }

        uint256 initDiff = poolTokenUsd > int256(targetValueUsd)
        ? uint256(poolTokenUsd) - targetValueUsd  // ∵ (poolTokenUsd > targetValueUsd && targetValueUsd > 0) ∴ (poolTokenUsd > 0)
        : uint256(int256(targetValueUsd) - poolTokenUsd);

        uint256 nextDiff = nextValueUsd > int256(targetValueUsd)
        ? uint256(nextValueUsd) - targetValueUsd
        : uint256(int256(targetValueUsd) - nextValueUsd);

        if (nextDiff < initDiff) {
            uint256 feeAdjust = at.taxBasisPoints * initDiff / targetValueUsd;
            return at.feeBasisPoints > feeAdjust ? at.feeBasisPoints - feeAdjust : 0;
        }

        uint256 avgDiff = (initDiff + nextDiff) / 2;
        return at.feeBasisPoints + (avgDiff > targetValueUsd ? at.taxBasisPoints : (at.taxBasisPoints * avgDiff) / targetValueUsd);
    }
}
