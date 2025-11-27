// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IEigenVerifier} from "@interfaces/IEigenVerifier.sol";

/// @dev Lightweight attestation verifier used for tests
contract MockEigenVerifier is IEigenVerifier {
    bool private _shouldVerify = true;
    bytes32 private _mrEnclave;
    bytes32 private _mrSigner;

    function setResult(bool valid, bytes32 mrEnclave, bytes32 mrSigner) external {
        _shouldVerify = valid;
        _mrEnclave = mrEnclave;
        _mrSigner = mrSigner;
    }

    function verifyAttestation(bytes calldata, bytes32) external view returns (bool, bytes32, bytes32) {
        return (_shouldVerify, _mrEnclave, _mrSigner);
    }
}

