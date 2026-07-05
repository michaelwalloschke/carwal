# PRD Quality Review — CarWal (Family Coordination App)

- **PRD:** `_bmad-output/planning-artifacts/prds/prd-carwal-2026-07-05/prd.md` (+ `addendum.md`)
- **Rubric:** `.claude/skills/bmad-prd/assets/prd-validation-checklist.md`
- **Stakes calibration:** hobby/solo — private app for 5 known family members, one evening-hours developer. Rigor bar is light; substance bar still applies. Reviewed accordingly.

## Overall verdict

A genuinely good PRD for its stakes: it has a real thesis (aggregate two German school apps into one family surface, for one specific mother), Non-Goals that do actual work, product-specific NFRs, and counter-metrics that show self-awareness ("if pushes get muted, volume/defaults are wrong"). The addendum correctly quarantines architecture depth out of the PRD. The main risk is done-ness fuzziness in a few FRs — "stale," "suitable entry," "at the right time" — which the solo developer will resolve implicitly, but which cost nothing to pin down now.

## Decision-readiness — strong

Decisions are stated as decisions, with what was given up named. The Non-Goals section carries rationale, not just exclusions ("a queryable track of two minors is a liability"; "infeasible via legitimate channels"). NFR1 explicitly names its "one conscious relaxation" (AI suggestions send title + type to an EU LLM provider) rather than pretending the sovereignty constraint is absolute. The addendum's "Right-sized decisions" table (event sourcing vs. CRUD, Keycloak vs. magic-link, etc.) is a model rationale record, including the one place discipline reversed direction (backups automated because "manual, when I remember" is *under*-sized). Open Questions are actually open, tagged `[stakeholder]`, with blocking status stated.

No findings.

## Substance over theater — strong

No persona theater: users are listed in one paragraph with exactly the attributes that drive decisions (Android vs. iPhone → PWA push story; non-technical primary user → passwordless auth; minor daughters → NFR2). NFRs are product-specific with real content — NFR2 ties minors' safety to concrete mechanisms (auto-expiry, minimal push payloads), not "the system must be secure." The Landscape digest in the addendum is earned research (named comparables with specific disqualifiers), not a differentiation section written to fill a template. Goal G5 ("It doesn't rot") is the opposite of vision theater — it could not swap into another PRD.

No findings.

## Strategic coherence — strong

Clear thesis: the walled-garden school apps are the problem, aggregation-plus-her-own-layer is the bet, and the mother is the user the app exists for. Prioritization follows the thesis — the Suggested Phasing puts a throwaway ingestion spike *first*, before any UI, which is exactly where the project risk lives. Success Metrics validate the thesis rather than measuring activity ("Mother opens CarWal instead of the school apps," "missed school thing incidents trend to ~zero" — not DAU). Counter-metrics are present and pointed (notification fatigue, operator time). MVP scope kind is coherent: problem-solving slice with the family layer as connective tissue.

No findings.

## Done-ness clarity — adequate

Most FRs carry a testable consequence: FR1's diff-and-flag behavior ("moved Tue→Thu, never silently mutated"), FR6's "scheduling survives app restarts," FR7's `[ASSUMPTION]`-tagged caps, FR8's auto-expire/nothing-persisted, FR12's "restore procedure is scripted and tested once." That is better than most PRDs at any stakes. But a handful of load-bearing words are still adjectives, and this is the dimension the rubric says to be unforgiving on — even for a solo builder, these are the spots where "done" will be decided ad hoc at midnight.

### Findings

