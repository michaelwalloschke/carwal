---
stepsCompleted: [1, 2, 3, 4, 5, 6]
documentsIncluded:
  prd: prds/prd-carwal-2026-07-05/prd.md
  prdAddendum: prds/prd-carwal-2026-07-05/addendum.md
  architecture: architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md
  epics: epics.md
  ux: none (intentionally omitted)
---

# Implementation Readiness Assessment Report

**Date:** 2026-07-05
**Project:** carwal

## Document Inventory

| Type | File | Status |
|---|---|---|
| PRD | `prds/prd-carwal-2026-07-05/prd.md` | Found |
| PRD Addendum | `prds/prd-carwal-2026-07-05/addendum.md` | Found (counted as part of PRD) |
| Architecture | `architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md` | Found (binding per CLAUDE.md) |
| Epics & Stories | `epics.md` | Found (whole document) |
| UX Design | — | Intentionally omitted (documented decision; internal 4-person family PWA) |

**Duplicates:** none.
**Working artifacts excluded:** `reconcile-draft.md`, `review-rubric.md`, `reviews/`, `.memlog.md` files.

## PRD Analysis

### Functional Requirements

- **FR1 — Calendar ingestion via iCal feeds.** Configured feed URL per school (IServ ICS Link-Freigabe; Schulmanager per-user iCal subscription); poller turns new/changed items into entries. Moved/removed events are diffed and flagged ("moved Tue→Thu"), never silently mutated.
- **FR2 — Message ingestion via email.** School emails auto-forwarded to dedicated app mailbox are polled, parsed into entries, marked read. Only whitelisted senders become entries; unknown-sender mail stays unread in mailbox. New school app joins by whitelisting its sender.
- **FR3 — Feed-health view + stale alert.** Read-only page with per-source last-success time. Stale = no successful poll > 24 h → push to operator. Page also shows count of unread unknown-sender mails.
- **FR4 — Unified entry model.** Appointments, ideas, tasks, ingested messages, AI suggestions are one `entry` concept (type/status/source); idea attaches via parent relationship; same relationship for manual mail→event linking (no automatic dedup). Every entry has `visibility` (`family` | `owner_only`, default `family`); v1 UI exposes toggle only on idea-notes.
- **FR5 — Manual create/edit.** Full CRUD on appointments, reminders, idea-notes from mobile web, incl. attaching an idea to an existing entry.
- **FR6 — Reminders via push.** Entry with remind-at fires scheduled push at set time (± 1 min); scheduling survives restarts. No automatic per-event reminders on ingested school events (digest + new-entry push cover them).
- **FR7 — Chat with media.** One family room, no 1:1 threads. Real-time chat, persisted history; images and voice notes over HTTP. [ASSUMPTION] indefinite retention; ~25 MB/file cap; media = images + voice notes.
- **FR8 — On-demand live location.** Time-boxed share initiated by the person being located; others see live position on map; auto-expires; nothing persisted. First-class "Where are you?" request pushes target; duration presets 15/30/60 min (default 15). No always-on.
- **FR9 — AI idea-suggestions.** On demand + [ASSUMPTION] proactively at most once per upcoming family-created occasion event (birthdays from member seed config as yearly recurring events). German ideas; proposals accepted/dismissed; default `owner_only`, family-visible on accept; only event title + type leaves the system. Provider swappable.
- **FR10 — Passwordless auth.** Magic-link via email (German sovereign mailbox); any reachable address; sessions ~1 year; operator does first logins hands-on; invite-by-hand for the 3 login-capable members.
- **FR11 — Installable PWA.** HTTPS, home-screen install, push on Android. One web client for all devices.
- **FR12 — Automated backup.** Family data incl. media automatically backed up off-box, encrypted; restore procedure scripted and tested once.
- **FR13 — Morning digest.** 07:00 push to both adults with today's events (school + family); no push on empty day. Complements new-entry push.

Total FRs: 13

