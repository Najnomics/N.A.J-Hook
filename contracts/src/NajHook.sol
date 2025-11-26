// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary,
    toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

import {ISwapHandler} from "@interfaces/ISwapHandler.sol";
import {IStrategyAdapter} from "@interfaces/IStrategyAdapter.sol";
import {IEigenVerifier} from "@interfaces/IEigenVerifier.sol";
import {FHE, InEuint128, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @title NajHook - Proprietary AMM with Strategy-Based Pricing
/// @notice Hook enabling market makers to launch proprietary pools with custom pricing strategies
/// @dev Each pool has its own strategy adapter defining proprietary pricing logic
contract NajHook is BaseHook, Ownable {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    ////////////////////////////////////////////////////
    ////////////////////// Structs /////////////////////
    ////////////////////////////////////////////////////

    /// @notice Configuration for each pool
    struct PoolConfig {
        address strategyAdapter; // Adapter defining pricing logic
        address thresholdAdapter; // Adapter defining threshold conditions
        bool initialized; // Whether pool config is set
    }

    ////////////////////////////////////////////////////
    ////////////////////// State ///////////////////////
    ////////////////////////////////////////////////////

    /// @notice Hook reserves per pool and currency
    mapping(bytes32 => mapping(Currency => uint256)) public hookReserves;

    /// @notice Pool configurations
    mapping(bytes32 => PoolConfig) public poolConfigs;

    /// @notice Authorized launchpad address
    address public launchpad;

    /// @notice Authorized swap handler (TEE)
    address public swapHandler;

    /// @notice EigenCompute attestation verifier
    IEigenVerifier public eigenVerifier;

    /// @notice Latest sealed batch id per pool
    mapping(bytes32 => bytes32) public sealedBatchIds;

    /// @notice Encrypted token0 batch volume per pool
    mapping(bytes32 => euint128) public encryptedToken0Flow;

    /// @notice Encrypted token1 batch volume per pool
    mapping(bytes32 => euint128) public encryptedToken1Flow;

    ////////////////////////////////////////////////////
    ////////////////////// Errors //////////////////////
    ////////////////////////////////////////////////////

    error NajHook__InsufficientHookReserves();
    error NajHook__PoolNotConfigured();
    error NajHook__InvalidStrategyAdapter();
    error NajHook__Unauthorized();
    error NajHook__InsufficientReserves();
    error NajHook__NoLiquidityAllowed();
    error NajHook__EigenVerifierNotConfigured();
    error NajHook__InvalidAttestation();
    error NajHook__BatchMismatch();
    error NajHook__UnsealedBatch();
    error NajHook__InvalidHookData();

    ////////////////////////////////////////////////////
    ////////////////////// Events //////////////////////
    ////////////////////////////////////////////////////

    event PoolConfigured(PoolId indexed poolId, address strategyAdapter, address thresholdAdapter);
    event LaunchpadSet(address indexed launchpad);
    event SwapHandlerSet(address indexed swapHandler);
    event EigenVerifierSet(address indexed eigenVerifier);
    event BatchAttested(PoolId indexed poolId, bytes32 batchId, bytes32 mrEnclave, bytes32 mrSigner);
    event BatchFinalized(PoolId indexed poolId, bytes32 batchId);
    event SwapRequested(PoolId indexed poolId, address sender, bool zeroForOne, int256 amountSpecified);
    event SwapExecutedByTEE(
        PoolId indexed poolId, bool zeroForOne, int256 amountSpecified, uint256 price, bytes32 batchId
    );

    ////////////////////////////////////////////////////
    ////////////////////// Modifiers ///////////////////
    ////////////////////////////////////////////////////

    modifier onlyLaunchpad() {
        _checkLaunchpad();
        _;
    }

    modifier onlySwapHandler() {
        _checkSwapHandler();
        _;
    }

    ////////////////////////////////////////////////////
    /////////////////// Constructor ////////////////////
    ////////////////////////////////////////////////////

    constructor(IPoolManager _poolManager, address _owner) BaseHook(_poolManager) Ownable(_owner) {}

    ////////////////////////////////////////////////////
    /////////////// Configuration Functions ////////////
    ////////////////////////////////////////////////////

    /// @notice Set the launchpad address (can only be set once)
    /// @param _launchpad Address of the NajLaunchpad contract
    function setLaunchpad(address _launchpad) external onlyOwner {
        if (launchpad != address(0)) revert NajHook__Unauthorized();
        launchpad = _launchpad;
        emit LaunchpadSet(_launchpad);
    }

    /// @notice Set the swap handler address (can only be set once)
    /// @param _swapHandler Address of the SwapHandler contract (TEE)
    function setSwapHandler(address _swapHandler) external onlyOwner {
        if (swapHandler != address(0)) revert NajHook__Unauthorized();
        swapHandler = _swapHandler;
        emit SwapHandlerSet(_swapHandler);
    }

    /// @notice Configure EigenCompute verifier contract
    /// @param _eigenVerifier Address of verifier
    function setEigenVerifier(address _eigenVerifier) external onlyOwner {
        if (_eigenVerifier == address(0)) revert NajHook__EigenVerifierNotConfigured();
        eigenVerifier = IEigenVerifier(_eigenVerifier);
        emit EigenVerifierSet(_eigenVerifier);
    }

    /// @notice Configure a pool with strategy and threshold adapters
    /// @dev Called by launchpad when initializing a pool
    /// @param key The pool key
    /// @param strategyAdapter Address of the strategy adapter for pricing
    /// @param thresholdAdapter Address of the threshold adapter for conditions
    function configurePool(PoolKey calldata key, address strategyAdapter, address thresholdAdapter)
        external
        onlyLaunchpad
    {
        bytes32 poolId = PoolId.unwrap(key.toId());

        if (strategyAdapter == address(0)) revert NajHook__InvalidStrategyAdapter();

        poolConfigs[poolId] =
            PoolConfig({strategyAdapter: strategyAdapter, thresholdAdapter: thresholdAdapter, initialized: true});

        emit PoolConfigured(key.toId(), strategyAdapter, thresholdAdapter);
    }

    /// @notice Store encrypted batch metadata following EigenCompute attestation
    function submitBatchAttestation(
        PoolKey calldata key,
        bytes32 batchId,
        bytes calldata attestation,
        InEuint128 calldata encryptedToken0Volume,
        InEuint128 calldata encryptedToken1Volume
    ) external onlySwapHandler {
        bytes32 poolId = PoolId.unwrap(key.toId());

        if (!poolConfigs[poolId].initialized) revert NajHook__PoolNotConfigured();
        if (address(eigenVerifier) == address(0)) revert NajHook__EigenVerifierNotConfigured();
        if (batchId == bytes32(0)) revert NajHook__BatchMismatch();

        bytes32 batchHash = keccak256(abi.encode(block.chainid, poolId, batchId));
        (bool valid, bytes32 mrEnclave, bytes32 mrSigner) = eigenVerifier.verifyAttestation(attestation, batchHash);
        if (!valid) revert NajHook__InvalidAttestation();

        sealedBatchIds[poolId] = batchId;
        encryptedToken0Flow[poolId] = FHE.asEuint128(encryptedToken0Volume);
        encryptedToken1Flow[poolId] = FHE.asEuint128(encryptedToken1Volume);

        FHE.allowThis(encryptedToken0Flow[poolId]);
        FHE.allowThis(encryptedToken1Flow[poolId]);

        emit BatchAttested(key.toId(), batchId, mrEnclave, mrSigner);
    }

    /// @notice Clear encrypted state when batch completes
    function finalizeBatch(PoolKey calldata key, bytes32 batchId) external onlySwapHandler {
        bytes32 poolId = PoolId.unwrap(key.toId());
        if (sealedBatchIds[poolId] != batchId) revert NajHook__BatchMismatch();

        sealedBatchIds[poolId] = bytes32(0);
        encryptedToken0Flow[poolId] = euint128.wrap(0);
        encryptedToken1Flow[poolId] = euint128.wrap(0);

        emit BatchFinalized(key.toId(), batchId);
    }

    ////////////////////////////////////////////////////
    /////////////// Hook Permission Setup //////////////
    ////////////////////////////////////////////////////

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        revert NajHook__NoLiquidityAllowed();
    }

    /// @notice Before removing liquidity
    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        revert NajHook__NoLiquidityAllowed();
    }

    /// @notice After removing liquidity - allow custom withdrawal amounts
    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        // Decode desired withdrawal (address asset, uint256 amount)
        (address asset, uint256 amountDesired) = abi.decode(hookData, (address, uint256));

        bytes32 poolId = PoolId.unwrap(key.toId());
        Currency currency = Currency.wrap(asset);

        // Ensure pool has sufficient reserves
        if (hookReserves[poolId][currency] < amountDesired) revert NajHook__InsufficientHookReserves();

        // Update reserves
        hookReserves[poolId][currency] -= amountDesired;

        // Convert to int128 (positive because user is receiving tokens)
        int128 customAmount = int128(int256(amountDesired));

        BalanceDelta hookBalanceDelta;

        if (currency == key.currency0) {
            int128 hookDelta = customAmount - (delta.amount0() - feesAccrued.amount0());
            hookBalanceDelta = toBalanceDelta(hookDelta, 0);
        } else {
            int128 hookDelta = customAmount - (delta.amount1() - feesAccrued.amount1());
            hookBalanceDelta = toBalanceDelta(0, hookDelta);
        }

        return (IHooks.afterRemoveLiquidity.selector, hookBalanceDelta);
    }

    ////////////////////////////////////////////////////
    ////////////////// View Functions //////////////////
    ////////////////////////////////////////////////////

    /// @notice Get pool configuration
    function getPoolConfig(PoolKey calldata key) external view returns (PoolConfig memory) {
        return poolConfigs[PoolId.unwrap(key.toId())];
    }

    /// @notice Get current reserves for a pool
    function getPoolReserves(PoolKey calldata key) external view returns (uint256 reserve0, uint256 reserve1) {
        bytes32 poolId = PoolId.unwrap(key.toId());
        reserve0 = hookReserves[poolId][key.currency0];
        reserve1 = hookReserves[poolId][key.currency1];
    }

    ////////////////////////////////////////////////////
    ///////////// SwapHandler Functions ////////////////
    ////////////////////////////////////////////////////

    /// @notice Before swap - handles both user requests and TEE batch execution
    /// @dev Regular users: swap request queued for TEE batch
    ///      SwapHandler: swap executes immediately
    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (address user, bytes32 batchId) = hookData.length == 0
            ? (sender, bytes32(0))
            : abi.decode(hookData, (address, bytes32));

        if (user == address(0)) user = sender;

        bytes32 poolId = PoolId.unwrap(key.toId());
        PoolConfig memory config = poolConfigs[poolId];

        // Ensure pool is configured
        if (!config.initialized) revert NajHook__PoolNotConfigured();

        // Check if caller is authorized SwapHandler (TEE)
        if (sender == swapHandler) {
            if (batchId == bytes32(0)) revert NajHook__InvalidHookData();
            if (sealedBatchIds[poolId] != batchId) revert NajHook__UnsealedBatch();
            return _executeSwapForTEE(poolId, key, config, params, user, batchId);
        } else {
            emit SwapRequested(key.toId(), sender, params.zeroForOne, params.amountSpecified);
            uint256 amountTaken = uint256(-int256(params.amountSpecified));
            Currency input = params.zeroForOne ? key.currency0 : key.currency1;
            poolManager.mint(address(this), input.toId(), amountTaken);

            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(amountTaken.toInt128(), 0), 0);
        }
    }

    /// @notice Execute swap for TEE batch (authorized caller)
    function _executeSwapForTEE(
        bytes32 poolId,
        PoolKey calldata key,
        PoolConfig memory config,
        SwapParams calldata params,
        address user,
        bytes32 batchId
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        // Get price from strategy adapter with swap direction and amount
        uint256 price = IStrategyAdapter(config.strategyAdapter)
            .price(
                ISwapHandler.SwapData({
                    sender: msg.sender,
                    zeroForOne: params.zeroForOne,
                    amountSpecified: params.amountSpecified,
                    tokenIn: params.zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1),
                    tokenOut: params.zeroForOne ? Currency.unwrap(key.currency1) : Currency.unwrap(key.currency0)
                })
            );

        // Calculate swap amounts based on strategy price
        BeforeSwapDelta beforeSwapDelta =
            _calculateSwapDelta(key, params.amountSpecified, params.zeroForOne, price, user);

        emit SwapExecutedByTEE(key.toId(), params.zeroForOne, params.amountSpecified, price, batchId);

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Calculate swap delta based on strategy price
    /// @param amountSpecified The amount specified by the user (negative for exact input, positive for exact output)
    /// @param zeroForOne Direction of the swap
    /// @param price The price from strategy adapter (scaled by 1e18)
    /// @return delta The calculated before swap delta
    function _calculateSwapDelta(
        PoolKey memory key,
        int256 amountSpecified,
        bool zeroForOne,
        uint256 price,
        address user
    ) internal returns (BeforeSwapDelta delta) {
        if (amountSpecified == 0) return BeforeSwapDeltaLibrary.ZERO_DELTA;

        int128 specifiedDelta;
        int128 unspecifiedDelta;

        // Exact input (negative amountSpecified)
        if (amountSpecified < 0) {
            uint256 amountIn = uint256(-amountSpecified);
            uint256 amountOut;

            if (zeroForOne) {
                // Selling token0 for token1
                // amountOut = amountIn * price / 1e18
                amountOut = (amountIn * price) / 1e18;

                specifiedDelta = int128(int256(amountIn)); // Hook takes token0
                unspecifiedDelta = -int128(int256(amountOut)); // Hook gives token1

            } else {
                // Selling token1 for token0
                // amountOut = amountIn * 1e18 / price
                amountOut = (amountIn * 1e18) / price;

                specifiedDelta = int128(int256(amountIn)); // Hook takes token1
                unspecifiedDelta = -int128(int256(amountOut)); // Hook gives token0

            }

            key.currency1.transfer(user, amountOut);
        }
        // Exact output (positive amountSpecified)
        else {
            uint256 amountOut = uint256(amountSpecified);
            uint256 amountIn;

            if (zeroForOne) {
                // Want exact token1 out, calculate token0 in
                // amountIn = amountOut * 1e18 / price
                amountIn = (amountOut * 1e18) / price;

                specifiedDelta = -int128(int256(amountOut)); // Hook gives token1
                unspecifiedDelta = int128(int256(amountIn)); // Hook takes token0
            } else {
                // Want exact token0 out, calculate token1 in
                // amountIn = amountOut * price / 1e18
                amountIn = (amountOut * price) / 1e18;

                specifiedDelta = -int128(int256(amountOut)); // Hook gives token0
                unspecifiedDelta = int128(int256(amountIn)); // Hook takes token1
            }
        }

        return toBeforeSwapDelta(specifiedDelta, unspecifiedDelta);
    }

    function _checkLaunchpad() internal view {
        if (msg.sender != launchpad) revert NajHook__Unauthorized();
    }

    function _checkSwapHandler() internal view {
        if (msg.sender != swapHandler) revert NajHook__Unauthorized();
    }
}
