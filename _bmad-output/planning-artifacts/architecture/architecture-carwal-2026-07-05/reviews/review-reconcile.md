# Input Reconciliation — CarWal Architecture Spine

- **Spine:** `ARCHITECTURE-SPINE.md` (this folder)
- **Inputs:** `prds/prd-carwal-2026-07-05/prd.md`, `addendum.md`, `.memlog.md`
- **Date:** 2026-07-05
- **Verdict:** PASS WITH GAPS — the spine carries the load-bearing structure (contexts, realtime, ingestion idempotency, ephemerality, visibility, sovereignty of the LLM path) and the quiet safety constraints around minors. Four gaps found; one (outbound email) is structural, the rest are decisions/constraints the AD structure dropped.

Note per task brief: AD-4 (all realtime over LiveView) intentionally supersedes the addendum's "Channels + Presence" wording — verified, not counted as a gap.

## Method

Every requirement, decision, and quiet constraint in the three inputs was traced to a spine landing spot: an AD, a Consistency Convention, a Stack row, the Structural Seed, the Capability Map, or Deferred. `.memlog.md` decisions were cross-checked against the PRD first (all 15 landed in prd.md/addendum.md — no memlog-only decisions exist), then traced through the PRD trace below.

## Gaps

### GAP-1 (structural) — Outbound email path absent; sovereignty constraint on it unrecorded

FR10 magic-link auth *sends* email; the PRD pins it: "sent through the German sovereign mailbox". The addendum names the ingestion mailbox provider class (mailbox.org/Posteo, German provider). The spine has:

- no mailer in the Stack table (Swoosh/SMTP — `yugo` covers IMAP *in* only),
- no convention or AD recording that outbound auth mail and the app mailbox must be a German/EU provider (NFR1 quiet constraint),
- no seed/config slot for SMTP credentials (runtime.exs env vars presumably, but unstated).

Without this, a builder can wire any transactional-mail SaaS (US-resident) and violate NFR1 silently. **Fix:** Stack row (Swoosh + SMTP via the German mailbox provider) + one line in Conventions or AD-9-style note: "all email in/out goes through the German-provider app mailbox".

### GAP-2 (decision loss) — Unified entry shape: `parent_id` and the no-auto-dedup decision

FR4 + addendum data model: one `entry` aggregate with self-referential `parent_id` (idea-attachments *and* manual mail→event linking), nullable `when`/`remind_at`, and the explicit decision **no automatic calendar/mail dedup** ("false merges cost more trust than duplicates" — a grilled, trust-load-bearing decision, memlog Q3). The spine names the `entry` table (AD-1) and the enums (Conventions) but never the parent relationship or the anti-dedup rule. A builder could reasonably add a "smart merge" in Ingestion and break the trust model. **Fix:** add `parent_id` to the Enums/IDs conventions row or AD-1, and one "Prevents" line: no automatic mail↔calendar merging; linking is manual via `parent_id`.

### GAP-3 (quiet constraint) — FR9 proactive volume guard and proposal lifecycle

The spine carries the privacy half of FR9 (AD-9: `owner_only`, minimal egress) but drops:

- the **volume guard**: proactive suggestions at most once per upcoming occasion-type family event (the explicit defense against the notification-fatigue counter-metric),
- the **accept lifecycle**: accepted proposals become `visibility: family` unless kept private,
- **German AI output** (NFR3 — the i18n convention covers gettext UI strings, not LLM output language).

All three are one sentence each on AD-9. Without the volume guard, "proactive" has no bound and the counter-metric drifts.

### GAP-4 (minor, decision loss) — Exactly one family chat room

FR7 (grilled decision, memlog Q9): one family room, no 1:1 threads. The spine's `Chat` context and `messages` table are silent on room structure; a rooms/threads schema would be a plausible over-build. One clause on AD-1 or AD-4 fixes it.

## Minor items (below gap threshold — note, don't block)

