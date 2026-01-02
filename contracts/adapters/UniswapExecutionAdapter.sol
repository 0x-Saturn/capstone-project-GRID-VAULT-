// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IExecutionAdapter.sol";

/**
 * @title UniswapExecutionAdapter (stub)
 * @notice Minimal stub for a Uniswap-like execution adapter. For now it does not
 * perform real swaps — it serves as a pluggable adapter interface for higher-level
 * automation or integration layers to call into when executing grid trades.
 *
 * Implementation notes:
 * - Owners can set an immutable router address to later enable real calls.
 * - `executeSwap` currently returns `amountIn` (1:1) as a placeholder and emits an event.
 */
contract UniswapExecutionAdapter is Ownable, IExecutionAdapter {
    constructor() Ownable(msg.sender) {}
    address public router;

    event RouterSet(address indexed router);
    event SwapExecuted(address indexed caller, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    function setRouter(address _router) external onlyOwner {
        router = _router;
        emit RouterSet(_router);
    }

    /// @dev Placeholder: returns `amountIn` as received amount. Real integration should
    ///      call the router (e.g., `swapExactTokensForTokens`) and return actual output.
    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 /* minAmountOut */
    ) external returns (uint256 amountOut) {
        // Placeholder logic: no external calls executed here.
        amountOut = amountIn;
        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }
}
