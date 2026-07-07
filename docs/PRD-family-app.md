# PRD — Family Coordination App (codename: **Hearth**)

> **Status:** Draft v1 · **Date:** 2026-07-05 · **Owner:** Wall-E · **Audience:** solo developer (self)
> **Scope discipline:** built for **5 known family members**, not for scale. Every decision below was right-sized to that fact.
> *Codename "Hearth" is a placeholder — see Open Questions.*

---

## 1. Problem Statement

The two daughters' schools each use a separate, walled-garden school app (calendar + teacher messages). Their mother has to open multiple apps, on multiple logins, to know what's happening — and there is no single place to add her own appointments, hang idea-notes off an event ("cake + present ideas" on a birthday), coordinate with the family, or get a nudge when something's due. The cost of not solving it is daily friction and missed school information scattered across apps that were never meant to talk to each other.

## 2. Goals

- **G1 — One surface.** Every appointment and message from both daughters' school apps appears in a single aggregated view, so she stops opening the individual school apps to stay informed.
- **G2 — Her own layer.** She can create appointments, reminders, and idea-notes, and attach ideas to any existing event, from her phone while on the road.
- **G3 — Family coordination.** The whole family (2 Android, 1 iPhone/web) can chat with media and, on demand, share live location.
- **G4 — Gentle intelligence.** The app proactively proposes concrete, useful ideas for events (present/cake/theme ideas) without her having to go hunting.
- **G5 — It doesn't rot.** Ingestion keeps working unattended, and when a feed breaks, *someone is told* rather than the calendar silently going stale.

## 3. Non-Goals (v1)

