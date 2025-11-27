// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Minimal EigenCompute attestation verifier interface used by NAJ Hook
interface IEigenVerifier {
    /// @notice Verify attestation emitted by EigenCompute enclave
    /// @param attestation Raw attestation bytes
    /// @param batchHash Deterministic hash commitment of batch inputs
    /// @return valid True when attestation is accepted
    /// @return mrEnclave Measurement hash describing enclave binary
    /// @return mrSigner Measurement hash describing signer of enclave
    function verifyAttestation(bytes calldata attestation, bytes32 batchHash)
        external
        view
        returns (bool valid, bytes32 mrEnclave, bytes32 mrSigner);
}

