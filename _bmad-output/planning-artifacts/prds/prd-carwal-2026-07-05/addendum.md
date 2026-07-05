# Addendum — CarWal PRD

Depth from the source draft (`docs/PRD-family-app.md`) that belongs downstream (architecture, solution design) rather than in the PRD itself. Section refs (§) point at that draft.

## Stack & Architecture (→ architecture)

- **Runtime:** Elixir / Phoenix on a Hetzner VPS (EU). Chosen for the realtime-dominant workload: Channels + Presence for chat & live GPS, supervised GenServers for pollers.
- **Client:** single LiveView PWA for all users; no second frontend, no app store. Background GPS is the only thing a PWA can't do — and background isn't required; on-demand/foreground GPS works.
- **Reverse proxy:** Caddy with automatic Let's Encrypt. TLS is load-bearing: service workers, PWA install, and Web Push all require a secure context.

## Data model (→ architecture)

- One `entry` aggregate: nullable `when`/`remind_at`; `type`/`status`/`source` enums; self-referential `parent_id` for idea-attachments.
- Plain Ecto CRUD (read-your-writes simplicity), **plus** a narrow `entry_revisions` change-log scoped only to feed-ingested entries — surfaces "moved Tue→Thu" instead of silent mutation. Deliberately **not** event-sourced.
- Chat in its own `messages` table (different volume/access pattern than `entry`).
- **No `location_history` table, ever.**

## Ingestion mechanics (→ architecture; schools confirmed 2026-07-05)

- School 1 = **IServ**, School 2 = **Schulmanager Online** (Robert-Bosch-Realschule Giengen); Schulmanager Kalender module confirmed licensed.
- **Calendars:** IServ ICS via Link-Freigabe (no credentials; CalDAV also available); Schulmanager per-user iCal subscription. One supervised GenServer polls both URLs. No scraping.
- **Messages:** IServ is a mail server → E-Mail-Umleitung to the app mailbox; Schulmanager emails Elternbriefe natively → inbox forward rule. Dedicated German-provider mailbox (mailbox.org/Posteo), IMAP-polled by a GenServer, parsed, marked read.
- **Auth model:** mother's guardian account wherever possible — one credential set, entitled to all children's data, no minors' passwords stored.
- **Rejected:** reverse-engineered/internal-JSON scraping (account-lock risk, credential storage, ToS) and US inbound-email SaaS (sovereignty).
- **Residual caveat:** in-app chat modules (IServ Messenger, Schulmanager Nachrichten) may not emit emails; if teachers use them, those stay in-app per Non-Goals.

## AI provider (→ architecture)

- Elixir `LLMProvider` behaviour (`suggest(entry) :: {:ok, [suggestion]}`) — swappable, reversible.
- **Default: Mistral EU managed API** (EU jurisdiction, in-EU data, no CLOUD Act). Linchpin rationale: Apache-2.0 open weights allow a later local Ollama adapter running the *same model family* (P2), prompts/evals port over.
- v1 = pure-LLM knowledge; SearXNG open-web grounding designed-for-later (P1). Pinterest/IG are deep-link-out targets, never data sources (APIs forbid storage/discovery; scrapers violate sovereignty + ToS).
- **Aleph Alpha** off the default list pending the Cohere (non-EU) acquisition announced 2026-04-24.
- Suggestions land as `source: ai, status: proposed`; lifecycle rides the `status` enum.

## Notifications (→ architecture)

- Web Push (VAPID), one channel for reminders, school entries, chat, location requests. Self-hostable, no Google/Apple dev accounts. Android solid; iOS PWA push weaker — lands only on the partner, who doesn't need it.
- Scheduling via Oban; jobs survive restarts (FR6).

## Media & storage (→ architecture)

- Local disk behind a thin storage abstraction, served via an authenticated Plug controller — never through the LiveView socket. Swappable to Hetzner Object Storage if independent durability is wanted later.

## Deployment (→ ops)

- Build on the M1 Mac with `docker buildx --platform linux/amd64` (Elixir releases are **not** arch-portable — the flag is load-bearing; bake it into the deploy script). Ship registry-free: `docker save | ssh | docker load`; run via Docker Compose.
- Explicit migration step post-load, pre-restart: `bin/app eval "CarWal.Release.migrate()"`.
- No GitLab-CI / registry / Ansible — disproportionate for one box.

## Backup / DR (→ ops)

- `launchd` LaunchAgent → `restic` pull over SSH to the FileVault'd MacBook; `launchd` runs missed jobs on wake, which makes an intermittently-open laptop viable.
- RPO is variable ("whenever the lid was last open"); media is the casualty in a long gap → mitigate with more-frequent media-only sync (P1).
- DR = documented restore onto a fresh box, tested once. Not Barman/PITR — overkill at this write volume.

## Right-sized decisions (rationale record)

| Tempting (work-stack) | Chosen (family-scale) | Why |
|---|---|---|
| Event sourcing / CQRS | Ecto CRUD + narrow change-log | 5 users, few writes/day; ES tax paid daily for payoffs never used |
| Spring Boot | Elixir/Phoenix | Realtime-dominant workload is BEAM's home turf |
| Keycloak | `phx.gen.auth` magic-link | Enterprise IdP for 5 known people is pure overhead |
| Barman PITR | `restic` nightly-ish pull | No need to recover to the second |
| GitLab-CI + registry + Ansible | `buildx` → `docker save/load` → Compose | Ceremony with no payoff for one box |

The one place discipline pointed the other way: backups — "manual, when I remember" is **under**-sized for irreplaceable photos → automate the pull.

## Landscape (research digest, 2026-07-05)

- **Comparables:** Cozi (US hub, dated, ads, US servers) · FamilyWall (feature-rich, subscription-gated, no school integrations) · TimeTree (shared calendars + per-event chat, JP servers, no DPA) · Google Family Calendar (free, good iCal, no family-hub features, US residency) · Klender (NL, privacy-forward) · Kalender.digital / Proton Calendar (GDPR-safe, generic).
- **School-app aggregation:** no product pulls IServ / Schulmanager / Sdui / Untis into a family calendar. Building blocks exist (WebUntis + Schulmanager iCal subscriptions, IServ calendar module), but nobody ships "school apps → family calendar". Genuine gap — validates the project without implying productization.
- **Self-hosted niche:** OpenFamily, Oikos (closest concept: CalDAV + ICS subscriptions), HomeHub, Nextcloud Calendar as DIY base. All hobby/early-stage; none do email-based school ingestion.
