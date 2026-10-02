-- No comment should be timestamped after it was loaded.
SELECT *
FROM {{ ref('silver_airport_comments') }}
WHERE comment_timestamp > now()
