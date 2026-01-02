// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IExecutionAdapter.sol";

interface IUniswapRouterMock {
    function simpleSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address to) external returns (uint256 amountOut);
}

/**
 * @title UniswapExecutionAdapterImpl
 * @notice Concrete execution adapter that forwards to a Uniswap-like router.
 * @dev For tests we expect a router with `simpleSwap` helper. The adapter assumes
 *      the caller (GridVault) transfers `tokenIn` to this adapter before calling
 *      `executeSwap`. The adapter then calls the router and requests the output
 *      to be sent back to the original caller (GridVault).
 */
contract UniswapExecutionAdapterImpl is Ownable, IExecutionAdapter {
    constructor() Ownable(msg.sender) {}
    address public router;

    event RouterSet(address indexed router);

    function setRouter(address _router) external onlyOwner {
        router = _router;
        emit RouterSet(_router);
    }

    function executeSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut) {
        require(router != address(0), "router not set");

        // Adapter is expected to already hold `amountIn` of `tokenIn` (transferred by GridVault).
        // Call router to perform the swap and send proceeds to the original caller (GridVault).
        amountOut = IUniswapRouterMock(router).simpleSwap(tokenIn, tokenOut, amountIn, minAmountOut, msg.sender);

        return amountOut;
    }
}
