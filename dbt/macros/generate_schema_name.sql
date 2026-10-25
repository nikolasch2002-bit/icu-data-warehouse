{#
    Build models into the schema they name (staging, marts) instead of
    dbt's default <target schema>_<custom schema>, e.g. dbt_staging.
    The security grants refer to these schemas by name.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ custom_schema_name if custom_schema_name else target.schema }}
{%- endmacro %}
