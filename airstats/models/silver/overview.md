{% docs __overview__ %}
# AirStats silver layer

`silver_airports` is the hub: one row per airport, keyed by `airport_ident`.

`silver_runways` (one row per runway) and `silver_airport_comments` (one row per
comment) each reference an airport through `airport_ident`. A runway or comment
belongs to exactly one airport, while an airport can have many of each. The
runways and comments tables do not reference each other directly; they connect
only through `silver_airports`.

The relationship tests are set to `severity: warn` because the source data is
crowd-sourced and referential integrity is not guaranteed. The snapshots
`scd_silver_airports` and `scd_silver_runways` record how these records change
over time.
{% enddocs %}
