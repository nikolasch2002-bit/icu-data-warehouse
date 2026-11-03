{#
    The analysts may read every column of dim_patient except subject_id,
    MIMIC's patient ID. They keep subject_key, the pseudonymous code, to
    follow a patient across admissions, and the date of death, which
    mortality analyses such as ICU-free days need.

    Set as a post_hook on dim_patient. The default privileges in
    security/roles.sql grant the analysts select on the whole table when dbt
    creates it; this hook replaces that with select on the listed columns,
    in the same transaction, so the table never exists with subject_id
    readable. A column added to the model later is not in the list, so the
    analysts cannot read it until it is added here: it fails closed.
#}

{% macro analyst_patient_columns() %}
    revoke select on {{ this }} from analyst_micu, analyst_sicu;

    grant select (
        patient_key,
        subject_key,
        gender,
        anchor_age,
        anchor_year,
        anchor_year_group,
        dod
    ) on {{ this }} to analyst_micu, analyst_sicu;
{% endmacro %}
