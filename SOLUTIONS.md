# AirStats Capstone — Solutions Walkthrough

Step-by-step record of how each part was actually solved: the files written,
the commands run, and the real verification output. Platform throughout:
**dbt Core + ClickHouse**, not Snowflake (see `CAPSTONE_BREAKDOWN.md` for why,
and the README's inline `[ClickHouse]` notes for the syntax corrections this
required).

---

## Part 1 — Project Setup

**What the assignment asks:** `dbt init`, configure `profiles.yml`, verify
with `dbt debug`, clean up the example models.

**What was actually done:**
1. `docker-compose.yml` + `docker/dbt/Dockerfile` set up first — ClickHouse
   25.8 and dbt Core 1.11 (Python 3.13) both in containers, since the host
   can't run dbt Core natively (Python 3.14 installed, dbt Core 1.11 doesn't
   support it) and there's no Snowflake account to connect to anyway.
2. Real `dbt init --skip-profile-setup airstats`, run inside the `dbt`
   container — not hand-made folders.
3. `models/example/` removed, and the example `+materialized: view` config
   block removed from `dbt_project.yml`, per Step 4.
4. `airstats/profiles.yml` written for ClickHouse (`type: clickhouse`, no
   Snowflake account/private key needed at all):
   ```yaml
   airstats:
     target: dev
     outputs:
       dev:
         type: clickhouse
         driver: http
         host: "{{ env_var('CH_HOST', 'localhost') }}"
         port: "{{ env_var('CH_PORT', '8126') | as_number }}"
         user: dbt
         password: dbt_password
         schema: dev
         secure: false
         threads: 4
         custom_settings:
           join_use_nulls: 1
   ```
5. `DBT_PROJECT_DIR`/`DBT_PROFILES_DIR` env vars added to `docker-compose.yml`
   so every `dbt` command works with zero extra flags (discovered this was
   needed after a bare `dbt debug` failed — see the git history for the fix).

**Verified:** `docker compose run --rm dbt debug` → **"All checks passed!"**

---

## Part 4 — Define Sources (Exercise 1)

**Requirement:** `models/sources.yml` for the 3 raw tables; `airport_comments`
must use source **name** `comments`, not `airport_comments`.

**File:** `airstats/models/sources.yml`
```yaml
version: 2

sources:
  - name: airstats
    schema: raw
    tables:
      - name: airports
      - name: comments        # required name, per Exercise 1
        identifier: airport_comments
      - name: runways
```

**Verified:**
```
dbt compile
Found 3 sources, 547 macros
```

---

## Part 5 — Staging Models / "bronze" layer (Exercises 2–4)

**Requirement:** one model per raw table, renaming columns per each
exercise's mapping table, referencing the source via a CTE.

**Files:** `airstats/models/bronze/{src_airports,src_airport_comments,src_runways}.sql`

```sql
-- src_airports.sql
WITH airports AS (
    SELECT * FROM {{ source('airstats', 'airports') }}
)
SELECT
    ident AS airport_ident, type AS airport_type, name AS airport_name,
    latitude_deg AS airport_lat, longitude_deg AS airport_long,
    continent, iso_country, iso_region
FROM airports
```
```sql
-- src_airport_comments.sql (note: source('airstats', 'comments'), not 'airport_comments')
WITH comments AS (
    SELECT * FROM {{ source('airstats', 'comments') }}
)
SELECT
    id AS comment_id, airport_ident, date AS comment_timestamp,
    member_nickname, subject AS comment_subject, body AS comment_body
FROM comments
```
```sql
-- src_runways.sql
WITH runways AS (
    SELECT * FROM {{ source('airstats', 'runways') }}
)
SELECT
    id AS runway_id, airport_ident, length_ft AS runway_length_ft,
    width_ft AS runway_width_ft, surface AS runway_surface,
    lighted AS runway_lighted, closed AS runway_closed
FROM runways
```

**Verified:**
```
dbt run
Found 3 models, 3 sources, 547 macros
Done. PASS=3 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=3
```
Spot-checked actual rows in ClickHouse directly (`dev.src_airports`,
`dev.src_airport_comments`, `dev.src_runways`) — renaming confirmed correct
on real data.

