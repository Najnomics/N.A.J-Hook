import { appConfig } from "./config.js";
import { decryptVolume, sealVolume } from "./fhenix.js";
import type { BatchRequest, BatchComputation, BatchSettlement, Hex } from "./types.js";

const Q96 = 2 ** 96;

function priceToSqrtPriceX96(price: number): Hex {
  const sqrtPrice = Math.sqrt(price);
  const scaled = BigInt(Math.floor(sqrtPrice * 1e9));
  const multiplier = BigInt(Math.floor(Q96 / 1e9));
  const value = scaled * multiplier;
  return `0x${value.toString(16)}` as Hex;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export function executeStrategy(batch: BatchRequest): BatchComputation {
  const volume0 = decryptVolume(batch.encryptedToken0Volume, appConfig.fhenixSecret);
  const volume1 = decryptVolume(batch.encryptedToken1Volume, appConfig.fhenixSecret);

  const oraclePrice = batch.metadata.oraclePrice;
  const params = batch.strategyParams ?? {};
  const baseSpread = params.baseSpreadBps ?? appConfig.strategySpreadBps;
  const inventorySkew = params.inventorySkewBps ?? 0;
  const spreadBps = clamp(baseSpread + inventorySkew, 0, 10_000);

  const token0Flow = volume0 - volume1;
  const token1Flow = -token0Flow;

  const grossPrice = oraclePrice * (1 + spreadBps / 10_000);
  const sqrtPriceX96 = priceToSqrtPriceX96(grossPrice);

  const settlement: BatchSettlement = {
    poolId: batch.poolId,
    batchId: batch.batchId,
    sqrtPriceX96,
    token0Flow: token0Flow.toString(),
    token1Flow: token1Flow.toString(),
    deadline: batch.metadata.timestamp + 300,
  };

  return {
    settlement,
    sealedVolumes: {
      token0: sealVolume(volume0, appConfig.fhenixSecret),
      token1: sealVolume(volume1, appConfig.fhenixSecret),
    },
    netFlow: {
      token0: token0Flow,
      token1: token1Flow,
    },
  };
}