| Item | Input | Spine status |
| --- | --- | --- |
| FR3 stale bound = >24 h no successful poll | prd FR3 | Not stated; capability map binds FR3, bound stays PRD-level. Acceptable — PRD is normative for thresholds. |
| FR6 reminder tolerance ±1 min | prd FR6 | Same class: PRD-level SLO, Oban covers mechanism. |
| FR13 skips empty days | prd FR13 | Feature detail; AD-7 covers routing + 07:00 Berlin. |
| FR8 default duration 15 min | prd FR8 | AD-8 lists 15/30/60 presets; default is UI detail. |
| FR10 ~1 y sessions, operator-hands-on first login | prd FR10 | Session length is config; onboarding is runbook (client envelope covers Family Link runbook, could mention first-login). |
| FR12 restore tested once | prd/addendum | Structural Seed covers restic; "restore scripted + tested once" is an ops acceptance criterion, lives fine in PRD. |
| Backup encrypted at rest (NFR5) | prd NFR5 | restic encrypts by default; implicit. |
| Pinterest/IG deep-link-out (P1) + media-only backup sync (P1) | prd Fast Follows, addendum | Not in Deferred list (SearXNG and English toggle are). No structural seam needed; harmless omission. |
| Guardian-account credential model, no minors' passwords stored | addendum ingestion | Feed URLs are credential-less ICS links; constraint self-satisfies. Seed comment would be nice. |
| No scraping / no US email SaaS (rejected alternatives) | addendum | Rationale record; spine's ICS+IMAP-only design embodies it. |
| Aleph Alpha excluded pending Cohere acquisition | addendum AI | Provider-selection rationale; AD-9 seam makes it moot. |
| iOS push weakness lands only on partner | addendum notifications | Accepted risk; client envelope covers Android path. |
| In-app school chat modules may not emit email | addendum caveat / prd Non-Goals | Non-goal, correctly out of spine. |

## Full trace (input → spine landing spot)

### PRD

| Item | Landed as |
| --- | --- |
| G1–G5 | via FR bindings (frontmatter `binds`, capability map) |
| Non-goals: no product/multi-tenancy | scope line, seed-driven config convention |
| Non-goal: no message bodies from closed channels | out of scope, ingestion = ICS + email only (AD-6, stack) |
| Non-goal: no IG/Pinterest ingestion | AD-9 v1 pure-LLM; Deferred (SearXNG) |
| Non-goal: no location history | AD-8 (no schema, no table, no coord logging) |
| Non-goal: near-flat visibility, `owner_only` only on ideas | AD-10 + Deferred "Visibility UI beyond ideas (P2)" |
| Non-goal: no admin UI | Config convention (seed script) |
| FR1 iCal ingestion, diff+flag moved events | AD-5, AD-6 (`entry_revisions`, flagged never deleted) |
| FR2 email ingestion, whitelist, unknown left unread+counted | AD-6, Config convention (whitelist via seed) |
| FR3 feed health, operator alert, unknown-mail count | AD-7 routing (feed health → operator), capability map. Bound: minor item above |
| FR4 unified entry, visibility field | AD-1, AD-10, Enums convention. `parent_id` + no-dedup: **GAP-2** |
| FR5 CRUD | `Entries` context, AD-2 |
| FR6 reminders survive restarts | AD-7 (Oban), Jobs convention |
| FR13 digest 07:00 Berlin, adults | AD-7, Time convention |
| FR7 chat + HTTP media, 25 MB | AD-4, AD-11. Single room: **GAP-4** |
| FR8 teen-agency share, TTL presets, request→target | AD-8 (server-side TTL), AD-7 (request → target routing) |
| FR9 suggestions, owner_only, minimal egress | AD-9, AD-10. Volume guard / accept lifecycle / German output: **GAP-3** |
| FR10 magic link | Capability map (phx.gen.auth). German sovereign mail transport: **GAP-1** |
| FR11 PWA, HTTPS | Client envelope, Caddy in stack |
| FR12 backup | Structural Seed (restic/launchd) |
| Routing defaults, daughters push-quiet | AD-7 (full role-default table incl. "chat → all but sender") |
| NFR1 EU sovereignty | Hetzner, Mistral EU, AD-9. Email leg: **GAP-1** |
| NFR2 minors' safety, minimal payloads | AD-7 ("New message", detail on open), AD-8 |
| NFR3 German UI, Berlin time | i18n + Time conventions. German AI output: **GAP-3** |
| NFR4 reliability | AD-6, AD-7, Oban; metrics stay PRD-level |
| NFR5 durability, media priority | Structural Seed backup; encryption implicit (minor) |
| Counter-metric: notification fatigue | AD-7 "Prevents: push fatigue drift"; proactive bound **GAP-3** |
| Open questions (feed handles, device) | Correctly absent — stakeholder items, non-architectural |
| Phasing | Non-architectural, correctly absent |