---

## Part 6 — Base Silver Tables (Exercises 5–8)

**Materialization setup:**
- `dbt_project.yml`: `models.airstats.silver.+materialized: table` (folder default)
- Each `bronze/src_*.sql` got its **own individual** `{{ config(materialized='ephemeral') }}` — not a folder default, per the explicit requirement
- `silver_airport_comments.sql` overrides to `incremental` in its own file

### Exercise 5 — `silver_airports` (plain copy)
```sql
WITH src_airports AS (
    SELECT * FROM {{ ref('src_airports') }}
)
SELECT * FROM src_airports
```

### Exercise 6 — `silver_runways` (defaults `runway_surface`)
```sql
WITH src_runways AS (
    SELECT * FROM {{ ref('src_runways') }}
)
SELECT
    runway_id, airport_ident, runway_length_ft, runway_width_ft,
    CASE WHEN runway_surface IS NULL OR runway_surface = '' THEN '__UNKNOWN__'
         ELSE runway_surface END AS runway_surface,
    runway_lighted, runway_closed
FROM src_runways
```

### Exercise 7 — `silver_airport_comments` (incremental)
```sql
{{ config(materialized='incremental') }}

WITH src_airport_comments AS (
    SELECT * FROM {{ ref('src_airport_comments') }}
)
SELECT
    comment_id, airport_ident, comment_timestamp,
    CASE WHEN member_nickname IS NULL OR member_nickname = '' THEN '__UNKNOWN__'
         ELSE member_nickname END AS member_nickname,
    comment_subject, comment_body, now() AS loaded_at
FROM src_airport_comments
WHERE comment_body IS NOT NULL AND comment_body != ''
{% if is_incremental() %}
  AND comment_id > (SELECT max(comment_id) FROM {{ this }})
{% endif %}
```
Watermarked on `comment_id` (a monotonic surrogate id) rather than a
timestamp — deliberately, since an id can't have clock-skew/duplicate-time
issues the way a timestamp watermark can.

**Verified (`dbt run`):**
```
Found 6 models, 3 sources, 547 macros
1 of 3 START sql table model `dev`.`silver_airports` ... OK
2 of 3 START sql incremental model `dev`.`silver_airport_comments` ... OK
3 of 3 START sql table model `dev`.`silver_runways` ... OK
Done. PASS=3 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=3
```
Note "Found 6 models" but only 3 ran — confirms the 3 `bronze` models are
correctly ephemeral (no longer separate build steps).

Row counts confirmed directly in ClickHouse:
| Table | Rows | Note |
|---|---|---|
| `silver_airports` | 86,135 | matches raw exactly (plain copy) |
| `silver_runways` | 48,267 | matches raw; 507 rows defaulted to `'__UNKNOWN__'` |
| `silver_airport_comments` | 16,413 | raw had 16,415 — 2 rows correctly filtered for null/empty `comment_body` |

Stale `View` objects left over from the `view → ephemeral` switch (`src_airports`,
`src_airport_comments`, `src_runways`) were manually dropped afterward —
same cleanup pattern needed any time a model's materialization changes.

### Exercise 8 — Update record, rebuild incrementally

**1. Insert a new record into `raw.airport_comments`:**
```sql
INSERT INTO raw.airport_comments VALUES
(999999999, NULL, NULL, '00A', now(), 'claude_test', 'Test comment', 'Testing the incremental watermark for Exercise 8');
```

**2. Rebuild only `silver_airport_comments` (no `--full-refresh`):**
```powershell
docker compose run --rm dbt run --select silver_airport_comments
```

**3. Verify in ClickHouse:**
```sql
SELECT * FROM dev.silver_airport_comments WHERE comment_id = 999999999;
```
→ exactly 1 new row appeared, with `loaded_at` showing the rebuild time (not
the insert time) — confirming `now()` evaluates at build time, and the
`comment_id > max(existing)` incremental filter correctly picked up only the
new row rather than reprocessing all 16,413+ existing ones.

---

