// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice Minimal abstraction for price oracles used by GridVault integrations.
 * @dev Implementations should return prices scaled to 1e18 (PRICE_PRECISION).
 */
interface IPriceOracle {
    /// @notice Get the price for a token scaled by 1e18
    function getPrice(address token) external view returns (uint256);
}
