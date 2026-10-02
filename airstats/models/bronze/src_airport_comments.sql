{{ config(materialized='ephemeral') }}

WITH comments AS (
    -- source name is "comments" (per Exercise 1), even though the real table is airport_comments
    SELECT * FROM {{ source('airstats', 'comments') }}
)
SELECT
    id AS comment_id,
    airport_ident,
    date AS comment_timestamp,
    member_nickname,
    subject AS comment_subject,
    body AS comment_body
FROM comments
