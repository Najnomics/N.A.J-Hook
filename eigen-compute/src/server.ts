import express from "express";
import pinoHttp from "pino-http";
import type { Logger } from "pino";
import { z } from "zod";
import type {
  AttestationInput,
  BatchMetadata,
  BatchRequest,
  BatchComputation,
  PythPriceData,
  InEuint128Struct,
  Hex,
} from "./types.js";

const hexString = (length?: number) =>
  z
    .string()
    .regex(
      length
        ? new RegExp(`^0x[0-9a-fA-F]{${length}}$`)
        : /^0x[0-9a-fA-F]+$/,
      "Invalid hex string"
    )
    .transform((value) => value as Hex);

const BatchSchema = z.object({
  poolId: hexString(64),
  batchId: hexString(),
  strategyParams: z
    .object({
      baseSpreadBps: z.number().int().min(0).max(10_000).optional(),
      inventorySkewBps: z.number().int().min(-5_000).max(5_000).optional(),
    })
    .optional(),
  metadata: z
    .object({
      timestamp: z.number().int().optional(),
      oraclePrice: z.number().optional(),
    })
    .optional(),
  orders: z
    .array(
      z.object({
        sender: hexString(40),
        zeroForOne: z.boolean(),
        amountSpecified: z.string(),
        tokenIn: hexString(40),
        tokenOut: hexString(40),
      })
    )
    .min(1),
}) as z.ZodType<BatchRequest>;

export interface AppDeps {
  logger: Logger;
  fetchPythPrice: () => Promise<PythPriceData>;
  executeStrategy: (
    batch: BatchRequest,
    ctx: {
      metadata: BatchMetadata;
      encryptVolume: (value: bigint) => Promise<InEuint128Struct>;
    }
  ) => Promise<BatchComputation>;
  encryptVolume: (value: bigint) => Promise<InEuint128Struct>;
  createAttestation: (input: AttestationInput) => Promise<string>;
  publicMetadata: {
    chainRpcUrl: string | null;
    launchpadAddress: string | null;
    hookAddress: string | null;
  };
}

export function createApp(deps: AppDeps) {
  const startedAt = new Date().toISOString();
  const app = express();

  const httpLogger = (pinoHttp as unknown as typeof pinoHttp.default) ?? (pinoHttp as any);

  app.use(express.json({ limit: "1mb" }));
  app.use(httpLogger({ logger: deps.logger }));

  app.get("/", (_req, res) => {
    res.json({
      ok: true,
      startedAt,
      docs: {
        eigencompute: "https://docs.eigencloud.xyz/eigencompute/get-started/quickstart",
        applicationEnvironment:
          "https://docs.eigencloud.xyz/eigencompute/howto/build/application-environment",
      },
      publicMetadata: deps.publicMetadata,
    });
  });

  app.post("/batch", async (req, res) => {
    try {
      const parsed = BatchSchema.parse(req.body);
      const pythPrice = await deps.fetchPythPrice();

      const metadata: BatchMetadata = {
        oraclePrice: pythPrice.price,
        timestamp: parsed.metadata?.timestamp ?? pythPrice.timestamp,
        pythConfidenceBps:
          pythPrice.price === 0
            ? undefined
            : Math.round((pythPrice.confidence / Math.abs(pythPrice.price)) * 10_000),
        priceUpdateData: pythPrice.priceUpdateData,
      };

      const computation = await deps.executeStrategy(parsed, {
        metadata,
        encryptVolume: deps.encryptVolume,
      });

      const attestation = await deps.createAttestation({
        settlement: computation.settlement,
        sealedVolumes: computation.encryptedVolumes,
      });

      res.json({
        ok: true,
        settlement: computation.settlement,
        encryptedVolumes: computation.encryptedVolumes,
        attestation,
        metadata,
      });
    } catch (err) {
      if (err instanceof z.ZodError) {
        res.status(400).json({ ok: false, message: "Invalid payload", issues: err.issues });
        return;
      }

      deps.logger.error({ err }, "Batch execution failed");
      res.status(500).json({ ok: false, message: "Batch execution failed" });
    }
  });

  return app;
}

