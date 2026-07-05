# Reconciliation — draft vs. prd.md + addendum.md

Input: `docs/PRD-family-app.md` (Draft v1, 2026-07-05)
Compared against: `prd.md` and `addendum.md` in this directory.
Rule applied: only items absent from **both** files are listed. Hearth→CarWal rename and PRD/addendum split are intentional and not flagged.

## Verdict

Coverage is strong. All P0/P1/P2 requirements, non-goals, architecture decisions, sovereignty framing, and success metrics carried over. The losses are qualitative: the user-story voice and a handful of "why"/safety-expectation sentences that FR structure flattened.

## Gaps (present in draft, missing from both outputs)

### 1. User-story rationales — the "so that" clauses (draft §5)

The entire User Stories section was dissolved into FRs. The *what* survived; several *whys* did not:

- **Trust framing for feed health:** "I want to be sure the school feeds are still working **so I can trust the calendar**" and the operator's "fix ingestion **before anyone notices**." FR3 has mechanics only. The point — feed health exists to protect the mother's *trust* in the aggregated view, and stale-alerts exist so failures are invisible to the family — is the acceptance bar for G5, not just a status page.
- **Teen agency / consent framing for location:** "share my live location for a set time **when asked**, and have it stop automatically, **so I keep control**." FR8/NFR2 keep auto-expiry as a safety default, but drop the consent model: the share is *initiated by the child in response to a request*, framed as the teen keeping control — not a parent-side tracking switch. This shapes UX (request → child accepts → time-boxed share), not just data retention.
- Minor same-family losses: G1's "so she stops opening the individual school apps to stay informed" (survives only implicitly via the success metric); G4's "without her having to go hunting"; mother persona's "wants everything in one place **with minimal fuss**."

### 2. Flat-visibility expectation caveat (draft §8)

Draft states plainly: "**a daughter's private note is visible to all in v1**; the `visibility` enum (P2-1) is a couple hours' work if it ever chafes." PRD Non-Goals says "flat family visibility, designed to be cheap to add later" but omits the concrete consequence — a minor's note has no privacy from the family — which is an expectation to set at onboarding, and the "couple hours' work" cost estimate that justifies deferring it.

### 3. Auth email rides the sovereign mailbox (draft P0-9)

Draft: magic-link login "via SMTP **through the German mailbox**." FR10 says "magic-link login via email"; the addendum's German-mailbox detail is scoped to *ingestion* only. The sovereignty constraint (NFR1: every third-party touchpoint EU-resident) implicitly covers it, but the draft's explicit decision — outbound auth mail uses the same German provider, no US transactional-email SaaS — is stated nowhere.

### 4. "Deferred by design" framing (draft §10)

The parking-lot preamble — "**None are gaps** — each is a conscious 'later, if needed,' and the architecture is shaped so adding them is cheap" — is dropped. The P2 section header "Designed-for, Not Built" gestures at it, but the explicit claim that deferrals are decisions (not omissions) is the defense against a future reviewer re-litigating scope.

### 5. Small factual residue (low priority)

- **Guardian access evidence:** "confirmed implicitly (screenshots from parent view)" (draft §11) — addendum states the auth model but not that guardian access is already verified.
- **Timeline framing:** "No hard deadline stated. Suggested build order **that de-risks earliest**" + the note that spike risk has dropped from "feasible at all?" to "mere extraction mechanics" (draft §12.1). The phasing steps survived; the de-risking rationale ordering them did not.
- **i18n mechanism:** Phoenix `gettext` named in draft §4; NFR3/addendum have locale requirements but not the mechanism (arguably fine — tech detail — but the addendum is where it would live and it isn't there).
- **Resolved open questions** ([self] codename — resolved by CarWal rename; [self] box RAM — resolved to "build on Mac") were dropped rather than recorded as resolved. Harmless, but the RAM resolution's "revisit only if the box is ≥ 8 GB" condition is lost.
- Problem-statement color: "apps that were never meant to talk to each other" (prose only, no content loss).

## Not gaps (checked, intentionally placed or covered)

Right-sizing appendix → addendum table · rejected alternatives (scraping, US SaaS, Aleph Alpha) → addendum · restic/launchd/RPO → addendum · iOS-push weakness → addendum · "survives restart", "marked read", "tested once", "invite-by-hand", DPA + title-and-type-only minimization → all present in prd.md. prd.md additions (counter-metrics, FR7 assumptions, Landscape) are net-new, not reconciliation issues.