- **medium** Stale threshold undefined (§ FR3) — "A stale feed triggers a push notification" — stale after how long? The Success Metrics imply < 24 h last-success is healthy, but FR3 never binds to it. *Fix:* one clause: "stale = no successful poll for 24 h (aligned with SM)".
- **medium** "Suitable entry" undefined for AI suggestions (§ FR9) — "For a suitable entry, the app proposes concrete ideas." What triggers a suggestion — entry type? keyword? every birthday-typed event? This decides both the UX volume and the counter-metric (notification fatigue). *Fix:* name the trigger, e.g. "entries of type appointment whose title matches occasion heuristics (birthday, party, school event), on creation/ingestion."
- **low** Reminder timing tolerance unstated (§ FR6) — "fires ... at the right time." Within a minute? Five? Matters only for choosing the scheduler granularity, but it's a two-word fix. *Fix:* "within ±1 min of remind-at."
- **low** Push-delivery SM has no measurement mechanism (§ Success Metrics) — "Push arrives for ≥ 95 % of scheduled reminders" — feeds get a health view (FR3), but nothing in the PRD counts reminder delivery. At 5 users this will be measured by complaint, which is honestly fine — just say so or drop the false precision. *Fix:* either note "measured informally" or reuse the feed-health page for a sent-count.

## Scope honesty — strong

Omissions are explicit and layered: Non-Goals (v1) with reasons, Fast Follows (P1), and a "Designed-for, Not Built (P2)" section that names what the design must keep cheap without building it — an unusually honest construct. The single `[ASSUMPTION]` tag (FR7: retention, 25 MB cap, media types) marks a real inference. Open Questions carry blocking status. De-scoping is done aloud ("full message *bodies* from closed in-app channels are out — surface the notification, deep-link for detail"), and the addendum records the residual caveat (in-app chat modules may never emit emails). Open-items density — 2 Open Questions, 1 assumption — is right for the stakes.

### Findings

- **low** No Assumptions Index (§ end of PRD) — one inline `[ASSUMPTION]` (FR7) with no index at the end. With a single entry this is nearly moot, but the FR7 assumption bundles three separable decisions (retention, size cap, media types) that could each be silently disagreed with. *Fix:* three-line index at the end, or split the tag.

## Downstream usability — adequate

This PRD feeds architecture (the addendum is explicitly structured as `→ architecture` / `→ ops` handoffs, and the section refs resolve). FR/NFR/G IDs are contiguous and unique (FR1–FR12, NFR1–5, G1–5); FR-to-Goal traceability is done via section headers ("Aggregation (G1, G5)"), which is lightweight and works. The `entry` concept is defined once (FR4) and used consistently in PRD and addendum. There is no Glossary, and domain nouns like "idea-note" / "idea" / "idea-attachment" drift slightly across FR4/FR5/G2 — but with one author who is also the sole downstream consumer, this costs little. Said plainly: for this PRD's single-developer chain, this dimension matters less, and it clears the bar it needs to.

### Findings

- **low** No Glossary; minor noun drift (§ FR4/FR5, G2, Phasing) — "idea-notes," "ideas," "idea-attachments" refer to the same `entry` type by three names. *Fix:* either a 4-line glossary (entry, idea, feed, source) or pick one term.

## Shape fit — strong

The shape is right and deliberately so. Hobby/solo capability-spec form: no User Journeys (correct — one primary user whose journey *is* the Context paragraph), operational rather than vanity metrics, a Suggested Phasing section that respects evening-hours reality (spike the risky thing first, throwaway). The PRD/addendum split is the standout: stack choices, data model, deploy mechanics, and DR live in the addendum tagged for downstream, keeping the PRD itself readable as requirements. Nothing is over-formalized; nothing load-bearing is under-formalized.

No findings.

## Mechanical notes

- Assumptions Index roundtrip: 1 inline `[ASSUMPTION]` (FR7), no index — see Scope honesty finding.
- ID continuity: FR1–FR12, NFR1–NFR5, G1–G5 all contiguous, no duplicates. FR→Goal cross-refs in section headers all resolve.
- No `[NOTE FOR PM]` callouts anywhere — acceptable at these stakes (the PM, developer, and operator are the same person), but noted.
- Addendum § refs point at `docs/PRD-family-app.md` (the source draft); readers of the addendum alone can't resolve them. Harmless, but a one-line note saying refs are to the source draft's numbering would help.
- Glossary absent — see Downstream usability finding.
- Frontmatter status is `draft` while the doc reads finished; bump to `final` when the two `[stakeholder]` questions close.
