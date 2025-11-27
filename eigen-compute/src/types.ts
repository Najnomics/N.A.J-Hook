export type Hex = `0x${string}`;

export interface BatchMetadata {
  oraclePrice: number;
  timestamp: number;
  pythConfidenceBps?: number;
}

export interface BatchRequest {
  poolId: Hex;
  batchId: Hex;
  encryptedToken0Volume: string;
  encryptedToken1Volume: string;
  strategyParams?: {
    baseSpreadBps?: number;
    inventorySkewBps?: number;
  };
  metadata: BatchMetadata;
}

export interface BatchSettlement {
  poolId: Hex;
  batchId: Hex;
  sqrtPriceX96: Hex;
  token0Flow: string;
  token1Flow: string;
  deadline: number;
}

export interface BatchComputation {
  settlement: BatchSettlement;
  sealedVolumes: {
    token0: Hex;
    token1: Hex;
  };
  netFlow: {
    token0: bigint;
    token1: bigint;
  };
}

