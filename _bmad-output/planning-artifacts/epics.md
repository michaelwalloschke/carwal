---
stepsCompleted: [1, 2, 3, 4]
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-carwal-2026-07-05/prd.md
  - _bmad-output/planning-artifacts/prds/prd-carwal-2026-07-05/addendum.md
  - _bmad-output/planning-artifacts/architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md
---

# CarWal - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for CarWal, decomposing the requirements from the PRD, UX Design if it exists, and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: Calendar ingestion via iCal feeds — configured feed URLs per school (IServ ICS Link-Freigabe, Schulmanager per-user iCal) are polled; new/changed items become entries; moved/removed events are diffed and flagged, never silently mutated.
FR2: Message ingestion via email — mails forwarded to the dedicated app mailbox are IMAP-polled, parsed into entries, marked read; only whitelisted senders become entries; unknown-sender mail stays unread in the mailbox.
FR3: Feed-health view + stale alert — read-only page with per-source last-success time and unknown-sender count; a feed with no successful poll for > 24 h triggers a push to the operator.
FR4: Unified entry model — appointments, ideas, tasks, ingested messages, and AI suggestions are one `entry` concept (type/status/source); idea-notes attach via parent relationship; the same relationship supports manual mail→event linking; every entry carries `visibility` (family | owner_only, default family), UI toggle only on idea-notes in v1.
FR5: Manual create/edit — full CRUD on appointments, reminders, idea-notes from mobile web, including attaching an idea to an existing entry.
FR6: Reminders via push — an entry with remind_at fires a push at the set time (± 1 min); scheduling survives restarts; no automatic per-event reminders on ingested school events.
FR7: Chat with media — one family room, real-time, persisted history (indefinite retention); images + voice notes upload over HTTP, ~25 MB/file cap.
FR8: On-demand live location — "Where are you?" request pushes the target; target starts a time-boxed share (15/30/60 min preset, default 15); others see live position on a map; auto-expires; nothing persisted.
FR9: AI idea-suggestions — on demand plus proactively at most once per upcoming occasion event (birthdays from member seed as yearly recurring entries); German output; minimal context (title + type) leaves the system; proposals default owner_only, accept → family-visible; provider swappable.
FR10: Passwordless auth — magic-link login via email through the German sovereign mailbox; any reachable address works (IServ school addresses suffice); ~1-year sessions; operator performs first login at onboarding; invite-by-hand for 5 people.
FR11: Installable PWA — HTTPS-only, installs to home screen, push works on Android; one web client for all devices.
FR12: Automated backup — family data including media automatically backed up off-box, encrypted; restore procedure scripted and tested once.
FR13: Morning digest — 07:00 push to both adults listing today's events (school + family); skipped on empty days; complements the new-entry push.
FR14 (cross-cutting): Notification routing — fixed role defaults from seed config: school entries → mother, digest → adults, reminders → creator/addressee, chat → all but sender, location request → target, feed health → operator; minimal payloads, detail fetched on open.

### NonFunctional Requirements

NFR1: EU sovereignty (hard) — self-hosted on EU infra under own control; every third-party touchpoint EU-resident; sole relaxation: minimal entry data (title + type) to Mistral EU under DPA; outbound mail only via the German sovereign mailbox.
NFR2: Minors' safety — ephemeral, time-boxed GPS with auto-expiry; no location history anywhere (no table, no logs); minimal push payloads so content stays out of push relays.
NFR3: Locale — German UI, Europe/Berlin dates, German AI output; all strings through gettext from day one.
NFR4: Reliability at family scale — feeds last-success < 24 h on ≥ 95 % of days; ≥ 95 % reminder delivery; no manual intervention between school terms.
NFR5: Data durability — backups encrypted at rest on the target device; irreplaceable media is the priority asset.

### Additional Requirements

