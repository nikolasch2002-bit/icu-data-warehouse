-- dim_date must hold every day between its first and last date, once.
-- A gap would make facts on that day lose their date. Returns a row if the
-- count of days does not match the length of the range.
select
    min(date_day) as first_day,
    max(date_day) as last_day,
    count(*) as n_days
from {{ ref('dim_date') }}
having count(*) <> max(date_day) - min(date_day) + 1
