# Restore Rehearsal Record

Story 1.5 AC2: prove `deploy/restore.sh` actually restores a real snapshot and
the app boots against it, before relying on the backup pipeline for real.

## Prerequisites

* `restic` installed on the operator's Mac (`brew install restic`).
* A restic repository already `restic init`'d (one-time, manual — see
  `deploy/README.md`), with `RESTIC_REPOSITORY`/`RESTIC_PASSWORD` in a
  `chmod 600` env file (default `~/.carwal-backup.env`).
* `CARWAL_HOST` reachable over passwordless SSH (key-based root/sudo user).
* `carwal:latest` image already built locally (`docker buildx build ... -t carwal:latest .`,
  same as `deploy/deploy.sh` — the restore rehearsal reuses it, does not rebuild).
* For the **local scratch mode** used in this rehearsal: a separate
  `~/.carwal-scratch/` directory with its own `.env.prod` / `.env.db`
  (dummy secrets are fine — it never talks to the real SMTP/VAPID
  providers) so `docker compose -p carwal-scratch` never touches the
  normal dev stack or the live VPS.

## What was run (2026-07-07, against `carwal.cloud`)

1. **Real backup**: `./deploy/backup.sh ~/.carwal-backup.env`
   * SSH'd to `root@carwal.cloud`, shipped `backup-remote.sh`, ran a fresh
     `pg_dump | gzip` on the live `carwal.cloud` Postgres (seed data: 3
     users), pruned dumps older than 7 days.
   * `~/carwal/media/` did not exist yet on the VPS (Subtask 1.2's
     "create it now" one-time step) — created manually via
     `ssh root@carwal.cloud "mkdir -p ~/carwal/media"` before the first
     successful run.
   * `rsync`'d the dump + (empty) media dir from the VPS into a local
     staging dir, then `restic backup` into the FileVault'd repo.
   * Result: snapshot `f50dbb29` — 2 new files, 5 new dirs, 6.397 KiB
     (5.521 KiB stored after restic dedup/compression).

2. **Restore rehearsal**: `./deploy/restore.sh ~/.carwal-backup.env`
   (local scratch mode — `SCRATCH_HOST` unset)
   * `restic restore latest` pulled the snapshot into
     `~/.carwal-restore-staging/` — 7 files/dirs, 3.426 KiB, under 1s.
   * Copied `compose.yml`, the restored dump, and the (empty) restored
     media dir into `~/.carwal-scratch/`.
   * Brought up `db` only (`docker compose -p carwal-scratch up -d --wait db`)
     — healthy in a few seconds.
   * Restored the dump via `gunzip -c ... | docker compose exec -T db psql`
     — full schema (`users`, `users_tokens`, `push_subscriptions`,
     `schema_migrations`) + data replayed cleanly.
   * Ran `CarWal.Release.migrate()` — `Migrations already up` (dump
     already included the latest schema).
   * Started `app` (no `caddy` — rehearsal doesn't need TLS/routing, just
     proof the app boots against restored data).
   * Health poll: two `000` responses while the app container was still
     booting (arm64 Mac running the `linux/amd64` image under emulation,
     same QEMU slowdown noted in `deploy/README.md`'s deploy record), then
     `200` — passed within the 120s timeout.
   * Login page smoke test: `GET /users/log-in` → `200`, page contains
     `Anmelden` / `Anmeldelink` (German login page renders).
   * Verified restored data directly: `select count(*) from users` → `3`,
     matching the 3 seeded family members on `carwal.cloud`.
   * Total rehearsal time: a few minutes, dominated by image
     pull/emulation warm-up, not by the restore steps themselves.
   * Torn down afterwards: `docker compose -p carwal-scratch down -v`.

## What was verified

| Check | Result |
| --- | --- |
| Fresh `pg_dump` from live VPS via `backup-remote.sh` | OK |
| `restic backup` (pull-based, from Mac) into FileVault'd repo | OK, snapshot `f50dbb29` |
| `restic restore latest` onto a scratch target | OK |
| Dump replay (`psql`) into a fresh Postgres container | OK, all tables + data present |
| App boots against restored data | OK, health check `200` |
| Login page renders | OK, German UI text present |
| Seeded user count matches source | OK, 3/3 |

## Known gaps / follow-ups

* **Media directory was empty for this rehearsal.** `CarWal.Storage`
  (Epic 4, AD-11) hasn't shipped yet, so there was no real media to
  restore — only the empty bind-mounted directory. **Re-run this
  rehearsal with real media once Epic 4 ships**, to prove large-file
  restore behavior, not just an empty directory.
  Also: **re-run once Epic 2/3 ship real family entries** (agenda
  items, chat, etc.) — this rehearsal only had the Story 1.2 seed data
  (3 user rows), not representative real-world data volume.
* **VPS `compose.yml` was not redeployed** with the new `media` bind
  mount during this rehearsal (only the media *directory* was created
  manually, per Subtask 1.2). A real `./deploy/deploy.sh` run is needed
  before the mount takes effect on `carwal.cloud` itself — tracked as a
  normal follow-up deploy, not blocking this story (the media dir is
  still empty either way).
* Remote scratch mode (`SCRATCH_HOST=user@host` instead of the local
  docker project used here) is implemented in `restore.sh` but not
  exercised in this rehearsal, since only the one VPS + this Mac were
  available. Both modes share the same restic-restore/psql/health-check
  logic — only the destination (ssh vs local docker) differs.