- **Starter template: `mix phx.new` (Phoenix 1.8.8)** — Bandit, esbuild, Tailwind 4 + daisyUI 5, LiveView 1.2.x, magic-link phx.gen.auth, scopes pattern. Impacts Epic 1 Story 1.
- Stack pins (spine): Elixir 1.20.x/OTP 27+, Oban 2.23 (Cron), PostgreSQL 18.x, ical ~> 2.0, yugo 1.0.x (IMAP), ex_nudge 1.0.x (VAPID), mistral 0.5.x, Swoosh SMTP, Caddy + Docker Compose.
- Architecture invariants binding all stories: AD-1 six contexts/one owner per table; AD-2 web layer never touches Repo; AD-3 direct calls for logic, PubSub only for UI; AD-4 all realtime over LiveView, one chat room; AD-5 materialized occurrences (expansion only in Ingestion, seed writes config only); AD-6 idempotent diffed ingestion, no auto-dedup; AD-7 notification contract (`schedule_reminder` on every remind_at mutation, digest cron calls `digest_for`); AD-8 location ephemeral (no schema/table/log); AD-9 LLMProvider behaviour, minimal egress; AD-10 two-tier visibility-scoped reads; AD-11 media via authenticated Plug + Storage behaviour; AD-12 closed entry enums + transition ownership; AD-13 one push pipeline (per-device subscriptions), one live_session/shell, canonical PubSub topics.
- Deployment: single Hetzner VPS, Docker Compose (app + Postgres + Caddy); image built on M1 Mac with `docker buildx --platform linux/amd64` (load-bearing flag), shipped registry-free (`docker save | ssh | docker load`); explicit migration step post-load pre-restart.
- Backup/DR: launchd → restic pull over SSH to FileVault'd MacBook; restore script in `deploy/`, tested once against a scratch box.
- Ingestion auth model: mother's guardian account wherever possible; no minors' passwords stored; no scraping.
- Seed script owns: family members + roles, feed URLs, sender whitelist, birthdays, notification routing defaults.
- Client envelope: Family Link on daughter's Android — onboarding runbook (whitelist domain, one-time "Permissions for sites" ritual); downtime silences her pushes (accepted).
- Config: runtime.exs env vars; time stored UTC, rendered/scheduled Europe/Berlin; errors as `{:ok, _} | {:error, _}` across context boundaries; tests ExUnit + DataCase + Mox, one render smoke test per LiveView.

### UX Design Requirements

None — no UX design contract exists. UI follows phx.new defaults (Tailwind 4 + daisyUI 5) with German gettext strings; a bmad-ux run can be added later if visual design becomes a concern.

### FR Coverage Map

FR1: Epic 2 - iCal calendar ingestion
FR2: Epic 2 - Email message ingestion with whitelist
FR3: Epic 2 - Feed-health view + stale alert
FR4: Epic 3 - Unified entry model UI (core schema lands in Epic 2 per AD-12)
FR5: Epic 3 - Manual create/edit + idea attachments
FR6: Epic 3 - Reminders via push
FR7: Epic 4 - Family chat with media
FR8: Epic 5 - On-demand live location
FR9: Epic 6 - AI idea-suggestions
FR10: Epic 1 - Passwordless magic-link auth
FR11: Epic 1 - Installable PWA + push foundation
FR12: Epic 1 - Automated backup + tested restore
FR13: Epic 3 - Morning digest
FR14: Epic 2 - Notification routing defaults (extended by Epics 3-5)

## Epic List

### Epic 1: Access & Foundation
The family can log in passwordlessly and install CarWal to their home screens; the operator can deploy, back up, and restore the system. App skeleton from `mix phx.new` (Phoenix 1.8.8 starter), magic-link auth via sovereign mailbox, PWA + single push pipeline (AD-13), Caddy/TLS, deploy script, restic backup with restore script + first restore test against seed data (re-test with real data once Epic 2/3 content exists).
**FRs covered:** FR10, FR11, FR12

