# Adversarial Review — ARCHITECTURE-SPINE.md (carwal)

- **Target:** `_bmad-output/planning-artifacts/architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md`
- **Driving PRD:** `_bmad-output/planning-artifacts/prds/prd-carwal-2026-07-05/prd.md`
- **Method:** Construct pairs of one-level-down units (epics/stories built by independent coding agents), each obeying every AD to the letter, and show where they still build incompatibly. Every reproducible clash is a hole; each hole gets a proposed AD fix.
- **Date:** 2026-07-05

## Verdict

**CONDITIONAL — the spine's seams are right, but the shared `entry` table is a commons with no constitution.** Six contexts and one-owner-per-table (AD-1) prevent cross-context Repo access, yet four stories (Ingestion, Manual Entries, AI Suggestions, Digest/Reminders) all converge on the *same* `entry` rows through the `Entries` public API — and the spine never fixes the enum values, the status lifecycle, or who triggers scheduling side effects. Independent agents will each invent a coherent, AD-compliant, mutually incompatible answer. Five holes below; H1–H3 are merge-blocking for any two-agent build.

---

## Attack setup

Two independent coding agents, each given the spine + PRD + one story:

- **Agent A — Story "Ingestion & Feed Health"** (FR1/FR2/FR3): pollers, `Entries.upsert_from_feed/2`, revisions, vanished-flagging, birthday recurrence expansion per AD-5.
- **Agent B — Story "Manual Entries, Reminders & Digest"** (FR4/FR5/FR6/FR13): CRUD LiveViews, remind-at scheduling, 07:00 digest Oban job.

Plus a second pairing where useful:

- **Agent C — Story "Chat + Media"** (FR7) vs **Agent B** — both need Web Push subscriptions and a LiveView shell.

Each agent below violates **no** AD. Every clash is therefore a spine defect, not an agent defect.

---

## H1 — `entry` enums and status lifecycle are unspecified (CRITICAL)

**The clash.** Conventions say `entry.type/status/source/visibility` are `Ecto.Enum` atoms with "single source in the `Entries` schema" — but the spine names only two values anywhere (`:proposed`, `:ai` in AD-9). So each agent authors the enum set his story needs, in the same schema file:

- Agent A (per AD-6 "flagged, never deleted"): `status: [:active, :moved, :vanished]`, `source: [:iserv, :schulmanager, :mail]`, `type: [:event, :message]`.
- Agent B (per FR4/FR5/FR6): `status: [:open, :done]`, `source: [:manual]`, `type: [:appointment, :reminder, :idea, :task]`.
- The later AI story needs `status: [:proposed, :accepted, :dismissed]` (AD-9) — orthogonal to both.

These aren't merge conflicts in one file (bad enough — both agents "own" the single source); they're **semantic** conflicts: Agent B's digest query `where status == :active` silently drops nothing or everything depending on whose lifecycle won, and "flagged as moved" (a *status* to A) collides with "done" (a *status* to B) on one column that is actually carrying two state machines.

**Also latent here:** AD-6's upsert key `(source, external_uid, occurrence_date)` — Agent A must decide what `external_uid`/`occurrence_date` are for manual and AI entries (NULL? sentinel?) to write the unique index; Agent B never thinks about it and inserts rows the index rejects or, worse, dedupes.

**Fix — new AD-12 "The entry state model is closed":** enumerate in the spine the complete v1 value sets and the lifecycle, e.g. `type: [:event, :message, :reminder, :idea]` · `source: [:iserv, :schulmanager, :mail, :manual, :seed, :ai]` · `status: [:active, :done, :moved, :vanished, :proposed, :dismissed]` with a transition table (who may set what: only Ingestion sets `:moved/:vanished`; only the owner sets `:done`; only Suggestions accept/dismiss moves `:proposed`). State the unique-index rule: the `(source, external_uid, occurrence_date)` key applies only to ingested/seed sources; manual/AI entries have `external_uid: nil` and are excluded via a partial index. Adding an enum value later = migration + spine amendment, not an agent's local decision.

---

## H2 — remind-at and digest: the scheduling side effect has two plausible owners (HIGH)

**The clash.** Capability map: "FR6 reminders · FR13 digest → `Notifications` (Oban)". AD-1: `Entries` owns the entry table (and thus `remind_at`). AD-3: side effects are explicit calls, "e.g. `Entries` → `Notifications.notify/2`". Two AD-compliant builds:

