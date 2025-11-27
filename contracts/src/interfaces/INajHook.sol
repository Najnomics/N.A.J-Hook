// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

interface INajHook {
    function configurePool(PoolKey calldata key, address strategyAdapter, address thresholdAdapter) external;

    function getPoolReserves(PoolKey calldata key) external view returns (uint256 reserve0, uint256 reserve1);

    function submitBatchAttestation(
        PoolKey calldata key,
        bytes32 batchId,
        bytes calldata attestation,
        InEuint128 calldata encryptedToken0Volume,
        InEuint128 calldata encryptedToken1Volume
    ) external;

    function finalizeBatch(PoolKey calldata key, bytes32 batchId) external;
}
