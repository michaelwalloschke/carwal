---
baseline_commit: 8ea6233a469178aed12d9f619d21e4ce1891563a
---

# Story 2.1: Throwaway Ingestion Spike

Status: ready-for-dev

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the operator,
I want a throwaway spike that parses both real school feeds and one real Elternbrief email,
so that the riskiest unknowns are burned down before any production ingestion code is written.

## Acceptance Criteria

1. **Given** the real feed handles exist (Wayfinder prerequisite: iCal URLs + mail forwards), **when** a `mix` spike task is run against the live IServ ICS Link-Freigabe and the Schulmanager iCal subscription, **then** both feeds parse into event structs (`ical ~> 2.0`), including at least one recurring event expanded, **and** parsing quirks (encodings, timezone quirks, RRULE oddities) are captured in a short findings note.
2. **Given** one real forwarded Elternbrief in the app mailbox, **when** the spike task polls via IMAP (`yugo`), **then** sender, subject, date, and text body are extracted and printed, **and** the spike code is marked throwaway (not wired into the app, deletable after Epic 2).

## Tasks / Subtasks

- [ ] Task 1: Confirm feed handles are available (AC: #1, #2)
  - [ ] Check with operator that the Wayfinder prerequisite is done: Schulmanager iCal abo URL copied, IServ ICS Link-Freigabe created, IServ mail redirection + one forwarded Elternbrief sitting in the app mailbox. If any are missing, STOP and report — this story cannot proceed against fixtures/mocks, it must hit real feeds.
  - [ ] Read the feed URLs and mailbox credentials from env vars (see Dev Notes → Config), never hardcode them in the spike source.
- [ ] Task 2: Add throwaway deps (AC: #1, #2)
  - [ ] Add `{:ical, "~> 2.0"}` and `{:yugo, "~> 1.0"}` to `mix.exs` deps, `mix deps.get`.
- [ ] Task 3: iCal spike task (AC: #1)
  - [ ] Create `lib/mix/tasks/spike.ical.ex` (`Mix.Tasks.Spike.Ical`), fetch **all configured feed URLs** (`Req.get!/1`) and parse each with `ICal.from_ics/1` — Schulmanager alone is now 3 feeds (see Dev Notes → Config), plus the one IServ feed. Iterate the list, don't hardcode two.
  - [ ] Print event count per feed and one sample event, labeled by feed name (e.g. `[schulmanager:allgemeine_termine]`, `[schulmanager:ferien_feiertage]`, `[iserv]`) so findings are traceable to a specific feed.
  - [ ] Find at least one recurring event (has `RRULE`); expand it via `ICal.Recurrence.from_ics/1` + `ICal.Recurrence.stream/2` and print the first few expanded occurrences. Note whether the feed emits RRULE at all or ships pre-expanded flat VEVENTs (both platforms: undocumented upstream, must observe directly).
  - [ ] **UID stability check:** poll each feed twice (a few minutes apart is enough for the spike; no edit required to prove basic stability, but if there's time, edit one event in the source app between polls and re-poll) — diff the `UID` values. This determines whether `UID` is safe as `external_uid` for Story 2.3, or whether a composite fallback key (hash of `UID+DTSTART+SUMMARY`) is needed.
  - [ ] **Timezone check:** inspect raw ICS bytes for a `VTIMEZONE` block vs. `Z`-suffixed UTC vs. floating local time; if possible, capture one event around a DST boundary (late March / late October) to catch off-by-one-hour bugs.
  - [ ] **IServ-specific:** if a confidential event is in the shared calendar, confirm it round-trips as `SUMMARY:Vertraulicher Termin` with no other detail (per IServ docs) — the real poller (2.3) needs to recognize and either drop or specially render this placeholder, not treat it as a normal entry.
  - [ ] Note encoding issues (umlauts, `ß`), timezone handling, and any RRULE/EXDATE edge cases hit along the way.
- [ ] Task 4: IMAP spike task (AC: #2)
  - [ ] Create `lib/mix/tasks/spike.mail.ex` (`Mix.Tasks.Spike.Mail`), start a one-off `Yugo.Client` (not under the app supervision tree — this is throwaway), subscribe with `Yugo.Filter.all()`, and print sender, subject, date, and text body of the first matching message.
  - [ ] **Header fidelity check:** print raw `From`, `Message-ID`, and `Date` headers of the forwarded message and compare against what the original sender actually sent (if knowable) — IServ's forwarding-header behavior (SRS/envelope rewriting) is undocumented upstream and directly determines whether Story 2.4 can key idempotency on `Message-ID` and whitelist on `From` as planned.
  - [ ] **Content-vs-notification check:** if the forwarded mail is from IServ's Elternbriefe module, expect a bare notification (sender "IServ Benachrichtigungssystem", link back to the portal, no letter text/PDF) rather than the actual letter — confirm this and record it; it means Story 2.4 cannot extract IServ Elternbrief *content* via email, only "new letter available" metadata. If the mailbox instead has a Schulmanager Elternbrief (real email, may include a PDF attachment), note the multipart structure for `yugo`'s body/attachment extraction.
- [ ] Task 5: Findings note (AC: #1, #2)
  - [ ] Write `_bmad-output/implementation-artifacts/2-1-findings.md`: what parsed cleanly, what didn't (encodings, timezone quirks, RRULE oddities, IMAP auth gotchas), and resolve each of the Open Unknowns listed in Dev Notes below with an observed answer (or "still unconfirmed, needs a second real-world case"). Include implications for the real pollers in Stories 2.3/2.4.
- [ ] Task 6: Mark throwaway + cleanup note (AC: #2)
  - [ ] Add a header comment to both spike task files: `# ponytail: throwaway spike (Story 2.1) — delete after Epic 2, do not wire into the app`.
  - [ ] Do not add tests for the spike code — it never ships (ponytail: no test for code marked for deletion).

## Dev Notes

- This is the one story in the whole roadmap explicitly allowed to be throwaway: no context module, no schema, no LiveView, no production wiring. Two `Mix.Tasks.*` files under `lib/mix/tasks/` is the full footprint. Resist the urge to build `Ingestion` context scaffolding here — that's Story 2.2/2.3's job.
- **Real feeds only.** The story exists to burn down unknowns in the *actual* IServ/Schulmanager output — fixture ICS files or a fake mailbox would defeat the purpose. If the operator hasn't extracted the real feed handles yet (PRD Open Questions, epics.md Epic 2 prerequisite), this story is blocked — say so, don't fabricate test data.
- **Config:** read feed URLs and mailbox credentials using the same empty-string-safe `read_env` pattern established in `config/runtime.exs:5-10`. **Schulmanager exports one ICS feed per category** (discovered 2026-07-08 — the deep-research assumption of a single merged feed was wrong), not one URL total. Operator decision: ingest 3 of the 6 available categories — `ISERV_ICAL_URL`, `SCHULMANAGER_ICAL_URL_ALLGEMEIN` (Allgemeine Termine), `SCHULMANAGER_ICAL_URL_SCHUELER` (Termine für Schüler), `SCHULMANAGER_ICAL_URL_FERIEN` (Ferien/Feiertage), `SPIKE_IMAP_SERVER`, `SPIKE_IMAP_USER`, `SPIKE_IMAP_PASSWORD`. Skipped categories (Praktikum, Präventionstermine, Prüfungen) — too narrow/infrequent for a family calendar, revisit if the mother wants them later. Note for Story 2.3: all 3 Schulmanager URLs share the **same access token** — if the operator ever regenerates it, all 3 URLs change together, not independently. — a bare `System.get_env/1`/`System.fetch_env!/1` treats a set-but-empty var as present and crashes downstream (Epic 1 retro learning, hit 3× in Stories 1.1/1.3). `read_env` isn't a shared module, it's a local anonymous fn — copy the same 5-line pattern into the spike task and fail fast (`raise`) when a required var resolves to `nil`, mirroring the required-prod-env contract used for `SECRET_KEY_BASE`/VAPID keys. Do not commit real credentials.
- Deps not yet in `mix.exs`: add `{:ical, "~> 2.0"}` and `{:yugo, "~> 1.0"}` (spine stack pins). `Req` is already a dep (`~> 0.5`) — use it for the HTTP fetch of the ICS feeds, no new HTTP client.

### ical (`~> 2.0`) API — confirmed against hexdocs.pm/GitHub (expothecary/ical)

```elixir
calendar = ICal.from_ics(ics_string)   # or ICal.from_file/1
%ICal{events: events} = calendar

# Recurring events: parse the RRULE, then expand it
rrule = ICal.Recurrence.from_ics("RRULE:FREQ=WEEKLY;COUNT=10")
occurrences = ICal.Recurrence.stream(rrule, event_or_component)
```

### yugo (`~> 1.0`) API — confirmed against codeberg.org/Flying-Toast/yugo

```elixir
# read_env: same empty-string-safe helper as config/runtime.exs:5-10, copied
# inline since it's a local anonymous fn, not a shared module.
read_env = fn name ->
  case String.trim(System.get_env(name, "")) do
    "" -> raise "missing required env var: #{name}"
    value -> value
  end
end

# One-off client for the spike — do NOT add this to CarWal.Application's supervision tree
{:ok, _pid} = Yugo.Client.start_link(
  name: :spike_client,
  server: read_env.("SPIKE_IMAP_SERVER"),
  username: read_env.("SPIKE_IMAP_USER"),
  password: read_env.("SPIKE_IMAP_PASSWORD")
)

Yugo.subscribe(:spike_client, Yugo.Filter.all())

receive do
  {:email, _client, message} ->
    IO.inspect({message.from, message.subject, message.date, message.text_body})
end
```

### Open Unknowns (from deep research, 2026-07-07 — resolve empirically in this spike)

Desk research (3 independent passes, official docs + community sources, see `2-1-deep-research-prompt.md`) confirmed the following are **not documented anywhere upstream** and can only be resolved by running this spike against real feeds/mail:

- **Schulmanager:** RRULE vs. pre-expanded recurrence; timezone form (`VTIMEZONE`/UTC/floating) + DST correctness; `UID` stability across polls/edits; per-child vs. per-account feed aggregation for multi-child parent accounts; umlaut/encoding fidelity; URL regeneration/revocation behavior; whether `UID`s collide or stay distinct across the 3 separate category feeds for the same child.
- **IServ (calendar):** RRULE/`EXDATE`/`RECURRENCE-ID` serialization in the exported ICS; `UID` stability across series edits and IServ version upgrades.
- **IServ (mail):** whether forwarding preserves `From`/`Message-ID`/`Date` verbatim or rewrites them (SRS/envelope); exact MIME structure of forwarded Elternbrief-notification mail.

Already **confirmed** by desk research (no spike time needed to re-verify, just design around them):
- Both feed URLs are capability URLs (secret in the URL itself, no session auth needed) — store as secrets, never log.
- Schulmanager iCal feed does **not** include Klassenarbeiten/Hausaufgaben/Vertretungen — those live in separate modules, out of scope for calendar ingestion entirely.
- IServ confidential events anonymize to `SUMMARY: "Vertraulicher Termin"`; private events are omitted from the feed entirely.
- IServ Elternbriefe are **not** emailed with content — only a notification mail ("IServ Benachrichtigungssystem" sender) pointing back to the portal; the actual letter/PDF requires portal login and is out of reach for an email poller. Schulmanager Elternbriefe, by contrast, **are** real emails, potentially with PDF attachments.
- IServ mail forwarding can be disabled or domain-restricted per-school by the admin; when that happens the only fallback is direct IMAP polling of the IServ mailbox itself (relevant for Story 2.4 design, not this spike).
- Both platforms warn that feed propagation can lag by up to a day (Schulmanager, explicit) or hit nightly maintenance windows (~04:00–06:00 for self-hosted IServ instances) — informs Story 2.3's poll interval and Story 2.5's health-check tolerance, not this spike.
- **Schulmanager is multi-feed, not single-feed** (confirmed empirically 2026-07-08, corrects the deep-research assumption): the "Kalender abonnieren" screen lists one ICS URL per category (Allgemeine Termine, Praktikum, Präventionstermine, Prüfungen, Termine für Schüler, Ferien/Feiertage), all sharing one access token. CarWal ingests 3 of them (see Config above); Story 2.3's poller must loop over a *list* of Schulmanager feed URLs, not assume one.

### Prerequisite status (2026-07-08)

- ✅ Schulmanager feed URLs obtained (3 of 6 categories, see Config).
- ✅ IServ Elternbrief notification format observed in the wild (matches deep-research prediction exactly — notification-only, sender "IServ Benachrichtigungssystem", link back to portal, no content). Arrived in a personal mailbox, not yet the CarWal app mailbox.
- ❌ IServ ICS calendar Link-Freigabe URL — not yet obtained.
- ❌ IServ mail forwarding to the CarWal app mailbox — not yet configured; the observed Elternbrief notification is sitting in a personal inbox, not the app mailbox `yugo` will poll.
- ❌ Schulmanager Elternbriefe routing — Schulmanager emails the account's registered address directly (currently the mother's personal web.de inbox), no IServ-style forwarding setting exists there. Decision: a web.de filter rule forwards Schulmanager-sender mail into the same CarWal app mailbox, rather than giving CarWal IMAP access to her personal account (see `docs/SCHOOL-FEED-SETUP.md` Part C.5). Not yet set up.
- **Task 1 still blocks** on the three ❌ items above.

### Architecture guardrails that still apply

- [Source: ARCHITECTURE-SPINE.md#AD-6] Real pollers (Story 2.3/2.4) will key upserts on `(source, external_uid, occurrence_date)` / `(source, external_uid)` — while spiking, note what stable identifier each feed/mail actually offers (UID field, Message-ID) so 2.3/2.4 aren't surprised.
- [Source: ARCHITECTURE-SPINE.md#AD-5] Recurrence expansion for the real system lives entirely in `Ingestion` over a rolling ~14-month horizon — the spike only needs to prove `ICal.Recurrence` can expand at least one real RRULE, not build the horizon logic.
- [Source: ARCHITECTURE-SPINE.md#NFR1] Everything here is EU-resident already (IServ/Schulmanager feeds, the sovereign mailbox) — no new sovereignty concern, but don't log full mail bodies anywhere they'd persist beyond the terminal.
- Stack pins confirm the versions: `ical ~> 2.0` (currently 2.0.2 on hex.pm), `yugo 1.0.x` (currently 1.0.4). [Source: epics.md#Additional Requirements]

### Project Structure Notes

- New throwaway files only: `lib/mix/tasks/spike.ical.ex`, `lib/mix/tasks/spike.mail.ex`, `_bmad-output/implementation-artifacts/2-1-findings.md`.
- No changes to `lib/carwal/*` context modules, no migrations, no `CarWalWeb` changes. `lib/carwal/ingestion.ex` already exists as an empty context stub from Story 1.1 — leave it untouched; Story 2.2/2.3 build it for real.
- This is the first story of Epic 2; no previous-story-in-epic learnings apply. Story 1.5 (most recent, Epic 1) is deploy/backup-focused and has no ingestion-relevant carryover.

### Testing Requirements

- None. Spike code is explicitly throwaway and untested (PRD/epics.md AC: "deletable after Epic 2"). `mix test` must still pass unmodified — don't let the new deps or tasks break the existing suite.
- Run `mix compile --warnings-as-errors` after adding the tasks to confirm they compile cleanly alongside the existing app (precommit alias expectation), even though they're not exercised by CI test runs.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.1: Throwaway Ingestion Spike] — acceptance criteria source.
- [Source: _bmad-output/planning-artifacts/epics.md#Epic 2: One Surface (School Aggregation)] — prerequisite: real feed handles from operator, blocks this story and both real pollers.
- [Source: _bmad-output/planning-artifacts/prds/prd-carwal-2026-07-05/prd.md#FR1, FR2] — iCal + email ingestion requirements this spike de-risks.
- [Source: _bmad-output/planning-artifacts/prds/prd-carwal-2026-07-05/prd.md#Suggested Phasing] — "Spike ingestion first, throwaway... before any UI."
- [Source: _bmad-output/planning-artifacts/architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md#AD-5, AD-6] — recurrence + idempotency contracts the real pollers must honor later.
- [Source: https://ical.hexdocs.pm/ and https://github.com/expothecary/ical] — `ical` v2.0.2 API (`ICal.from_ics/1`, `ICal.Recurrence.from_ics/1`, `ICal.Recurrence.stream/2`).
- [Source: https://codeberg.org/Flying-Toast/yugo] — `yugo` v1.0.4 API (`Yugo.Client`, `Yugo.subscribe/2`, `Yugo.Filter.all/0`).
- [Source: _bmad-output/implementation-artifacts/2-1-deep-research-prompt.md] — deep-research prompt used to gather the platform-specific findings above (3 independent research passes, 2026-07-07).

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
