-- One row per country: airport and runway totals.
WITH airports AS (
    SELECT * FROM {{ ref('silver_airports') }}
),
runway_totals AS (
    SELECT airport_ident, count() AS runway_count
    FROM {{ ref('silver_runways') }}
    GROUP BY airport_ident
)
SELECT
    a.iso_country,
    count() AS total_airports,
    countIf(a.airport_type = 'closed') AS closed_airports,
    sum(coalesce(r.runway_count, 0)) AS total_runways,
    countIf(coalesce(r.runway_count, 0) > 0) AS airports_with_runways
FROM airports AS a
LEFT JOIN runway_totals AS r ON r.airport_ident = a.airport_ident
GROUP BY a.iso_country
