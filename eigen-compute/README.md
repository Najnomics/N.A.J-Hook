# EigenCompute Batch Executor (N.A.J Hook)

Deterministic EigenCompute application that ingests encrypted Fhenix batches, evaluates Naj strategy logic inside a TDX enclave, and emits attestations for `NajHook`. All instructions in this folder follow the EigenCloud docs (`CONTEXT/eigencloud-docs/docs/eigencompute/...`) so the service can be deployed with the EigenX CLI.

## 1. Prerequisites

- EigenX CLI installed per [Quickstart](../CONTEXT/eigencloud-docs/docs/eigencompute/get-started/quickstart.md).
- Docker desktop (or server) logged in (TEE builds target `linux/amd64` and run as root as required by EigenCompute).
- `pnpm` or `npm` for local development (repo uses pnpm, but EigenX deploys through Docker, so any Node package manager works).
- Access to a Sepolia/Mainnet RPC (public endpoint recorded in `_PUBLIC` env vars).

## 2. Project Layout

```
eigen-compute/
├── Dockerfile                # Matches Eigen docs: linux/amd64 + root + EXPOSE 8080
├── env.example               # Copy to .env before local dev (Eigen will auto-seal vars)
├── package.json / tsconfig   # TypeScript Express service
└── src/
    ├── attestation.ts        # Deterministic HMAC attestation (swap out with Eigen key)
    ├── config.ts             # Zod-validated env loader
    ├── fhenix.ts             # Helper mirroring fhe-hook-template encryption flow
    ├── strategy.ts           # Pricing + sealed volume computation
    ├── types.ts              # Batch request/response contracts
    └── index.ts              # Express HTTP entrypoint (GET /, POST /batch)
```

## 3. Environment Variables

EigenCompute exposes container env vars; `_PUBLIC` suffix indicates values that can be revealed to users (per docs). Copy the template:

```bash
cp env.example .env
```

Key vars:

| Variable | Description |
| --- | --- |
| `MNEMONIC` | Auto-generated Eigen app wallet (in production the enclave injects this). |
| `FHENIX_SHARED_SECRET` | Symmetric key that mirrors the Fhenix hook template for decrypting `InEuint128`. |
| `CHAIN_RPC_URL_PUBLIC` | Public RPC endpoint disclosed for transparency (suffix `_PUBLIC`). |
| `NAJ_LAUNCHPAD_ADDRESS_PUBLIC` | Launchpad address this enclave services (public). |
| `SEQUENCER_WEBHOOK` | Optional callback URL back to the Naj sequencer. |
| `STRATEGY_SPREAD_BPS` | Default spread used by the template strategy. |
| `BATCH_INTERVAL_MS` | How often the enclave polls for new work (if you wire a scheduler). |

## 4. Local Development

```bash
cd eigen-compute
pnpm install           # or npm install
cp env.example .env
pnpm dev               # runs tsx src/index.ts
```

Test the batch endpoint:

```bash
curl -X POST http://localhost:8080/batch \
  -H "Content-Type: application/json" \
  -d '{
        "poolId": "0xabc...123",
        "batchId": "0x01",
        "metadata": { "oraclePrice": 2000, "timestamp": 1730000000 },
        "encryptedToken0Volume": "0xdeadbeef",
        "encryptedToken1Volume": "0xfeedface",
        "strategyParams": { "baseSpreadBps": 25 }
      }'
```

Response:

```json
{
  "ok": true,
  "settlement": {
    "poolId": "0xabc...123",
    "batchId": "0x01",
    "sqrtPriceX96": "0x1234...",
    "token0Flow": "1234500000000000000",
    "token1Flow": "-987000000",
    "deadline": 1730000300
  },
  "sealedVolumes": {
    "token0": "0xfd...01",
    "token1": "0xaa...ff"
  },
  "attestation": "0x8af7..."
}
```

## 5. Build & Deploy via EigenX

1. **Generate the project in EigenX (optional)**  
   ```bash
   eigenx app create naj-compute typescript
   # replace the generated src/ + Dockerfile with this folder's contents
   ```

2. **Configure environment**  
   ```bash
   eigenx env set sepolia           # or mainnet
   eigenx auth login                # or eigenx auth generate --store
   eigenx billing subscribe         # once per account (see docs/billing.md)
   ```

3. **Deploy**  
   ```bash
   pnpm build
   eigenx app deploy
   eigenx app info
   eigenx app logs
   ```

   The CLI follows the sequence from the docs: build → push → launch TEE → report app ID.

## 6. Integration Notes

- The Naj sequencer posts encrypted volumes to `POST /batch`. The payload matches the structure expected by `NajHook`’s `submitBatchAttestation`.
- Attestations are generated deterministically via `attestation.ts`. Replace this with Eigen’s TEE key material once you wire the Eigen attestation reference implementation in `docs/eigencompute/howto/verify/verify-tee-signature.md`.
- The Fhenix helper mimics the [`fhe-hook-template`](../CONTEXT/fhe-hook-template) so encrypted `InEuint128` values can be decrypted using the same shared secret for local smoke tests. Swap this logic for the actual CoFHE SDK when you have enclave bindings.
- Keep `_PUBLIC` env vars in sync with on-chain configuration so verifiers can audit the app, per EigenCloud guidance.

## 7. Further Reading

- EigenCloud Docs  
  - Quickstart: `docs/eigencompute/get-started/quickstart.md`  
  - Application environment: `docs/eigencompute/howto/build/application-environment.md`  
  - Template creation: `docs/eigencompute/howto/build/create-app-from-template.md`
- Fhenix Hook Template: `CONTEXT/fhe-hook-template`
- Naj Sequencer design: `sequencer/AGENTS.md`

This folder is the single source of truth for the EigenCompute deployment. Update it together with the sequencer whenever the batch schema changes so we remain compliant with Eigen’s attestation and environment requirements.