### Epic 2: One Surface (School Aggregation)
The mother sees both schools' appointments and messages in one aggregated calendar and can trust it: **throwaway ingestion spike first** (parse real IServ ICS + Schulmanager iCal + one forwarded Elternbrief before any UI — PRD phasing step 1), entry model core (AD-12), iCal poller, IMAP poller + sender whitelist, aggregated calendar view (**agenda-list first**, month view later — mobile-first for a 6-inch screen), feed-health page + stale alert, notification routing defaults from seed.
**Prerequisite (operator, not the loop):** extract the real feed handles — Schulmanager iCal abo address, IServ ICS Link-Freigabe + mail redirection — from the guardian logins. Blocks the spike and both pollers.
**FRs covered:** FR1, FR2, FR3, FR14

### Epic 3: Her Own Layer
The mother adds her own appointments, reminders, and idea-notes (with surprise-safe visibility), links school mails to events, and both adults get the 07:00 digest. Manual CRUD, idea attachments + visibility toggle, manual mail→event linking, reminder contract (AD-7), morning digest, birthday seed expansion.
**FRs covered:** FR4, FR5, FR6, FR13

### Epic 4: Family Chat
The family chats in one room with images and voice notes; media uploads over HTTP behind the storage abstraction.
**FRs covered:** FR7

### Epic 5: Live Location
A family member asks "Where are you?", the target shares their live position time-boxed (15/30/60 min), it auto-expires, nothing is persisted.
**FRs covered:** FR8

### Epic 6: Idea Intelligence
The app proposes concrete German-language ideas for occasions — on demand and proactively once per occasion — via the swappable LLM provider, surprise-safe by default.
**FRs covered:** FR9

## Epic 1: Access & Foundation

The family can log in passwordlessly and install CarWal to their home screens; the operator can deploy, back up, and restore the system.

### Story 1.1: App Skeleton from Phoenix Starter

As the operator,
I want a running Phoenix app generated from the current starter with the project conventions in place,
So that every later story builds on the same verified foundation.

**Acceptance Criteria:**

**Given** a machine with Elixir 1.20/OTP 27+ and Docker,
**When** the repo is cloned and `mix setup && mix phx.server` is run,
**Then** the app (generated via `mix phx.new` 1.8.8: Bandit, LiveView, Tailwind 4 + daisyUI 5) boots against local PostgreSQL 18
**And** the default locale is German via gettext with `Europe/Berlin` as configured timezone.

**Given** the generated codebase,
**When** the context directories are inspected,
**Then** `lib/carwal/` contains the six context roots (accounts, entries, ingestion, chat, location, notifications) per AD-1
**And** `mix test` passes with the generated test suite.

### Story 1.2: Magic-Link Login for Seeded Members

As a family member,
I want to log in with just my email address via a magic link,
So that I never need a password and stay logged in long-term.

**Acceptance Criteria:**

**Given** a member seeded in the database (no public sign-up path exists),
**When** they enter their email address on the login page,
**Then** a German-language magic-link email is sent via Swoosh SMTP through the sovereign mailbox
**And** clicking the link creates a session valid for ~1 year.

**Given** an email address that is not seeded,
**When** it is submitted on the login page,
**Then** no email is sent and the UI response is identical to the success case (no user enumeration).

**Given** a logged-in member,
**When** they navigate the app,
**Then** all authenticated LiveViews run in a single `live_session` with the shared layout/nav shell (AD-13) and scope-based data access (AD-2).

### Story 1.3: Deploy to the VPS over HTTPS

As the operator,
I want a scripted deploy that ships the app to the Hetzner VPS behind TLS,
So that the family reaches CarWal at its domain and every later deploy is one command.

**Acceptance Criteria:**

**Given** the VPS and domain exist (Wayfinder prerequisites: VPS provisioned, DNS pointing),
**When** `deploy/deploy.sh` runs on the M1 Mac,
**Then** the image is built with `docker buildx --platform linux/amd64`, shipped via `docker save | ssh | docker load`, migrations run via `bin/carwal eval "CarWal.Release.migrate()"` before restart
**And** Docker Compose runs app + PostgreSQL + Caddy with automatic Let's Encrypt.