## Part 7 — Snapshots (Exercises 9–10)

**Requirement:** snapshot `silver_airports` and `silver_runways`, using
`check` strategy on all columns (neither model has a reliable timestamp
column) — this is the real-world implementation of Interview QA Question 3.

**Files:**
```yaml
# snapshots/scd_silver_airports.yml
snapshots:
  - name: scd_silver_airports
    relation: ref('silver_airports')
    config:
      unique_key: airport_ident   # the only identifier silver_airports has
      strategy: check
      check_cols: all
```
```yaml
# snapshots/scd_silver_runways.yml
snapshots:
  - name: scd_silver_runways
    relation: ref('silver_runways')
    config:
      unique_key: runway_id
      strategy: check
      check_cols: all
```

Both snapshot the **silver** models (`relation: ref(...)`), not the raw
sources directly — different from `airbnb-for-me`'s snapshots, which watch
sources. This matters operationally: any raw change must be propagated via
`dbt run --select <silver_model>` *before* `dbt snapshot` can see it, since
the snapshot never looks at `raw` at all.

**Baseline run:**
```powershell
docker compose run --rm dbt snapshot
```
→ both snapshots created, 86,135 and 48,267 rows respectively, matching
their source tables exactly (everything captured as current, `dbt_valid_to = NULL`).

### Exercise 9 — the LA Sheriff's heliport closure

**A real discrepancy hit immediately:** the assignment's airport
`01CN` doesn't exist in the current data — OurAirports (this dataset updates
daily) re-coded this exact heliport's `ident` to **`US-9364`** at some point
after the assignment was written. It was also already `type = 'closed'` in
the live data, baseline-captured as such. Both facts made the literal
exercise text ("close this airport") already true before touching anything.

**To still demonstrate the snapshot mechanism for real** (not just an empty
baseline), the closure was simulated as a round-trip — reopen, capture,
reclose, capture — ending back at the true, real-world state:

```sql
-- 1. reopen
ALTER TABLE raw.airports UPDATE type = 'heliport'
WHERE ident = 'US-9364' SETTINGS mutations_sync = 1;
```
```powershell
# 2. propagate + snapshot
docker compose run --rm dbt run --select silver_airports
docker compose run --rm dbt snapshot
```
```sql
-- 3. reclose (restore real state)
ALTER TABLE raw.airports UPDATE type = 'closed'
WHERE ident = 'US-9364' SETTINGS mutations_sync = 1;
```
```powershell
# 4. propagate + snapshot again
docker compose run --rm dbt run --select silver_airports
docker compose run --rm dbt snapshot
```

**Result — verified in ClickHouse:**
```sql
SELECT airport_ident, airport_type, dbt_valid_from, dbt_valid_to
FROM dev.scd_silver_airports WHERE airport_ident = 'US-9364' ORDER BY dbt_valid_from;
```
| airport_ident | airport_type | dbt_valid_from | dbt_valid_to |
|---|---|---|---|
| US-9364 | closed | 06:05:37 | 06:36:19 |
| US-9364 | heliport | 06:36:19 | 06:37:00 |
| US-9364 | closed | 06:37:00 | NULL (current) |

Full 3-version SCD2 history, correctly detected by `check` strategy with no
timestamp column involved at all.

**A real mistake made and fixed along the way:** the first attempt ran both
raw `ALTER TABLE` changes back-to-back, without the `dbt run` + `dbt snapshot`
pair in between each one. Result: the snapshot still showed only 1 row,
because the intermediate "heliport" state never reached `silver_airports`
before being overwritten again — the snapshot never got the chance to see
it. Fixed by strictly interleaving: **raw change → `dbt run` → `dbt snapshot`
→ next raw change**, never two raw changes in a row.

### Exercise 10 — runway closure (same mechanism, different model)

Same round-trip pattern, applied to runway `232758` at `TNCA` (closed → true state is open):

