
{{ config(materialized='incremental') }}

WITH src_airport_comments AS (
    SELECT * FROM {{ ref('src_airport_comments') }}
)
SELECT
    comment_id,
    airport_ident,
    comment_timestamp,
    CASE
        WHEN member_nickname IS NULL OR member_nickname = '' THEN '__UNKNOWN__'
        ELSE member_nickname
    END AS member_nickname,
    comment_subject,
    comment_body,
    now() AS loaded_at
FROM src_airport_comments
WHERE comment_body IS NOT NULL AND comment_body != ''
{% if is_incremental() %}
  AND comment_id > (SELECT max(comment_id) FROM {{ this }})
{% endif %}
