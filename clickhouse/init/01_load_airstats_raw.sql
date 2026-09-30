-- Raw layer for the AirStats capstone (Snowflake in the original assignment), for ClickHouse.
-- Runs by itself on the first `docker compose up` (empty volume). "E + L" step, not dbt.
--
-- Data: OurAirports.com (Public Domain), mounted locally at /raw-data (see docker-compose.yml)
-- instead of the official assignment's S3 bucket, since the CSVs already sit in this repo's
-- ourairports-data/ folder.
--
-- IMPORTANT: airport-comments.csv's real header is camelCase (threadRef, airportRef,
-- airportIdent, memberNickname) -- NOT the snake_case documented in DATASETS.md / the
-- README's Exercise 3 rename table. Renamed to snake_case right here at load time, using
-- `format_csv_skip_first_lines = 1` (skip the header) + an explicit positional structure,
-- rather than relying on any header-name matching. airports.csv/runways.csv already use
-- snake_case in the real file, so no rename is needed for those two.

CREATE DATABASE IF NOT EXISTS raw;

-- ------------------------------------------------------------------- airports
-- Real header order verified against ourairports-data/airports.csv. Note the real file has
-- an `icao_code` column between scheduled_service and iata_code that DATASETS.md doesn't
-- document -- kept here for fidelity to the source; no exercise currently references it.
DROP TABLE IF EXISTS raw.airports;
CREATE TABLE raw.airports
(
    id                 Int32,
    ident              String,
    type               String,
    name               String,
    latitude_deg       Nullable(Float64),
    longitude_deg      Nullable(Float64),
    elevation_ft       Nullable(Int32),
    continent          Nullable(String),
    iso_country        Nullable(String),
    iso_region         Nullable(String),
    municipality       Nullable(String),
    scheduled_service  Nullable(String),
    icao_code          Nullable(String),
    iata_code          Nullable(String),
    gps_code           Nullable(String),
    local_code         Nullable(String),
    home_link          Nullable(String),
    wikipedia_link     Nullable(String),
    keywords           Nullable(String)
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO raw.airports
SELECT * FROM file(
    'raw-data/airports.csv', 'CSV',
    'id Int32, ident String, type String, name String, latitude_deg Nullable(Float64),
     longitude_deg Nullable(Float64), elevation_ft Nullable(Int32), continent Nullable(String),
     iso_country Nullable(String), iso_region Nullable(String), municipality Nullable(String),
     scheduled_service Nullable(String), icao_code Nullable(String), iata_code Nullable(String),
     gps_code Nullable(String), local_code Nullable(String), home_link Nullable(String),
     wikipedia_link Nullable(String), keywords Nullable(String)')
SETTINGS input_format_csv_skip_first_lines = 1;

-- -------------------------------------------------------------------- runways
-- Real header order verified against ourairports-data/runways.csv -- already snake_case,
-- no rename needed. Most le_*/he_* fields are frequently empty in the real data.
DROP TABLE IF EXISTS raw.runways;
CREATE TABLE raw.runways
(
    id                         Int32,
    airport_ref                Int32,
    airport_ident              String,
    length_ft                  Nullable(Int32),
    width_ft                   Nullable(Int32),
    surface                    Nullable(String),
    lighted                    Nullable(Int32),
    closed                     Nullable(Int32),
    le_ident                   Nullable(String),
    le_latitude_deg            Nullable(Float64),
    le_longitude_deg           Nullable(Float64),
    le_elevation_ft            Nullable(Int32),
    le_heading_degT            Nullable(Float64),
    le_displaced_threshold_ft  Nullable(Int32),
    he_ident                   Nullable(String),
    he_latitude_deg            Nullable(Float64),
    he_longitude_deg           Nullable(Float64),
    he_elevation_ft            Nullable(Int32),
    he_heading_degT            Nullable(Float64),
    he_displaced_threshold_ft  Nullable(Int32)
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO raw.runways
SELECT * FROM file(
    'raw-data/runways.csv', 'CSV',
    'id Int32, airport_ref Int32, airport_ident String, length_ft Nullable(Int32),
     width_ft Nullable(Int32), surface Nullable(String), lighted Nullable(Int32),
     closed Nullable(Int32), le_ident Nullable(String), le_latitude_deg Nullable(Float64),
     le_longitude_deg Nullable(Float64), le_elevation_ft Nullable(Int32),
     le_heading_degT Nullable(Float64), le_displaced_threshold_ft Nullable(Int32),
     he_ident Nullable(String), he_latitude_deg Nullable(Float64),
     he_longitude_deg Nullable(Float64), he_elevation_ft Nullable(Int32),
     he_heading_degT Nullable(Float64), he_displaced_threshold_ft Nullable(Int32)')
SETTINGS input_format_csv_skip_first_lines = 1;

-- ---------------------------------------------------------------- airport_comments
-- Real header is camelCase: id, threadRef, airportRef, airportIdent, date, memberNickname,
-- subject, body. Renamed to snake_case here (matching DATASETS.md / the README's Exercise 3)
-- via positional structure -- the source name is "comments" (per the assignment), the
-- table name stays airport_comments.
DROP TABLE IF EXISTS raw.airport_comments;
CREATE TABLE raw.airport_comments
(
    id               Int32,
    thread_ref       Nullable(Int32),
    airport_ref      Nullable(Int32),
    airport_ident    String,
    date             DateTime,
    member_nickname  Nullable(String),
    subject          Nullable(String),
    body             Nullable(String)
)
ENGINE = MergeTree
ORDER BY (airport_ident, date);

INSERT INTO raw.airport_comments
SELECT * FROM file(
    'raw-data/airport-comments.csv', 'CSV',
    'id Int32, thread_ref Nullable(Int32), airport_ref Nullable(Int32), airport_ident String,
     date DateTime, member_nickname Nullable(String), subject Nullable(String), body Nullable(String)')
SETTINGS input_format_csv_skip_first_lines = 1;

-- KEEP THIS LAST: the docker healthcheck waits for `dev` to exist = "raw data fully loaded".
CREATE DATABASE IF NOT EXISTS dev;
