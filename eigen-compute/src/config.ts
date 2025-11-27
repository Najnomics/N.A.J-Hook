import { config as loadEnv } from "dotenv";
import { z } from "zod";

loadEnv();

const hexString = z
  .string()
  .regex(/^0x[0-9a-fA-F]+$/, "Expected hex string prefixed with 0x");

const EnvSchema = z.object({
  MNEMONIC: z.string().optional(),
  FHENIX_SHARED_SECRET: z.string().min(1, "FHENIX_SHARED_SECRET required"),
  SEQUENCER_WEBHOOK: z.string().url().optional(),
  STRATEGY_SPREAD_BPS: z.coerce.number().min(0).max(10_000).default(35),
  BATCH_INTERVAL_MS: z.coerce.number().int().positive().default(5000),
  EXPRESS_PORT: z.coerce.number().int().positive().default(8080),
  EXPRESS_HOST: z.string().default("0.0.0.0"),
  CHAIN_RPC_URL_PUBLIC: z.string().url().optional(),
  NAJ_LAUNCHPAD_ADDRESS_PUBLIC: hexString.optional(),
  NAJ_HOOK_ADDRESS_PUBLIC: hexString.optional(),
});

const parsed = EnvSchema.safeParse(process.env);

if (!parsed.success) {
  console.error(parsed.error.flatten().fieldErrors);
  throw new Error("Invalid eigen-compute environment");
}

export const appConfig = {
  mnemonic: parsed.data.MNEMONIC ?? null,
  fhenixSecret: parsed.data.FHENIX_SHARED_SECRET,
  sequencerWebhook: parsed.data.SEQUENCER_WEBHOOK ?? null,
  strategySpreadBps: parsed.data.STRATEGY_SPREAD_BPS,
  batchIntervalMs: parsed.data.BATCH_INTERVAL_MS,
  expressPort: parsed.data.EXPRESS_PORT,
  expressHost: parsed.data.EXPRESS_HOST,
  publicMetadata: {
    chainRpcUrl: parsed.data.CHAIN_RPC_URL_PUBLIC ?? null,
    launchpadAddress: parsed.data.NAJ_LAUNCHPAD_ADDRESS_PUBLIC ?? null,
    hookAddress: parsed.data.NAJ_HOOK_ADDRESS_PUBLIC ?? null,
  },
} as const;

