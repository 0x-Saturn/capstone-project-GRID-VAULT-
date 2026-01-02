// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Minimal router mock used in tests. It simply transfers `amountIn` of `tokenOut`
 * to the `to` address and returns `amountIn` as `amountOut` (1:1 swap). Test harness
 * should ensure the router holds sufficient `tokenOut` balance before swap.
 */
contract UniswapRouterMock {
    function simpleSwap(address /*tokenIn*/, address tokenOut, uint256 amountIn, uint256 /*minOut*/, address to) external returns (uint256 amountOut) {
        amountOut = amountIn;
        IERC20(tokenOut).transfer(to, amountOut);
    }
}
