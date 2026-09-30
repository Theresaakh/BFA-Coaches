# BFA Coach Attendance

A small web app for Beirut Football Academy to record which coaches attended each day and count their sessions at the end of the month.

**Live app:** https://theresaakh.github.io/BFA-Coaches/ (after GitHub Pages is turned on, see below)

## What it does

- **Branches**: Furn El Chebbek, Hazmieh, Sin El Fil, Mansourieh, Beit Meri and Hadath. Each branch has its own coach list, calendar and report. A coach only shows in the branches they were added to; someone who works at two branches can be in both, and each branch counts only its own sessions.
- **Who sees what**: open the app with a **branch PIN** to see and edit only that branch (including approving it). The **main admin PIN** sees every branch: a branch picker at the top switches between one branch and *All branches* (a combined, read-only overview), and the **Branches** tab sets each branch's name and PIN.
- **Coaches**: add a branch's coaches once. Type or paste the names, one per line. The same name in two branches is the same person. You can fix a misspelled name or remove a coach from a branch later; their past sessions stay in reports. In *All branches*, the main admin taps branch chips to decide where each coach works.
- **Calendar**: a month view where each day shows how many people came. Tap a day to see the branch's coach list and tick who attended. Each ticked person has two counters, **Coach** and **Assistant**, so someone can do e.g. 1 session as coach and 1 as assistant on the same day. A new tick starts in the role the person had last time. There's also *All present* and *Clear day*.
- **Monthly report**: for each person, days attended, coach sessions and assistant sessions (always kept separate, never added together), plus a day-by-day register (filled = coach, outlined A = assistant, 1+1A = both). In *All branches* there is one line per coach showing coach and assistant sessions for each branch, then the total coach and total assistant sessions; a ✓ marks the branches where that coach is approved. Sessions always stay in the branch where they were entered. Export to CSV (opens in Excel) or print.
- **Approve**: in the monthly report, approve each person's sessions (or *Approve all*) once they're checked. Approved sessions are locked for that month and branch, and the database itself refuses changes. *Reopen* unlocks them if a correction is needed.

Data syncs between phones and computers. Each open page refreshes every 30 seconds and whenever you come back to it.

## How it's built

- `index.html`: the whole app, plain HTML/CSS/JS with no build step.
- Data lives in the Supabase project **bfa-coach-attendance** (Frankfurt, free plan).
- `supabase/migrations/`: the database setup. Tables are closed to the public; the app only calls PIN-checked database functions.

The Supabase key in `index.html` is the *publishable* key, which is meant to be public. It can only call those functions, and they refuse to do anything without the right PIN.

## Turning on the live link (one time)

1. On GitHub, open the repository, then **Settings → Pages**.
2. Under **Build and deployment**, set **Source** to *Deploy from a branch*, branch **main**, folder **/ (root)**, then **Save**.
3. After a minute or two the app is live at https://theresaakh.github.io/BFA-Coaches/.

## Notes

- A free Supabase project pauses after about a week with no activity. If the app says it can't connect after a long break, open the project in the Supabase dashboard and click **Restore**.
- A branch PIN can add, edit, approve and reopen only its own branch; the database enforces this. Keep the main admin PIN to yourself. Longer PINs (6–8 digits) are harder to guess.
- A backup of the coaches, sessions and approvals from before the branch change is kept in the database schema `backup_20260930`.
