# Rubric Review — ARCHITECTURE-SPINE.md (carwal)

- **Target:** `_bmad-output/planning-artifacts/architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md`
- **Driving spec:** `_bmad-output/planning-artifacts/prds/prd-carwal-2026-07-05/prd.md`
- **Stakes calibration:** hobby/solo, 5 users, built largely by coding agents via bmad-loop.
- **Date:** 2026-07-05

## Verdict

**Pass with minor gaps.** The spine is a genuinely good build substrate for this altitude: the eleven ADs hit the real divergence points, the rules are mechanically checkable, and Deferred is clean. Two silent dimensions (outbound email, test conventions) and one stale version pin are the substantive findings; none blocks starting the skeleton phase, but the email one should be fixed before FR10 work.

## Rubric pass

### 1. Fixes the real divergence points for the level below — mostly yes

For epics/stories implemented by coding agents, the places two agents would plausibly diverge are: who writes which table (AD-1), where business logic lives (AD-2), events vs. calls (AD-3), sockets vs. channels (AD-4), recurrence math (AD-5), dedup/idempotency (AD-6), notification recipient logic (AD-7), location persistence (AD-8), LLM coupling (AD-9), visibility filtering (AD-10), media transport (AD-11). That is the right list, and each AD names a concrete divergence it prevents. The Consistency Conventions table (time, enums, error tuples, jobs-as-Oban, config-via-seed) closes the smaller drift vectors agents actually produce.

**Missed divergence points:** see Findings F1 (mailer) and F3 (test conventions), and the smaller F4 (birthday-recurrence ownership).

### 2. Every AD's Rule is enforceable and prevents its stated divergence — yes

Each Rule is phrased as a mechanically checkable constraint, not an aspiration:

- AD-1/AD-2: grep-able ("no `Repo`/schema references in `CarWalWeb`", "cross-context access only via public functions").
- AD-3: "No domain decision may depend on receiving a broadcast" — checkable in review; the example function names (`Entries.upsert_from_feed/2`) anchor implementers.
- AD-5: "Recurrence logic exists only in Ingestion and the seed" — enforceable, though see F4 on ownership ambiguity.
- AD-6: concrete upsert key `(source, external_uid, occurrence_date)`; "flagged, never deleted" is a testable property.
- AD-8: "no Ecto schema, no table, no log line containing coordinates" — the log clause is the kind of thing usually forgotten; good that it is explicit.
- AD-10: "Every `Entries` read function takes the acting user" — an agent cannot half-comply; a read function without a user param is visibly wrong. This is the right enforcement point for the highest-trust-cost failure (a child seeing her surprises).

No AD is a platitude; all bind to specific FR/NFRs.

### 3. Nothing under Deferred could let two units diverge — yes

- SearXNG grounding: correctly noted that AD-9 already isolates the seam.
- English toggle: pure gettext locale, no structure.
- Object storage: `CarWal.Storage` behaviour is already the seam, so the deferral is safe.
- TWA, visibility UI: no server-side/structural impact; the visibility *field* ships everywhere (AD-10), so per-type UI deferral cannot fork the data model.
- PG tuning/PITR/staging: explicitly out of scope by PRD decision — a deliberate deferral, not a silence.

This section is exemplary: each deferral names why it is safe to defer.

### 4. Named tech verified-current — one stale pin

Verified against hex.pm on 2026-07-05:

| Package | Spine pins | Latest | Status |
| --- | --- | --- | --- |
| phoenix | 1.8.8 | 1.8.8 | current |
| phoenix_live_view | 1.2.x | 1.2.5 | current |
| oban | 2.23.x | 2.23.0 | current |
| yugo | 1.0.x | 1.0.4 | current |
| ex_nudge | 1.0.x | 1.0.2 | current |
| mistral | 0.5.x | 0.5.0 | current |
| **ical** | **~1.1** | **2.0.2** | **stale pin (F2)** |

PostgreSQL 16.x is supported (not latest major, fine at this scale). Elixir 1.20/OTP 27+ consistent with the Phoenix 1.8.8 pin.

### 5. Covers the driving spec's capabilities — yes, with one soft spot