- Agent B(-as-Entries): "Notifications owns scheduled sends (AD-7), so it must own scheduling — I just persist `remind_at`." He ships CRUD that writes the field and broadcasts PubSub. Per AD-3 no domain decision may depend on a broadcast, so *nobody schedules the job*. Or he assumes Notifications runs a periodic sweep.
- Agent B'(-as-Notifications): "AD-3 says effects are explicit calls, so Entries will call my `schedule_reminder/1`." He ships the Oban worker and waits for a call that never comes.

Both readings are literal AD-3/AD-7 compliance. Worse on **edit/delete**: user moves `remind_at` from 14:00 to 16:00 — who cancels the stale Oban job? Nothing in the spine says an update must re-invoke Notifications, so a stale reminder fires (directly attacking the "≥95 % of scheduled reminders" metric and the notification-fatigue counter-metric).

Digest has the twin ambiguity: the 07:00 job (in Notifications) must read "today's events" — through which `Entries` function, and as **which acting user** (see H3)?

**Fix — tighten AD-7 with a contract clause:** "`Entries` calls `Notifications.schedule_reminder(entry)` in the same transaction-commit path on every create/update/delete touching `remind_at`; `Notifications` upserts/cancels the Oban job keyed `(entry_id)` (unique job args). The digest cron job calls `Entries.digest_for(user, date)` — a function `Entries` must export — once per recipient." Name the two functions in the spine; the seam is exactly these signatures.

---

## H3 — AD-10 makes system callers (digest, Ingestion, seed) impossible to write consistently (HIGH)

**The clash.** AD-10: "**Every** `Entries` read function takes the acting user … no read path that returns entries without a user scope." Taken literally:

- Agent B's digest job must pick an acting user. Options he can defensibly choose: query as the recipient (each adult gets their own view — mother's digest includes her `owner_only` gift ideas *for the partner's birthday*, pushing surprise-adjacent titles through a push relay the day-of); query as some system user (violates AD-10's letter or invents an unseeded user); query family-visible only (digest silently omits your own private entries — also a defensible read of "minimal payloads").
- Agent A's Ingestion needs to *read* entries to diff against feed state ("changed ingested entry writes a revision") — as which user? He either invents `Entries.get_by_external_uid/2` without a user scope (violating AD-10 as written) or threads a fake operator user through pollers (poisoning AD-10's guarantee).
- The seed and the AI proactive hook (FR9 "at most once per upcoming event") have the same problem.

Two agents resolve this differently and you get one context that demands a user on every call and callers that pass `nil`/operator/recipient inconsistently — the exact "one forgotten where clause" AD-10 exists to prevent, now guaranteed by ambiguity instead of forgetfulness.

**Fix — amend AD-10:** split the read API into two explicitly named tiers: user-facing reads (`for_user/2`-style, visibility-filtered, the only functions `CarWalWeb` and Notifications-push-content may call) and a small enumerated set of system reads (`Entries.get_ingested/1` for Ingestion diffing, `Entries.digest_for(recipient, date)` defined as *visibility-filtered as the recipient*). State the digest privacy rule outright: digest content for user U applies U's visibility scope, and `owner_only` entries never appear in any push payload for anyone but the owner (extends NFR2's minimal-payload logic).

---

## H4 — birthdays: three AD-compliant owners for seeded recurring entries (HIGH)

**The clash.** AD-5: recurrence logic exists "only in `Ingestion` **and the seed**"; "pollers/**seed** expand; an Oban job extends the horizon." AD-1: `Accounts` owns the "membership seed"; birthdays come from member seed config (FR9). Three literal-compliance builds:

