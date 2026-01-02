// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../GridVault.sol"; // for PRICE_PRECISION constant reference
import "./IPriceOracle.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function decimals() external view returns (uint8);
}

/**
 * @title ChainlinkOracleAdapter (stub)
 * @notice Maps ERC20 tokens to Chainlink aggregators and normalizes price to 1e18.
 * @dev Minimal, ownership-controlled mapping. No validation beyond answer>0.
 */
contract ChainlinkOracleAdapter is Ownable, IPriceOracle {
    constructor() Ownable(msg.sender) {}
    // token -> aggregator
    mapping(address => address) public feeds;

    event FeedSet(address indexed token, address indexed feed);

    function setFeed(address token, address feed) external onlyOwner {
        feeds[token] = feed;
        emit FeedSet(token, feed);
    }

    function getPrice(address token) external view returns (uint256) {
        address feed = feeds[token];
        require(feed != address(0), "no feed");
        AggregatorV3Interface agg = AggregatorV3Interface(feed);
        (, int256 answer, , , ) = agg.latestRoundData();
        require(answer > 0, "invalid answer");
        uint8 d = agg.decimals();

        // normalize to 1e18
        if (d == 18) return uint256(answer);
        if (d < 18) return uint256(answer) * (10 ** (18 - d));
        return uint256(answer) / (10 ** (d - 18));
    }
}
