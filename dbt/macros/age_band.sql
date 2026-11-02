{#
    An age in years as a 10-year band, e.g. 67 -> '60-69', for the
    marts_public views. MIMIC caps ages above 89 at 91, so everyone from 90
    up is '90+'. The demo's youngest patient is 21.

    age is pasted in as SQL text, so it is wrapped in parentheses: for
    'a + b - c', floor(a + b - c / 10) would divide only c.
#}

{% macro age_band(age) %}
    case
        when ({{ age }}) >= 90 then '90+'
        else
            (floor(({{ age }}) / 10) * 10)::integer
            || '-'
            || (floor(({{ age }}) / 10) * 10 + 9)::integer
    end
{% endmacro %}
