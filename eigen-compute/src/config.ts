import { config as loadEnv } from "dotenv";
import { z } from "zod";

loadEnv();

const address = z
  .string()
  .regex(/^0x[0-9a-fA-F]{40}$/, "Expected EVM address");

const hexString = z
  .string()
  .regex(/^0x[0-9a-fA-F]+$/, "Expected hex string prefixed with 0x");

const hex32 = z
  .string()
  .regex(/^0x[0-9a-fA-F]{64}$/, "Expected 32-byte hex value");

const EnvSchema = z.object({
  MNEMONIC: z.string().min(1, "MNEMONIC required"),
  FHENIX_SHARED_SECRET: z.string().min(1, "FHENIX_SHARED_SECRET required"),
  SEQUENCER_WEBHOOK: z.string().url().optional(),
  STRATEGY_SPREAD_BPS: z.coerce.number().min(0).max(10_000).default(35),
  BATCH_INTERVAL_MS: z.coerce.number().int().positive().default(5000),
  EXPRESS_PORT: z.coerce.number().int().positive().default(8080),
  EXPRESS_HOST: z.string().default("0.0.0.0"),
  CHAIN_RPC_URL_PUBLIC: z.string().url().optional(),
  NAJ_LAUNCHPAD_ADDRESS_PUBLIC: hexString.optional(),
  NAJ_HOOK_ADDRESS_PUBLIC: hexString.optional(),
  PYTH_HERMES_URL: z.string().url(),
  PYTH_FEED_ID: hex32,
  COFHE_SIGNER_PRIVATE_KEY: z
    .string()
    .regex(/^0x[0-9a-fA-F]{64}$/, "Expected 32-byte hex private key"),
  SWAP_HANDLER_ADDRESS: address,
  COFHE_SECURITY_ZONE: z.coerce.number().int().min(-128).max(127).default(0),
  CHAIN_ID: z.coerce.bigint().default(11155111n),
  MR_ENCLAVE_PUBLIC: hex32,
  MR_SIGNER_PUBLIC: hex32,
});

const parsed = EnvSchema.safeParse(process.env);

if (!parsed.success) {
  console.error(parsed.error.flatten().fieldErrors);
  throw new Error("Invalid eigen-compute environment");
}

export const appConfig = {
  mnemonic: parsed.data.MNEMONIC,
  fhenixSecret: parsed.data.FHENIX_SHARED_SECRET,
  sequencerWebhook: parsed.data.SEQUENCER_WEBHOOK ?? null,
  strategySpreadBps: parsed.data.STRATEGY_SPREAD_BPS,
  batchIntervalMs: parsed.data.BATCH_INTERVAL_MS,
  expressPort: parsed.data.EXPRESS_PORT,
  expressHost: parsed.data.EXPRESS_HOST,
  pyth: {
    hermesUrl: parsed.data.PYTH_HERMES_URL,
    feedId: parsed.data.PYTH_FEED_ID,
  },
  cofhe: {
    signerPrivateKey: parsed.data.COFHE_SIGNER_PRIVATE_KEY,
    securityZone: parsed.data.COFHE_SECURITY_ZONE,
    swapHandler: parsed.data.SWAP_HANDLER_ADDRESS,
  },
  chainId: parsed.data.CHAIN_ID,
  attestation: {
    mrEnclave: parsed.data.MR_ENCLAVE_PUBLIC,
    mrSigner: parsed.data.MR_SIGNER_PUBLIC,
  },
  publicMetadata: {
    chainRpcUrl: parsed.data.CHAIN_RPC_URL_PUBLIC ?? null,
    launchpadAddress: parsed.data.NAJ_LAUNCHPAD_ADDRESS_PUBLIC ?? null,
    hookAddress: parsed.data.NAJ_HOOK_ADDRESS_PUBLIC ?? null,
  },
} as const;

