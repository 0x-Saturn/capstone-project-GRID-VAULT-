// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./adapters/IPriceOracle.sol";
import "./adapters/IExecutionAdapter.sol";

/**
 * @title GridVault
 * @notice Modular, deterministic grid-trading vault core logic (math-only, no oracles/execution).
 * @dev Designed for extensibility: oracles, keepers, and DEX adapters can be added later.
 * Prices and amounts are expected to use a common fixed-point scale (e.g. 1e18) for determinism.
 */
contract GridVault is Ownable, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PRECISION = 1e18; // convention: prices are scaled by 1e18

    struct Position {
        address owner;      // creator / owner of the position
        address token;      // ERC20 token held in vault (quote currency for estimation)
        uint256 lowerPrice; // scaled price (1e18)
        uint256 upperPrice; // scaled price (1e18)
        uint256 gridCount;  // number of grid steps
        uint256 amount;     // amount of `token` deposited (scaled by token decimals)
        bool active;        // whether position is open
    }

    // --- Adapter management ---
    function setPriceOracle(address oracle) external onlyOwner {
        priceOracle = IPriceOracle(oracle);
        emit PriceOracleSet(oracle);
    }

    function setExecutionAdapter(address adapter) external onlyOwner {
        executionAdapter = IExecutionAdapter(adapter);
        emit ExecutionAdapterSet(adapter);
    }

    // Keeper management is handled by AccessControl `grantRole` / `revokeRole` for `KEEPER_ROLE`.

    /**
     * @notice Estimate a position's profit using the configured price oracle.
     * @param positionId id of the position
     * @param spreadBps spread to derive grid around current price
     */
    function estimatePositionProfitFromOracle(uint256 positionId, uint256 spreadBps) external view returns (uint256) {
        require(address(priceOracle) != address(0), "no oracle");
        Position storage pos = _positions[positionId];
        require(pos.active, "position inactive");
        uint256 currentPrice = priceOracle.getPrice(pos.token);
        (uint256 lower, uint256 upper) = autoDeriveGrid(currentPrice, spreadBps);
        return estimatePositionProfit(lower, upper, pos.gridCount, pos.amount);
    }

    /**
     * @notice Execute a swap via the configured execution adapter for a position.
     * @dev This function forwards the execution intent to the adapter. Real token flow
     *      requires a concrete adapter implementation (router calls, approvals). This core
     *      function is an integration hook to allow automation layers to call into adapters.
     */
    function executeSwapViaAdapter(
        uint256 positionId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) public nonReentrant returns (uint256 amountOut) {
        require(address(executionAdapter) != address(0), "no execution adapter");
        Position storage pos = _positions[positionId];
        require(pos.active, "position inactive");
        require(msg.sender == pos.owner || msg.sender == owner() || hasRole(KEEPER_ROLE, msg.sender), "not authorized");

        // Transfer tokenIn from vault to the adapter so adapter/router can execute the swap.
        IERC20(tokenIn).safeTransfer(address(executionAdapter), amountIn);

        // Forward the call to the adapter. Note: adapters must implement actual token movement.
        amountOut = executionAdapter.executeSwap(tokenIn, tokenOut, amountIn, minAmountOut);

        emit TradeExecuted(positionId, msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /**
     * @notice Record a partial or full fill for a specific grid in a position.
     * @dev `amountSpentQuote` is amount of quote token spent (debit), `amountReceivedQuote` is amount of quote token received (credit).
     *      Net effect on the position's `amount` = +amountReceivedQuote - amountSpentQuote.
     * @param positionId id of the position
     * @param gridIndex index of the grid (0-based)
     * @param amountSpentQuote amount of quote spent (e.g., buying base)
     * @param amountReceivedQuote amount of quote received (e.g., selling base)
     * @param price execution price (scaled by PRICE_PRECISION)
     */
    function recordGridFill(
        uint256 positionId,
        uint256 gridIndex,
        uint256 amountSpentQuote,
        uint256 amountReceivedQuote,
        uint256 price
    ) public nonReentrant {
        Position storage pos = _positions[positionId];
        require(pos.active, "position inactive");
        require(gridIndex < pos.gridCount, "grid index OOB");
        require(msg.sender == pos.owner || msg.sender == owner() || hasRole(KEEPER_ROLE, msg.sender), "not authorized");

        // update accumulated per-grid quote amount
        gridFilledAmount[positionId][gridIndex] += amountSpentQuote + amountReceivedQuote;

        // adjust position's quote amount by net received - spent
        if (amountReceivedQuote >= amountSpentQuote) {
            pos.amount += (amountReceivedQuote - amountSpentQuote);
        } else {
            pos.amount -= (amountSpentQuote - amountReceivedQuote);
        }

        emit GridFilled(positionId, gridIndex, amountSpentQuote, amountReceivedQuote, price);
    }

    /**
     * @notice Convenience helper to execute a single grid trade and record the fill.
     * @dev Caller must be position owner, keeper or contract owner. The vault transfers
     *      `amountQuote` of the position token to the configured adapter, which should
     *      execute the swap and return proceeds to the vault. After execution the vault
     *      records the fill against `gridIndex`.
     * @param positionId id of the position
     * @param gridIndex index of the grid to execute
     * @param amountQuote amount of the position token (quote) to spend on this grid
     * @param tokenOut token expected back from the swap (for now can be same as position token)
     * @param minAmountOut slippage guard forwarded to adapter
     */
    function autoExecuteGrid(
        uint256 positionId,
        uint256 gridIndex,
        uint256 amountQuote,
        address tokenOut,
        uint256 minAmountOut
    ) external nonReentrant returns (uint256 amountOut) {
        Position storage pos = _positions[positionId];
        require(pos.active, "position inactive");
        require(gridIndex < pos.gridCount, "grid index OOB");
        require(msg.sender == pos.owner || msg.sender == owner() || hasRole(KEEPER_ROLE, msg.sender), "not authorized");
        require(address(executionAdapter) != address(0), "no execution adapter");

        // Ensure vault has sufficient token balance
        require(IERC20(pos.token).balanceOf(address(this)) >= amountQuote, "insufficient vault balance");

        // Transfer and execute via adapter (this will transfer pos.token to adapter internally)
        amountOut = executeSwapViaAdapter(positionId, pos.token, tokenOut, amountQuote, minAmountOut);

        // Record fill: amountSpentQuote is amountQuote, amountReceivedQuote is amountOut if tokenOut == pos.token
        uint256 receivedQuote = tokenOut == pos.token ? amountOut : 0;
        uint256 price = 0;
        if (address(priceOracle) != address(0)) {
            price = priceOracle.getPrice(pos.token);
        }

        recordGridFill(positionId, gridIndex, amountQuote, receivedQuote, price);
    }

    // Compact storage: positions by id, and user -> array of ids
    mapping(uint256 => Position) private _positions;
    mapping(address => uint256[]) private _userPositions;
    uint256 private _nextPositionId;
    IPriceOracle public priceOracle;
    IExecutionAdapter public executionAdapter;
    event PositionCreated(uint256 indexed positionId, address indexed owner);
    event PositionClosed(uint256 indexed positionId, address indexed owner);
    event PriceOracleSet(address indexed oracle);
    event ExecutionAdapterSet(address indexed adapter);
    event TradeExecuted(uint256 indexed positionId, address indexed caller, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    event GridFilled(uint256 indexed positionId, uint256 indexed gridIndex, uint256 amountSpentQuote, uint256 amountReceivedQuote, uint256 price);

    // amount of quote currency applied to each grid (accumulated)
    mapping(uint256 => mapping(uint256 => uint256)) public gridFilledAmount;

    /**
     * @param initialOwner explicit initial owner for Ownable
     */
    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != address(0), "initialOwner zero");
        _nextPositionId = 1; // start ids at 1
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(KEEPER_ROLE, initialOwner);
    }

    // --- Core user functions ---

    /**
     * @notice Create a grid position and deposit `amount` of `token` into the vault.
     * @dev For simplicity this vault holds the deposited token until `closePosition`.
     * @param token ERC20 token address (quote token used for estimation & storage)
     * @param lowerPrice lower bound (scaled by PRICE_PRECISION)
     * @param upperPrice upper bound (scaled by PRICE_PRECISION)
     * @param gridCount number of equal grids to split the range into
     * @param amount amount of `token` to deposit (must be approved beforehand)
     * @return positionId the newly created position id
     */
    function createPosition(
        address token,
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 gridCount,
        uint256 amount
    ) external nonReentrant returns (uint256 positionId) {
        require(token != address(0), "token zero");
        require(gridCount > 0, "gridCount zero");
        require(lowerPrice > 0 && upperPrice > lowerPrice, "invalid price range");
        require(amount > 0, "amount zero");

        // transfer tokens into vault
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        positionId = _nextPositionId++;
        _positions[positionId] = Position({
            owner: msg.sender,
            token: token,
            lowerPrice: lowerPrice,
            upperPrice: upperPrice,
            gridCount: gridCount,
            amount: amount,
            active: true
        });

        _userPositions[msg.sender].push(positionId);
        emit PositionCreated(positionId, msg.sender);
    }

    /**
     * @notice Close an open position and withdraw the deposited token amount back to owner.
     * @dev No trading/execution is performed in this core contract; integration layer will
     *      handle actual buy/sell actions. Closing simply returns deposited funds.
     * @param positionId id of the position to close
     */
    function closePosition(uint256 positionId) external nonReentrant {
        Position storage pos = _positions[positionId];
        require(pos.active, "position inactive");
        require(pos.owner == msg.sender, "not owner");

        pos.active = false;

        // return funds
        IERC20(pos.token).safeTransfer(pos.owner, pos.amount);

        emit PositionClosed(positionId, msg.sender);
    }

    // --- View / estimation helpers ---

    /**
     * @notice Get all positions for a user (memory copy). Useful for frontends/tests.
     * @param user address whose positions to return
     * @return positions array of Position structs
     */
    function getUserPositions(address user) external view returns (Position[] memory positions) {
        uint256 len = _userPositions[user].length;
        positions = new Position[](len);
        for (uint256 i = 0; i < len; ++i) {
            positions[i] = _positions[_userPositions[user][i]];
        }
    }

    /**
     * @notice Get a single position by id.
     */
    function getPosition(uint256 positionId) external view returns (Position memory) {
        return _positions[positionId];
    }

    /**
     * @notice Deterministic estimate of position profit expressed in the same token units as `amount`.
     * @dev Model: split the price range into `gridCount` equal steps. For each grid i:
     *      - allocate C = amount / gridCount (quote currency)
     *      - buy qty = C / p_i (base units)
     *      - sell at p_{i+1} to receive C * p_{i+1} / p_i
     *      - profit_i = C * (p_{i+1}/p_i - 1) = C * (step / p_i)
     *      Total profit = sum_i profit_i.
     *      All math assumes prices are scaled by PRICE_PRECISION (1e18) for deterministic fixed-point arithmetic.
     * @param lower lower price (scaled)
     * @param upper upper price (scaled)
     * @param gridCount number of grids
     * @param amount total capital allocated (in quote token units)
     * @return estimatedProfit total estimated profit (same token units as `amount`)
     */
    function estimatePositionProfit(
        uint256 lower,
        uint256 upper,
        uint256 gridCount,
        uint256 amount
    ) public pure returns (uint256 estimatedProfit) {
        require(gridCount > 0, "gridCount zero");
        require(lower > 0 && upper > lower, "invalid range");
        require(amount > 0, "amount zero");

        uint256 step = (upper - lower) / gridCount; // price increment per grid (scaled)
        uint256 perGrid = amount / gridCount; // simple equal allocation

        // Sum profit across each grid: perGrid * step / p_i
        // Use loop; gridCount should be modest in practice to keep gas reasonable.
        for (uint256 i = 0; i < gridCount; ++i) {
            uint256 p_i = lower + step * i;
            // avoid division by zero
            if (p_i == 0) continue;
            // profit_i = perGrid * step / p_i
            // since prices are scaled, division is safe without extra scaling of perGrid
            uint256 profit_i = (perGrid * step) / p_i;
            estimatedProfit += profit_i;
        }
    }

    /**
     * @notice Auto-derive a symmetric grid range around `currentPrice` using `spreadBps`.
     * @param currentPrice current price scaled by PRICE_PRECISION
     * @param spreadBps spread in basis points (1 bps = 0.01%). Must be <= 10000.
     * @return lower derived lower price
     * @return upper derived upper price
     */
    function autoDeriveGrid(uint256 currentPrice, uint256 spreadBps)
        public
        pure
        returns (uint256 lower, uint256 upper)
    {
        require(spreadBps <= 10000, "spreadBps>10000");
        // lower = current * (1 - spread)
        // upper = current * (1 + spread)
        lower = (currentPrice * (10000 - spreadBps)) / 10000;
        upper = (currentPrice * (10000 + spreadBps)) / 10000;
    }

    // --- Admin utilities ---

    /**
     * @notice Emergency withdraw tokens from the contract.
     * @dev Only owner. Intended for recovery during development; real deployments should
     *      consider timelocks or governance-controlled recovery.
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "to zero");
        IERC20(token).safeTransfer(to, amount);
    }
}
