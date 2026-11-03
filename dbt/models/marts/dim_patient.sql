-- One row per patient, with a pseudonymous subject_key.
--
-- subject_key = HMAC-SHA256(subject_id, secret key), computed by
-- privacy.pseudonymize() from security/pseudonymize.sql, which explains
-- why a key is needed and how to rotate it. The key lives outside the
-- database (ICU_HMAC_KEY in .env and in GitHub Secrets). The pre_hook puts
-- it in a setting that lasts only for this model's transaction
-- (set_config(..., true)); the model reads it with current_setting(), and
-- it is never stored in a table.
--
-- The hook is a template string, filled in only when it runs. Building it
-- with ~ env_var(...) instead would save the key's value in manifest.json,
-- which the published dbt docs are made from.
--
-- The post_hook lets the analysts read every column but subject_id: see
-- macros/analyst_patient_columns.sql.
{{
    config(
        pre_hook="select set_config('app.hmac_key', '{{ env_var(\"ICU_HMAC_KEY\") }}', true)",
        post_hook="{{ analyst_patient_columns() }}"
    )
}}

select
    row_number() over (order by subject_id)::integer as patient_key,
    privacy.pseudonymize(
        subject_id::text, current_setting('app.hmac_key')
    ) as subject_key,
    -- Kept only so the facts can look up patient_key while they are built.
    -- The marts_public views never expose it, and the analysts cannot
    -- read it.
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    anchor_year_group,
    -- Never exposed in marts_public.
    dod
from {{ ref('stg_hosp__patients') }}
