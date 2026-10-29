-- One row per patient, with a pseudonymous subject_key.
--
-- subject_key = HMAC-SHA256(subject_id, secret key). The key lives outside
-- the database (ICU_HMAC_KEY in .env and in GitHub Secrets). The pre_hook
-- puts it in a setting that lasts only for this model's transaction
-- (set_config(..., true)); the model reads it with current_setting(), and
-- it is never stored in a table.
--
-- A plain hash without a key would not be pseudonymization: anyone could
-- hash every possible subject_id and match the results.
--
-- The hook is a template string, filled in only when it runs. Building it
-- with ~ env_var(...) instead would save the key's value in manifest.json,
-- which the published dbt docs are made from.
{{
    config(
        pre_hook="select set_config('app.hmac_key', '{{ env_var(\"ICU_HMAC_KEY\") }}', true)"
    )
}}

select
    row_number() over (order by subject_id)::integer as patient_key,
    encode(
        hmac(subject_id::text, current_setting('app.hmac_key'), 'sha256'),
        'hex'
    ) as subject_key,
    -- Kept only so the facts can look up patient_key while they are built.
    -- The marts_public views never expose it.
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    anchor_year_group,
    -- Never exposed in marts_public.
    dod
from {{ ref('stg_hosp__patients') }}
