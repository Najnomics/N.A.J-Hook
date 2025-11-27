import pino from "pino";
import { Hex } from "viem";
import { appConfig } from "./config.js";
import { executeStrategy } from "./strategy.js";
import { createAttestationFactory } from "./attestation.js";
import { fetchPythPrice } from "./pyth.js";
import { CofheClient } from "./fhenix.js";
import { createApp } from "./server.js";

const logger = pino({ level: process.env.LOG_LEVEL ?? "info" });

async function bootstrap() {
  const cofheClient = new CofheClient({
    rpcUrl: appConfig.cofhe.rpcUrl,
    chainId: appConfig.chainId,
    signerPrivateKey: appConfig.cofhe.signerPrivateKey as Hex,
    swapHandler: appConfig.cofhe.swapHandler as Hex,
    securityZone: appConfig.cofhe.securityZone,
    environment: appConfig.cofhe.environment,
    coFheUrl: appConfig.cofhe.coFheUrl ?? undefined,
    verifierUrl: appConfig.cofhe.verifierUrl ?? undefined,
    thresholdNetworkUrl: appConfig.cofhe.thresholdNetworkUrl ?? undefined,
  });

  await cofheClient.init();

  const attestor = createAttestationFactory({
    mnemonic: appConfig.mnemonic,
    mrEnclave: appConfig.attestation.mrEnclave as Hex,
    mrSigner: appConfig.attestation.mrSigner as Hex,
  });

  const app = createApp({
    logger,
    fetchPythPrice,
    executeStrategy,
    encryptVolume: (value) => cofheClient.encryptVolume(value),
    createAttestation: attestor,
    publicMetadata: appConfig.publicMetadata,
  });

  app.listen(appConfig.expressPort, appConfig.expressHost, () => {
    logger.info(
      {
        port: appConfig.expressPort,
        host: appConfig.expressHost,
        signer: appConfig.cofhe.swapHandler,
      },
      "EigenCompute batch executor ready"
    );
  });
}

bootstrap().catch((error) => {
  logger.error({ error }, "Failed to start EigenCompute server");
  process.exitCode = 1;
});

