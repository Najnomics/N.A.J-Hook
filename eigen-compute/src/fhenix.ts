import crypto from "node:crypto";
import type { Hex, InEuint128Struct } from "./types.js";

const EUINT128_TYPE = 6;

export function encryptVolume(value: bigint, sharedSecret: string): InEuint128Struct {
  const payload = Buffer.from(value.toString(16).padStart(64, "0"), "hex");
  const ctHash = crypto.createHash("sha256").update(payload).digest("hex");
  const signature = crypto.createHmac("sha256", sharedSecret).update(payload).digest("hex");

  return {
    ctHash: `0x${ctHash}`,
    securityZone: 0,
    utype: EUINT128_TYPE,
    signature: `0x${signature}`,
  };
}