Plus cross-cutting requirement: **Notification routing** — fixed role defaults from seed config, no settings UI (new school entries → mother · digest → both adults · reminders → creator/addressee · chat → all except sender · location requests → person asked · feed health → operator; daughters push-quiet).

### Non-Functional Requirements

- **NFR1 — EU sovereignty (hard).** Self-hosted EU infra; every third-party touchpoint EU-resident. One relaxation: AI suggestions send title + type to EU-managed LLM under DPA.
- **NFR2 — Minors' safety.** Ephemeral time-boxed GPS, auto-expiry, no location history; minimal push payloads ("New message", detail fetched on open).
- **NFR3 — Locale.** German UI, `Europe/Berlin`, German AI output; English later (P1).
- **NFR4 — Reliability at family scale.** Ingestion liveness + reminder delivery per success metrics; no manual intervention between school terms.
- **NFR5 — Data durability.** Encrypted backups at rest on target device; irreplaceable media is priority asset.

Total NFRs: 5

### Additional Requirements & Constraints

- **Non-Goals (v1):** no productization, no school-app replacement (no full closed-channel message bodies), no Instagram/Pinterest ingestion, no location history, near-flat visibility (only `owner_only` on ideas/AI proposals), no admin UI (seed-driven config + read-only feed health).
- **Fast Follows (P1):** search-grounded AI suggestions · Pinterest/IG deep-links · more-frequent media-only backup sync · English UI toggle.
- **Designed-for, not built (P2):** visibility toggle on more entry types · native app shell · local-LLM adapter · minimal admin UI.
- **Addendum constraints (binding downstream):** Elixir/Phoenix LiveView PWA on Hetzner VPS; Caddy + Let's Encrypt; one `entry` aggregate + `entry_revisions` change-log (feed-ingested only); separate `messages` table; no `location_history` table ever; `LLMProvider` behaviour with Mistral EU default; Web Push VAPID; Oban scheduling; local-disk media behind storage abstraction via authenticated Plug; buildx amd64 + docker save/load deploy; restic pull backup to MacBook; DR restore tested once.
- **Open Questions (stakeholder):** concrete feed handles (blocking FR1/FR2, trivially resolvable) · younger daughter's device (non-blocking).

### PRD Completeness Assessment

PRD is complete and unusually crisp: 13 numbered FRs each with testable behavior, 5 NFRs, explicit non-goals, phasing proposal, success + counter-metrics, marked assumptions ([ASSUMPTION] tags), and a rationale record for right-sizing decisions. Two open stakeholder questions, one blocking (feed handles) but trivially resolvable. UX document intentionally omitted (internal 4-person app). No gaps that block epic coverage validation.

## Epic Coverage Validation

Note: epics.md promotes the PRD's cross-cutting notification-routing requirement to **FR14** — a deliberate renumbering, not an orphan requirement. All PRD FR texts in epics.md match the PRD faithfully (verified line-by-line; epics add spine details like "outbound mail via sovereign mailbox" on NFR1 and "gettext from day one" on NFR3, consistent with the architecture).

### Coverage Matrix

| FR | PRD Requirement (short) | Epic Coverage | Status |
|---|---|---|---|
| FR1 | iCal calendar ingestion, diffed changes | Epic 2 — Story 2.3 (+ spike 2.1) | ✓ Covered |
| FR2 | Email ingestion + sender whitelist | Epic 2 — Story 2.4 (+ spike 2.1) | ✓ Covered |
| FR3 | Feed-health view + stale alert | Epic 2 — Story 2.5 | ✓ Covered |
| FR4 | Unified entry model, parent links, visibility | Epic 3 — Story 3.2 (schema core: Epic 2 Story 2.2 per AD-12) | ✓ Covered |
| FR5 | Manual CRUD incl. idea attachment | Epic 3 — Story 3.1 (+ 3.2) | ✓ Covered |
| FR6 | Reminders via push, restart-safe | Epic 3 — Story 3.3 | ✓ Covered |
| FR7 | Family chat with media | Epic 4 — Stories 4.1, 4.2 | ✓ Covered |
| FR8 | On-demand live location, ephemeral | Epic 5 — Stories 5.1, 5.2 | ✓ Covered |
| FR9 | AI idea-suggestions, surprise-safe | Epic 6 — Stories 6.1, 6.2 | ✓ Covered |
| FR10 | Passwordless magic-link auth | Epic 1 — Story 1.2 | ✓ Covered |
| FR11 | Installable PWA + push | Epic 1 — Story 1.4 | ✓ Covered |
| FR12 | Automated backup + tested restore | Epic 1 — Story 1.5 | ✓ Covered |
| FR13 | Morning digest 07:00 | Epic 3 — Story 3.4 | ✓ Covered |
| FR14 | Notification routing defaults (PRD cross-cutting) | Epic 2 — Story 2.5; extended in 3.3, 3.4, 4.1, 5.2, 6.2 | ✓ Covered |

