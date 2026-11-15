// price-history: closing prices for one ticker over a chart range.
//
// POST { ticker: "NVDA", range: "1D" | "1W" | "1M" | "3M" | "1Y" }
// 200  { ticker, range, currency, points: [{ t: ISO-8601, p: number }] }  (oldest first)
//
// Upstream: Yahoo Finance's public chart endpoint (no key). It's unofficial, so it's kept in one
// function (fetchCandles) that can be swapped for a keyed provider without an app release.
// Deploy: supabase functions deploy price-history

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type Range = "1D" | "1W" | "1M" | "3M" | "1Y";

const RANGES: Record<Range, { range: string; interval: string; ttl: number }> = {
  "1D": { range: "1d", interval: "5m", ttl: 60 },
  "1W": { range: "5d", interval: "30m", ttl: 300 },
  "1M": { range: "1mo", interval: "1d", ttl: 1800 },
  "3M": { range: "3mo", interval: "1d", ttl: 3600 },
  "1Y": { range: "1y", interval: "1d", ttl: 3600 },
};

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json", ...headers },
  });
}

type Point = { t: string; p: number };

async function fetchCandles(ticker: string, range: Range): Promise<{ currency: string; points: Point[] } | null> {
  const cfg = RANGES[range];
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}` +
    `?range=${cfg.range}&interval=${cfg.interval}&includePrePost=false`;
  const res = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0 (compatible; MonetaBackend/1.0)" } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`upstream ${res.status}`);

  const body = await res.json();
  const result = body?.chart?.result?.[0];
  if (!result) return null;

  const timestamps: number[] = result.timestamp ?? [];
  const closes: (number | null)[] = result.indicators?.quote?.[0]?.close ?? [];
  const points: Point[] = [];
  timestamps.forEach((ts, i) => {
    const price = closes[i];
    if (typeof price === "number" && Number.isFinite(price)) {
      points.push({ t: new Date(ts * 1000).toISOString(), p: Math.round(price * 10_000) / 10_000 });
    }
  });
  return { currency: (result.meta?.currency ?? "USD").toUpperCase(), points };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  let ticker: string;
  let range: Range;
  try {
    const body = await req.json();
    ticker = String(body?.ticker ?? "").trim().toUpperCase();
    range = String(body?.range ?? "1M").toUpperCase() as Range;
  } catch {
    return json({ error: "Body must be JSON: { ticker, range }" }, 400);
  }
  if (!/^[A-Z0-9.\-^=]{1,15}$/.test(ticker)) return json({ error: "Invalid ticker" }, 400);
  if (!(range in RANGES)) return json({ error: "range must be one of 1D, 1W, 1M, 3M, 1Y" }, 400);

  try {
    const candles = await fetchCandles(ticker, range);
    if (!candles) return json({ error: `No price history for ${ticker}` }, 404);
    return json(
      { ticker, range, currency: candles.currency, points: candles.points },
      200,
      { "Cache-Control": `public, max-age=${RANGES[range].ttl}` },
    );
  } catch (error) {
    return json({ error: `Couldn't load price history: ${(error as Error).message}` }, 502);
  }
});
