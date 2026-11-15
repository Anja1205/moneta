# Moneta

Moneta watches the live web around the stocks you own — news, investor pages, careers and pricing pages — and warns you before the market moves. An AI agent scores every change it finds for impact (1–5) and direction (bullish, bearish or neutral) and explains in one sentence why it matters.

*Named for Juno Moneta, from Latin* monere, *"to warn".*

## Features

- **Sign in and onboarding**: email and password accounts (Supabase Auth), then pick stocks from the Top 20 or search any company.
- **Home**: your portfolio value and gain, each watched stock's price, intraday chart, web sentiment and latest important signal.
- **Markets**: the Top 30 companies with live prices; watch any of them in one tap.
- **Signals feed**: every signal for your stocks, filtered by Important/All and Bullish/Bearish, with impact and direction at a glance.
- **Stock detail**: price chart (1D to 1Y) with signal markers, your position, web sentiment and the signal timeline.
- **Alerts**: notifications and a Live Activity (Lock Screen and Dynamic Island) for new signals with impact 4 or 5, batched so a burst arrives as one.
- **Live updates**: prices, signals, your watchlist and the Top 30 update in real time over Supabase Realtime.
- **Demo mode**: fictional companies on a simulated market, switchable in Settings, for trying the app without the backend.

## Requirements

- Xcode 27 or later (the project uses the JSON `project.xcproj` format)
- iOS 26 or later (Liquid Glass UI)
- The Supabase project the app is configured for (see [Backend](#backend))

## Getting started

1. Open `moneta.xcodeproj` in Xcode. Swift Package Manager resolves [supabase-swift](https://github.com/supabase/supabase-swift) (2.55 or later) on first open.
2. Select the `moneta` scheme and an iPhone simulator or device.
3. Build and run. Create an account in the app, pick a few stocks, and you're in.

The Supabase URL and the publishable key are in `moneta/Services/BackendConfig.swift`. The publishable key is meant for clients and only reaches what row-level security allows. Never put a secret or service-role key in the app.

## Project layout

```
moneta/                 iOS app (target "moneta")
  Views/                Screens: Auth, Onboarding, Home, Markets, Signals, Stock detail, Settings, Search
  Components/           Reusable views: cards, tiles, ImpactMeter, charts, logos, banners
  DesignSystem/         Colours, type scale, Brand tokens, formatters, Quicksand font
  Models/               App models, Supabase row models, MarketStore (the single source of truth)
  Services/             Supabase client, AuthService, LiveAccount (watchlist, Realtime), price and
                        signal services (backend and mock), AlertService (notifications, Live Activity)
MonetaWidget/           Widget extension: the Live Activity for Lock Screen and Dynamic Island
Shared/                 Code shared by the app and the widget (Live Activity attributes)
supabase/               Backend sources: Edge Functions, migrations, Windows deploy prompt
Legacy/                 Earlier version of the app, kept for reference; not compiled
```

## Architecture

- **`MarketStore`** (`@Observable`) holds the watchlist with positions, quotes, intraday prices, signals, sentiment and the Top 30. Views read only from it.
- Prices and signals come through three protocols (`PriceService`, `WebMonitorService`, `SignalAgent`) with a backend and a mock implementation; `DataSource` picks which.
- With the backend, **`LiveAccount`** adds the user's watchlist rows, positions, sentiment, the Top 30 and one Realtime channel (`moneta-live`).
- **`AuthService`** routes between splash, sign in, onboarding and the main app, and the store is created only once the user is onboarded.

## Backend

The backend is a Supabase project with row-level security on every table.

| Table | Used for |
| --- | --- |
| `profiles` | Display name and whether onboarding is done |
| `companies` | Top 20 (onboarding) and Top 30 (Markets) with logos and prices |
| `stocks` | Tracked companies and their latest prices |
| `watchlist` | Each user's stocks and positions (shares, average cost) |
| `signals` | Web changes with AI impact, direction and "why" |
| `price_history` | Captured prices for charts |
| `stock_sentiment` (view) | 0–100 sentiment per stock |

Edge Functions the app calls: `add-stock`, `search-companies`, `poll-news`, `refresh-prices` and `price-history`. `score-signals` runs on the backend only (a database webhook on new signals).

The sources for `price-history`, `score-signals` and the scoring migration are in `supabase/`. To deploy them with the [Supabase CLI](https://supabase.com/docs/guides/cli):

```bash
supabase link --project-ref <project-ref>
supabase db push
supabase secrets set ANTHROPIC_API_KEY=... SCORING_SECRET=...
supabase functions deploy price-history
supabase functions deploy score-signals --no-verify-jwt
```

Then add a database webhook on `signals` INSERT that calls `score-signals` with the header `x-moneta-secret: <SCORING_SECRET>`. On Windows, `supabase/WINDOWS_DEPLOY_PROMPT.md` walks a coding agent through the same steps.

## Debug launch arguments

Debug builds accept launch arguments for checking screens without tapping (none of these exist in release builds):

| Argument | Effect |
| --- | --- |
| `-MonetaOpen <route>` | Opens a screen on launch: `splash`, `auth`, `authCreate`, `markets`, `signals`, `settings`, `search`, `stock`, `signal`, `add` |
| `-MonetaPosition TICKER:shares:avgCost` | Sets a position (`TICKER:clear` removes it) |
| `-dataSource demo` | Runs on demo data for that launch |
