import { secp256k1 } from "@noble/curves/secp256k1";
import { bytesToHex, hexToBytes, keccak256 } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { Hex, InEuint128Struct } from "./types.js";

const EUINT128_TYPE = 6;
const HASH_MASK_FOR_METADATA = ((1n << 256n) - 1n) - ((1n << 16n) - 1n);
const UINT_TYPE_MASK = 0x7f;
const TRIVIAL_MASK = 0x80;

function toBytes(value: bigint, size: number): Uint8Array {
  const hex = value.toString(16).padStart(size * 2, "0");
  return hexToBytes(`0x${hex}`);
}

function addressToBytes(address: bigint): Uint8Array {
  return toBytes(address, 20);
}

function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const buffer = new Uint8Array(total);
  let offset = 0;

  for (const part of parts) {
    buffer.set(part, offset);
    offset += part.length;
  }

  return buffer;
}

function metadataByte(isTrivial: boolean, utype: number): number {
  return (isTrivial ? TRIVIAL_MASK : 0) | (utype & UINT_TYPE_MASK);
}

function normalizeSecurityZone(securityZone: number): number {
  if (securityZone < -128 || securityZone > 127) {
    throw new Error("securityZone must be between -128 and 127");
  }
  return (securityZone + 256) % 256;
}

export interface CofheEncoderConfig {
  chainId: bigint;
  signerPrivateKey: Hex;
  swapHandler: Hex;
  securityZone: number;
}

export class CofheEncoder {
  private readonly chainId: bigint;
  private readonly signerKey: Uint8Array;
  private readonly signerAddress: Hex;
  private readonly sender: bigint;
  private readonly securityZone: number;
  private salt = 0n;

  constructor(config: CofheEncoderConfig) {
    this.chainId = config.chainId;
    this.signerKey = hexToBytes(config.signerPrivateKey);
    this.securityZone = config.securityZone;
    const account = privateKeyToAccount(config.signerPrivateKey);
    this.signerAddress = account.address as Hex;
    this.sender = BigInt(config.swapHandler);
  }

  get signer() {
    return this.signerAddress;
  }

  async encryptVolume(value: bigint): Promise<InEuint128Struct> {
    const normalizedValue = value < 0n ? -value : value;
    const ctHash = this.computeCtHash(normalizedValue);
    const signature = await this.signInput(ctHash);

    return {
      ctHash,
      securityZone: normalizeSecurityZone(this.securityZone),
      utype: EUINT128_TYPE,
      signature,
    };
  }

  private computeCtHash(value: bigint): Hex {
    const valueBytes = toBytes(value, 32);
    const senderBytes = toBytes(this.sender, 32);
    const saltBytes = toBytes(this.salt, 32);
    const saltDigest = hexToBytes(keccak256(bytesToHex(saltBytes)));

    const combined = concatBytes(valueBytes, senderBytes, saltDigest);
    const preCtHash = BigInt(keccak256(bytesToHex(combined)));

    const cleared = preCtHash & HASH_MASK_FOR_METADATA;
    const meta =
      (BigInt(metadataByte(false, EUINT128_TYPE)) << 8n) |
      BigInt(normalizeSecurityZone(this.securityZone));
    this.salt += 1n;

    return `0x${(cleared | meta).toString(16).padStart(64, "0")}` as Hex;
  }

  private async signInput(ctHash: Hex): Promise<Hex> {
    const hashBytes = hexToBytes(ctHash);
    const utypeBytes = Uint8Array.from([EUINT128_TYPE]);
    const zoneByte = Uint8Array.from([normalizeSecurityZone(this.securityZone)]);
    const senderBytes20 = addressToBytes(this.sender);
    const chainBytes = toBytes(this.chainId, 32);

    const packed = concatBytes(
      hashBytes,
      utypeBytes,
      zoneByte,
      senderBytes20,
      chainBytes
    );

    const digestHex = keccak256(bytesToHex(packed));
    const digestBytes = hexToBytes(digestHex);
    const signature = secp256k1.sign(digestBytes, this.signerKey);
    const compact = signature.toCompactRawBytes();
    const signatureBytes = new Uint8Array(65);
    signatureBytes.set(compact, 0);
    signatureBytes[64] = (signature.recovery ?? 0) + 27;
    return bytesToHex(signatureBytes);
  }
}
