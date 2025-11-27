import crypto from "node:crypto";
import type { Hex } from "./types.js";

/**
 * Deterministic helper that mirrors the behavior of fhe-hook-template.
 * In production replace this with the official CoFHE SDK bindings.
 */
export function decryptVolume(ciphertext: string, sharedSecret: string): bigint {
  const payload =
    ciphertext.startsWith("0x") && ciphertext.length > 2
      ? Buffer.from(ciphertext.slice(2), "hex")
      : Buffer.from(ciphertext, "base64");

  const derived = crypto
    .createHmac("sha256", sharedSecret)
    .update(payload)
    .digest("hex");

  // cap the bigint so local tests remain in a reasonable range
  const value = BigInt(`0x${derived}`) % BigInt(1_000_000_000_000_000_000n);
  return value;
}

export function sealVolume(value: bigint, sharedSecret: string): Hex {
  const bytes = Buffer.from(value.toString(16).padStart(32, "0"), "hex");
  const digest = crypto
    .createHmac("sha256", sharedSecret)
    .update(bytes)
    .digest("hex");
  return `0x${digest}` as Hex;
}

