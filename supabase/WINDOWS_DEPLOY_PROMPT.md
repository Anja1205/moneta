# Prompt: deploy Moneta's Supabase backend changes from Windows

Paste everything below the line into Claude Code (or another coding agent) running on the Windows PC.

---

I'm on Windows (PowerShell). Help me deploy three backend changes to my Supabase project `bxyqeamxplugchlfjhxz`. Run the commands for me where you can, and stop and ask me whenever a step needs my input (signing in, passwords, API keys). Never print, log or write my API keys or secrets into any file, and never put them in a command's output.

## Steps, in this order

1. **Supabase CLI.** Check whether `supabase --version` works. If not, install it with Scoop (`scoop bucket add supabase https://github.com/supabase/scoop-bucket.git`, then `scoop install supabase`); if Scoop isn't installed, use `npx supabase` instead of `supabase` for every command below (needs Node.js). Ask me before installing anything.
2. **Project folder.** Create a folder `moneta-backend` in my home directory (or use one I name) and create the three files below in it, with exactly the contents given, at exactly these paths:
   - `supabase\migrations\20261115000000_signals_scoring.sql`
   - `supabase\functions\score-signals\index.ts`
   - `supabase\functions\price-history\index.ts`
   If there is no `supabase\config.toml`, run `supabase init` in that folder first (answer no to any IDE settings prompts), then add the files.
3. **Sign in and link.** Run `supabase login` (it opens a browser; wait for me to finish), then `supabase link --project-ref bxyqeamxplugchlfjhxz`. It may ask for my database password: tell me it's in the Supabase dashboard under Project Settings > Database, and let me type it myself.
4. **Migration.** Run `supabase db push`. It must only apply `20261115000000_signals_scoring.sql`; if it wants to apply or reset anything else, stop and show me what it plans to do before continuing.
5. **Secrets.** Ask me for my Anthropic API key. Generate a random secret for `SCORING_SECRET` (e.g. 32 random hex characters with PowerShell), show it to me once so I can save it, then run `supabase secrets set ANTHROPIC_API_KEY=<my key> SCORING_SECRET=<secret>`.
6. **Deploy.** Run `supabase functions deploy price-history` and `supabase functions deploy score-signals --no-verify-jwt`.
7. **Check price-history.** Call it and confirm it returns a list of points:
   `Invoke-RestMethod -Method Post -Uri "https://bxyqeamxplugchlfjhxz.supabase.co/functions/v1/price-history" -Headers @{ apikey = "sb_publishable_p17AsVNlaAutsJegSAQqGg_7SvxFS0X"; Authorization = "Bearer sb_publishable_p17AsVNlaAutsJegSAQqGg_7SvxFS0X" } -ContentType "application/json" -Body '{"ticker":"NVDA","range":"1M"}'`
8. **Backfill scores.** Call score-signals with `{"limit":200}` and the header `x-moneta-secret: <SCORING_SECRET>`. Repeat until the response says `"found": 0`. Report the `found` / `scored` / `skipped` numbers from each call. If every call skips everything, run `supabase functions logs score-signals` (or check the dashboard logs) and tell me the error.
9. **Webhook (I do this in the dashboard).** Tell me exactly how to add it: Database > Webhooks > Create a new hook, table `signals`, event `INSERT`, type Supabase Edge Functions, function `score-signals`, method POST, plus an HTTP header `x-moneta-secret` with the secret from step 5.

At the end, give me a short summary: what was deployed, what the checks returned, and anything that failed.

## File: supabase\migrations\20261115000000_signals_scoring.sql

```sql
-- Scoring by the score-signals Edge Function.
-- scored_at: when Claude rated the row (null = not scored yet, so the backfill picks it up).
-- relevant:  false when the story isn't really about the company, or isn't in English.
alter table public.signals
  add column if not exists scored_at timestamptz,
  add column if not exists relevant boolean not null default true;

create index if not exists signals_unscored_idx
  on public.signals (detected_at desc)
  where scored_at is null;
```

## File: supabase\functions\score-signals\index.ts

```ts
// score-signals: Claude rates each signal for its stock - impact 1-5, bullish/bearish/neutral,
// a one-sentence "why", and whether the story is relevant at all.
//
// Two ways in (POST, header `x-moneta-secret: <SCORING_SECRET>`):
//   - Database Webhook on `signals` INSERT: body { type: "INSERT", record: {...} } scores that row.
//   - Backfill: body { limit?: number } scores up to `limit` unscored rows (default 50, max 200).
//
// Secrets: ANTHROPIC_API_KEY, SCORING_SECRET. SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are
// provided by Supabase. Needs the 20261115000000_signals_scoring migration (scored_at, relevant).
// Deploy: supabase functions deploy score-signals --no-verify-jwt --project-ref <ref>

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "claude-opus-5-5";
const MAX_PARALLEL = 4;

type SignalRow = {
  id: string;
  ticker: string;
  stock_name: string | null;
  source_kind: string | null;
  source_name: string | null;
  title: string;
  description: string | null;
  url: string | null;
  published_at: string | null;
  detected_at: string;
};

type Score = {
  relevant: boolean;
  impact: 1 | 2 | 3 | 4 | 5;
  direction: "bullish" | "bearish" | "neutral";
  why: string;
};

const SCORE_SCHEMA = {
  type: "object",
  properties: {
    relevant: {
      type: "boolean",
      description: "True only if the story is substantively about this company and written in English.",
    },
    impact: { type: "integer", enum: [1, 2, 3, 4, 5] },
    direction: { type: "string", enum: ["bullish", "bearish", "neutral"] },
    why: { type: "string", description: "One sentence, at most 25 words." },
  },
  required: ["relevant", "impact", "direction", "why"],
  additionalProperties: false,
};

const SYSTEM = `You rate news and web changes for Moneta, an app that warns retail investors about \
things on the web that could move a stock they own, before the market reacts.

