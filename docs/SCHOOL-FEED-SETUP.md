# School Feed Setup — Getting the Real Ingestion Handles

Operator runbook for extracting the real IServ + Schulmanager Online integration handles CarWal needs before Story 2.1 (Throwaway Ingestion Spike) can run. This is a one-time, per-family setup done from the guardian accounts — no CarWal code involved.

**Why this matters:** Story 2.1 is explicitly forbidden from running against fixtures or mock data — it must hit the real feeds to burn down real unknowns (see `_bmad-output/implementation-artifacts/2-1-throwaway-ingestion-spike.md`). Nothing downstream (Story 2.3 iCal poller, Story 2.4 email poller) can be built correctly until this is done.

You need three things:

1. **Schulmanager Online** — iCal subscription URL
2. **IServ** — ICS calendar Link-Freigabe URL
3. **IServ** — mail forwarding to CarWal's app mailbox

---

## Part A — Schulmanager Online: iCal subscription URL

1. Log in to [schulmanager-online.de](https://www.schulmanager-online.de/) with the guardian account.
2. Open the **„Kalender"** module in the main navigation.
3. In the Terminübersicht (event overview), look at the **bottom left**. Click **„Kalender abonnieren"**.
4. Schulmanager shows a subscription URL. It looks like:
   ```
   https://login.schulmanager-online.de/ical/calendar/<token>
   ```
   or with query params:
   ```
   https://login.schulmanager-online.de/ics/<id>?user=<uid>&password=<token>
   ```
   Both forms have been seen in the wild — copy exactly what's shown, don't guess the format.
5. Copy the **entire URL**. This is `SCHULMANAGER_ICAL_URL`.

**Multiple children at the same school:** if you've merged multiple children into one guardian account (via „Code hinzufügen" in the profile menu), one subscription URL likely returns all of them merged — Story 2.1 will confirm this empirically. Copy just the one URL from the merged account first.

**Multiple children at different schools:** Schulmanager does NOT merge across schools at the export level (even though its mobile app visually merges them for you). You need a **separate URL per school** — repeat steps 1–5 once per school domain.

**Treat this URL as a secret.** The token in the URL is the entire authorization — anyone with the link can read the calendar. Don't paste it into chat messages, tickets, or commit it to git. It goes only into CarWal's env var.

**What will NOT be in this feed:** Klassenarbeiten (exams), Hausaufgaben (homework), and Stundenplan/Vertretungen (timetable/substitutions) live in separate Schulmanager modules and are not exported via this calendar subscription. Don't expect them to show up in CarWal via this path — this is a known, confirmed platform gap (research-verified 2026-07-07), not a bug to chase.

---

## Part B — IServ: Calendar ICS Link-Freigabe

1. Log in to the school's IServ instance with the guardian account.
2. Open the **„Kalender"** module.
3. Go to **„Einstellungen"** → **„Kalender verwalten"**.
4. Select the calendar you want to share (the one showing the child's school appointments). Calendars with a hand icon in the right column support Link-Freigabe.
5. Open that calendar's details and find **„Link-Freigaben"** (or the share/link section).
6. Choose a visibility mode:
   - **„Freigabe für sichtbare Termine"** (recommended default) — exports events marked visible; **anonymizes** confidential events to `SUMMARY: "Vertraulicher Termin"` (no other detail); **omits** private events entirely.
   - **„Freigabe für alle Termine"** — exports everything including confidential/private event details. Only use this if you specifically need that data and understand the privacy tradeoff.
7. Save. Copy the generated ICS feed URL. This is `ISERV_ICAL_URL`.

**Treat this URL as a secret too** — same capability-URL model as Schulmanager, no login needed to read it once you have the link.

**If you ever need a new link:** IServ lets you revoke and regenerate Link-Freigaben at any time from the same screen. If you do, update the env var — the old URL stops working immediately.

**Version note:** IServ is self-hosted per school and schools run different versions. Menu wording can drift slightly ("sichtbar" vs. "öffentlich" on older versions) — if a label doesn't match exactly, look for the closest equivalent; the underlying feature is stable across versions even when labels aren't.

---

## Part C — IServ: Mail forwarding (Weiterleitung)

This forwards Elternbriefe notifications and other school mail to CarWal's dedicated app mailbox.

1. In IServ, open the **„E-Mail"** module.
2. Click **„Einstellungen"**.
3. Go to **„Konten"**, select the relevant email identity, click **„Verwalten"**.
4. Open the **„Umleitung"** tab.
5. Tick **„Eingehende E-Mails zu folgender E-Mail-Adresse umleiten"**.
6. Enter CarWal's app mailbox address (the sovereign-mailbox address configured for ingestion — check with the operator config / seed script for the exact address).
7. **Tick „Eine Kopie auf dem Server behalten".** Do this even though it's optional — if you don't, IServ deletes the message from your IServ inbox the instant it forwards it. Skipping this step means losing your own copy of official school mail. Not optional in practice.
8. Click **„Speichern"**.

**If forwarding is greyed out or missing:** some schools disable external mail forwarding for guardian accounts entirely (admin-controlled, via "Freigeschaltete E-Mail-Umleitungsziele" / "E-Mail-Umleitungen einschränken" on the school's side). There is no user-side workaround — this needs a different ingestion path (direct IMAP polling of the IServ mailbox, a later-story decision, not something to solve here). If this happens, tell the operator instead of trying to force it.

**Important — what actually arrives:** IServ's **Elternbriefe module does not send mail content**. What forwards is a bare notification email (sender: "IServ Benachrichtigungssystem") with a link back to the IServ portal — the actual letter text and any PDF stay behind IServ's login. This is expected, confirmed platform behavior, not a setup mistake. CarWal can detect "a new Elternbrief exists" via email but cannot extract its content that way.

**Waiting for a real test message:** once forwarding is on, wait for a real Elternbrief or other school mail to arrive naturally — don't fabricate one. Story 2.1 needs one real forwarded message in the app mailbox before its IMAP spike task can run.

---

## Part D — Feeding the values to Story 2.1

Once you have all three (or as many as your school setup allows), set these as environment variables in your local shell before running the spike (`mix spike.ical`, `mix spike.mail` — created by Story 2.1):

```bash
export ISERV_ICAL_URL="<the IServ Link-Freigabe URL from Part B>"
export SCHULMANAGER_ICAL_URL="<the Schulmanager subscription URL from Part A>"
export SPIKE_IMAP_SERVER="<your sovereign mailbox IMAP host>"
export SPIKE_IMAP_USER="<the app mailbox address>"
export SPIKE_IMAP_PASSWORD="<the app mailbox password>"
```

Never commit these to git, never paste them into a story file, chat log, or issue. They're throwaway shell exports for the spike only — production config (Story 2.3/2.4) will read the equivalent values from `runtime.exs` env vars per the deploy convention.

Tell the operator once these are set — Story 2.1's Task 1 checks for them before doing anything else.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| Schulmanager "Kalender abonnieren" button missing | You're not on the parent/guardian account, or the school hasn't enabled the calendar module | Confirm account type; ask the school if the Kalender module is active |
| IServ has no "Link-Freigaben" option on a calendar | You don't have write rights on that calendar | Check whether it's a personal vs. class calendar; ask the school's IServ admin |
| IServ mail forwarding checkbox is disabled/hidden | School admin restricted external forwarding | Report to operator — needs an IMAP-polling fallback decision, not a workaround here |
| Forwarded mail vanished from IServ inbox | "Kopie auf Server behalten" wasn't ticked | Re-enable forwarding with that box ticked; can't recover the already-deleted copy |

## Sources

Step-by-step paths and platform behavior confirmed against official documentation and cross-verified via three independent deep-research passes (2026-07-07):

- Schulmanager Online Hilfe — [Kalender abonnieren](https://schulmanager.zammad.com/help/de-de/1-kalender/46-wie-kann-ich-die-schultermine-in-einem-anderen-kalender-abonnieren)
- Schulmanager Online Hilfe — [Schnittstellen (iCal-Abo scope, module coverage)](https://schulmanager.zammad.com/help/de-de/3-verwaltung/29-schnittstellen)
- IServ Dokumentation — [Kalendermodul (Link-Freigaben, Sichtbarkeitsstufen)](https://doku.iserv.de/modules/calendar/)
- IServ Hilfe-Center — [Abwesenheitsnotiz und E-Mail-Weiterleitung](https://hilfe.iserv.de/abwesenheitsnotiz-e-mail-weiterleitung)
- IServ Dokumentation — [E-Mail-Umleitung, Admin-Einschränkungen](https://doku.iserv.de/advanced/redirect/)

Full source citations for every individual finding (including the ones behind the "confirmed facts" and "open unknowns" in Story 2.1) are in `_bmad-output/implementation-artifacts/2-1-deep-research-prompt.md` and the corresponding section of `_bmad-output/implementation-artifacts/2-1-throwaway-ingestion-spike.md`.
