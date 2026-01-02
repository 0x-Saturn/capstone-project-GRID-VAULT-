// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/GridVault.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/UniswapRouterMock.sol";
import "../contracts/adapters/UniswapExecutionAdapterImpl.sol";
import "../contracts/mocks/AggregatorMock.sol";
import "../contracts/adapters/ChainlinkOracleAdapter.sol";

contract GridVaultTest is Test {
    GridVault vault;
    MockERC20 token;

    function setUp() public {
        token = new MockERC20("Mock", "MCK", 1_000_000 * 1e18);
        vault = new GridVault(address(this));
    }

    function testEstimateSimple() public {
        uint256 lower = 1e18; // price 1
        uint256 upper = 2e18; // price 2
        uint256 grid = 1;
        uint256 amount = 1e18; // 1 token (scaled)

        uint256 profit = vault.estimatePositionProfit(lower, upper, grid, amount);

        // For single grid from 1 -> 2: expected profit = 1 token (scaled)
        assertEq(profit, 1e18);
    }

    function testCreateAndClose() public {
        uint256 amount = 1000 * 1e18;
        token.mint(address(this), amount);
        token.approve(address(vault), amount);

        uint256 lower = 1e18;
        uint256 upper = 2e18;
        uint256 grid = 2;

        uint256 pid = vault.createPosition(address(token), lower, upper, grid, amount);
        GridVault.Position memory pos = vault.getPosition(pid);
        assertTrue(pos.active);

        vault.closePosition(pid);
        GridVault.Position memory pos2 = vault.getPosition(pid);
        assertFalse(pos2.active);

        // After closing, vault returns deposited tokens
        assertEq(token.balanceOf(address(this)), amount);
    }

    function testExecuteViaAdapter() public {
        // Deploy router mock and adapter implementation
        UniswapRouterMock router = new UniswapRouterMock();
        UniswapExecutionAdapterImpl adapter = new UniswapExecutionAdapterImpl();
        adapter.setRouter(address(router));
        vault.setExecutionAdapter(address(adapter));

        // Create two tokens: tokenA (deposited into vault) and tokenB (router holds outputs)
        MockERC20 tokenB = new MockERC20("MockB", "MCKB", 0);

        uint256 amount = 100 * 1e18;
        token.mint(address(this), amount);
        token.approve(address(vault), amount);

        // Mint output tokens to the router so router can pay out swaps
        tokenB.mint(address(router), amount);

        uint256 pid = vault.createPosition(address(token), 1e18, 2e18, 1, amount);

        // Execute a swap of 1 tokenA -> tokenB via adapter
        uint256 out = vault.executeSwapViaAdapter(pid, address(token), address(tokenB), 1e18, 0);
        assertEq(out, 1e18);

        // Vault should have received tokenB from router
        assertEq(tokenB.balanceOf(address(vault)), 1e18);
    }

    function testKeeperCanExecute() public {
        // Deploy router mock and adapter implementation
        UniswapRouterMock router = new UniswapRouterMock();
        UniswapExecutionAdapterImpl adapter = new UniswapExecutionAdapterImpl();
        adapter.setRouter(address(router));
        vault.setExecutionAdapter(address(adapter));

        // Register keeper via AccessControl
        address keeper = address(0xBEEF);
        bytes32 KEEPER_ROLE = keccak256("KEEPER_ROLE");
        vault.grantRole(KEEPER_ROLE, keeper);

        // Create two tokens: tokenA (deposited into vault) and tokenB (router holds outputs)
        MockERC20 tokenB = new MockERC20("MockB", "MCKB", 0);

        uint256 amount = 100 * 1e18;
        token.mint(address(this), amount);
        token.approve(address(vault), amount);

        // Mint output tokens to the router so router can pay out swaps
        tokenB.mint(address(router), amount);

        uint256 pid = vault.createPosition(address(token), 1e18, 2e18, 1, amount);

        // Keeper executes the swap (use vm.prank to impersonate keeper)
        vm.prank(keeper);
        uint256 out = vault.executeSwapViaAdapter(pid, address(token), address(tokenB), 1e18, 0);
        assertEq(out, 1e18);

        // Vault should have received tokenB from router
        assertEq(tokenB.balanceOf(address(vault)), 1e18);
    }

    function testGridFillAccounting() public {
        // Deploy router mock and adapter implementation
        UniswapRouterMock router = new UniswapRouterMock();
        UniswapExecutionAdapterImpl adapter = new UniswapExecutionAdapterImpl();
        adapter.setRouter(address(router));
        vault.setExecutionAdapter(address(adapter));

        // Register keeper via AccessControl
        address keeper = address(0xCAFE);
        bytes32 KEEPER_ROLE = keccak256("KEEPER_ROLE");
        vault.grantRole(KEEPER_ROLE, keeper);

        uint256 amount = 100 * 1e18;
        token.mint(address(this), amount);
        token.approve(address(vault), amount);

        uint256 pid = vault.createPosition(address(token), 1e18, 2e18, 10, amount);

        // Keeper records a buy fill that spends 1 quote token
        vm.prank(keeper);
        vault.recordGridFill(pid, 0, 1e18, 0, 1e18);

        GridVault.Position memory pos = vault.getPosition(pid);
        // position.amount should be reduced by 1e18
        assertEq(pos.amount, amount - 1e18);

        // Keeper records a sell fill that receives 2 quote tokens
        vm.prank(keeper);
        vault.recordGridFill(pid, 0, 0, 2e18, 2e18);

        GridVault.Position memory pos2 = vault.getPosition(pid);
        // position.amount should be increased by 2e18 (net +1e18 from previous)
        assertEq(pos2.amount, amount + 1e18);
    }

    function testAutoExecuteGrid() public {
        // Deploy router mock and adapter implementation
        UniswapRouterMock router = new UniswapRouterMock();
        UniswapExecutionAdapterImpl adapter = new UniswapExecutionAdapterImpl();
        adapter.setRouter(address(router));
        vault.setExecutionAdapter(address(adapter));

        // Register keeper via AccessControl
        address keeper = address(0xD00D);
        bytes32 KEEPER_ROLE = keccak256("KEEPER_ROLE");
        vault.grantRole(KEEPER_ROLE, keeper);

        uint256 amount = 100 * 1e18;
        token.mint(address(this), amount);
        token.approve(address(vault), amount);

        // mint tokenOut to router so it can pay back
        token.mint(address(router), amount);

        uint256 pid = vault.createPosition(address(token), 1e18, 2e18, 10, amount);

        // Keeper executes autoExecuteGrid spending 1e18 quote and expecting same token back
        vm.prank(keeper);
        uint256 out = vault.autoExecuteGrid(pid, 0, 1e18, address(token), 0);
        assertEq(out, 1e18);

        // position.amount should be decreased by 1e18 then increased by received 1e18 -> net 0 change
        GridVault.Position memory pos = vault.getPosition(pid);
        assertEq(pos.amount, amount);
    }

    function testChainlinkAdapterNormalizationAndEstimate() public {
        // Deploy aggregator mock with 8 decimals and price = 2000 * 1e8
        AggregatorMock agg = new AggregatorMock(8, int256(2000 * 1e8));

        ChainlinkOracleAdapter oracle = new ChainlinkOracleAdapter();
        // set feed mapping
        oracle.setFeed(address(token), address(agg));

        // normalized price should be 2000 * 1e18
        uint256 normalized = oracle.getPrice(address(token));
        assertEq(normalized, 2000 * 1e18);

        // wire oracle to vault
        vault.setPriceOracle(address(oracle));

        // create position with gridCount = 1 and amount = 1e18
        uint256 amount = 1e18;
        token.mint(address(this), amount);
        token.approve(address(vault), amount);
        uint256 pid = vault.createPosition(address(token), 1e18, 2e18, 1, amount);

        uint256 profit = vault.estimatePositionProfitFromOracle(pid, 1000); // spreadBps = 10%

        // compute expected profit: perGrid * step / p_i where p_i = lower
        uint256 currentPrice = normalized;
        (uint256 lower, uint256 upper) = vault.autoDeriveGrid(currentPrice, 1000);
        uint256 step = (upper - lower) / 1;
        uint256 perGrid = amount / 1;
        uint256 expected = (perGrid * step) / lower;

        assertEq(profit, expected);
    }
}
