import pino from "pino";
import { Hex } from "viem";
import { appConfig } from "./config.js";
import { executeStrategy } from "./strategy.js";
import { createAttestationFactory } from "./attestation.js";
import { fetchPythPrice } from "./pyth.js";
import { CofheEncoder } from "./fhenix.js";
import { createApp } from "./server.js";

const logger = pino({ level: process.env.LOG_LEVEL ?? "info" });

const encoder = new CofheEncoder({
  chainId: appConfig.chainId,
  signerPrivateKey: appConfig.cofhe.signerPrivateKey as Hex,
  swapHandler: appConfig.cofhe.swapHandler as Hex,
  securityZone: appConfig.cofhe.securityZone,
});

const attestor = createAttestationFactory({
  mnemonic: appConfig.mnemonic,
  mrEnclave: appConfig.attestation.mrEnclave as Hex,
  mrSigner: appConfig.attestation.mrSigner as Hex,
});

const app = createApp({
  logger,
  fetchPythPrice,
  executeStrategy,
  encryptVolume: (value) => encoder.encryptVolume(value),
  createAttestation: attestor,
  publicMetadata: appConfig.publicMetadata,
});

app.listen(appConfig.expressPort, appConfig.expressHost, () => {
  logger.info(
    {
      port: appConfig.expressPort,
      host: appConfig.expressHost,
      signer: encoder.signer,
    },
    "EigenCompute batch executor ready"
  );
});

