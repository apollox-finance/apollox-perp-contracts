// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IOraclePrice.sol";

interface IChainlinkPrice is IOraclePrice {

    function addChainlinkPriceFeed(address token, address priceFeed) external;

    function removeChainlinkPriceFeed(address token) external;

    function getPriceFromChainlink(address token) external view returns (PriceInfo memory priceInfo);

    function chainlinkPriceFeeds() external view returns (PriceFeedInfo[] memory priceFeeds);
}