The Capability → Architecture Map covers FR1–FR13 and the frontmatter binds all FRs and NFRs. Cross-checked each PRD FR against the map: all land in a named context under named ADs. NFR1 (sovereignty) is handled in AD-9 (minimal egress) and the self-hosted structural seed; NFR2 in AD-7 (minimal payloads) + AD-8; NFR3 in conventions (gettext, Berlin time); NFR4 via AD-6/AD-7/Oban; NFR5 via the restic backup line. Soft spot: FR12's "restore procedure is scripted and tested once" is only half-reflected — the spine names the backup mechanism but not the scripted restore (F5).

### 6. Every owned dimension decided, deferred, or open — two silences

Decided: paradigm, context boundaries, communication style, realtime model, persistence conventions, job scheduling, config strategy, deployment topology, backup mechanism, client envelope (the Family Link runbook is an unusually good operational-envelope catch — most spines miss the managed-device constraint entirely). Deferred: listed above, all justified. Open questions: none listed in the spine — acceptable since the PRD's two open questions are stakeholder items with no architectural impact.

Silent: outbound transactional email (F1) and test conventions (F3).

## Findings

### F1 — MEDIUM — Outbound email is a silent dimension: no mailer in the stack

FR10 (magic-link auth) requires the app to *send* email "through the German sovereign mailbox," and NFR1 constrains the provider. The spine decides email *ingestion* (yugo/IMAP) but says nothing about email *sending*: no Swoosh (or alternative) in the Stack table, no SMTP adapter/config decision, no note on whether the same sovereign mailbox account is used for both IMAP polling and SMTP sending. `phx.gen.auth` magic link presumes a configured mailer. Two coding agents hitting this will pick divergently (Swoosh SMTP vs. a Req-based API client vs. local sendmail), and it is an NFR1-constrained external touchpoint — exactly the kind of decision the spine exists to make. **Fix:** one Stack row (e.g. Swoosh + SMTP adapter against the sovereign mailbox) and one line in conventions or the seed.

### F2 — LOW — `ical` pinned at ~1.1; hex latest is 2.0.2

A 2.x major exists (2.0.2, "iCalendar parsing, serialization, and recurrence generation"). Pinning ~1.1 means starting on a superseded major of the one library AD-5's recurrence expansion leans on. Verify the 2.x API covers RRULE expansion as assumed and bump the pin (or record why 1.1 is deliberately chosen).

### F3 — LOW — Test conventions are silent, and the builders are coding agents

For a codebase built largely by bmad-loop agents across many sessions, "how do we test" is a per-unit divergence vector the spine owns: context-level tests vs. LiveView tests, DataCase/ConnCase usage, whether external seams (LLMProvider, Storage, IMAP, push) get Mox-style behaviour mocks. The behaviours are already there (AD-9, AD-11), which strongly implies Mox — but nothing says so, so each agent will decide independently. One convention row (e.g. "ExUnit; behaviours mocked via Mox; every context function has a test; no LiveView-only coverage of business rules") would close it. Calibrated to hobby stakes this is LOW, but it is the checklist's "silent dimension is a finding" case.

### F4 — LOW — Birthday-recurrence ownership is ambiguous in AD-5

AD-5 says recurrence logic exists "only in `Ingestion` and the seed," and "an Oban job extends the horizon." For feed RRULEs the owner is clearly Ingestion. For seeded birthdays: the seed expands the initial 14 months, but which context owns the horizon-extension job for birthdays — Ingestion (which per AD-1 must not write entries except via the Entries API, and semantically doesn't own birthdays) or somewhere else? Two implementers could reasonably put it in different contexts. One clause naming the owning context (and confirming it goes through `Entries.upsert_from_feed/2` or a sibling API) resolves it.

### F5 — LOW — Restore script/test not reflected

FR12 requires the restore procedure be "scripted and tested once." The Structural Seed names restic pull + launchd but not a restore script location (`deploy/` is the obvious home) or the tested-once expectation. One line keeps a coding agent from shipping backup-only.

## What is notably good

- Deferred section justifies each deferral against an existing seam — the strongest section.
- The Family Link onboarding runbook in the client envelope: an environmental constraint most architecture docs never discover.
- AD-10's enforcement point (filter inside the context, user param mandatory) is the correct structural answer to the PRD's highest-trust failure mode.
- Right-sized throughout: no staging, no k8s, no event sourcing — the spine resists over-engineering at 5-user scale without going silent on the dimensions that matter.
