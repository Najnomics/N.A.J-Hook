import express from "express";
import pino from "pino";
import pinoHttp from "pino-http";
import { z } from "zod";
import { appConfig } from "./config.js";
import { executeStrategy } from "./strategy.js";
import { createAttestation } from "./attestation.js";
import type { BatchRequest } from "./types.js";

const logger = pino({ level: process.env.LOG_LEVEL ?? "info" });
const startedAt = new Date().toISOString();

const BatchSchema = z.object({
  poolId: z.string().regex(/^0x[0-9a-fA-F]{64}$/),
  batchId: z.string().regex(/^0x[0-9a-fA-F]+$/),
  encryptedToken0Volume: z.string().min(4),
  encryptedToken1Volume: z.string().min(4),
  strategyParams: z
    .object({
      baseSpreadBps: z.number().int().min(0).max(10_000).optional(),
      inventorySkewBps: z.number().int().min(-5_000).max(5_000).optional(),
    })
    .optional(),
  metadata: z.object({
    oraclePrice: z.number().positive(),
    timestamp: z.number().int().positive(),
    pythConfidenceBps: z.number().int().optional(),
  }),
}) satisfies z.ZodType<BatchRequest>;

const app = express();
app.use(express.json({ limit: "1mb" }));
app.use(
  pinoHttp({
    logger,
  })
);

app.get("/", (_req, res) => {
  res.json({
    ok: true,
    startedAt,
    docs: {
      eigencompute: "https://docs.eigencloud.xyz/eigencompute/get-started/quickstart",
      applicationEnvironment:
        "https://docs.eigencloud.xyz/eigencompute/howto/build/application-environment",
    },
    publicMetadata: appConfig.publicMetadata,
    hasMnemonic: Boolean(appConfig.mnemonic),
  });
});

app.post("/batch", async (req, res) => {
  try {
    const parsed = BatchSchema.parse(req.body);
    const computation = executeStrategy(parsed);
    const attestation = createAttestation({
      settlement: computation.settlement,
      sealedVolumes: computation.sealedVolumes,
      mnemonic: appConfig.mnemonic,
    });

    res.json({
      ok: true,
      settlement: computation.settlement,
      sealedVolumes: computation.sealedVolumes,
      attestation,
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ ok: false, message: "Invalid payload", issues: err.issues });
      return;
    }
    logger.error({ err }, "Batch execution failed");
    res.status(500).json({ ok: false, message: "Batch execution failed" });
  }
});

app.listen(appConfig.expressPort, appConfig.expressHost, () => {
  logger.info(
    {
      port: appConfig.expressPort,
      host: appConfig.expressHost,
      docs: "https://docs.eigencloud.xyz/eigencompute/get-started/quickstart",
    },
    "EigenCompute batch executor ready"
  );
});

