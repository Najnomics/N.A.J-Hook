export type Hex = `0x${string}`;

export interface BatchMetadata {
  oraclePrice: number;
  timestamp: number;
  pythConfidenceBps?: number;
}

export interface BatchOrderInput {
  sender: Hex;
  zeroForOne: boolean;
  amountSpecified: string;
  tokenIn: Hex;
  tokenOut: Hex;
}

export interface BatchRequest {
  poolId: Hex;
  batchId: Hex;
  strategyParams?: {
    baseSpreadBps?: number;
    inventorySkewBps?: number;
  };
  metadata: BatchMetadata;
  orders: BatchOrderInput[];
}

export interface BatchSettlement {
  poolId: Hex;
  batchId: Hex;
  sqrtPriceX96: Hex;
  token0Flow: string;
  token1Flow: string;
  deadline: number;
}

export interface InEuint128Struct {
  ctHash: Hex;
  securityZone: number;
  utype: number;
  signature: Hex;
}

export interface BatchComputation {
  settlement: BatchSettlement;
  encryptedVolumes: {
    token0: InEuint128Struct;
    token1: InEuint128Struct;
  };
  netFlow: {
    token0: bigint;
    token1: bigint;
  };
}