**Given** a deployed app,
**When** the domain is opened via HTTP,
**Then** the request is redirected to HTTPS and the login page renders.

### Story 1.4: PWA Install + Push Foundation

As a family member,
I want to install CarWal to my home screen and receive a test push,
So that the app feels native and notifications provably arrive on my device.

**Acceptance Criteria:**

**Given** the HTTPS-served app on Android Chrome,
**When** the member uses "Add to home screen",
**Then** the PWA installs with manifest icon/name and opens standalone.

**Given** an installed PWA,
**When** the member grants notification permission,
**Then** exactly one service worker registers and the subscription is stored per device via `Notifications.register_subscription(user, endpoint, keys)` keyed `(user_id, endpoint)` (AD-13)
**And** a "send me a test push" action delivers a minimal-payload push (ex_nudge/VAPID) to that device.

**Given** a second device of the same user,
**When** it subscribes,
**Then** both subscriptions coexist and both receive the test push.

### Story 1.5: Backup + First Restore Rehearsal

As the operator,
I want automated encrypted pull-backups and a rehearsed restore,
So that family data (especially media) survives the loss of the box.

**Acceptance Criteria:**

**Given** the deployed VPS and the FileVault'd MacBook with restic + SSH access (Wayfinder prerequisite: backup target ready),
**When** the launchd LaunchAgent fires (including catch-up after wake),
**Then** restic pulls an encrypted snapshot of the Postgres dump and media directory to the MacBook.

**Given** an existing snapshot with seed data,
**When** `deploy/restore.sh` is run against a scratch box/VM,
**Then** the app boots against the restored data and the rehearsal result is documented in `deploy/RESTORE.md`
**And** a re-test with real data is flagged for after go-live.

## Epic 2: One Surface (School Aggregation)

The mother sees both schools' appointments and messages in one aggregated calendar and can trust it.

### Story 2.1: Throwaway Ingestion Spike

As the operator,
I want a throwaway spike that parses both real school feeds and one real Elternbrief email,
So that the riskiest unknowns are burned down before any production ingestion code is written.

**Acceptance Criteria:**

**Given** the real feed handles exist (Wayfinder prerequisite: iCal URLs + mail forwards),
**When** a `mix` spike task is run against the live IServ ICS Link-Freigabe and the Schulmanager iCal subscription,
**Then** both feeds parse into event structs (ical ~> 2.0), including at least one recurring event expanded
**And** parsing quirks (encodings, timezone quirks, RRULE oddities) are captured in a short findings note.

**Given** one real forwarded Elternbrief in the app mailbox,
**When** the spike task polls via IMAP (yugo),
**Then** sender, subject, date, and text body are extracted and printed
**And** the spike code is marked throwaway (not wired into the app, deletable after Epic 2).

### Story 2.2: Entry Core + Agenda View

As the mother,
I want a mobile-first agenda list showing upcoming entries,
So that the one surface exists that all school and family items will land on.

**Acceptance Criteria:**

**Given** the `Entries` context with the AD-12 schema (closed enums for type/status/source/visibility, `parent_id`, `entry_revisions` table, partial unique index on `(source, external_uid, occurrence_date)` for ingested/seed sources),
**When** `Entries.upsert_from_feed/2` is called twice with the same payload,
**Then** exactly one entry row exists (idempotent, AD-6).

**Given** seeded sample entries,
**When** the mother opens the agenda LiveView on a phone-sized viewport,
**Then** entries render as a chronological agenda list (today first, German dates, Europe/Berlin)
**And** all reads are visibility-scoped through user-scoped context functions (AD-10)
**And** the view subscribes to the `"entries"` PubSub topic and live-updates on new entries.

