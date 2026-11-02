-- Pseudonymization: the function that turns a patient's subject_id into
-- the subject_key in marts.dim_patient.
--
--   subject_key = encode(hmac(subject_id::text, key, 'sha256'), 'hex')
--
-- Why a key: a plain hash is not pseudonymization. MIMIC's subject_ids
-- are 8-digit numbers, so anyone can hash all 100 million of them in
-- minutes and look every hash up again. HMAC mixes in a secret key;
-- without the key nobody can compute the codes, so nobody can build that
-- lookup table. That matches GDPR Art. 4(5): pseudonymized data cannot be
-- linked to a person without additional information kept separately.
--
-- Where the key lives: outside the database, in ICU_HMAC_KEY (.env
-- locally, GitHub Secrets in CI). dbt passes it to dim_patient's
-- transaction as the setting app.hmac_key, which ends with the
-- transaction; the key is never stored in a table. Someone who copies the
-- whole database still cannot reverse a subject_key.
--
-- Rotation: if the key leaks, generate a new one (64 hex characters, e.g.
-- python -c "import secrets; print(secrets.token_hex(32))"), replace it in
-- .env and in GitHub Secrets, and rebuild with dbt. Every subject_key
-- changes, so the leaked key matches nothing any more, and every other
-- column stays the same. The cost: anything saved outside the warehouse
-- under the old subject_keys no longer joins. tests/test_security.py
-- proves this by rebuilding dim_patient with a new key.
--
-- Run as the owner before dbt builds, after roles.sql. Safe to run again.

create extension if not exists pgcrypto;

create schema if not exists privacy;

create or replace function privacy.pseudonymize(value text, hmac_key text)
returns text
language plpgsql
-- Same input, same output: the pseudonym is stable, so a patient can be
-- followed across admissions. strict: a null value gives a null code.
immutable strict
-- pgcrypto is in public; a fixed search_path stops another schema's
-- hmac() from being picked up instead.
set search_path = pg_catalog, public
as $$
begin
    -- Fail rather than produce weak pseudonyms: a short or empty key can
    -- be guessed, and then the codes are no better than a plain hash.
    if length(hmac_key) < 32 then
        raise exception 'pseudonymize: the HMAC key must be at least 32 characters';
    end if;
    return encode(hmac(value, hmac_key, 'sha256'), 'hex');
end
$$;

-- The owner runs it while building dim_patient. Nobody else needs it.
revoke all on function privacy.pseudonymize(text, text) from public;
