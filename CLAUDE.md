# CarWal

Private family coordination app (one household — 4 people, 3 login-capable; a 9-year-old is tracked but has no login): Elixir/Phoenix LiveView PWA aggregating two German school apps (IServ, Schulmanager) via iCal + email. Planning artifacts live in `_bmad-output/` (PRD, architecture spine, epics); binding architecture invariants: `_bmad-output/planning-artifacts/architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md`. Coding standards + Elixir/Phoenix/LiveView conventions: `AGENTS.md`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (michaelwalloschke/carwal, `gh` CLI); external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
