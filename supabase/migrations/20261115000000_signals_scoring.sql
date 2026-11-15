-- Scoring by the score-signals Edge Function.
-- scored_at: when Claude rated the row (null = not scored yet, so the backfill picks it up).
-- relevant:  false when the story isn't really about the company, or isn't in English.
alter table public.signals
  add column if not exists scored_at timestamptz,
  add column if not exists relevant boolean not null default true;

create index if not exists signals_unscored_idx
  on public.signals (detected_at desc)
  where scored_at is null;
