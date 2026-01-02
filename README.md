# Grid Vault — Demo

This repository contains a minimal, extensible Grid Trading Vault smart contract implemented in Solidity 0.8.20.

Highlights

Quick start
1. Install dependencies:
```bash
npm install
```
2. Run tests:
```bash
npm test
```

Design notes

Next steps
 Adapters included
 - `contracts/adapters/IPriceOracle.sol` — oracle interface (returns price scaled to 1e18).
 - `contracts/adapters/ChainlinkOracleAdapter.sol` — ownership-controlled Chainlink feed mapper (normalizes decimals).
 - `contracts/adapters/IExecutionAdapter.sol` — execution interface for DEX swaps.
 - `contracts/adapters/UniswapExecutionAdapter.sol` — Uniswap-style execution stub (emit-only placeholder).

 These are intentionally minimal, pluggable stubs to make it straightforward to wire in
 real oracle feeds and DEX routers later (Chainlink, Pyth, Uniswap, 0x, etc.).
# capstone-project-GRID-VAULT-
GridVault implements on-chain grid trading with configurable price ranges, capital allocation, and profit estimation for ERC-20 assets. It allows users to define price ranges, split capital into grids, and capture market volatility across any ERC-20 token.