```sql
ALTER TABLE raw.runways UPDATE closed = 1 WHERE id = 232758 SETTINGS mutations_sync = 1;
```
```powershell
docker compose run --rm dbt run --select silver_runways
docker compose run --rm dbt snapshot
```
```sql
ALTER TABLE raw.runways UPDATE closed = 0 WHERE id = 232758 SETTINGS mutations_sync = 1;
```
```powershell
docker compose run --rm dbt run --select silver_runways
docker compose run --rm dbt snapshot
```

**Result:**
| runway_id | runway_closed | dbt_valid_from | dbt_valid_to |
|---|---|---|---|
| 232758 | 0 | 06:05:37 | 06:41:12 |
| 232758 | 1 | 06:41:12 | 06:41:51 |
| 232758 | 0 | 06:41:51 | NULL (current) |

Confirms the same `check`-strategy mechanism works correctly on a numeric
flag column, not just a text column — same ordering rule, same result shape.

---

## Part 8 — Tests

**Requirement:** `unique`/`not_null` (educated guess) on every silver table,
one `accepted_values`, `relationships` between all three tables at
`severity: warn`, 3+ `dbt_expectations` tests, 2 singular tests, and
`store_failures` configured.

**Step 0 — install `dbt_expectations`:**
```yaml
# airstats/packages.yml
packages:
  - package: calogica/dbt_expectations
    version: 0.10.4
```
```powershell
docker compose run --rm dbt deps
```

**`models/silver/schema.yml`** — the full test suite:
```yaml
version: 2

models:
  - name: silver_airports
    data_tests:
      - dbt_expectations.expect_table_row_count_to_be_between:
          arguments:
            min_value: 50000
            max_value: 150000   # generous -- this is live, daily-updating data
    columns:
      - name: airport_ident
        data_tests: [unique, not_null]
      - name: airport_type
        data_tests:
          - accepted_values:
              arguments:
                values: ['small_airport', 'medium_airport', 'large_airport',
                         'heliport', 'seaplane_base', 'balloonport', 'closed']
      - name: airport_lat
        data_tests:
          - dbt_expectations.expect_column_values_to_be_between:
              arguments: {min_value: -90, max_value: 90}
      - name: airport_long
        data_tests:
          - dbt_expectations.expect_column_values_to_be_between:
              arguments: {min_value: -180, max_value: 180}

  - name: silver_runways
    columns:
      - name: runway_id
        data_tests: [unique, not_null]
      - name: airport_ident
        data_tests:
          - not_null
          - relationships:
              arguments: {to: ref('silver_airports'), field: airport_ident}
              config: {severity: warn}

  - name: silver_airport_comments
    columns:
      - name: comment_id
        data_tests: [unique, not_null]
      - name: airport_ident
        data_tests:
          - not_null
          - relationships:
              arguments: {to: ref('silver_airports'), field: airport_ident}
              config: {severity: warn}
```

**The 2 singular tests:**
```sql
-- tests/comment_not_in_future.sql
SELECT * FROM {{ ref('silver_airport_comments') }}
WHERE comment_timestamp > now()
```
```sql
-- tests/runway_length_positive.sql
{{ config(severity='warn') }}
SELECT * FROM {{ ref('silver_runways') }}
WHERE runway_length_ft IS NOT NULL AND runway_length_ft <= 0
```

**`dbt_project.yml` addition:**
```yaml
data_tests:
  airstats:
    +store_failures: true
    +schema: test_failures
```

**Verified (`dbt build`):**
```
Finished running 1 incremental model, 2 snapshots, 2 table models, 16 data tests
Done. PASS=20 WARN=1 ERROR=0 SKIP=0 NO-OP=0 TOTAL=21
```

**A real data quality finding, caught by `runway_length_positive`, not a test
bug:** 6 real runways have `runway_length_ft = 0` paired with
`runway_surface = 'UNK'`:
```
runway_id | airport_ident | runway_length_ft | runway_surface
   246297 | LFQL          |                0 | UNK
   246298 | LFQL          |                0 | UNK
   249233 | LFAK          |                0 | UNK
   255232 | EGSL          |                0 | UNK
   259295 | YROB          |                0 | N
   263789 | AR-0378       |                0 | GRE
```
The source data uses `0` as a placeholder for "genuinely unknown" rather
than `NULL` — a real, crowdsourced-data quirk, not a mistake in the test.
Set to `severity: warn` and documented, same principle as the
"two Bruce Willis" test in the airbnb course project: a real finding stays
*visible*, it doesn't get silently excluded from the `WHERE` clause.

