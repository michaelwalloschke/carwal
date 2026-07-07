---
baseline_commit: 6589bd526bc4bbaea1e12d21622a2a9e6d1a29ef
---

# Story 1.5: Backup + First Restore Rehearsal

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the operator,
I want automated encrypted pull-backups and a rehearsed restore,
so that family data (especially media) survives the loss of the box.

## Acceptance Criteria

1. **Given** the deployed VPS and the FileVault'd MacBook with restic + SSH access (Wayfinder prerequisite: backup target ready), **when** the launchd LaunchAgent fires (including catch-up after wake), **then** restic pulls an encrypted snapshot of the Postgres dump and media directory to the MacBook.
2. **Given** an existing snapshot with seed data, **when** `deploy/restore.sh` is run against a scratch box/VM, **then** the app boots against the restored data and the rehearsal result is documented in `deploy/RESTORE.md`, and a re-test with real data is flagged for after go-live.

## Tasks / Subtasks

- [x] Task 1: Remote pg_dump + media staging script on the VPS (AC: 1)
  - [x] Subtask 1.1: `deploy/backup-remote.sh` (runs on VPS via SSH, or SSH'd into from the launchd job): `docker compose exec -T db pg_dump -U carwal carwal | gzip > ~/carwal/backups/carwal-$(date +%Y%m%d-%H%M%S).sql.gz`, prune dumps older than N days (keep last 7 locally — restic keeps the real history).
  - [x] Subtask 1.2: Create `~/carwal/media/` directory on the VPS now (empty — no Storage adapter exists yet, ships in Epic 4/AD-11) so the backup target exists from day one and Epic 4 needs zero backup-side changes when it starts writing there. Bind-mount it into the `app` service in `compose.yml` at a path `CarWal.Storage`'s future local-disk adapter will use (document the convention; do not implement the adapter).
- [x] Task 2: launchd LaunchAgent on the MacBook (AC: 1)
  - [x] Subtask 2.1: `deploy/com.carwal.backup.plist` — `StartCalendarInterval` (e.g. daily), `RunAtLoad: false`, catches up after sleep/wake because launchd re-evaluates missed calendar intervals on wake (unlike `cron`).
  - [x] Subtask 2.2: `deploy/backup.sh` (runs on the Mac): SSH to VPS to trigger `backup-remote.sh` (dump + prune), then `restic backup` over SSH (`sftp:` or `rest:` backend, whichever the operator's restic repo uses) pulling `~/carwal/backups/` (dumps) and `~/carwal/media/` from the VPS into the restic repo on the FileVault'd volume. Pull-based: initiated from the Mac, not the VPS, per spine.
  - [x] Subtask 2.3: `restic init` (one-time, operator does this manually per README instructions — do not script repo creation with a hardcoded password) and `RESTIC_PASSWORD`/`RESTIC_REPOSITORY` sourced from a `chmod 600` env file on the Mac, never committed.
- [x] Task 3: Restore script (AC: 2)
  - [x] Subtask 3.1: `deploy/restore.sh` — target a scratch box/VM (fresh Docker host, no existing `~/carwal/`): `restic restore latest --target <path>` for the dump + media snapshot, `scp`/copy `compose.yml` + `caddy/` there, bring up `db` only, `gunzip -c <dump>.sql.gz | docker compose exec -T db psql -U carwal carwal` (or `pg_restore` if the dump is custom-format — plain SQL dump via Subtask 1.1 uses `psql`), restore `~/carwal/media/` from the snapshot, then `docker compose up -d --wait db` → migrate → `docker compose up -d`.
  - [x] Subtask 3.2: Health-check + login smoke test against the scratch box (reuse the `deploy.sh` health-poll pattern) to confirm the app boots against restored data.
- [x] Task 4: Rehearsal + documentation (AC: 2)
  - [x] Subtask 4.1: Run one real backup (`deploy/backup.sh`) against the deployed `carwal.cloud` seed data, then run `deploy/restore.sh` against a scratch VM/box.
  - [x] Subtask 4.2: Write `deploy/RESTORE.md`: prerequisites, exact commands run, timing, what was verified (app boots, login page renders, seeded members present), and a flagged TODO to re-run this rehearsal with real family data once Epic 2/3 content exists (per AC2).
  - [x] Subtask 4.3: Document the full backup env contract (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, restic backend choice, launchd install steps) in `deploy/README.md`, following the existing `.env.prod` contract style.

## Dev Notes

- **Nothing here touches app code.** Every file in this story lives under `deploy/` (ops scripts, launchd plist, docs). No `lib/`, no `assets/`, no migrations, no mix deps. This is the first story of the epic that is pure ops — do not add Elixir mix tasks or Oban jobs for this (Oban lands in Epic 3 for reminders/digest; do not pull it forward here).
- **Data lives in a Docker named volume (`pgdata`), not a bind mount** [Source: `deploy/compose.yml`]. Do not `restic backup` the volume directly — use `pg_dump` inside the running `db` container (Task 1) for a portable, version-independent snapshot, matching the AC's "Postgres dump" wording exactly.
- **No media exists yet.** `CarWal.Storage` (AD-11, local-disk adapter) is Epic 4 scope — not built. This story still must back up a "media directory" per AC1/spine (FR12). Resolve by creating the directory now (Task 1.2) and bind-mounting it, so Epic 4 only needs to start writing files — zero backup-script changes later. Do not build the Storage behaviour/Plug controller here.
- **Pull-based, not push-based.** Spine: "restic pull over SSH to FileVault'd MacBook via launchd." The trigger and the restic repo both live on the Mac; the VPS only stages the dump + serves files over SSH. Do not run restic on the VPS or push from VPS→Mac.
- **restic repo init is a one-time manual operator step**, like `.env.prod` creation in Story 1.3 — do not script `restic init` with a baked-in password. Document it in the README exactly like the 1.3 first-run steps.
- **launchd, not cron.** macOS-native; `StartCalendarInterval` + missed-run catch-up on wake is the reason it's specified over cron (spine: "including catch-up after wake"). `launchctl load -w ~/Library/LaunchAgents/com.carwal.backup.plist` is the install step — document, don't automate (no launchctl calls belong in a repo script since paths are per-operator-machine).
- **Reuse `deploy.sh` conventions**: `set -euo pipefail`, SSH-based remote commands quoted per the existing pattern, `chmod 600` for any new secret file, health-poll loop style for Task 3.2 (mirror `deploy.sh`'s `http_code` polling, don't reinvent). Deferred hardening from 1.3 reviews (`ConnectTimeout`/`ServerAliveInterval` on SSH, retag-on-success for transfers) is optional here — call out but don't block on it; flag any new instance to `deferred-work.md` instead of implementing speculatively.
- **Errors convention N/A** — this is shell, not Elixir; `set -euo pipefail` + explicit `|| { echo ...; exit 1; }` guards (mirror `deploy.sh`'s `.env.prod` existence check) is the equivalent discipline.
- **Restore target is a scratch box/VM, never the live VPS.** AC2 says "scratch box/VM" explicitly — do not restore over `carwal.cloud`.
- **Real-data re-test is out of scope for this story.** AC2's final clause ("a re-test with real data is flagged for after go-live") is a documentation flag in `RESTORE.md`, not a task to perform now — Epic 2/3 haven't shipped, so there is no real data yet.

### Project Structure Notes

- New: `deploy/backup.sh` (Mac-side trigger), `deploy/backup-remote.sh` (VPS-side dump), `deploy/restore.sh`, `deploy/com.carwal.backup.plist`, `deploy/RESTORE.md`.
- Modified: `deploy/compose.yml` (add `~/carwal/media` bind mount to `app`), `deploy/README.md` (restic/backup env contract + launchd install steps, append after the existing `.env.prod` section).
- NOT in this story: any `lib/`, `assets/`, `config/`, `mix.exs`, or migration changes; `CarWal.Storage`/media upload implementation (Epic 4); Oban (Epic 3); any change to `deploy.sh` itself (deploy and backup are separate concerns — don't merge them).

### References

- Epic + ACs: [Source: _bmad-output/planning-artifacts/epics.md#Story 1.5]
- FR12 (automated encrypted backup, scripted+tested restore), NFR5 (data durability, encrypted at rest, media is the priority asset): [Source: epics.md#Functional/NonFunctional Requirements]
- Deployment/backup invariant — restic pull over SSH via launchd, restore script in `deploy/`, tested once against a scratch box: [Source: _bmad-output/planning-artifacts/architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md line 162, FR-mapping table line 178]
- AD-11 (media via authenticated Plug + Storage behaviour, local-disk adapter, not yet built): [Source: ARCHITECTURE-SPINE.md#AD-11]
- Current deploy topology (named `pgdata` volume, no media volume, `.env.prod`/`.env.db` split, health-poll pattern, SSH-based `deploy.sh` conventions): [Source: deploy/compose.yml, deploy/deploy.sh, deploy/README.md]
- Story 1.3 first-run precedent for documenting one-time manual operator setup steps (README "First Deploy Record" section): [Source: _bmad-output/implementation-artifacts/1-3-deploy-to-the-vps-over-https.md]
- Story 1.4 precedent for scoping a story strictly to its files and deferring out-of-scope hardening to `deferred-work.md`: [Source: _bmad-output/implementation-artifacts/1-4-pwa-install-push-foundation.md]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5 (bmad-dev-story workflow)

### Debug Log References

- Real rehearsal run 2026-07-07: `deploy/backup.sh` against `carwal.cloud` (restic snapshot `f50dbb29`), `deploy/restore.sh` against a local scratch docker compose project (`carwal-scratch`) on the operator's Mac. Full record in `deploy/RESTORE.md`.

### Completion Notes List

- Implemented `deploy/backup-remote.sh`, `deploy/backup.sh`, `deploy/restore.sh`, `deploy/com.carwal.backup.plist` per Dev Notes conventions (`set -euo pipefail`, `chmod 600` guards, `deploy.sh`-style health polling).
- `restore.sh` supports two scratch-target modes: local docker compose project (`SCRATCH_HOST` unset — used for this rehearsal, no second host available) and remote SSH host (`SCRATCH_HOST=user@host` — implemented but not exercised, only one VPS available).
- Restore skips starting `caddy` — AC2 only requires the app to boot against restored data and the login page to render, not TLS/routing, so health/login checks run via `docker compose exec app curl ...` against the app container directly.
- Added `deploy/test-backup-scripts.sh`: syntax check (`bash -n`) + missing-env-file guard checks for all three scripts (no real infra needed, run manually).
- Ran the real rehearsal end-to-end with user-provided VPS access (`root@carwal.cloud`, passwordless SSH): installed `restic` locally, `restic init`'d a new FileVault'd repo, ran a real `pg_dump`-based backup, then a full restore into a local scratch stack — health check `200`, login page renders German text, restored user count (3) matches the seeded `carwal.cloud` data. Full record: `deploy/RESTORE.md`.
- One operator action needed mid-rehearsal: `~/carwal/media/` didn't exist yet on the VPS (Subtask 1.2's "create it now" step) — created manually via `ssh root@carwal.cloud "mkdir -p ~/carwal/media"`. Documented in `deploy/README.md`'s one-time setup steps.
- Flagged in `deploy/RESTORE.md`: the VPS `compose.yml` was not redeployed with the new media bind mount during this rehearsal (no data at risk since media is still empty) — a normal follow-up `deploy.sh` run, not a story blocker.

### File List

- `deploy/backup-remote.sh` (new)
- `deploy/backup.sh` (new)
- `deploy/restore.sh` (new)
- `deploy/com.carwal.backup.plist` (new)
- `deploy/RESTORE.md` (new)
- `deploy/test-backup-scripts.sh` (new)
- `deploy/compose.yml` (modified — `media` bind mount on `app`)
- `deploy/README.md` (modified — Backup & Restore section appended)

## Change Log

- 2026-07-07: Story 1.5 created from epics + architecture spine. Status → ready-for-dev.
- 2026-07-07: Implemented Tasks 1-4 (backup/restore scripts, launchd plist, docs), ran real backup + restore rehearsal against `carwal.cloud`. Status → review.
