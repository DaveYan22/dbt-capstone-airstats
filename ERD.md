# AirStats — Entity-Relationship Diagram

**Scope: 3 tables only.** `ourairports-data/` (the vendored open dataset) has 7
CSVs total, but this project's assignment (`README.md` Part 4) explicitly
scopes the raw layer to exactly 3: `airports`, `runways`, `airport_comments`.
`airport-frequencies.csv`, `countries.csv`, `navaids.csv`, and `regions.csv`
sit in the same folder but are out of scope — not loaded, not referenced by
any exercise.

---

## Diagram

```mermaid
erDiagram
    AIRPORTS ||--o{ RUNWAYS : "has (via airport_ident)"
    AIRPORTS ||--o{ AIRPORT_COMMENTS : "has (via airport_ident)"

    AIRPORTS {
        int id PK
        string ident "ICAO code — the join key"
        string type
        string name
        float latitude_deg
        float longitude_deg
        int elevation_ft
        string continent
        string iso_country
        string iso_region
        string municipality
        string scheduled_service
        string icao_code "not in DATASETS.md, present in real data"
        string iata_code
        string gps_code
        string local_code
        string home_link
        string wikipedia_link
        string keywords
    }

    RUNWAYS {
        int id PK
        int airport_ref FK "numeric FK to airports.id"
        string airport_ident FK "ICAO code FK to airports.ident"
        int length_ft
        int width_ft
        string surface
        int lighted
        int closed
        string le_ident "low-end designator, e.g. 09L"
        string he_ident "high-end designator, e.g. 27R"
    }

    AIRPORT_COMMENTS {
        int id PK
        int thread_ref
        int airport_ref FK "numeric FK to airports.id"
        string airport_ident FK "ICAO code FK to airports.ident"
        datetime date
        string member_nickname
        string subject
        string body
    }
```

*(`runways` also carries 10 more low-end/high-end detail columns —
`le_latitude_deg`, `le_longitude_deg`, `le_elevation_ft`, `le_heading_degT`,
`le_displaced_threshold_ft` and their `he_*` mirrors — omitted above to keep
the diagram readable; full list is in `DATASETS.md` and the raw load script.)*

---

## The relationships, in plain terms

- **One airport → many runways.** An airport typically has 1–4 runways; a
  runway always belongs to exactly one airport.
- **One airport → many comments.** Any number of users can comment on the
  same airport; a comment always refers to exactly one airport.
- **Two parallel join keys exist for both child tables**: a numeric
  `airport_ref` (→ `airports.id`) and a string `airport_ident` (→
  `airports.ident`, the ICAO code). The assignment's own exercises join on
  **`airport_ident`**, not `airport_ref` — worth being consistent about which
  one you use in `relationships` tests later, since both technically work.
- **No relationship between `runways` and `airport_comments` directly** —
  they only relate to each other *through* `airports`.

## Cardinality note worth knowing before writing `relationships` tests

Neither child table is guaranteed to have a matching parent in 100% of real
rows — this is crowd-sourced open data, not a clean synthetic dataset. That's
exactly why the assignment (Part 8) asks for `relationships` tests at
`severity: warn` rather than the default `error`: referential integrity is a
useful signal to watch, not a hard guarantee to enforce here.

---

## Bonus: the *full* OurAirports dataset (7 tables) — not part of this project

You asked whether all tables connect — within this project's 3-table scope,
no. But `ourairports-data/` actually has 7 CSVs, and I checked all their real
headers: **across the full dataset, every table does connect, transitively,
through `airports` as the central hub.** It's a connected graph, not a fully
connected mesh — most pairs relate only *through* `airports`, not directly to
each other. **None of this is used by the capstone assignment** — shown here
purely for context, since you asked.

```mermaid
erDiagram
    COUNTRIES ||--o{ REGIONS : "iso_country = code"
    COUNTRIES ||--o{ AIRPORTS : "iso_country = code"
    REGIONS ||--o{ AIRPORTS : "iso_region = code"
    AIRPORTS ||--o{ RUNWAYS : "airport_ident"
    AIRPORTS ||--o{ AIRPORT_COMMENTS : "airport_ident"
    AIRPORTS ||--o{ AIRPORT_FREQUENCIES : "airport_ident"
    AIRPORTS ||--o{ NAVAIDS : "associated_airport = ident"

    COUNTRIES {
        int id PK
        string code "2-letter ISO code"
        string name
        string continent
    }

    REGIONS {
        int id PK
        string code "e.g. AD-02"
        string local_code
        string name
        string continent
        string iso_country FK "-> countries.code"
    }

    AIRPORTS {
        int id PK
        string ident "ICAO code, central join key"
        string type
        string name
        string iso_country FK "-> countries.code"
        string iso_region FK "-> regions.code"
    }

    RUNWAYS {
        int id PK
        int airport_ref FK
        string airport_ident FK
    }

    AIRPORT_COMMENTS {
        int id PK
        int airport_ref FK
        string airport_ident FK
    }

    AIRPORT_FREQUENCIES {
        int id PK
        int airport_ref FK
        string airport_ident FK
        string type
        float frequency_mhz
    }

    NAVAIDS {
        int id PK
        string ident
        string type
        string associated_airport FK "-> airports.ident"
        string iso_country FK "-> countries.code"
    }
```

**How each connects, verified against the real CSV headers** (not assumed):
- `countries.code` (2-letter ISO) ← referenced by `regions.iso_country`, `airports.iso_country`, and `navaids.iso_country`
- `regions.code` (e.g. `AD-02`) ← referenced by `airports.iso_region`
- `airports.ident` (ICAO code) ← referenced by `runways.airport_ident`, `airport_comments.airport_ident`, `airport-frequencies.airport_ident`, and `navaids.associated_airport` (same join key, different column name)
- `airports.id` (numeric) ← referenced in parallel by `runways.airport_ref`, `airport_comments.airport_ref`, `airport-frequencies.airport_ref`

So the honest full answer: it's **one connected component**, shaped like
`countries → regions → airports → {runways, airport_comments,
airport-frequencies, navaids}` — a hierarchy feeding into a hub, not a web
where every table touches every other one directly.
