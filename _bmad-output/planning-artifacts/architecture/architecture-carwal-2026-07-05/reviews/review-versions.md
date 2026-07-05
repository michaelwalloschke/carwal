# Review: Stack Versions & Technology Reality-Check

- **Target:** `ARCHITECTURE-SPINE.md` (architecture-carwal-2026-07-05)
- **Lens:** every committed stack decision web-verified against hex.pm / official sources, 2026-07-05
- **Verdict:** PASS WITH CORRECTIONS — the stack is real and fits, but the `ical` pin is a major version behind and Postgres 16 is two majors behind current.

## Verified line by line

| Spine claim | Reality (verified 2026-07-05) | Status |
| --- | --- | --- |
| Elixir 1.20.x / OTP 27+ | Elixir 1.20 released 2026-06-03; requires OTP 27+, compatible through OTP 29 (latest build 1.20.2-otp-29). | OK |
| Phoenix 1.8.8 | Latest Phoenix release, 2026-06-10. | OK — current |
| `mix phx.new` defaults: Bandit, esbuild, Tailwind 4 + daisyUI 5 | Phoenix 1.8 blog/changelog confirm daisyUI shipped with tailwind in generated apps (light/dark themes + toggle); Bandit is the default adapter since 1.8. | OK |
| Phoenix 1.8 scopes | Confirmed: `phx.gen.auth` creates `%Accounts.Scope{}`; `phx.gen.live/html/json` thread scope through context functions. | OK |
| Magic-link auth | Confirmed: `phx.gen.auth` defaults to magic-link login/registration; password auth is opt-in. | OK |
| Phoenix LiveView 1.2.x | Latest 1.2.5, 2026-06-30. | OK |
| Oban (OSS) 2.23.x, Cron plugin | Latest 2.23.0, 2026-05-27; `Oban.Plugins.Cron` is part of the OSS package. | OK |
| PostgreSQL 16.x | Exists, supported (16.14 current patch, EOL Nov 2028) — but PG 18.4 is the current stable and 19 is in beta. | STALE (Finding 2) |
| `ical` ~1.1 (ICS parsing + recurrence) | Package exists: "iCalendar parsing, serialization, and recurrence generation" — fits ICS + RRULE expansion. But latest is **2.0.2** (2026-05-28); `~> 1.1` pins a superseded major. | STALE PIN (Finding 1) |
| `yugo` 1.0.x (IMAP) | Exists, 1.0.4 (2026-04-15), "easy and high-level IMAP client" — fits mailbox ingestion. Hosted on Codeberg. | OK |
| `ex_nudge` 1.0.x (Web Push / VAPID) | Exists, 1.0.2 (2025-07-28), "Web Push notifications in compliance with RFC 8291", VAPID + payload encryption. ~99k downloads. | OK |
| `mistral` 0.5.x (Req-based) | Exists, 0.5.0 (2026-02-13), by rodloboz; mix.exs confirms `req ~> 0.5` runtime dep; supports chat completions, streaming, tool use. | OK |
| Caddy / Docker Compose "current" | Unpinned by design; no version claim to verify. | OK |

## Findings

### F1 — `ical` pinned to a superseded major (Severity: Medium)

Spine says `~1.1`; the package's latest is **2.0.2** (released 2026-05-28), part of a rapid 1.0→2.0 evolution since the package first appeared in Feb 2026. A greenfield project starting now should target `~> 2.0` — pinning 1.1 adopts a major the author has already moved past, and the 2.x line is where recurrence fixes will land. Action: change the Stack row to `ical ~> 2.0`.

### F2 — PostgreSQL 16 is two majors behind for a greenfield (Severity: Low-Medium)

PG 18.4 is current stable (18 GA since late 2025); 19 is in beta with GA expected Sep/Oct 2026. PG 16 is still supported until Nov 2028, so nothing breaks — but a greenfield single-VPS app has zero migration cost to start on 17 or 18, and 16 forfeits ~2 years of support runway plus PG 18's I/O improvements. Action: bump to 17.x or 18.x unless something (e.g. a Hetzner image constraint) pins 16; if 16 is deliberate, the spine should say why.

### F3 — Three load-bearing deps are niche, single-maintainer packages (Severity: Low, informational)

`ical` (~1.3k total downloads, first published Feb 2026), `mistral` (~1.8k downloads), and `yugo` (Codeberg-hosted, one maintainer) are all real and fit their jobs, but each is a small-community package carrying a core capability (occurrence expansion, AI suggestions, mail ingestion). The spine's seams (AD-9 behaviour, Ingestion-only recurrence per AD-5) already contain the blast radius — this is noted as accepted risk, not a change request. Worth one line in the spine acknowledging it.

### F4 — OTP floor is fine but conservative (Severity: Info)

"OTP 27+" is correct as Elixir 1.20's minimum; current pairing in the wild is OTP 28/29 (1.20.2-otp-29 exists). No change needed — just don't read 27 as the target, only the floor.

## Not independently reconfirmed

- Bandit as the phx.new default adapter rests on the Phoenix 1.8 changelog framing rather than a fresh generator run; confidence high, but a `mix phx.new` smoke test at project start settles it for free.
