# BFA Coach Attendance

A small web app for Beirut Football Academy to record which coaches attended each day and count their sessions at the end of the month.

**Live app:** https://theresaakh.github.io/BFA-Coaches/ (after GitHub Pages is turned on, see below)

## What it does

- **Branches**: Furn El Chebbek, Hazmieh, Sin El Fil, Mansourieh, Beit Meri and Hadath. Each branch has its own coach list, calendar and report. A coach only shows in the branches they were added to; someone who works at two branches can be in both, and sessions always stay in the branch where they were entered.
- **Who sees what**: open the app with a **branch PIN** to see and edit only that branch (including approving it); a branch admin starts on today's attendance. The **main admin PIN** starts on the **Overview**: one card per branch with the month's coach and assistant sessions, how many are approved, and branches still missing a PIN, with an *Open* button for each branch. A branch picker at the top switches between one branch and *All branches*; the **Branches** tab sets each branch's name and PIN.
- **Calendar**: tap a day to see the branch's coaches in a table (Name · Coach · Assistant) with a search box and "x of y present". Tick who came and use the small − / + counters for coach and assistant sessions (someone can do both on the same day). Coaches still to approve are listed first; approved, locked coaches are listed at the bottom. There's also *All present* and *Clear day*.
- **Monthly report**: coach sessions and assistant sessions are always kept separate, never added together. In one branch: one line per person with days, coach and assistant sessions and the Approve / Reopen button. In *All branches*, **By branch** shows a summary tile per branch, a section per branch (with Approve / Reopen), and an *All branches together* table listing each person once with the branches they worked at; **One table** shows the same as a single wide table. A day-by-day register is grouped by branch. Export to CSV (opens in Excel) or print.
- **Coaches**: add a branch's coaches once by typing or pasting names, one per line. The same name in two branches is the same person. The main admin sees every coach in a table with one tick box per branch, plus search and a filter (needs a branch, one branch, hidden).
- **Approve**: approve each person's sessions (or *Approve all*) once they're checked. Approved sessions are locked for that month and branch, and the database itself refuses changes. *Reopen* unlocks them if a correction is needed.

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
