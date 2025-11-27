import { encodeAbiParameters, keccak256, stringToHex } from "viem";
import { mnemonicToAccount } from "viem/accounts";
import type { AttestationInput, Hex } from "./types.js";

interface AttestationConfig {
  mnemonic: string;
  mrEnclave: Hex;
  mrSigner: Hex;
}

export function createAttestationFactory(config: AttestationConfig) {
  const account = mnemonicToAccount(config.mnemonic);

  return async function createAttestation(
    input: AttestationInput
  ): Promise<Hex> {
    const message = JSON.stringify({
      settlement: input.settlement,
      sealed: {
        token0: input.sealedVolumes.token0.ctHash,
        token1: input.sealedVolumes.token1.ctHash,
      },
    });

    const signature = await account.signMessage({ message });
    const messageHash = keccak256(stringToHex(message));

    return encodeAbiParameters(
      [
        { type: "string" },
        { type: "bytes32" },
        { type: "bytes" },
        { type: "address" },
        { type: "bytes32" },
        { type: "bytes32" },
      ],
      [
        message,
        messageHash,
        signature,
        account.address,
        config.mrEnclave,
        config.mrSigner,
      ]
    ) as Hex;
  };
}
