-- A runway can't physically have zero or negative length. NULL is allowed
-- (unknown length), only a present-but-impossible value should fail.
-- severity: warn -- real finding, not a bug: 6 real runways have
-- length_ft=0 paired with surface='UNK', meaning the source data uses 0 as
-- a placeholder for "genuinely unknown" rather than NULL. Keeping this
-- visible rather than excluding length_ft=0 from the WHERE clause.
{{ config(severity='warn') }}
SELECT *
FROM {{ ref('silver_runways') }}
WHERE runway_length_ft IS NOT NULL AND runway_length_ft <= 0
