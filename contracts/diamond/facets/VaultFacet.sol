// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../security/OnlySelf.sol";
import "../../utils/Constants.sol";
import "../interfaces/IVault.sol";
import "../libraries/LibVault.sol";
import "../libraries/LibPriceFacade.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VaultFacet is IVault, OnlySelf {

    using SafeERC20 for IERC20;
    using Address for address payable;

    function initVaultFacet(address wbnb) external {
        LibAccessControlEnumerable.checkRole(Constants.DEPLOYER_ROLE);
        require(wbnb != address(0), "VaultFacet: Invalid wbnb");
        LibVault.initialize(wbnb);
    }

    function addToken(
        address tokenAddress, uint16 feeBasisPoints, uint16 taxBasisPoints, bool stable,
        bool dynamicFee, bool asMargin, uint16[] memory weights
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.TOKEN_OPERATOR_ROLE);
        require(tokenAddress != address(0), "VaultFacet: Token address can't be 0 address");
        LibVault.addToken(tokenAddress, feeBasisPoints, taxBasisPoints, stable, dynamicFee, asMargin, weights);
    }

    function removeToken(address tokenAddress, uint16[] memory weights) external override {
        LibAccessControlEnumerable.checkRole(Constants.TOKEN_OPERATOR_ROLE);
        require(tokenAddress != address(0), "VaultFacet: Token address can't be 0 address");
        LibVault.removeToken(tokenAddress, weights);
    }

    function updateToken(address tokenAddress, uint16 feeBasisPoints, uint16 taxBasisPoints, bool dynamicFee) external override {
        LibAccessControlEnumerable.checkRole(Constants.TOKEN_OPERATOR_ROLE);
        require(tokenAddress != address(0), "VaultFacet: Token address can't be 0 address");
        LibVault.updateToken(tokenAddress, feeBasisPoints, taxBasisPoints, dynamicFee);
    }

    function updateAsMagin(address tokenAddress, bool asMagin) external override {
        LibAccessControlEnumerable.checkRole(Constants.TOKEN_OPERATOR_ROLE);
        require(tokenAddress != address(0), "VaultFacet: Token address can't be 0 address");
        LibVault.updateAsMagin(tokenAddress, asMagin);
    }

    function changeWeight(uint16[] memory weights) external override {
        LibAccessControlEnumerable.checkRole(Constants.TOKEN_OPERATOR_ROLE);
        LibVault.changeWeight(weights);
    }

    // The value of securityMarginRate can be greater than 10000
    function setSecurityMarginP(uint16 _securityMarginP) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        require(_securityMarginP > 0, "VaultFacet: Invalid securityMarginP");
        LibVault.setSecurityMarginP(_securityMarginP);
    }

    function securityMarginP() external view override returns (uint16) {
        return LibVault.vaultStorage().securityMarginP;
    }

    function tokensV2() external view override returns (Token[] memory) {
        LibVault.VaultStorage storage vs = LibVault.vaultStorage();
        Token[] memory tokens = new Token[](vs.tokenAddresses.length);
        for (uint256 i; i < vs.tokenAddresses.length; i++) {
            tokens[i] = getTokenByAddress(vs.tokenAddresses[i]);
        }
        return tokens;
    }

    function getTokenByAddress(address tokenAddress) public view override returns (Token memory) {
        LibVault.AvailableToken memory at = LibVault.getTokenByAddress(tokenAddress);
        return Token(
            at.tokenAddress, at.weight, at.feeBasisPoints,
            at.taxBasisPoints, at.stable, at.dynamicFee, at.asMargin
        );
    }

    function getTokenForTrading(address tokenAddress) external view override returns (MarginToken memory) {
        LibVault.AvailableToken memory at = LibVault.getTokenByAddress(tokenAddress);
        return MarginToken(at.tokenAddress, at.asMargin, at.decimals, LibPriceFacade.getPrice(tokenAddress));
    }

    function itemValue(address token) external view override returns (LpItem memory lpItem) {
        LibVault.VaultStorage storage vs = LibVault.vaultStorage();
        LibVault.AvailableToken storage at = vs.tokens[token];
        require(at.tokenAddress != address(0), "VaultFacet: token does not exist");
        return _itemValue(at, vs.treasury[token]);
    }

    function _itemValue(LibVault.AvailableToken storage at, uint256 tokenValue) private view returns (IVault.LpItem memory lpItem) {
        address tokenAddress = at.tokenAddress;
        uint256 price = LibPriceFacade.getPrice(tokenAddress);
        uint256 valueUsd = price * tokenValue * 1e10 / (10 ** at.decimals);
        lpItem = IVault.LpItem(
            tokenAddress, int256(tokenValue), at.decimals, int256(valueUsd),
            at.weight, at.feeBasisPoints, at.taxBasisPoints, at.dynamicFee
        );
    }

    function totalValue() external view override returns (LpItem[] memory lpItems) {
        LibVault.VaultStorage storage vs = LibVault.vaultStorage();
        address[] storage tokenAddresses = vs.tokenAddresses;
        lpItems = new IVault.LpItem[](tokenAddresses.length);
        for (uint256 i; i < tokenAddresses.length; i++) {
            LibVault.AvailableToken storage at = vs.tokens[tokenAddresses[i]];
            lpItems[i] = _itemValue(at, vs.treasury[tokenAddresses[i]]);
        }
    }

    function increaseByCloseTrade(address token, uint256 amount) external onlySelf override {
        LibVault.deposit(token, amount);
    }

    function decreaseByCloseTrade(address token, uint256 amount) external onlySelf override returns (ITradingClose.SettleToken[] memory) {
        return LibVault.decreaseByCloseTrade(token, amount);
    }


    function maxWithdrawAbleUsd() external view returns (int256) {
        return LibVault.maxWithdrawAbleUsd();
    }

    //    function transferToExchangeTreasury(address[] calldata tokens_, uint256[] calldata amounts) external override {
    //        LibAccessControlEnumerable.checkRole(BALANCE_FUNDS_ROLE);
    //        require(tokens_.length == amounts.length, "VaultFacet: Parameter error");
    //        LibVault.VaultStorage storage vs = LibVault.vaultStorage();
    //        for (uint256 i; i < tokens_.length;) {
    //            LibVault.AvailableToken storage at = vs.tokens[tokens_[i]];
    //            _transferToExchangeTreasury(at, amounts[i]);
    //            unchecked {
    //                i++;
    //            }
    //        }
    //        emit TransferToExchangeTreasury(tokens_, amounts);
    //    }

    //    function _transferToExchangeTreasury(LibVault.AvailableToken storage at, uint256 amount) private {
    //        require(amount > 0, "VaultFacet: Amount must be greater than 0");
    //        require(at.weight > 0, "VaultFacet: Token does not exist");
    //        LibVault.withdraw(LibVault.exchangeTreasury(), at.tokenAddress, amount);
    //    }

    //    function transferToExchangeTreasuryBNB(uint256 amount) external override {
    //        LibAccessControlEnumerable.checkRole(BALANCE_FUNDS_ROLE);
    //        require(amount > 0, "VaultFacet: Amount must be greater than 0");
    //        LibVault.VaultStorage storage vs = LibVault.vaultStorage();
    //        LibVault.AvailableToken storage at = vs.tokens[LibVault.WBNB()];
    //        require(at.weight > 0, "VaultFacet: Token does not exist");
    //        LibVault.withdrawBNB(payable(LibVault.exchangeTreasury()), amount);
    //        emit TransferToExchangeTreasuryBNB(amount);
    //    }

    //    function receiveFromExchangeTreasury(bytes[] calldata messages, bytes[] calldata signatures) external override {
    //        LibAccessControlEnumerable.checkRole(BALANCE_FUNDS_ROLE);
    //        require(messages.length > 0 && messages.length == signatures.length, "VaultFacet: Parameter error");
    //        address[] memory tokens_ = new address[](messages.length);
    //        uint256[] memory amounts = new uint256[](messages.length);
    //        for (uint256 i; i < messages.length;) {
    //            (address token, uint256 amount) = _receiveFromExchangeTreasury(messages[i], signatures[i]);
    //            tokens_[i] = token;
    //            amounts[i] = amount;
    //            unchecked {
    //                i++;
    //            }
    //        }
    //        emit ReceiveFromExchangeTreasury(tokens_, amounts);
    //    }

    //    function _receiveFromExchangeTreasury(bytes calldata message, bytes calldata signature) private returns (address, uint256) {
    //        (, address payable to, bool isBNB, address token, uint256 amount,) = abi.decode(message, (uint256, address, bool, address, uint256, uint256));
    //        require(to == address(this), "VaultFacet: Incorrect receiving address");
    //        require(amount > 0, "VaultFacet: Amount must be greater than 0");
    //        if (isBNB) {
    //            token = LibVault.WBNB();
    //        }
    //        LibVault.AvailableToken storage at = LibVault.vaultStorage().tokens[token];
    //        require(at.weight > 0, "VaultFacet: Token does not exist");
    //        IExchangeTreasury(LibVault.exchangeTreasury()).claim(message, signature);
    //        if (isBNB) {
    //            LibVault.depositBNB(amount);
    //        } else {
    //            LibVault.deposit(token, amount);
    //        }
    //        return (token, amount);
    //    }

}