A design choice worth noting on the `dbt_expectations` tests picked: all
three (`expect_column_values_to_be_between` ×2, `expect_table_row_count_to_be_between`)
were deliberately chosen to avoid regex- or quantile-based macros, which are
known from the earlier course project to compile to ClickHouse functions
that don't exist (`regexp_instr`, `percentile_cont`) without custom
`clickhouse__*` dispatch-macro overrides — none of which exist in this
project yet.

---

## Part 7 leftovers — analysis and README placeholders

**Exercise 9 analysis:** `airstats/analyses/la_heliport_closed.sql` selects
every version of `US-9364` from `scd_silver_airports`, ordered by
`dbt_valid_from`. Analyses are compiled but never materialized, so
`dbt compile --select la_heliport_closed` and then running the compiled file
against ClickHouse is how it gets executed. The result returns the three
expected versions: `closed` → `heliport` → `closed` (current).

The README's Exercise 8 and Exercise 9 `REPLACE THIS CODE BLOCK` placeholders
are now filled with the SQL, commands, and results used above.

---

## Part 9 — Documentation

**Requirement:** descriptions on the silver tables and their columns, at
least one `{{ doc("...") }}` reference, and an `overview.md` explaining how the
silver tables interconnect.

**`airstats/models/silver/docs.md`** — a doc block for the shared join key:
```
{% docs airport_ident %}
ICAO airport code, the shared join key across the silver layer. ...
{% enddocs %}
```

**`airstats/models/silver/overview.md`** — the `__overview__` block shown on
the dbt docs homepage. It describes `silver_airports` as the hub, with
runways and comments both referencing it through `airport_ident`, and notes
that the relationship tests are `severity: warn` because the source data
isn't guaranteed to be consistent.

**`airstats/models/silver/schema.yml`** — descriptions added for every
silver column (22 in total). `airport_ident` is written as
`description: '{{ doc("airport_ident") }}'` in all three models. All existing
tests are unchanged.

**Verified:**
- `dbt build` → `PASS=20 WARN=1 ERROR=0 TOTAL=21` (unchanged from Part 8)
- `dbt docs generate` → catalog written with no errors
- the manifest holds the resolved `airport_ident` doc text and the
  `__overview__` block

---

## Part 10 (optional extension) — Gold layer

Not part of the original assignment. Added as an extension: business-facing
marts built on the silver layer. The spec is in README Part 10.

**Files:**
- `airstats/models/gold/gold_airport_activity.sql`: one row per airport, with
  `runway_count`, `comment_count`, `latest_comment_timestamp`
- `airstats/models/gold/gold_country_airport_stats.sql`: one row per country,
  with `total_airports`, `closed_airports`, `total_runways`, `airports_with_runways`
- `airstats/models/gold/schema.yml`: descriptions, `unique`/`not_null`,
  `relationships` (warn), and a row-count check
- `dbt_project.yml`: `gold: +materialized: table`

**Issue hit and fixed:** `gold_airport_activity` initially failed three tests
with `Unknown expression identifier airport_ident`. The join key was present on
both sides of the join, so ClickHouse kept a qualified name instead of
`airport_ident`. Fixed by aliasing it explicitly: `a.airport_ident AS airport_ident`.

**Verified (`dbt build --select gold`):** `PASS=8 WARN=0 ERROR=0`

**Cross-checked against silver:**

| Check | Gold | Silver |
|---|---|---|
| airports | 86,135 | 86,135 |
| runways | 48,267 | 48,267 |
| comments | 16,414 | 16,414 |
| closed airports | 13,546 | 13,546 |

---

## Still open

Nothing for Parts 1–9. To view the docs, run
`docker compose run --rm --service-ports dbt docs serve --host 0.0.0.0 --port 8080`
and open `http://localhost:8081` (the compose file maps container port 8080 to host port 8081).
