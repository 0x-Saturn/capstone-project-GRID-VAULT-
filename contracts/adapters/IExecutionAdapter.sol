// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice Execution adapter abstraction for swapping tokens on a DEX.
 * @dev Implementations will be DEX specific (Uniswap, 0x, etc.).
 */
interface IExecutionAdapter {
    /// @notice Execute a swap from tokenIn -> tokenOut
    /// @param tokenIn token being sold
    /// @param tokenOut token being bought
    /// @param amountIn amount of tokenIn to sell
    /// @param minAmountOut minimum acceptable amount of tokenOut (slippage guard)
    /// @return amountOut the actual amount received of tokenOut
    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);
}
