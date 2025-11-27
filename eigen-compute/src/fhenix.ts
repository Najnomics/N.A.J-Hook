import { JsonRpcProvider, Wallet } from "ethers";
import { cofhejs, Encryptable } from "cofhejs/node";
import type { CoFheInUint128, Result } from "cofhejs/node";
import type { Hex, InEuint128Struct } from "./types.js";

export type CofheEnvironment = "MOCK" | "LOCAL" | "TESTNET" | "MAINNET";

export interface CofheClientConfig {
  rpcUrl: string;
  chainId: bigint;
  signerPrivateKey: Hex;
  swapHandler: Hex;
  securityZone: number;
  environment?: CofheEnvironment;
  coFheUrl?: string;
  verifierUrl?: string;
  thresholdNetworkUrl?: string;
}

function toHex(value: bigint): Hex {
  return `0x${value.toString(16).padStart(64, "0")}` as Hex;
}

function unwrapResult<T>(result: Result<T>, action: string): T {
  if (!result.success) {
    const message = result.error?.message ?? `cofhejs ${action} failed`;
    throw new Error(message);
  }
  return result.data;
}

export class CofheClient {
  private readonly provider: JsonRpcProvider;
  private readonly signer: Wallet;
  private readonly securityZone: number;
  private initialized = false;

  constructor(private readonly config: CofheClientConfig) {
    this.provider = new JsonRpcProvider(config.rpcUrl, Number(config.chainId));
    this.signer = new Wallet(config.signerPrivateKey, this.provider);
    this.securityZone = config.securityZone;
  }

  async init() {
    const initResult = await cofhejs.initializeWithEthers({
      ethersProvider: this.provider,
      ethersSigner: this.signer,
      environment: this.config.environment,
      coFheUrl: this.config.coFheUrl,
      verifierUrl: this.config.verifierUrl,
      thresholdNetworkUrl: this.config.thresholdNetworkUrl,
      generatePermit: false,
    });

    unwrapResult(initResult, "initialize");
    this.initialized = true;
  }

  private ensureInitialized() {
    if (!this.initialized) {
      throw new Error("CoFHE client is not initialized");
    }
  }

  async encryptVolume(value: bigint): Promise<InEuint128Struct> {
    this.ensureInitialized();

    const magnitude = value < 0n ? -value : value;
    const encryptResult = await cofhejs.encrypt([
      Encryptable.uint128(magnitude, this.securityZone),
    ]);

    const [encrypted] = unwrapResult(encryptResult, "encrypt");
    return this.toInEuint128(encrypted);
  }

  private toInEuint128(input: CoFheInUint128): InEuint128Struct {
    return {
      ctHash: toHex(input.ctHash),
      securityZone: input.securityZone,
      utype: input.utype,
      signature: input.signature as Hex,
    };
  }
}
