{#
    Row-level security per care unit, added as a post_hook to the three
    facts that hold per-stay data. dbt drops and recreates these tables on
    every build, which erases their policies. The hook runs in the same
    transaction that builds the table, so the new table never exists
    without its policies; if it fails, the build fails and the old table
    stays.

    The roles come from security/roles.sql, which must have run first.

    Which rows each analyst sees (docs/project-spec.md, "Changes to the
    spec"):
      fact_icu_stay    stays whose first or last care unit is theirs
      fact_vital_sign  vitals of those stays
      fact_lab_result  every lab of an admission with such a stay: ward
                       labs before and after the ICU, and labs from the
                       admission's other ICU stays, so the analyst sees the
                       whole admission
    etl_writer, the pipeline, sees and writes every row. The owner (who
    runs dbt) is not limited by RLS on its own tables.
#}

{% macro analyst_care_units() %}
    {{ return({
        'analyst_micu': 'Medical Intensive Care Unit (MICU)',
        'analyst_sicu': 'Surgical Intensive Care Unit (SICU)',
    }) }}
{% endmacro %}


{% macro row_level_security() %}
    alter table {{ this }} enable row level security;

    create policy etl_writer_all on {{ this }}
        for all to etl_writer
        using (true) with check (true);

    {% if this.identifier == 'fact_icu_stay' %}
        {# One policy per analyst: the care unit is what differs. #}
        {% for role, care_unit in analyst_care_units().items() %}
            create policy {{ role }}_care_unit on {{ this }}
                for select to {{ role }}
                using (exists (
                    select 1
                    from {{ ref('dim_care_unit') }} as cu
                    where
                        cu.care_unit = '{{ care_unit }}'
                        and cu.care_unit_key in (
                            {{ this.identifier }}.first_care_unit_key,
                            {{ this.identifier }}.last_care_unit_key
                        )
                ));
        {% endfor %}

    {#
        The other two facts follow the stays. The subquery runs as the
        analyst, so fact_icu_stay's own policy filters it: each analyst
        finds only their own stays, and one policy serves both analysts.
    #}
    {% elif this.identifier == 'fact_vital_sign' %}
        create policy analysts_visible_stays on {{ this }}
            for select to {{ analyst_care_units().keys() | join(', ') }}
            using (exists (
                select 1
                from {{ ref('fact_icu_stay') }} as s
                where s.stay_id = {{ this.identifier }}.stay_id
            ));

    {% elif this.identifier == 'fact_lab_result' %}
        create policy analysts_visible_admissions on {{ this }}
            for select to {{ analyst_care_units().keys() | join(', ') }}
            using (exists (
                select 1
                from {{ ref('fact_icu_stay') }} as s
                where s.admission_key = {{ this.identifier }}.admission_key
            ));

    {% else %}
        {{ exceptions.raise_compiler_error(
            'row_level_security has no policy for ' ~ this.identifier
        ) }}
    {% endif %}
{% endmacro %}
