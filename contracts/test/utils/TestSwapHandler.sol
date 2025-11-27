    using CurrencyLibrary for Currency;
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SwapHandler} from "@utils/SwapHandler.sol";
import {SyntheticLiquidityHelper} from "@test/utils/SyntheticLiquidityHelper.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

/// @notice Test-only SwapHandler that rewrites PoolManager storage to simulate healthy liquidity between swaps.
contract TestSwapHandler is SwapHandler {
    using PoolIdLibrary for PoolKey;

    SyntheticLiquidityHelper public immutable syntheticHelper;

    struct SyntheticConfig {
        bytes32 slot0Snapshot;
        uint128 liquidity;
    }

    mapping(PoolId => SyntheticConfig) internal syntheticConfigs;

    constructor(
        address _tee,
        address _najLaunchpad,
        address _najHook,
        address _poolManager,
        address _universalRouter,
        address _najRouter,
        address _permit2,
        address _syntheticHelper
    ) SwapHandler(_tee, _najLaunchpad, _najHook, _poolManager, _universalRouter, _najRouter, _permit2) {
        syntheticHelper = SyntheticLiquidityHelper(_syntheticHelper);
    }

    function configureSyntheticLiquidity(PoolKey calldata key, bytes32 slot0Snapshot, uint128 liquidity) external {
        bytes32 snapshot = slot0Snapshot;
        require(snapshot != bytes32(0), "SyntheticSwapHandler: empty snapshot");
        require(liquidity != 0, "SyntheticSwapHandler: liquidity zero");
        syntheticConfigs[key.toId()] = SyntheticConfig({slot0Snapshot: snapshot, liquidity: liquidity});
    }

    function _executeSwap(PoolKey memory key, SwapData memory swapData, bytes32 batchId) internal override {
        SyntheticConfig memory cfg = syntheticConfigs[key.toId()];
        if (cfg.slot0Snapshot != bytes32(0) && cfg.liquidity != 0) {
            syntheticHelper.resetPoolState(IPoolManager(address(poolManager)), key, cfg.slot0Snapshot, cfg.liquidity);
        }

        super._executeSwap(key, swapData, batchId);

        // Net out deltas so PoolManager unlock() can settle cleanly.
        Currency currency0 = key.currency0;
        Currency currency1 = key.currency1;
        uint256 balance0 = currency0.balanceOf(address(this));
        uint256 balance1 = currency1.balanceOf(address(this));
        if (balance0 > 0) {
            currency0.transfer(address(poolManager), balance0);
        }
        if (balance1 > 0) {
            currency1.transfer(address(poolManager), balance1);
        }
    }
}