### Story 2.3: iCal Poller for Both Schools

As the mother,
I want both schools' calendars to appear and stay current in the agenda automatically,
So that I never open the school apps to check dates.

**Acceptance Criteria:**

**Given** two feed URLs configured via seed,
**When** the supervised Ingestion GenServer polls (interval configurable, default hourly),
**Then** new events land as `source: :ical` entries via `Entries.upsert_from_feed/2`, recurring events materialized over a rolling ~14-month horizon (AD-5) with the horizon-extension Oban job in place.

**Given** an already-ingested event whose time changes in the feed,
**When** the next poll runs,
**Then** the entry is updated in place, an `entry_revisions` row records the change, and the agenda shows a "moved" flag (e.g. "Di→Do") instead of silent mutation.

**Given** an event that disappears from the feed,
**When** the next poll runs,
**Then** the entry is flagged `status: :cancelled`, never deleted.

**Given** a feed that errors (timeout, 404, parse failure),
**When** the poll fails,
**Then** the failure is recorded per source (for feed health) and the poller keeps running (no crash loop).

### Story 2.4: Email Poller with Sender Whitelist

As the mother,
I want school emails to show up as messages in the same surface,
So that Elternbriefe stop living in a separate inbox.

**Acceptance Criteria:**

**Given** the app mailbox receives a mail from a whitelisted sender (seed-configured: IServ domain, Schulmanager),
**When** the IMAP poller (yugo) runs,
**Then** a `type: :message, source: :email` entry is created with sender, subject, date, and text body, and the mail is marked read.

**Given** a mail from a non-whitelisted sender,
**When** the poller runs,
**Then** no entry is created, the mail stays unread in the mailbox, and the unknown-sender counter increments.

**Given** the same mail seen twice (poller restart),
**When** polling repeats,
**Then** no duplicate entry is created (idempotency via `(source, external_uid)` = Message-ID).

### Story 2.5: New-Entry Push + Feed Health

As the mother and the operator,
I want a push when something new arrives from school and a health view proving ingestion is alive,
So that I can trust the calendar without checking the source apps.

**Acceptance Criteria:**

**Given** the seed-configured routing defaults (FR14),
**When** the poller creates a new school entry,
**Then** the mother receives a minimal-payload push ("Neuer Schuleintrag") whose tap opens the entry — and nobody else is pushed.

**Given** the feed-health LiveView,
**When** the operator opens it,
**Then** it shows per-source last-success timestamp and the unknown-sender count, read-only.

**Given** a source with no successful poll for > 24 h,
**When** the hourly health check (Oban cron) runs,
**Then** the operator receives a stale-feed push, once per stale episode (no repeat spam).

## Epic 3: Her Own Layer

The mother adds her own appointments, reminders, and idea-notes, links school mails to events, and both adults get the 07:00 digest.

### Story 3.1: Manual Create/Edit of Entries

As the mother,
I want to create and edit appointments, tasks, and idea-notes from my phone,
So that the family calendar is complete beyond what the schools send.

**Acceptance Criteria:**

**Given** a logged-in member on the mobile agenda,
**When** she creates an appointment (title, date/time), a task, or an idea-note,
**Then** the entry is saved via the `Entries` context (`source: :manual`), appears in the agenda immediately (PubSub `"entries"`), with German validation errors on bad input.

**Given** her own manual entry,
**When** she edits or deletes it,
**Then** the change persists and the agenda updates live; ingested entries offer no edit/delete of source fields.

**Given** a `type: :task` entry,
**When** she taps its checkbox,
**Then** status toggles `active`↔`done` (AD-12 transition) and the agenda renders it struck through.

### Story 3.2: Idea Attachments, Visibility, Mail→Event Linking

As the mother,
I want to hang idea-notes off any entry and keep them hidden when they're surprises,
So that cake and present ideas live on the birthday they belong to — unseen by the birthday child.

**Acceptance Criteria:**

