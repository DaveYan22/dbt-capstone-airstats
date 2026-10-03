{% docs airport_ident %}
ICAO airport code, the shared join key across the silver layer. `silver_airports`
owns it, and `silver_runways` and `silver_airport_comments` both reference it.
OurAirports occasionally re-codes airports (for example `01CN` became `US-9364`),
so a historical value may no longer match the current data.
{% enddocs %}
