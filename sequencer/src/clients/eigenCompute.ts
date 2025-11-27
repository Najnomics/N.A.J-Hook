import { keccak256, encodePacked } from "viem";
import { config } from "../config/index.js";
import { logger } from "../logger.js";
import type { PoolId, SwapOrder, EigenBatchResponse } from "../types.js";

export interface EigenComputePayload {
  poolId: PoolId;
  batchId: `0x${string}`;
  orders: Array<{
    sender: string;
    zeroForOne: boolean;
    amountSpecified: string;
    tokenIn: string;
    tokenOut: string;
  }>;
}

export function generateBatchId(poolId: PoolId): `0x${string}` {
  const now = BigInt(Math.floor(Date.now() / 1000));
  return keccak256(encodePacked(["bytes32", "uint256"], [poolId, now]));
}

export async function requestEigenComputation(input: {
  poolId: PoolId;
  batchId: `0x${string}`;
  orders: SwapOrder[];
}): Promise<EigenBatchResponse> {
  const payload = {
    poolId: input.poolId,
    batchId: input.batchId,
    metadata: {
      oraclePrice: config.defaultOraclePrice,
      timestamp: Math.floor(Date.now() / 1000),
    },
    orders: input.orders.map((order) => ({
      sender: order.sender,
      zeroForOne: order.zeroForOne,
      amountSpecified: order.amountSpecified.toString(),
      tokenIn: order.tokenIn,
      tokenOut: order.tokenOut,
    })),
  };

  const response = await fetch(new URL("/batch", config.eigenComputeUrl), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(config.eigenComputeApiKey ? { Authorization: `Bearer ${config.eigenComputeApiKey}` } : {}),
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    logger.error(
      { status: response.status, statusText: response.statusText, body: text },
      "EigenCompute request failed"
    );
    throw new Error(`EigenCompute request failed (${response.status})`);
  }

  const result = (await response.json()) as { ok: boolean } & EigenBatchResponse;
  if (!result.ok) {
    logger.error({ result }, "EigenCompute response flagged error");
    throw new Error("EigenCompute returned error");
  }
  return result as EigenBatchResponse;
}

