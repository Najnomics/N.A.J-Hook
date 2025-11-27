// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @dev Minimal Pyth stub for local testing
contract MockPyth is IPyth {
    PythStructs.Price private price;

    function setPrice(int64 price_, uint64 conf, int32 expo, uint publishTime) external {
        price = PythStructs.Price({price: price_, conf: conf, expo: expo, publishTime: publishTime});
    }

    function getUpdateFee(bytes[] calldata) external pure override returns (uint) {
        return 0;
    }

    function updatePriceFeeds(bytes[] calldata) external payable override {}

    function updatePriceFeedsIfNecessary(
        bytes[] calldata,
        bytes32[] calldata,
        uint64[] calldata
    ) external payable override {}

    function getPriceNoOlderThan(bytes32, uint) external view override returns (PythStructs.Price memory) {
        return price;
    }

    function getPriceUnsafe(bytes32) external view override returns (PythStructs.Price memory) {
        return price;
    }

    function getEmaPriceUnsafe(bytes32) external view override returns (PythStructs.Price memory) {
        return price;
    }

    function getEmaPriceNoOlderThan(bytes32, uint) external view override returns (PythStructs.Price memory) {
        return price;
    }

    function getTwapUpdateFee(bytes[] calldata) external pure override returns (uint) {
        return 0;
    }

    function parsePriceFeedUpdates(
        bytes[] calldata,
        bytes32[] calldata,
        uint64,
        uint64
    ) external payable override returns (PythStructs.PriceFeed[] memory) {
        revert("NOT_IMPLEMENTED");
    }

    function parsePriceFeedUpdatesWithConfig(
        bytes[] calldata,
        bytes32[] calldata,
        uint64,
        uint64,
        bool,
        bool,
        bool
    ) external payable override returns (PythStructs.PriceFeed[] memory, uint64[] memory) {
        revert("NOT_IMPLEMENTED");
    }

    function parseTwapPriceFeedUpdates(
        bytes[] calldata,
        bytes32[] calldata
    ) external payable override returns (PythStructs.TwapPriceFeed[] memory) {
        revert("NOT_IMPLEMENTED");
    }

    function parsePriceFeedUpdatesUnique(
        bytes[] calldata,
        bytes32[] calldata,
        uint64,
        uint64
    ) external payable override returns (PythStructs.PriceFeed[] memory) {
        revert("NOT_IMPLEMENTED");
    }
}

