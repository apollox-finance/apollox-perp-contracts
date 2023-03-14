// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IOraclePrice.sol";
import "../interfaces/IChainlinkPrice.sol";
import "../libraries/LibChainlinkPrice.sol";
import "../libraries/LibAccessControlEnumerable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ZERO, ONE, UC, uc, into} from "unchecked-counter/src/UC.sol";

contract ChainlinkPriceFacet is IChainlinkPrice {

    bytes32 public constant PRICE_FEED_OPERATOR_ROLE = keccak256("PRICE_FEED_OPERATOR_ROLE");

    function addChainlinkPriceFeed(address token, address priceFeed) external override {
        LibAccessControlEnumerable.checkRole(PRICE_FEED_OPERATOR_ROLE);
        require(token != address(0), "ChainlinkPriceFacet: Token address can't be 0 address");
        require(priceFeed != address(0), "ChainlinkPriceFacet: Price feed address can't be 0 address");
        LibChainlinkPrice.addChainlinkPriceFeed(token, priceFeed);
    }

    function removeChainlinkPriceFeed(address token) external override {
        LibAccessControlEnumerable.checkRole(PRICE_FEED_OPERATOR_ROLE);
        require(token != address(0), "ChainlinkPriceFacet: Token address can't be 0 address");
        LibChainlinkPrice.removeChainlinkPriceFeed(token);
    }

    function getPriceFromChainlink(address token) external view override returns (PriceInfo memory priceInfo) {
        (uint256 price, uint8 decimals,) = LibChainlinkPrice.getPriceFromChainlink(token);
        priceInfo = PriceInfo(price, decimals);
    }

    function chainlinkPriceFeeds() external view override returns (PriceFeedInfo[] memory priceFeeds) {
        LibChainlinkPrice.ChainlinkPriceStorage storage cps = LibChainlinkPrice.chainlinkPriceStorage();
        uint256 numFeeds = cps.tokenAddresses.length;
        priceFeeds = new PriceFeedInfo[](numFeeds);
        for (UC i = ZERO; i < uc(numFeeds); i = i + ONE) {
            address token = cps.tokenAddresses[i.into()];
            LibChainlinkPrice.PriceFeed storage pf = cps.priceFeeds[token];
            priceFeeds[i.into()].token = token;
            priceFeeds[i.into()].feedAddress = pf.feedAddress;
            AggregatorV3Interface oracle = AggregatorV3Interface(pf.feedAddress);
            priceFeeds[i.into()].description = oracle.description();
            priceFeeds[i.into()].decimals = oracle.decimals();
        }
    }
}