### Addendum

| Item | Landed as |
| --- | --- |
| Elixir/Phoenix on Hetzner, realtime rationale | Stack, Structural Seed |
| Channels + Presence | **Superseded by AD-4** (LiveView-only) — intentional, per task brief |
| Single LiveView PWA, foreground GPS only | Client envelope, AD-4 (JS hook for Geolocation) |
| Caddy TLS load-bearing | Stack, Structural Seed |
| Entry aggregate details (nullable when/remind_at, parent_id) | Enums convention partial; **GAP-2** |
| CRUD + narrow `entry_revisions`, not event-sourced | AD-6 (revision scope: ingested only) |
| `messages` own table | AD-1 (Chat owns messages) |
| No `location_history` ever | AD-8 |
| IServ/Schulmanager mechanics, GenServer pollers, IMAP | AD-1 (Ingestion), stack (ical, yugo), AD-5/AD-6 |
| German-provider mailbox | **GAP-1** |
| Guardian-account auth model | Minor item (self-satisfying via credential-less ICS) |
| LLMProvider behaviour, Mistral EU, open-weights rationale | AD-9, stack (mistral 0.5.x) |
| SearXNG P1 / local-LLM P2 | Deferred |
| Web Push VAPID, no vendor accounts | Stack (ex_nudge), AD-7 |
| Oban scheduling, digest cron | AD-7, Jobs convention |
| Routing + whitelist + birthdays in seed | Config convention, Structural Seed (seeds.exs), AD-5 (birthday expansion) |
| Storage behaviour, Plug controller, object-storage later | AD-11, Deferred |
| buildx amd64, save/ssh/load, migrate step | Structural Seed deployment (verbatim) |
| restic/launchd, variable RPO, DR restore | Structural Seed backup; restore-test minor item |
| Right-sized decisions table | Rationale record; embodied (no ES, no Keycloak, no PITR — Deferred notes Postgres tuning/PITR out) |
| Landscape research | Non-architectural, correctly absent |

### .memlog.md

All 15 decisions/assumptions trace into prd.md or addendum.md (verified line-by-line); no memlog-only content. Grilling decisions Q1–Q12 land per the PRD rows above; Q3 (no auto-dedup) and Q9 (one room) are the two whose spine landing is a gap (GAP-2, GAP-4).

## Tone/safety/sovereignty spot-check (quiet constraints)

- **Teen agency framing (FR8):** structurally preserved — AD-8 ephemerality + AD-7 request-routes-to-target means the architecture cannot express parent-side tracking. Held.
- **Minors' liability framing:** AD-8 "Prevents" line carries it verbatim. Held.
- **Push-quiet daughters / fatigue:** AD-7 defaults table carries routing; proactive-AI bound missing (GAP-3).
- **Sovereignty:** LLM leg held (AD-9); email leg dropped (GAP-1).
- **Trust framing ("fix before anyone notices", no false merges):** feed-health held (AD-7); no-dedup dropped (GAP-2).
