// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

interface Vm {
    function store(address target, bytes32 slot, bytes32 value) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

/// @notice Test-only helper that directly seeds PoolManager liquidity via storage writes.
/// @dev Allows integration tests to simulate healthy pools without touching production contracts.
contract SyntheticLiquidityHelper is Test {
    using PoolIdLibrary for PoolKey;

Vm internal constant HEVM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
uint256 internal poolsSlotIndex;
bool internal poolsSlotInitialized;

    /// @notice Reset PoolManager state (slot0 + liquidity) to deterministic synthetic values.
    function resetPoolState(IPoolManager manager, PoolKey memory key, bytes32 slot0Snapshot, uint128 liquidity) external {
        _ensurePoolsSlot(manager, key);
        bytes32 poolId = PoolId.unwrap(key.toId());
        bytes32 baseSlot = keccak256(abi.encode(poolId, poolsSlotIndex));
        bytes32 liquiditySlot = bytes32(uint256(baseSlot) + 3); // Pool.State.liquidity offset

        HEVM.store(address(manager), baseSlot, slot0Snapshot);
        HEVM.store(address(manager), liquiditySlot, bytes32(uint256(liquidity)));
    }

    /// @notice Capture the current Slot0 storage value for a pool.
    function captureSlot0(IPoolManager manager, PoolKey memory key) public returns (bytes32) {
        _ensurePoolsSlot(manager, key);
        bytes32 poolId = PoolId.unwrap(key.toId());
        bytes32 baseSlot = keccak256(abi.encode(poolId, poolsSlotIndex));
        return HEVM.load(address(manager), baseSlot);
    }

    function _ensurePoolsSlot(IPoolManager manager, PoolKey memory key) internal {
        if (poolsSlotInitialized) return;

        bytes32 poolId = PoolId.unwrap(key.toId());
        for (uint256 slot = 0; slot < 10; slot++) {
            bytes32 baseSlot = keccak256(abi.encode(poolId, slot));
            bytes32 value = manager.extsload(baseSlot);
            if (value != bytes32(0)) {
                poolsSlotIndex = slot;
                poolsSlotInitialized = true;
                break;
            }
        }

        require(poolsSlotInitialized, "SyntheticHelper: slot not found");
    }
}