**Given** any existing entry,
**When** she adds an idea-note to it,
**Then** the idea is stored with `parent_id` pointing at the entry and renders nested under it.

**Given** an idea-note form,
**When** she flips the visibility toggle to "nur ich",
**Then** the idea is `visibility: :owner_only` and no other member sees it in any view, push, or digest (AD-10); the toggle exists only on idea-notes.

**Given** an ingested mail entry announcing an event that also exists as a calendar entry,
**When** she uses "mit Termin verknüpfen" and picks the event,
**Then** the mail entry's `parent_id` links it to the event and it renders under the event — no automatic dedup ever runs (AD-6).

### Story 3.3: Reminders via Push

As a family member,
I want an entry with a reminder time to ping me exactly then,
So that nothing due slips by.

**Acceptance Criteria:**

**Given** an entry she owns,
**When** she sets, changes, or clears `remind_at`,
**Then** `Entries` calls `Notifications.schedule_reminder(entry)` on every mutation and the Oban job is upserted/cancelled keyed by entry id (AD-7) — no sweep polling.

**Given** a scheduled reminder,
**When** the remind-at time arrives,
**Then** the creator/addressee (FR14) receives a minimal-payload push within ± 1 min, and an app restart between scheduling and firing does not lose the job
**And** every push send is logged (one line per send) — NFR4's ≥ 95 % target is assessed qualitatively from these logs; no delivery-tracking subsystem is built.

**Given** an ingested school event,
**When** it is created by the poller,
**Then** no automatic reminder is scheduled (FR6).

### Story 3.4: Morning Digest

As an adult,
I want one 07:00 push listing today's events,
So that the day's school and family items are in view before it starts.

**Acceptance Criteria:**

**Given** the Oban cron at 07:00 Europe/Berlin,
**When** it fires,
**Then** each adult (FR14 routing) receives one push built from `Entries.digest_for(recipient, date)`, visibility-scoped as that recipient — another member's `owner_only` ideas never appear (AD-10).

**Given** a day with no events,
**When** the cron fires,
**Then** no push is sent.

**Given** the digest push,
**When** it is tapped,
**Then** the agenda opens on today; the push body itself stays minimal (count + first items, no sensitive detail).

### Story 3.5: Birthdays from Seed

As the mother,
I want family birthdays to appear every year automatically,
So that occasions are never forgotten and later AI suggestions have something to hook onto.

**Acceptance Criteria:**

**Given** member birthdates in the seed config (seed writes config only, AD-5),
**When** Ingestion expands them,
**Then** yearly occurrences materialize as `source: :seed` entries through `Entries.upsert_from_feed/2` over the rolling ~14-month horizon, idempotent on re-seed (partial unique index).

**Given** materialized birthday entries,
**When** agenda or digest render,
**Then** birthdays appear like any other entry (flat rows, no special-case recurrence logic downstream of Ingestion).

## Epic 4: Family Chat

The family chats in one room with images and voice notes.

### Story 4.1: Text Chat in the Family Room

As a family member,
I want to send and read messages in one family room in real time,
So that family coordination happens where the calendar already lives.

**Acceptance Criteria:**

**Given** a logged-in member in the chat LiveView,
**When** they send a text message,
**Then** it persists to the `messages` table (Chat context, AD-1), renders for all connected members in real time via LiveView streams + PubSub `"chat"` (AD-4), and history loads on open (indefinite retention).

**Given** members not currently in the chat view,
**When** a message arrives,
**Then** everyone except the sender receives a minimal-payload push ("Neue Nachricht", FR14) whose tap opens the room.

**Given** the one-room rule (AD-4),
**When** the chat UI renders,
**Then** there is no room list, no thread creation — exactly one family room.

### Story 4.2: Images and Voice Notes

As a family member,
I want to share photos and voice notes in the chat,
So that quick media replaces typing when it's faster.

**Acceptance Criteria:**

