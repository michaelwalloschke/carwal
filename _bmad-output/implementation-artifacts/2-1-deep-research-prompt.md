# Deep Research Prompt: IServ + Schulmanager Online Ingestion Unknowns

## Objective

CarWal is a private family coordination app aggregating two German school platforms — **IServ** (walled-garden school server software) and **Schulmanager Online** (SaaS school management platform) — into one family calendar. Before writing production ingestion code (Story 2.1: Throwaway Ingestion Spike), we need a deep, source-verified understanding of both platforms' calendar-export and mail-forwarding mechanisms, their quirks, and their stability as integration surfaces. Ground every claim in a primary source (official docs, official help centers, or first-party school IT documentation) — no speculation, no uncredited claims.

## Background / Context

- Stack: Elixir/Phoenix. Calendar parsing via the `ical` hex package (`~> 2.0`, `ICal.from_ics/1`, `ICal.Recurrence.from_ics/1` + `.stream/2`). Mail polling via `yugo` (`~> 1.0`, IMAP client, `Yugo.Client` + `Yugo.subscribe/2` + `Yugo.Filter`).
- IServ: mother's guardian account exposes an ICS "Link-Freigabe" (read-only share link) for the school calendar, and a mail-forwarding setting that redirects IServ-internal mail (Elternbriefe) to CarWal's dedicated app mailbox.
- Schulmanager Online: mother's guardian account exposes an "iCal-Abo" (subscription URL) for school appointments.
- Architecture invariants that constrain how we can use this data: ingestion is idempotent, keyed on `(source, external_uid, occurrence_date)` for calendar / `(source, external_uid)` = Message-ID for mail; recurring events are materialized as flat rows over a rolling ~14-month horizon; moved/cancelled events are diffed and flagged, never silently mutated or deleted; no scraping, no credential storage for the school apps themselves (feed URLs and forwarded mail are the only integration surface, on purpose — see NFR1 EU sovereignty, no third-party API calls beyond the feed/mailbox).
- This research feeds Story 2.1 (spike, already scoped) and the real pollers in Stories 2.3 (iCal poller) and 2.4 (email poller with sender whitelist).

## Research Questions

### A. Schulmanager Online — iCal feed

1. What is the exact, current UI path (2026) for a *parent/guardian* account to generate the iCal subscription URL? Has this changed recently, or is there a per-child vs. per-family distinction in the URL?
2. Does the iCal feed URL contain an embedded, unguessable token (capability URL) or is it tied to session/account auth? What happens if the parent regenerates it — does the old URL keep working?
3. What calendar item types appear in the feed (homework/exam dates, school-wide events, class-specific events, teacher absence notices)? Any known gaps (items visible in the Schulmanager UI but NOT exported to iCal)?
4. RRULE / recurrence: does Schulmanager emit RRULE-based recurring events, or does it always emit pre-expanded single VEVENTs? Any known malformed RRULE cases reported by other integrators?
5. Timezone handling: is VEVENT `DTSTART`/`DTEND` emitted as UTC, floating time, or with an embedded `VTIMEZONE` block? Known DST-transition bugs?
6. UID stability: is each VEVENT's `UID` stable across polls (safe to use as `external_uid`), or does it change on edit/regeneration?
7. Polling etiquette: any documented or community-observed rate limit, caching header (`ETag`/`Last-Modified`), or terms-of-service constraint on automated polling frequency for the iCal feed specifically (not the general Schulmanager API)?
8. Known encoding issues (umlauts, special characters in event titles) reported by third-party integrators.

### B. IServ — calendar Link-Freigabe (ICS)

1. Exact current UI path (2026) for a parent account to create a Link-Freigabe for a specific calendar, and the distinction between "sichtbare Termine" / "alle Termine" / vertrauliche/private event handling in the exported feed (per doku.iserv.de/modules/calendar/).
2. Is the Link-Freigabe URL capability-based (secret token in URL, no further auth) or does it require periodic re-authentication? Expiry behavior — do these links expire or need manual renewal?
3. RRULE support and recurrence expansion behavior — same questions as Schulmanager (A4).
4. Confidential/private event handling: the docs mention "vertrauliche Termine werden anonymisiert veröffentlicht" — what does the anonymized VEVENT actually contain (empty SUMMARY? placeholder text?)? This matters for not creating garbage/duplicate entries.
5. UID stability across IServ software version upgrades (IServ is self-hosted per-school; different schools may run different IServ versions with behavioral differences).
6. Any documented differences in Link-Freigabe behavior between IServ versions currently in wide deployment (IServ is actively versioned software, not a fixed SaaS product).

### C. IServ — mail forwarding (Weiterleitung)

1. Exact current UI path (2026) for setting up inbound mail redirection to an external address (doku confirms: E-Mail → Einstellungen → "Eingehende Mails zu folgender Adresse umleiten").
2. Does IServ preserve original headers (`From`, `Message-ID`, `Date`) on forwarded mail, or does it rewrite/wrap the message (e.g. as an attachment, or via SRS/envelope rewriting that changes the effective `From`)? This is critical for CarWal's sender whitelist (Story 2.4 keys on sender domain) and idempotency key (Message-ID).
3. Is there a per-school-admin setting that can disable/restrict forwarding for guardian accounts specifically (the earlier search noted "Ob Weiterleitungen möglich sind, hängt von den IServ-Einstellungen Ihrer Schule ab")? What's the fallback if the school has disabled it (alternative: IMAP polling of the IServ mailbox directly instead of forwarding)?
4. "Kopie auf Server behalten" option — implications for CarWal's IMAP poller if enabled (would CarWal ever poll the IServ mailbox directly, or is forwarding-to-external-mailbox the only supported path)?
5. Typical Elternbrief mail structure from IServ-based schools: plain text vs. HTML body, common attachment patterns (PDFs), any known multipart-parsing gotchas relevant to `yugo`'s body extraction.

### D. Cross-cutting / integration risk

1. Are there known outage patterns or maintenance windows for either platform that a feed-health monitor (Story 2.5) should account for (e.g. nightly maintenance windows that cause transient 5xx/timeout)?
2. Any GDPR/data-protection guidance from either vendor about third-party calendar aggregation of pupil/guardian data — relevant given NFR1 (EU sovereignty) and NFR2 (minors' safety), even though CarWal only reads title+type+date, not full pupil records.
3. Community reports (school IT forums, GitHub issues, blog posts from other developers who've built similar aggregators) of specific parsing bugs in either platform's ICS export — cite and summarize any found.

## Constraints

- German-language sources are expected and preferred (both platforms are Germany-only); translate key findings into English for the findings note, but quote German UI labels verbatim (they're needed for the operator runbook).
- Prioritize: official help centers (schulmanager.zammad.com, hilfe.iserv.de, doku.iserv.de) > school-published PDF guides (many exist, cross-reference at least 2 independent school sources per claim where official docs are silent) > developer blog posts / forum threads (cite explicitly as community-sourced, lower confidence) > any AI-generated summary without a traceable source (reject).
- Do not speculate about undocumented behavior — mark unknowns explicitly as "unconfirmed, needs empirical verification during the Story 2.1 spike" rather than guessing.

## Desired Output

A findings report with one section per question above (A1–A8, B1–B6, C1–C5, D1–D3), each answer tagged with:
- **Confidence:** official-doc-confirmed / community-corroborated / unconfirmed
- **Source(s):** direct links
- **Implication for CarWal:** one sentence on what this means for the Story 2.1 spike or the real pollers (2.3/2.4)

Close with a short "Open Unknowns" list — anything not resolvable by desk research and requiring empirical verification once Story 2.1 runs against real feeds.
