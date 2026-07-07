---
title: "CarWal — Family Coordination App"
status: final
created: 2026-07-05
updated: 2026-07-05
---

# PRD — CarWal (Family Coordination App)

## Context

The two daughters' schools each use a separate, walled-garden school app (calendar + teacher messages). Their mother has to open multiple apps, on multiple logins, to know what's happening — and there is no single place to add her own appointments, hang idea-notes off an event, coordinate with the family, or get a nudge when something's due. The cost of not solving it is daily friction and missed school information.

CarWal is a **private app for 5 known family members** — not a product. No sign-up, no app store, no multi-tenancy. Market research confirms the gap is real: no existing product aggregates German school apps (IServ, Schulmanager Online) into a family calendar (see addendum, Landscape).

**Users:** Mother (Android, non-technical, primary — the app exists for her) · elder daughter (Android, teen) · younger daughter (device TBD) · partner (iPhone, web/PWA sufficient; also the operator/developer). UI and dates are German (`Europe/Berlin`); English toggle is a fast-follow for the partner.

## Goals

- **G1 — One surface.** Every appointment and message from both daughters' school apps appears in a single aggregated view.
- **G2 — Her own layer.** She can create appointments, reminders, and idea-notes, and attach ideas to any existing event, from her phone on the road.
- **G3 — Family coordination.** The whole family can chat with media and, on demand, share live location.
- **G4 — Gentle intelligence.** The app proactively proposes concrete, useful ideas for events (present/cake/theme).
- **G5 — It doesn't rot.** Ingestion keeps working unattended; when a feed breaks, someone is told rather than the calendar silently going stale.

## Non-Goals (v1)

- Not a product: no public sign-up, app-store distribution, multi-tenancy, or billing.
- Not a school-app replacement: sources remain the system of record; full message *bodies* from closed in-app channels are out — surface the notification, deep-link for detail.
- No live Instagram/Pinterest ingestion (infeasible via legitimate channels) — suggest from model knowledge, link out instead.
- No stored location history — ephemeral live-share only; a queryable track of two minors is a liability.
- Near-flat visibility: everything defaults to family-visible; the only per-person control in v1 is the `owner_only` toggle on idea-notes and AI proposals (so surprises stay surprises — see FR4/FR9). No broader privacy walls; a daughter's ordinary note is visible to the whole family (set this expectation at onboarding).
- No admin UI in v1 — seed-driven config + read-only feed-health view.

## Functional Requirements

### Aggregation (G1, G5)

- **FR1 — Calendar ingestion via iCal feeds.** Given a configured feed URL per school (IServ ICS Link-Freigabe; Schulmanager per-user iCal subscription), the poller turns new/changed items into entries. A moved or removed event is diffed and flagged ("moved Tue→Thu"), never silently mutated.
- **FR2 — Message ingestion via email.** School emails auto-forwarded to a dedicated app mailbox are polled, parsed into entries, and marked read. Only whitelisted senders (IServ domain, Schulmanager) become entries; mail from unknown senders is left unread in the mailbox — no entry, no loss. Covers IServ mail redirection and Schulmanager Elternbrief emails; a new school app joins by whitelisting its sender.
- **FR3 — Feed-health view + stale alert.** A read-only page shows per-source last-success time. A feed is stale when it has had no successful poll for > 24 h (the same bound the success metric uses); a stale feed triggers a push notification to the operator — so he can fix ingestion *before anyone notices*, and she can trust the calendar without checking the source apps. The page also shows a count of unread unknown-sender mails, so a legitimate new sender (school change, parent council) can't rot silently outside the whitelist.

### Family layer (G2)

- **FR4 — Unified entry model.** Appointments, ideas, tasks, ingested messages, and AI suggestions are one `entry` concept distinguished by type/status/source; an idea-note ("idea" for short) attaches to any entry via a parent relationship. The same relationship supports manually linking an ingested mail entry to the calendar event it announces — there is deliberately no automatic calendar/mail dedup (false merges cost more trust than duplicates). Every entry carries a `visibility` field (`family` | `owner_only`, default `family`); in v1 the UI exposes the toggle only on idea-notes, so gift ideas can be hidden from the person they're for.
- **FR5 — Manual create/edit.** Full CRUD on appointments, reminders, and idea-notes from mobile web, including attaching an idea to an existing entry.
- **FR6 — Reminders via push.** An entry with a remind-at time fires a scheduled push notification at the set time (± 1 min); scheduling survives app restarts. Ingested school events get no automatic per-event reminders — the morning digest (FR13) and the new-entry push cover them; she sets remind-at deliberately on the ones that matter.
- **FR13 — Morning digest.** At 07:00 a push to both adults lists today's events (school + family); no push on an empty day. It complements, not replaces, the new-school-entry push (digest says *today*, entry push says *new* — different jobs).

### Communication (G3)

