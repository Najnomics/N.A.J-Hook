import crypto from "node:crypto";
import type { BatchSettlement, Hex, InEuint128Struct } from "./types.js";

export function createAttestation(input: {
  settlement: BatchSettlement;
  sealedVolumes: { token0: InEuint128Struct; token1: InEuint128Struct };
  mnemonic: string | null;
}): Hex {
  const secret = input.mnemonic ?? "local-dev-mnemonic";
  const hmac = crypto.createHmac("sha256", secret);
  hmac.update(Buffer.from(JSON.stringify(input.settlement)));
  hmac.update(Buffer.from(input.sealedVolumes.token0.ctHash.slice(2), "hex"));
  hmac.update(Buffer.from(input.sealedVolumes.token1.ctHash.slice(2), "hex"));
  return `0x${hmac.digest("hex")}`;
}