- Agent A: birthdays are just another source — Ingestion reads birthday config and upserts via `Entries.upsert_from_feed/2` with `source: :seed`.
- A seed-story agent: AD-5 says *the seed expands* — so `priv/repo/seeds.exs` inserts entry rows **directly via Repo** (a script isn't a context; AD-1's "a *module* reads/writes another context's data only through public functions" doesn't literally bind it), with whatever shape it likes and no `(source, external_uid, occurrence_date)` key.
- Either agent: the horizon-extension Oban job goes "in the owning context's namespace" (Jobs convention) — owner of *what*? Ingestion (it expands), Entries (it owns the rows), or Accounts (it owns birthday config)? Two agents ship two horizon jobs, and re-running seeds duplicates every birthday because the seed path never adopted AD-6's idempotency key.

**Fix — tighten AD-5:** "Seeded birthdays are an Ingestion source. `seeds.exs` writes *config only* (Accounts membership incl. birthdates); it never writes entry rows. `Ingestion.BirthdayPoller` expands birthdays through the same `Entries.upsert_from_feed/2` path with `source: :seed`, `external_uid: member_id`, so AD-6 idempotency covers them. The single horizon-extension job lives in `Ingestion`." Delete "and the seed" from AD-5's rule sentence.

---

## H5 — push-subscription registration and the LiveView shell have no owner (MEDIUM)

**The clash (Chat story vs Reminders story, both AD-compliant).** `Notifications` owns the `push_subscriptions` *table* (AD-1) — but nothing owns the *acquisition path*: the JS hook (`assets/` is in the structural seed, unowned by any context), the permission prompt, and the endpoint that persists the subscription. Agent C (Chat) ships `PushHook` + a LiveView event storing one subscription per user (upsert — "she reinstalls, row replaced"). Agent B (Reminders) ships `WebPushHook` + a controller storing one row per device/endpoint (mother has phone + tablet). Both call `Notifications` public functions; both are AD-compliant; the second one merged silently overwrites or duplicates the first's rows and one of the two features loses push on multi-device users — undetectable at family scale until a reminder just doesn't arrive (the ≥95 % metric again).

Same shape one level up: Chat, Calendar, Feed-health, and Location are each "a LiveView" with no decision on the navigation shell, live_session boundaries, or PubSub topic naming (AD-3 mandates broadcasts but never names topics — Agent A broadcasts `"entries"`, Agent B subscribes to `"entries:family"`, calendar never live-updates and nobody violated an AD).

**Fix — new AD-13 "One push doorway, one shell":** (a) exactly one JS hook (`PushSubscription`) and one context function `Notifications.register_subscription(user, endpoint, keys)`, upsert keyed on `(user_id, endpoint)` — multi-device is rows-per-endpoint by definition; sends fan out over all of a user's endpoints and prune on 404/410. (b) One authenticated `live_session` with a shared app-shell layout component (bottom-tab nav: Calendar/Chat/Map/Health) that every feature LiveView mounts into. (c) Canonical PubSub topics named in the spine: `"entries"`, `"chat"`, `"presence:location"`, `"feed_health"` — owning context broadcasts, anyone subscribes.

---

## Minor findings (no AD needed, but note in conventions)

- **M1 — `parent_id` double duty (FR4):** "idea attaches to entry" and "manually link mail entry to calendar event" both ride "the same relationship." Fine if it's literally one nullable `parent_id` FK — say so in one line, or an agent models the mail-link as a join table and another as `parent_id`, and the calendar view walks only one of them.
- **M2 — routing-table home (AD-7):** "seeded role-default routing" — code table in `Notifications`, or rows in an Accounts-owned seed? One clause ("routing defaults are a compile-time map in `Notifications`; roles come from `Accounts`") closes it.
- **M3 — `entry_revisions` reader:** AD-6 writes revisions; nothing says who reads them or how "moved Tue→Thu" reaches the UI (Entries read function? part of the entry payload?). Cheap to name now.

## Summary table

| # | Hole | Severity | Fix |
| --- | --- | --- | --- |
| H1 | entry enums/lifecycle unspecified; four stories co-author one state column | Critical | New AD-12: closed enum sets + transition table + partial-index rule for the upsert key |
| H2 | remind-at/digest scheduling side effect has two plausible owners; stale jobs on edit | High | Tighten AD-7: named contract functions `Notifications.schedule_reminder/1` (on every remind_at mutation) and `Entries.digest_for/2` |
| H3 | AD-10 "every read takes acting user" impossible for digest/Ingestion/seed callers | High | Amend AD-10: two-tier read API; digest scoped as recipient; owner_only never in others' push content |
| H4 | Birthdays: seed vs Ingestion vs Accounts all defensible owners; seed bypasses AD-6 | High | Tighten AD-5: seed writes config only; birthdays are an Ingestion source through `upsert_from_feed/2` |
| H5 | Push-subscription acquisition and LiveView shell/topics unowned | Medium | New AD-13: one hook + `register_subscription` keyed `(user_id, endpoint)`; one live_session/shell; canonical topic names |
