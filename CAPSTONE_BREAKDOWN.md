# AirStats Capstone — Assignment Breakdown

What this repo actually is, what the real data looks like (verified against
the actual CSVs, not just the docs), and a part-by-part walkthrough of the
assignment tying each exercise back to what's already been built in
`airbnb-for-me` / `dbt_project_flights`.

**Current state: nothing built yet.** No `airstats/` dbt project folder
exists — this is a fresh, empty template repo, exactly as `dbt init` would
leave it before Part 1's first step.

---

## 1. What this project is

- The capstone assignment for the same "Complete dbt Bootcamp" course as the
  airbnb project — a graded, fill-in-the-blanks exercise (`README.md` has
  literal `REPLACE THIS CODE BLOCK` placeholders you're meant to paste your
  own work into).
- **Snowflake-based**, same as the airbnb course originally was: `pyproject.toml`
  pins `dbt-snowflake~=1.11.0`, and the README's own `profiles.yml` example
  is `type: snowflake`.
- Real data: [OurAirports.com](https://ourairports.com/data/) global aviation
  data, Public Domain, vendored as a git submodule at `ourairports-data/`
  (David Megginson's daily-updated mirror).
- Dev environment: `uv` (not pip/venv), Python `==3.13.*` pinned exactly, a
  devcontainer for GitHub Codespaces.

---

## 2. The dataset — verified against the real files, not just `DATASETS.md`

`DATASETS.md` documents 3 tables sharing `airport_ident` (ICAO code) as a
join key:
```
airports (~72K rows)
    ├──< runways (~44K rows)          via airport_ident
    └──< airport_comments (variable)   via airport_ident
```

**I checked the real CSV headers in `ourairports-data/` directly, and found
three real discrepancies worth knowing before you start:**

| # | What `DATASETS.md` says | What the real CSV actually has |
|---|---|---|
| 1 | `airports` columns list has no `icao_code` | The real header has an extra `icao_code` column, sitting between `scheduled_service` and `iata_code` |
| 2 | `airport_comments` columns are snake_case: `thread_ref`, `airport_ref`, `airport_ident`, `member_nickname` | The real CSV header is **camelCase**: `threadRef`, `airportRef`, `airportIdent`, `memberNickname` |
| 3 | `airport_comments` table description lists `loaded_at` as if it's a raw source column | It isn't — the README's Exercise 7 makes clear `loaded_at` is something **you add yourself** downstream (`current_timestamp()` default), not part of the raw data at all |

**Why this matters in practice:** the README's Exercise 3 column-rename table
(the one that actually matters, since it's the graded requirement) uses
snake_case source names (`airport_ident`, `date`, `member_nickname`, etc.) —
matching `DATASETS.md`, *not* the real local CSV's camelCase headers. This
tells you the **official Snowflake `AIRSTATS.RAW` table** (set up by the
course, via `COPY INTO`) was loaded with renamed/snake_case columns — the
local `ourairports-data/` CSVs are the *original* upstream data, one step
before that renaming happened. If we ever build our own ClickHouse load from
these local CSVs directly, we'll need to explicitly rename camelCase → snake_case
during that load to match what the exercises assume — same idea as the
raw→staging renaming step, just one layer earlier than usual.

One more real fact: the comments CSV's sample rows show dates from
**2026-09-22**, i.e. genuinely live/current data — `ourairports-data`'s own
README confirms it's regenerated daily. So exact row counts will drift over
time; treat "~72K" / "~44K" as approximate, not fixed.

---

## 3. Platform mismatch — same problem as your other two projects, not solved yet

This is a **Snowflake** assignment (`dbt-snowflake`, `type: snowflake`,
data documented as loaded via Snowflake `COPY INTO` from
`s3://dbt-datasets/airstats/csv/`). Same conversion problem already solved
twice: `airbnb-for-me` and `dbt_project_flights` both needed a Docker +
ClickHouse setup before anything could actually run.

**One thing that's easier here than before:** the raw CSVs are already
sitting locally in `ourairports-data/` — no S3 bucket to reach at all. A
ClickHouse init script could load directly from these local files.

**Not set up yet.** This breakdown is the "understand the assignment" step;
the Docker/ClickHouse/profiles.yml setup is a separate next step, described
in §6.

---

## 4. Part-by-part breakdown of `README.md`

### Part 1 — Project setup
Plain `dbt init airstats`, same motion as before. One wrinkle: the project
pins Python `==3.13.*` exactly via `uv`, and the README's own instructions
assume `uv sync` + a venv, not Docker. Given the host's Python is 3.14 (same
incompatibility that forced Docker for the other two projects), this needs a
decision when we actually set it up: Docker (consistent with your other two
projects) or a `uv`-managed Python 3.13 env (closer to what the assignment
itself expects, since `uv` can install its own pinned Python version
independent of the host's).

### Part 4 — Sources
Same exercise as your `sources.yml` in `airbnb-for-me`. One deliberate
naming twist: the source **name** for the `airport_comments` table must be
`comments`, not `airport_comments` — a pointed exercise in `source()`'s two
independent arguments (`source('comments', ...)` pointing at a table
literally called `airport_comments`), reinforcing that the source name and
the table's real name never have to match.

### Part 5 — Staging models ("bronze" layer)
Directly parallels `src_hosts`/`src_listings`/`src_reviews`: rename raw
columns to a consistent convention, reference via `source()`, one model per
raw table (`src_airports`, `src_airport_comments`, `src_runways`).

**This is your live example of the bronze/silver/gold question from a few
messages ago** — this assignment literally names its staging folder
`models/bronze/`. Here, "bronze" *is* what `airbnb-for-me` calls `src`,
folder-named accordingly rather than by dbt's more common `staging/` label.

### Part 6 — "Silver" (core/dim-equivalent) layer — several genuinely new patterns

- **`silver_airports`** — trivial `SELECT *` passthrough, same shape as a
  thin dim.
- **`silver_runways`** — NULL-handling on `surface`, same idea as
  `COALESCE(host_name, 'Anonymous')`, but with an explicit sentinel string
  (`__UNKNOWN__`) and a **column-order-must-match-exactly** requirement
  that's stated more strictly here than anywhere in `airbnb-for-me` so far.
- **`silver_airport_comments`** — incremental, same `is_incremental()` +
  "max existing key" pattern as `fct_reviews`, but the watermark here is
  **`comment_id` (a monotonic surrogate ID), not a timestamp**. This is
  arguably a *cleaner* incremental pattern than a timestamp watermark — an
  ID only ever increases, so there's no clock-skew or "what if two rows share
  the same second" ambiguity that a timestamp watermark can have.
  Also introduces something new: a column whose default value is
  `current_timestamp()` (`loaded_at`) — nothing in `airbnb-for-me` adds a
  load-timestamp column like this yet.
- **Exercise 8** — add a row, rebuild only that one incremental model, verify
  it landed. This is the *exact same motion* as the "Zoltan" review-insert
  test already done in `airbnb-for-me`'s incremental lesson — same idea,
  different table.
- Materialization rule: silver defaults to `table` via `dbt_project.yml`,
  `silver_airport_comments` overrides to `incremental` — the same
  "project-wide default + one file's override" pattern already used for
  `dim`/`src` in `airbnb-for-me`.

### Part 7 — Snapshots — the one part with a real new concept, and it's already been rehearsed

This is the part that's genuinely different from anything built so far: it
explicitly requires the **`check` strategy**, not `timestamp` — *"this model
doesn't have a timestamp column we can work with."*

**This is precisely Interview Question 3** worked through earlier (unreliable/
missing timestamps → switch to `check` + explicit `check_cols`) — except this
time it's the real implementation, not a multiple-choice answer about it.

Exercise 9 closes a real heliport (`01CN`, "Los Angeles County Sheriff's
Department Heliport") and has you watch the snapshot capture that
transition — the same "update, re-run twice, watch history split" motion
already done with `scd_raw_hosts`, just with `check` instead of `timestamp`
as the change-detection mechanism.

It also asks for `analyses/la_heliport_closed.sql` — a genuinely new file
type across all three projects; `analyses/` folders exist elsewhere but
haven't actually been used yet.

### Part 8 — Tests
Same test categories already built (`unique`, `not_null`, `accepted_values`,
`relationships`, singular tests, `store_failures`) — with two new elements:

- **`relationships` tests explicitly set to `severity: warn`** across all
  three tables. `airbnb-for-me`'s `relationships` test uses the default
  (`error`) severity — this assignment asks for the softer version, since
  cross-table referential integrity isn't guaranteed to hold for
  crowd-sourced open data the way it does for a clean course dataset.
- **At least 3 `dbt_expectations` tests, required.** This package hasn't
  been installed in `airbnb-for-me` yet — that project only uses
  `dbt_utils`-style custom macros so far. Worth flagging early: `dbt_expectations`
  has no native ClickHouse support (already confirmed during the earlier
  scratch-testing done for `CLICKHOUSE_COURSE_GUIDE.md`), so the same
  `clickhouse__regexp_instr`/`clickhouse__quantile` dispatch-macro workaround
  would likely be needed again here once this runs on ClickHouse.

### Part 9 — Documentation
Same pattern as the course's docs lesson: `{{ doc("...") }}` blocks, column/
table descriptions, plus a fresh `overview.md` specifically explaining how
the 3 silver tables interconnect (a new, model-specific overview — not a
repeat of anything already written).

---

## 5. What's genuinely new here vs. everything built so far

- `check` snapshot strategy used for real (only `timestamp` strategy has
  been used in `airbnb-for-me`)
- A default-value column (`current_timestamp()`) bolted onto an incremental model
- `relationships` tests at `severity: warn` (only default/error severity used before)
- `dbt_expectations` actually installed and exercised (only `dbt_utils`-style
  custom macros so far)
- A real, used `analyses/*.sql` file
- An incremental watermark on a surrogate ID (`comment_id`) instead of a timestamp

---

## 6. Suggested next step

Same three-part pattern already used twice: (1) Docker + ClickHouse compose
setup, (2) a raw-load script pulling from the 3 CSVs already sitting in
`ourairports-data/` (with the camelCase→snake_case rename noted in §2 baked
in), (3) a conversion guide for whatever Snowflake-specific syntax turns up
while working through the exercises (same spirit as `CLICKHOUSE_COURSE_GUIDE.md`).

Say when you're ready and I'll start on the Docker/ClickHouse setup the same
way it was done for the other two projects.
