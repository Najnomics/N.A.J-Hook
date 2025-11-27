// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

interface ISwapHandler {
    ////////////////////////////////////////////////////
    ////////////////////// Structs /////////////////////
    ////////////////////////////////////////////////////

    /// @notice Individual swap data from TEE
    struct SwapData {
        address sender;
        bool zeroForOne;
        int256 amountSpecified;
        address tokenIn;
        address tokenOut;
    }

    /// @notice Callback data for unlock pattern
    struct CallbackData {
        PoolKey key;
        SwapData[] swaps;
        bytes32 batchId;
    }

    struct BatchMetadata {
        bytes32 batchId;
        bytes attestation;
        InEuint128 encryptedToken0Volume;
        InEuint128 encryptedToken1Volume;
    }

    function postBatch(
        PoolId poolId,
        bytes calldata strategyUpdateParams,
        SwapData[] calldata swaps,
        BatchMetadata calldata metadata
    ) external;
}
