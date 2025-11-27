import pino from "pino";
import request from "supertest";
import { describe, expect, it } from "vitest";
import { createApp } from "../server.js";
import { executeStrategy } from "../strategy.js";
import type { PythPriceData, InEuint128Struct, AttestationInput } from "../types.js";

const logger = pino({ level: "silent" });

const fakePrice: PythPriceData = {
  price: 2000,
  confidence: 1,
  timestamp: 1_730_000_000,
  priceUpdateData: [],
};

const encryptStub = async (value: bigint): Promise<InEuint128Struct> => ({
  ctHash: `0x${value.toString(16).padStart(64, "0")}`,
  securityZone: 0,
  utype: 6,
  signature: `0x${"11".repeat(65)}`,
});

const attestationStub = async (_input: AttestationInput) => "0xdeadbeef";

const app = createApp({
  logger,
  fetchPythPrice: async () => fakePrice,
  executeStrategy,
  encryptVolume: encryptStub,
  createAttestation: attestationStub,
  publicMetadata: {
    chainRpcUrl: null,
    launchpadAddress: null,
    hookAddress: null,
  },
});

describe("POST /batch smoke tests", () => {
  it("rejects invalid payloads", async () => {
    const res = await request(app).post("/batch").send({});
    expect(res.status).toBe(400);
    expect(res.body.ok).toBe(false);
  });

  it("processes a valid batch", async () => {
    const payload = {
      poolId: `0x${"11".repeat(32)}`,
      batchId: "0x01",
      orders: [
        {
          sender: `0x${"22".repeat(20)}`,
          zeroForOne: true,
          amountSpecified: "-100000000000000000",
          tokenIn: `0x${"33".repeat(20)}`,
          tokenOut: `0x${"44".repeat(20)}`,
        },
      ],
    };

    const res = await request(app).post("/batch").send(payload);

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.settlement.poolId).toBe(payload.poolId);
    expect(res.body.attestation).toBe("0xdeadbeef");
  });
});

