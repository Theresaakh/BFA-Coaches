# BFA Coach Attendance

A small web app for Beirut Football Academy to record which coaches attended each day and count their sessions at the end of the month.

**Live app:** https://theresaakh.github.io/BFA-Coaches/ (after GitHub Pages is turned on, see below)

## What it does

- **Coaches**: add all your coaches once. Type or paste the names, one per line. You can fix a misspelled name or remove a coach later; removed coaches keep their past attendance in reports.
- **Calendar**: a month view where each day shows how many people came. Tap a day to see the whole list and tick who attended, then choose **Coach** or **Assistant** for each person (new ticks start with the role they had last time). There's also *All present* and *Clear day*. If someone ran more than one session that day, use − / +.
- **Monthly report**: for each person, days attended, sessions as coach, sessions as assistant and the total, plus a day-by-day register (filled = coach, outlined A = assistant). Export to CSV (opens in Excel) or print.
- **Approve**: in the monthly report, approve each person's sessions (or *Approve all*) once they're checked. Approved sessions are locked for that month, and the database itself refuses changes. *Reopen* unlocks them if a correction is needed.
- **Team PIN**: the first person to open the app creates a 4–8 digit PIN. Everyone else enters it once per device. It can be changed on the Coaches tab.

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
- Anyone with the link and the PIN can add and edit entries, and approve or reopen a month, so share the PIN only with staff. A longer PIN (6–8 digits) is harder to guess.
