import crypto from "node:crypto";
import type { BatchSettlement, Hex } from "./types.js";

export function createAttestation(input: {
  settlement: BatchSettlement;
  sealedVolumes: { token0: Hex; token1: Hex };
  mnemonic: string | null;
}): Hex {
  const secret = input.mnemonic ?? "local-dev-mnemonic";
  const hmac = crypto.createHmac("sha256", secret);
  hmac.update(Buffer.from(JSON.stringify(input.settlement)));
  hmac.update(Buffer.from(input.sealedVolumes.token0.slice(2), "hex"));
  hmac.update(Buffer.from(input.sealedVolumes.token1.slice(2), "hex"));
  return `0x${hmac.digest("hex")}`;
}

