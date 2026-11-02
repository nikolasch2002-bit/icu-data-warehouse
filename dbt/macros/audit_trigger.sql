{#
    Attaches the audit trigger from security/audit.sql to a dimension, so
    every insert, update and delete on it is logged in audit.change_log.

    Set as a post_hook on all of marts in dbt_project.yml; it adds the
    trigger to the dim_* tables and nothing to the facts. dbt recreates the
    dimensions on every build, and a trigger is dropped with its table, so
    the hook adds it again in the same transaction that creates the table.
    security/audit.sql must have run first: it creates the function.
#}

{% macro audit_trigger() %}
    {% if this.identifier.startswith('dim_') %}
        create trigger audit_changes
        after insert or update or delete on {{ this }}
        for each row execute function audit.log_change();
    {% endif %}
{% endmacro %}