- **FR7 — Chat with media.** One family room — no 1:1 threads (private messaging stays on the messengers the family already uses). Real-time chat with persisted history; images and voice notes upload over HTTP. [ASSUMPTION] History is retained indefinitely (family-scale volume); uploads capped at ~25 MB/file; media types are images + voice notes.
- **FR8 — On-demand live location.** A user starts a time-boxed share; others see the live position on a map; the share auto-expires; nothing is persisted. Sharing is initiated by the person being located ("share when asked, and it stops automatically, so I keep control") — teen agency, not parent-side tracking. The ask is a first-class "Where are you?" request that pushes the target; they answer by starting a share with a duration preset (15/30/60 min, default 15). No always-on option.

### Intelligence (G4)

- **FR9 — AI idea-suggestions.** The app proposes concrete ideas for an entry on demand (user taps "suggest ideas"), and [ASSUMPTION] proactively at most once per upcoming family-created event with an occasion character (birthday, party) — a volume guard against the notification-fatigue counter-metric. Family birthdays come from the member seed config as yearly recurring events; proactive suggestions hook there. Ideas (presents, cake, themes) are in German. Suggestions arrive as proposals the user accepts or dismisses; proposals default to `visibility: owner_only` (the birthday child must not see her own surprises) and become family-visible on accept unless kept private; only the minimum context (event title + type) leaves the system. Provider is swappable (see addendum).

### Access

- **FR10 — Passwordless auth.** Magic-link login via email (sent through the German sovereign mailbox); any reachable address works — the daughters' IServ school addresses suffice, since the link is needed rarely. Sessions effectively never expire (~10 years — widened from ~1 year per operator decision in Story 1.2); the operator performs each member's first login hands-on at onboarding. Invite-by-hand for the 3 login-capable members (operator, mother, 15-year-old daughter); the 9-year-old daughter is tracked but has no login.
- **FR11 — Installable PWA.** Served over HTTPS; installs to the home screen; push works on Android. One web client for all devices.

### Operations

- **FR12 — Automated backup.** Family data (including media) is automatically backed up off-box, encrypted; the restore procedure is scripted and tested once.

### Notification routing (cross-cutting)

Fixed role defaults from seed config, no settings UI: new school entries → mother · morning digest → both adults · reminders → their creator/addressee · chat → everyone except the sender · location requests → the person asked · feed health → operator. The daughters stay push-quiet by design — the app must remain bearable for teens.

## Fast Follows (P1)

Search-grounded AI suggestions (current, buyable results with real links) · Pinterest/Instagram deep-links appended to suggestions · more-frequent media-only backup sync · English UI toggle.

## Designed-for, Not Built (P2)

Visibility toggle on further entry types (the `visibility` field ships in v1, UI-exposed only on ideas) · native app shell if reliable iOS push or background GPS becomes a need · local-LLM adapter (sovereignty upgrade) · minimal admin UI. None of these are gaps — each is a conscious "later, if needed," and the architecture is shaped so adding them is cheap.

## Non-Functional Requirements

- **NFR1 — EU sovereignty (hard).** Everything self-hosted on EU infra under own control; every third-party touchpoint EU-resident. One conscious relaxation: AI suggestions send minimal entry data (title + type) to the EU-managed LLM provider under a DPA.
- **NFR2 — Minors' safety.** Two users are minors: ephemeral, time-boxed GPS with auto-expiry as the safety default; no location history; minimal push payloads ("New message" — detail fetched on open) so content stays out of push relays.
- **NFR3 — Locale.** German UI, `Europe/Berlin` dates, German AI output; English as personal preference later (P1).
- **NFR4 — Reliability at family scale.** Ingestion liveness and reminder delivery per Success Metrics; no manual intervention needed between school terms.
- **NFR5 — Data durability.** Backups are encrypted at rest on the target device; irreplaceable media is the priority asset.

## Success Metrics

**Leading**
- Mother opens CarWal instead of the school apps (target: school apps opened rarely within 2 weeks of go-live).
- Both feeds show last-success < 24 h on ≥ 95 % of days.
- Push arrives for ≥ 95 % of scheduled reminders.

**Lagging**
- "Did we miss a school thing?" incidents trend to ~zero.
- Family uses chat/idea-notes unprompted (qualitative).
- Operator burden stays low: no manual intervention between school terms.

**Counter-metrics**
- Notification fatigue: if pushes get muted, volume/defaults are wrong — fewer, better nudges beat more.
- Operator time: if keeping ingestion alive costs regular evenings, G5 has failed regardless of feature completeness.

## Open Questions

- **[stakeholder] Concrete feed handles** — copy the Schulmanager iCal abo address; create the IServ ICS Link-Freigabe and set the mail redirection. Blocking for FR1/FR2, trivially resolvable from her logins.
- **[stakeholder] Younger daughter's device** — affects push/GPS behavior. Non-blocking.

## Suggested Phasing (solo, evening hours)

1. Spike ingestion first, throwaway (both iCal feeds + one forwarded email) — before any UI.
2. Skeleton: app, data model, auth, TLS, deploy, restore-tested backup.
3. Ingestion for real (FR1, FR2) + feed health (FR3).
4. Manual entries + idea-attachments (FR4, FR5) + aggregated calendar view.
5. Reminders + push (FR6, FR11).
6. Chat + media (FR7).
7. On-demand GPS (FR8).
8. AI suggestions (FR9).
9. Onboard the family (seed config).
10. Fast follows (P1).
