import { HermesClient } from "@pythnetwork/hermes-client";
import { appConfig } from "./config.js";
import type { PythPriceData } from "./types.js";

const client = new HermesClient(appConfig.pyth.hermesUrl, {});

export async function fetchPythPrice(): Promise<PythPriceData> {
  const latest = await client.getLatestPriceUpdates([appConfig.pyth.feedId]);

  if (!latest?.parsed || latest.parsed.length === 0) {
    throw new Error("No Pyth price data available");
  }

  type ParsedPrice = {
    price?: string;
    conf?: string;
    expo?: number;
    publishTime?: number;
  };

  const parsed = latest.parsed[0];
  const priceInfo: ParsedPrice = parsed.price ?? {};
  const expo = priceInfo.expo ?? 0;
  const base = Math.pow(10, expo);

  const price =
    Number(priceInfo.price ?? "0") * base;
  const confidence =
    Number(priceInfo.conf ?? "0") * base;

  const priceUpdateData =
    latest.binary && Array.isArray(latest.binary.data)
      ? latest.binary.data.map((hex: string) =>
          hex.startsWith("0x") ? hex : `0x${hex}`
        )
      : undefined;

  const timestamp = priceInfo.publishTime ?? Math.floor(Date.now() / 1000);

  return {
    price,
    confidence,
    timestamp,
    priceUpdateData,
  };
}

