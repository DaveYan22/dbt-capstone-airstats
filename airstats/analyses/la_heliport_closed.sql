-- Validates the Exercise 9 snapshot: every version of the LA Sheriff's Department
-- Heliport in scd_silver_airports. Note: the assignment's ident 01CN was re-coded
-- to US-9364 in the live OurAirports data.
SELECT
    airport_ident,
    airport_name,
    airport_type,
    dbt_valid_from,
    dbt_valid_to
FROM {{ ref('scd_silver_airports') }}
WHERE airport_ident = 'US-9364'
ORDER BY dbt_valid_from