**Given** the chat composer,
**When** a member uploads an image or a voice note (in-browser recording is Android-Chrome-first; attaching an existing audio file works everywhere — iOS-Safari recording explicitly out of scope),
**Then** the file goes over HTTP through the authenticated Plug controller against `CarWal.Storage` (local-disk adapter, AD-11) — never through the LiveView socket — and the message references it.

**Given** an upload over ~25 MB,
**When** it is submitted,
**Then** it is rejected with a German error message before transfer completes.

**Given** a message with media,
**When** the room renders,
**Then** images display inline (constrained size) and voice notes play via an audio element; media URLs require an authenticated session (no public links).

## Epic 5: Live Location

A family member asks "Where are you?", the target shares their live position time-boxed, it auto-expires, nothing is persisted.

### Story 5.1: Start a Share + Live Map

As a daughter,
I want to share my live location for a time span I choose and have it stop by itself,
So that I stay in control while the family sees where I am.

**Acceptance Criteria:**

**Given** a logged-in member,
**When** they start a share with a preset (15/30/60 min, default 15),
**Then** their position streams via the Geolocation JS hook over the LiveView socket into Phoenix.Presence (AD-4) and other members see the moving marker on an OSM map (Leaflet).

**Given** a running share,
**When** the TTL expires (server-enforced),
**Then** the share ends automatically for all viewers; the sharer can also stop early at any time.

**Given** the whole feature (AD-8),
**When** the code and logs are inspected,
**Then** no Ecto schema, table, or log line contains coordinates — positions live only in process state/Presence.

### Story 5.2: "Where Are You?" Request

As the mother,
I want to ask a family member for their location with one tap,
So that the ask is explicit and the answer stays in their hands.

**Acceptance Criteria:**

**Given** the family member list,
**When** she taps "Wo bist du?" on a member,
**Then** only that member receives a push (FR14) naming the requester.

**Given** the request push,
**When** the target taps it,
**Then** the share-start dialog opens with the presets — sharing starts only by their action, and declining/ignoring is a valid, silent outcome (no auto-share, no nag).

## Epic 6: Idea Intelligence

The app proposes concrete German-language ideas for occasions — surprise-safe by default.

### Story 6.1: LLM Provider + On-Demand Suggestions

As the mother,
I want to tap "suggest ideas" on an entry and get concrete German suggestions,
So that inspiration comes to me instead of me hunting for it.

**Acceptance Criteria:**

**Given** the `CarWal.LLMProvider` behaviour with the Mistral EU adapter (AD-9),
**When** `suggest/1` is invoked for an entry,
**Then** the request payload contains at most the event title + type (verified in the adapter test via Mox) and returns German-language idea suggestions.

**Given** a suitable entry,
**When** she taps "Ideen vorschlagen",
**Then** returned ideas land as child entries (`source: :ai, status: :proposed, visibility: :owner_only`, AD-12) visible only to her.

**Given** a proposed idea,
**When** she accepts it,
**Then** it becomes `status: :active` and `visibility: :family` unless she keeps it private; dismissing sets `status: :dismissed` (terminal).

**Given** a provider failure (timeout, API error),
**When** suggestions are requested,
**Then** she sees a friendly German error and no partial entries are written.

### Story 6.2: Proactive Occasion Suggestions

As the mother,
I want the app to propose ideas for upcoming occasions on its own,
So that inspiration arrives before I even think to ask.

**Acceptance Criteria:**

**Given** the daily Oban scan over upcoming occasion entries (seeded birthdays from Story 3.5, occasion-flagged family events),
**When** an occasion enters the lookahead window,
**Then** at most one proposal set is generated per occasion event ever (volume guard, FR9) with the same owner_only/accept/dismiss lifecycle as 6.1.

**Given** generated proactive proposals,
**When** they land,
**Then** only the event's creator receives a single minimal push ("Ideen für …"), counting against the notification-fatigue counter-metric — no repeat pushes for the same occasion.