FRs in epics but not in PRD: none (FR14 is the PRD's cross-cutting routing section, explicitly promoted).
Story 3.5 (Birthdays from Seed) traces to FR9's seed-birthday dependency — supporting story, not orphan scope.

### Missing Requirements

None. Every PRD FR has a traceable story path.

### Coverage Statistics

- Total PRD FRs: 13 (+1 cross-cutting promoted to FR14)
- FRs covered in epics: 14/14
- Coverage percentage: **100 %**

## UX Alignment Assessment

### UX Document Status

**Not found — intentionally omitted** (confirmed by stakeholder; documented in epics.md §UX Design Requirements: "None — no UX design contract exists").

### Is UX Implied?

Yes — CarWal is a user-facing LiveView PWA. However, the gap is consciously mitigated rather than ignored:

- **UI baseline decided:** phx.new defaults (Tailwind 4 + daisyUI 5), German gettext strings from day one (epics.md Additional Requirements).
- **Key UX decisions live in PRD/epics instead:** mobile-first agenda-list before month view (Epic 2, sized for a 6-inch screen); visibility toggle placement (idea-notes only); notification routing designed against notification fatigue (daughters push-quiet); location sharing UX designed for teen agency (target-initiated, presets, silent decline valid).
- **Escape hatch documented:** "a bmad-ux run can be added later if visual design becomes a concern."

### Alignment Issues

None. The UX-relevant decisions present in PRD and epics are mutually consistent and supported by the architecture (LiveView + one live_session shell per AD-13; PWA/push per FR11/AD-13; mobile-first agenda per Epic 2).

### Warnings

- ⚠️ **LOW:** No visual design contract — acceptable for a 4-person internal app with a non-technical primary user, but the primary user's tolerance is the real acceptance test. Risk is rework on the agenda/chat screens, not missed requirements. Mitigation already named in epics (later bmad-ux run if needed).

## Epic Quality Review

Standards applied: create-epics-and-stories best practices (user value, epic independence, no forward dependencies, story sizing, BDD acceptance criteria, just-in-time schema creation).

### Epic Structure

| Epic | User value | Independent | Verdict |
|---|---|---|---|
| 1 Access & Foundation | Family logs in + installs; operator deploys/restores (operator is a real user — the partner) | Stands alone | ✓ |
| 2 One Surface | Mother sees both schools in one calendar | Needs only Epic 1 | ✓ |
| 3 Her Own Layer | Mother's own entries, reminders, digest | Needs Epics 1–2 (entry core 2.2, push 1.4) | ✓ |
| 4 Family Chat | Family chats with media | Needs only Epic 1 | ✓ |
| 5 Live Location | Time-boxed location sharing | Needs only Epic 1 | ✓ |
| 6 Idea Intelligence | AI ideas for occasions | Needs Epics 2–3 (entries, birthdays 3.5) | ✓ |

All dependencies point backward. Epic N never requires Epic N+1. No technical-milestone epics: Epic 1 is auth + install + operability framed as user/operator outcomes, and the starter-template rule is satisfied — architecture pins `mix phx.new` (Phoenix 1.8.8) and Story 1.1 is exactly "set up from starter."

### Story Quality

- **Sizing:** all 16 stories single-session sized; largest (2.3 iCal poller) is four coherent AC blocks around one GenServer — acceptable.
- **BDD format:** Given/When/Then throughout, specific and testable (e.g. idempotency via double `upsert_from_feed/2` call; Mox-verified minimal LLM payload; no-enumeration login response).
- **Error paths present:** feed errors (2.3), provider failure (6.1), oversize upload (4.2), non-seeded email (1.2), invalid input (3.1).
- **Schema timing:** just-in-time throughout — entry schema in 2.2 (not 1.1), `messages` in 4.1, subscriptions in 1.4, no location table ever (AD-8). ✓
- **Traceability:** every story maps to an FR; Story 3.5 is a supporting story for FR9, correctly placed before Epic 6 needs it.

### Findings

#### 🔴 Critical Violations

None.

#### 🟠 Major Issues

None.

#### 🟡 Minor Concerns

1. **Story 2.1 (spike) is a technical story** — justified: PRD phasing step 1 mandates the throwaway spike, and the story marks the code deletable. Keep, no change.
2. **Missing negative-path ACs** (add during story prep, not blocking):
   - 1.4: notification permission *denied* — expected UI state?
   - 5.1: geolocation permission denied / GPS unavailable mid-share — expected behavior for sharer and viewers?
   - 2.4: unparsable/malformed email from a whitelisted sender — entry with raw fallback, or skip + count?
3. **Story 1.5 restore rehearsal runs against seed data only** — real-data re-test is explicitly deferred inside the story ("flagged for after go-live"). Conscious, documented; ensure it actually lands on a checklist.
4. **Epic 2 external prerequisite** (real feed handles from guardian logins) is operator work outside the dev loop — correctly modeled as a prerequisite, not a story, but it blocks 2.1/2.3/2.4; schedule it before Epic 2 starts.

### Best Practices Compliance

- [x] Epics deliver user value
- [x] Epics function independently (backward deps only)
- [x] Stories appropriately sized
- [x] No forward dependencies
- [x] Database tables created when needed
- [x] Clear, testable acceptance criteria
- [x] FR traceability maintained

## Summary and Recommendations

### Overall Readiness Status

**READY** — proceed to Phase 4 implementation.

### Critical Issues Requiring Immediate Action

None. Zero critical and zero major findings across all assessment categories.

One **blocking external prerequisite** (not an artifact defect): the real feed handles — Schulmanager iCal abo address, IServ ICS Link-Freigabe + mail redirection — must be extracted from the guardian logins before Epic 2 (blocks Stories 2.1, 2.3, 2.4). Trivially resolvable, already tracked as an open question in the PRD and a prerequisite in Epic 2.

### Recommended Next Steps

1. **Resolve the feed-handle prerequisite now** — operator task, ~30 minutes with the guardian logins; unblocks the Epic 2 spike which is the project's riskiest unknown.
2. **Start Epic 1 Story 1.1** (starter-template setup) — nothing blocks it.
3. **During story prep, add the three missing negative-path ACs** (1.4 push permission denied, 5.1 geolocation denied/lost mid-share, 2.4 malformed whitelisted email) — small, non-blocking.
4. **Put the real-data restore re-test on a post-go-live checklist** so Story 1.5's deferred flag doesn't evaporate.
5. Optional, only if the primary user balks at the default UI: run bmad-ux later (escape hatch already documented in epics.md).

### Final Note

This assessment identified **5 issues across 2 categories** (1 LOW UX warning, 4 minor epic-quality concerns) — none blocking. Requirements traceability is complete (14/14 FRs, 100 % coverage), epic structure follows best practices without exception (backward-only dependencies, just-in-time schema creation, starter-template rule satisfied), and PRD/architecture/epics are mutually consistent. The plan is unusually well right-sized for its scale; the findings above can be folded into story preparation without revising any artifact.

---
*Assessed 2026-07-05 by bmad-check-implementation-readiness (facilitated by Claude, reviewed with Michael).*
