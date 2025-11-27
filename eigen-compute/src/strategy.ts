import { appConfig } from "./config.js";
import type {
  BatchRequest,
  BatchComputation,
  BatchSettlement,
  Hex,
  BatchOrderInput,
  BatchMetadata,
  InEuint128Struct,
} from "./types.js";

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

function aggregateOrders(orders: BatchOrderInput[]): { token0: bigint; token1: bigint } {
  let token0 = 0n;
  let token1 = 0n;
  for (const order of orders) {
    const amount = BigInt(order.amountSpecified);
    if (order.zeroForOne) {
      token0 += -amount; // amountSpecified is negative exact input
      token1 += amount;
    } else {
      token0 += amount;
      token1 += -amount;
    }
  }
  return { token0, token1 };
}

interface StrategyContext {
  metadata: BatchMetadata;
  encryptVolume: (value: bigint) => Promise<InEuint128Struct>;
}

export async function executeStrategy(
  batch: BatchRequest,
  ctx: StrategyContext
): Promise<BatchComputation> {
  const flow = aggregateOrders(batch.orders);
  const metadata = ctx.metadata;
  const oraclePrice = metadata.oraclePrice;
  const params = batch.strategyParams ?? {};
  const baseSpread = params.baseSpreadBps ?? appConfig.strategySpreadBps;
  const inventorySkew = params.inventorySkewBps ?? 0;
  const spreadBps = clamp(baseSpread + inventorySkew, 0, 10_000);

  const token0Flow = flow.token0;
  const token1Flow = flow.token1;

  const grossPrice = oraclePrice * (1 + spreadBps / 10_000);
  const sqrtPriceX96 = priceToSqrtPriceX96(grossPrice);

  const settlement: BatchSettlement = {
    poolId: batch.poolId,
    batchId: batch.batchId,
    sqrtPriceX96,
    token0Flow: token0Flow.toString(),
    token1Flow: token1Flow.toString(),
    deadline: metadata.timestamp + 300,
  };

  const encryptedVolumes = {
    token0: await ctx.encryptVolume(token0Flow < 0n ? -token0Flow : token0Flow),
    token1: await ctx.encryptVolume(token1Flow < 0n ? -token1Flow : token1Flow),
  };

  return {
    settlement,
    encryptedVolumes,
    netFlow: {
      token0: token0Flow,
      token1: token1Flow,
    },
  };
}

