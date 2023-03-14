// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IOraclePrice {

    struct PriceInfo {
        uint256 price;
        uint8 decimals;
    }

    struct PriceFeedInfo {
        address token;
        address feedAddress;
        string description;
        uint8 decimals;
    }
}