- **Not a product.** No public sign-up, app-store distribution, multi-tenancy, or billing. Invite-by-hand for the 3 login-capable household members.
- **Not a school-app replacement.** We aggregate/notify; the source apps remain the system of record. Full message *bodies* from closed apps are out — we surface the notification, deep-link to the app for detail.
- **No live Instagram/Pinterest ingestion.** Infeasible via legitimate, sovereignty-respecting channels (see §7.4). We suggest from the model's own knowledge and *link out* to Pinterest/IG searches instead.
- **No stored location history.** Ephemeral live-share only. A queryable track of two minors is a liability, not a feature.
- **No granular per-person privacy walls in v1.** Flat family visibility (designed so it's cheap to add later).
- **No admin UI in v1.** Seed-driven config + a read-only feed-health view.

## 4. Target Users / Personas

- **Mother (Admin/primary).** Android. Non-technical. The person the app exists for. Wants everything in one place with minimal fuss.
- **Elder daughter.** Android. Teen; will use chat, calendar, on-demand location.
- **Younger daughter.** Device TBD; has the birthday-party use case.
- **Partner (me).** iPhone; **web/PWA is sufficient**. Also the operator/developer.

**Language:** UI, dates (`Europe/Berlin`), and AI suggestions are **German** by default (Phoenix `gettext`), with an English toggle as a personal preference for the partner.

## 5. User Stories

**Mother (Admin)**
- As the mother, I want both daughters' school calendars and messages merged into one view so I don't have to open each school app.
- As the mother, I want to add my own appointments and reminders so the family calendar is complete.
- As the mother, I want to attach idea-notes to an existing event (e.g. cake/present ideas on a birthday) from my phone while out.
- As the mother, I want the app to suggest concrete ideas for an event so I get inspiration without searching.
- As the mother, I want to be sure the school feeds are still working so I can trust the calendar.

**Daughters**
- As a daughter, I want to see the shared family calendar and chat so I know what's planned.
- As a daughter, I want to share my live location for a set time when asked, and have it stop automatically, so I keep control.

**Partner / Operator**
- As the partner, I want to use the app in the browser so I don't need a native iOS app.
- As the operator, I want an alert when a feed goes stale so I can fix ingestion before anyone notices.

## 6. Requirements

### Must-Have (P0) — v1 cannot ship without these

| ID | Requirement | Acceptance criteria |
|----|-------------|---------------------|
| P0-1 | **Calendar ingestion via iCal feeds** (IServ ICS Link-Freigabe; Schulmanager per-user iCal subscription) | Given a configured feed URL per school, when the poller runs, then new/changed items appear as `entry` rows; a moved/removed event is diffed and flagged, not silently mutated. |
| P0-2 | **Message ingestion via email** (IServ mail forwarding; Schulmanager Elternbrief emails) | Given school emails auto-forwarded to the app mailbox, when the IMAP poller runs, then each is parsed into an `entry` and marked read. |
| P0-3 | **Unified `entry` model** | Appointments, ideas, tasks, ingested messages, AI suggestions are all `entry` rows distinguished by `type`/`status`/`source`; ideas attach via self-referential parent. |
| P0-4 | **Manual create/edit** of appointments, reminders, idea-notes | She can CRUD entries and attach an idea to any existing entry from mobile web. |
| P0-5 | **Reminders → Web Push** | An entry with `remind_at` fires an Oban job that emits a VAPID Web Push at the right time; survives app restart. |
| P0-6 | **Chat with media** | Real-time messages over Phoenix Channels persisted to `messages`; images/voice-notes upload over HTTP via the storage abstraction. |
| P0-7 | **On-demand GPS share** | A user starts a time-boxed share; others see live position over Presence on an OSM map; the share auto-expires; nothing is written to Postgres. |
| P0-8 | **AI idea-suggestions (pure-LLM)** | For a suitable entry, the app proposes concrete ideas via the `LLMProvider` behaviour (default: Mistral EU API); suggestions land as `source: ai, status: proposed` and can be accepted/dismissed. |
| P0-9 | **Passwordless auth** | Magic-link login (`phx.gen.auth`) via SMTP through the German mailbox; long-lived sessions. |
| P0-10 | **Feed-health status view** | Read-only page showing per-source last-success time; a stale feed triggers a Web Push to the operator. |
| P0-11 | **TLS + PWA installability** | Served over HTTPS (Caddy + Let's Encrypt); installs to home screen; Web Push works on Android. |
| P0-12 | **Automated backup** | `launchd` + `restic` pull to the FileVault'd MacBook; restore procedure scripted and tested once. |

### Nice-to-Have (P1) — fast follows

- **P1-1 SearXNG grounding** for AI suggestions (current/specific/buyable results + real links).
- **P1-2 Pinterest/Instagram deep-links** appended to suggestions (browse, don't ingest).
- **P1-3 More-frequent media-only backup sync** when the Mac is at the desk (shrinks photo RPO).
- **P1-4 English UI toggle** for the partner.

### Future Considerations (P2) — design for, don't build

- **P2-1 `visibility` enum** (`family` | `owner_only`) + per-sibling privacy, if a teen wants it.
- **P2-2 Capacitor native shell** (2 Android phones) — only if reliable iOS push *or* background/continuous GPS becomes a real need.
- **P2-3 Local Ollama adapter** (Mistral open-weight) — one-swap sovereignty upgrade behind the existing behaviour.
- **P2-4 Minimal admin UI** — add member / paste feed URL / manage forwards, if she outgrows seed config.

## 7. Architecture & Key Technical Decisions

### 7.1 Stack
- **Runtime:** Elixir / Phoenix, self-hosted on a **Hetzner** VPS (EU). Chosen for realtime fit (Channels + Presence for chat & live GPS) and supervised GenServers for pollers.
- **Client:** a **single LiveView PWA** for all users (Android, iPhone, desktop). No app store, no second frontend. Justified because on-demand/foreground GPS is the only requirement a PWA can't do — and it doesn't need background location.
- **Reverse proxy:** **Caddy** (automatic Let's Encrypt TLS). TLS is mandatory — service workers, PWA install, and Web Push all require a secure context.

### 7.2 Data
- **One `entry` aggregate.** Nullable `when`/`remind_at`; `type`/`status`/`source` enums; self-referential `parent_id` for idea-attachments.
- **Persistence: plain Ecto CRUD** (read-your-writes simplicity for the UX), **plus a narrow `entry_revisions` change-log scoped only to feed-ingested entries** (to surface "moved Tue→Thu" rather than silent mutation). AI lifecycle rides the `status` enum. *Deliberately not event-sourced.*
- **Chat is its own `messages` table**, not `entry` rows (different volume/access pattern).
- **No `location_history` table, ever.**

### 7.3 Ingestion (two pipelines — **school apps confirmed 2026-07-05:** School 1 = **IServ**, School 2 = **Schulmanager Online**)
- **Calendars (iCal poller, both schools):** IServ exposes calendars as a read-only **ICS feed via Link-Freigabe** (no credentials needed; full CalDAV also available). Schulmanager offers a **per-user iCalendar subscription** from its Kalender module. One supervised GenServer polls both URLs. *No scraping, no RSS parser needed.*
- **Messages (email → IMAP poller, both schools):** IServ **is a mail server** — set an E-Mail-Umleitung from the guardian's IServ mailbox to the app mailbox. Schulmanager **emails Elternbriefe to parents natively** — a forward rule in her inbox covers it. Both feed the dedicated **German-provider mailbox** (mailbox.org/Posteo) that a GenServer **IMAP-polls**, parses, marks read. Generalizes free to any future email-sending school app.
- **Residual caveats:** (a) ~~Schulmanager Kalender module~~ **confirmed licensed 2026-07-05.** (b) In-app chat modules (IServ Messenger, Schulmanager Nachrichten) may not emit emails; if teachers use them, those stay in-app per §3.
- **Auth model:** connect via the **mother's guardian account** wherever possible — one credential set, entitled to all children's data, no minors' passwords stored.
- **Explicitly rejected:** reverse-engineered/internal-JSON scraping (account-lock risk, credential storage, ToS) and US inbound-email SaaS (sovereignty).

### 7.4 AI
- Behind an Elixir **`LLMProvider` behaviour** (`suggest(entry) :: {:ok, [suggestion]}`) — provider is swappable, so the choice is reversible and not lock-in.
- **Default adapter: Mistral EU managed API** (EU jurisdiction, data in-EU by default, no CLOUD Act, no model ops). Mistral chosen as the linchpin because its open-weight Apache-2.0 models let a **local Ollama adapter** run the *same model family* later (P2-3) with prompts/evals porting over.
- **v1 = pure-LLM knowledge** (great for evergreen ideas); **SearXNG open-web grounding designed-for-later** (P1-1). Pinterest/IG are **deep-link-out targets, never data sources** — their official APIs don't do public discovery and forbid storage; unofficial scrapers violate sovereignty + ToS.
- **Aleph Alpha** was the natural German-sovereign pick but is **off the default list** pending the Cohere (non-EU) acquisition announced 2026-04-24.

### 7.5 Notifications
- **Web Push (VAPID)**, one channel for reminders, new school entries, chat, and location requests. Self-hostable (no Google/Apple dev accounts). Android solid; iOS PWA push weaker — but that weak spot lands only on the partner, who doesn't need it.
- Scheduling via **Oban**. **Minimal payloads** ("New message") with detail fetched on open, to keep sensitive content out of the APNs/FCM relays.

### 7.6 Media & Storage
- Uploaded media on **local disk behind a thin storage abstraction**, served via an authenticated Plug controller — **never through the LiveView socket**. Sufficient at family scale; durability handled by backups. Swappable to Hetzner Object Storage if independent durability is later wanted.

### 7.7 Deployment
- Build image on the **M1 Mac** with `docker buildx --platform linux/amd64` (Elixir releases are **not** arch-portable), ship **registry-free** (`docker save | ssh | docker load`), run via **Docker Compose** on the box.
- **The `--platform linux/amd64` flag is load-bearing** — bake it into the deploy script.
- **Explicit migration step** post-load, pre-restart: `bin/app eval "Hearth.Release.migrate()"`.
- *No GitLab-CI / registry / Ansible* — disproportionate for one box.

### 7.8 Backup / DR
- **`launchd` LaunchAgent → `restic` pull over SSH** to the FileVault'd MacBook. `launchd` runs missed jobs on wake, which is what makes an intermittently-open laptop a viable automated target.
- **RPO is variable** = "whenever the lid was last open." Media (irreplaceable) is the casualty in a long gap → mitigate with more-frequent media-only sync (P1-3).
- DR = **restore onto a fresh box from backup, documented** — not a hot standby. **Restore must be tested once.** *Not Barman/PITR* — overkill at this write volume.

## 8. Privacy, Sovereignty & Safety

- **EU sovereignty is a hard requirement.** Everything self-hosted on EU infra you control; every third-party touchpoint is EU-resident (Hetzner, German mailbox, Mistral EU).
- **Two users are minors.** This drove: ephemeral-only + time-boxed GPS (auto-expiry as the key safety default), no location history, and minimal push payloads.
- **Scoped AI relaxation (conscious):** the suggestion feature sends entry data to Mistral (French third party). Mitigation: **DPA in place**, and send only the **minimum** a suggestion needs (event title + type), never the whole entry graph.
- **Backup holds an encrypted copy of family data** on the Mac → **FileVault on**, restic client-side encryption.
- **Flat visibility caveat:** a daughter's private note is visible to all in v1; the `visibility` enum (P2-1) is a couple hours' work if it ever chafes.

## 9. Success Metrics (family-scale, not business)

**Leading**
- Mother's usage: does she open Hearth instead of the individual school apps? (Target: school apps opened rarely within 2 weeks of go-live.)
- Ingestion liveness: both feeds show last-success < 24h, ≥ 95% of days.
- Reminder delivery: push arrives for ≥ 95% of scheduled reminders.

**Lagging**
- "Did we miss a school thing?" incidents trend to ~zero.
- The family actually uses chat/idea-notes unprompted (qualitative).
- Operator burden stays low: no manual intervention needed between school terms.

## 10. Deferred by Design (parking lot)

SearXNG grounding · Pinterest/IG deep-links · Capacitor native shell · local Ollama adapter · `visibility`/per-sibling privacy · admin UI · Hetzner Object Storage for media. *None are gaps — each is a conscious "later, if needed," and the architecture is shaped so adding them is cheap.*

## 11. Open Questions

- ~~Actual school apps~~ **Resolved 2026-07-05:** IServ (school 1) + Schulmanager Online (school 2, Robert-Bosch-Realschule Giengen). Both classified green — see §7.3. Guardian access confirmed implicitly (screenshots from parent view). **Schulmanager Kalender module confirmed licensed** — per-user iCal abo available.
- **[stakeholder] Extract the concrete feed handles:** Schulmanager → copy the abo address from the Kalender module; IServ → create the ICS Link-Freigabe and set the E-Mail-Umleitung. **Blocking for P0-1/P0-2, but trivially resolvable from her logins.**
- **[stakeholder] Younger daughter's device** (for push/GPS behavior). Non-blocking.
- **[self] Codename/real name** for the app. Non-blocking.
- **[self] Box RAM headroom** — already resolved to "build on Mac" (§7.7), so this no longer blocks; revisit only if the box is comfortably ≥ 8 GB and you'd prefer building on it.

## 12. Timeline / Suggested Phasing (solo, evening hours)

No hard deadline stated. Suggested build order that de-risks earliest:

1. **Spike ingestion first (throwaway).** Pull the IServ ICS Link-Freigabe + the Schulmanager iCal abo, and parse one forwarded school email, *before* building UI. (Since both apps are confirmed green, the risk here has dropped from "is this feasible at all" to mere extraction mechanics.)
2. **Skeleton:** Phoenix app, `entry`/`messages` schema, magic-link auth, Caddy+TLS, deploy script, restore-tested backup.
3. **Ingestion for real** (P0-1, P0-2) + feed-health view (P0-10).
4. **Manual entries + idea-attachments** (P0-3, P0-4) and the aggregated calendar view.
5. **Reminders + Web Push** (P0-5, P0-11).
6. **Chat + media** (P0-6).
7. **On-demand GPS** (P0-7).
8. **AI suggestions** (P0-8).
9. **Onboard the family** (seed config).
10. Fast-follows: SearXNG grounding, deep-links, English toggle.

## Appendix — Decisions Deliberately Right-Sized

The through-line of this design: five times the day-job stack offered an oversized hammer; each was set aside for the family-scale choice.

| Tempting (work-stack) | Chosen (family-scale) | Why |
|-----------------------|-----------------------|-----|
| Event sourcing / CQRS | Ecto CRUD + narrow change-log | 5 users, few writes/day; ES tax paid daily for payoffs never used |
| Spring Boot | Elixir/Phoenix | Realtime-dominant workload is BEAM's home turf |
| Keycloak | `phx.gen.auth` magic-link | Enterprise IdP for 5 known people is pure overhead |
| Barman PITR | `restic` nightly-ish pull | No need to recover to the second; nightly is fine |
| GitLab-CI + registry + Ansible | `buildx` → `docker save`/`load` → Compose | Ceremony with no payoff for one box |

*The one place the discipline pointed the other way: backups. "Manual, when I remember" is **under**-sized for irreplaceable photos → automate the pull.*
