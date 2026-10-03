-- One row per airport: how many runways and comments it has, and when it was last commented on.
WITH airports AS (
    SELECT * FROM {{ ref('silver_airports') }}
),
runway_counts AS (
    SELECT airport_ident, count() AS runway_count
    FROM {{ ref('silver_runways') }}
    GROUP BY airport_ident
),
comment_counts AS (
    SELECT
        airport_ident,
        count() AS comment_count,
        max(comment_timestamp) AS latest_comment_timestamp
    FROM {{ ref('silver_airport_comments') }}
    GROUP BY airport_ident
)
SELECT
    a.airport_ident AS airport_ident,
    a.airport_name,
    a.iso_country,
    coalesce(r.runway_count, 0) AS runway_count,
    coalesce(c.comment_count, 0) AS comment_count,
    c.latest_comment_timestamp
FROM airports AS a
LEFT JOIN runway_counts AS r ON r.airport_ident = a.airport_ident
LEFT JOIN comment_counts AS c ON c.airport_ident = a.airport_ident