For each item you get the company, its ticker, where the item was found, its headline and its \
description. Judge it the way an experienced equity analyst would.

relevant: true only if the item is substantively about this company (its business, products, \
people, finances, legal or regulatory position, or its market) and is written in English. \
Passing mentions, general market roundups, celebrity or lifestyle stories, and items about a \
different company with a similar name are not relevant.

impact (how likely this is to move the stock price):
1 = noise: irrelevant, or no plausible effect on the price
2 = minor: real news about the company, unlikely to move the price
3 = notable: could move the price modestly
4 = significant: likely to move the price
5 = major: likely to move the price sharply (earnings surprise, guidance change, CEO exit, \
merger or acquisition, major lawsuit or regulatory action, large contract, major product or \
pricing change)
When relevant is false, impact is 1 and direction is neutral.

direction: bullish if it is good for the share price, bearish if bad, neutral if unclear or mixed.

why: one plain-English sentence, at most 25 words, saying why it matters for the share price. \
Don't restate the headline, don't hedge, no markdown. If it isn't relevant, say briefly why not.`;

const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const COLUMNS = "id,ticker,stock_name,source_kind,source_name,title,description,url,published_at,detected_at";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/** Asks Claude for a score. Null when the request was declined or the output wasn't usable. */
async function score(row: SignalRow): Promise<Score | null> {
  const item = [
    `Company: ${row.stock_name ?? row.ticker} (${row.ticker})`,
    `Found on: ${row.source_name ?? "unknown"} (${row.source_kind ?? "news"})`,
    row.published_at ? `Published: ${row.published_at}` : null,
    `Headline: ${row.title}`,
    row.description ? `Description: ${row.description}` : null,
    row.url ? `URL: ${row.url}` : null,
  ].filter(Boolean).join("\n");

  const response = await anthropic.beta.messages.create({
    model: MODEL,
    max_tokens: 2000,
    // If a safety classifier declines, the API re-runs the request on its recommended fallback model.
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    output_config: {
      effort: "low",
      format: { type: "json_schema", schema: SCORE_SCHEMA },
    },
    system: SYSTEM,
    messages: [{ role: "user", content: item }],
  });

  if (response.stop_reason === "refusal" || response.stop_reason === "max_tokens") return null;
  const text = response.content.find((block) => block.type === "text");
  if (!text || text.type !== "text") return null;
  try {
    const parsed = JSON.parse(text.text) as Score;
    if (![1, 2, 3, 4, 5].includes(parsed.impact)) return null;
    return parsed;
  } catch {
    return null;
  }
}

/** Scores one row and writes the result. Returns whether it was scored. */
async function scoreAndSave(row: SignalRow): Promise<boolean> {
  let result: Score | null;
  try {
    result = await score(row);
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) {
      console.warn(`rate limited on ${row.id}; left for the next run`);
    } else if (error instanceof Anthropic.APIError) {
      console.error(`Claude API error ${error.status} on ${row.id}: ${error.message}`);
    } else {
      console.error(`scoring ${row.id} failed: ${(error as Error).message}`);
    }
    return false;
  }
  if (!result) {
    // Declined or unusable: mark it scored with neutral defaults so it isn't retried forever.
    await supabase.from("signals").update({ scored_at: new Date().toISOString() }).eq("id", row.id);
    return false;
  }

  const relevant = result.relevant;
  const { error } = await supabase
    .from("signals")
    .update({
      relevant,
      impact: relevant ? result.impact : 1,
      direction: relevant ? result.direction : "neutral",
      why: result.why.trim(),
      scored_at: new Date().toISOString(),
    })
    .eq("id", row.id);
  if (error) {
    console.error(`saving ${row.id} failed: ${error.message}`);
    return false;
  }
  return true;
}

/** Runs `work` over `items`, at most `limit` at a time. */
async function inParallel<T, R>(items: T[], limit: number, work: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const index = next++;
      results[index] = await work(items[index]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  const secret = Deno.env.get("SCORING_SECRET");
  if (!secret || req.headers.get("x-moneta-secret") !== secret) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: { type?: string; record?: { id?: string }; limit?: number } = {};
  try {
    body = await req.json();
  } catch {
    // Empty body: backfill with the default limit.
  }

  let rows: SignalRow[];
  if (body.record?.id) {
    // Database Webhook: score the inserted row.
    const { data, error } = await supabase.from("signals").select(COLUMNS).eq("id", body.record.id).limit(1);
    if (error) return json({ error: error.message }, 500);
    rows = (data ?? []) as SignalRow[];
  } else {
    const limit = Math.min(Math.max(Number(body.limit) || 50, 1), 200);
    const { data, error } = await supabase
      .from("signals")
      .select(COLUMNS)
      .is("scored_at", null)
      .order("detected_at", { ascending: false })
      .limit(limit);
    if (error) return json({ error: error.message }, 500);
    rows = (data ?? []) as SignalRow[];
  }

  const outcomes = await inParallel(rows, MAX_PARALLEL, scoreAndSave);
  const scored = outcomes.filter(Boolean).length;
  return json({ found: rows.length, scored, skipped: rows.length - scored });
});
```

## File: supabase\functions\price-history\index.ts

```ts
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
```
