-- subject_key must depend on the secret key. If it equalled a plain SHA-256
-- of subject_id (for example because the key was empty), anyone could
-- rebuild it by hashing every possible subject_id. Returns any patient
-- whose subject_key is a plain hash, or is not 64 hex characters.
select
    patient_key,
    subject_key
from {{ ref('dim_patient') }}
where
    subject_key = encode(digest(subject_id::text, 'sha256'), 'hex')
    or subject_key !~ '^[0-9a-f]{64}$'
