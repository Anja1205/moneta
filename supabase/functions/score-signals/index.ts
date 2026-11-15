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
