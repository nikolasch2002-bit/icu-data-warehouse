from decimal import Decimal

from analytics.run import format_value, query_files, read_header, to_markdown


def test_read_header():
    sql_text = (
        "-- 01 Title\n"
        "--\n"
        "-- First paragraph,\n"
        "-- over two lines.\n"
        "--\n"
        "-- Second paragraph.\n"
        "\n"
        "select 1\n"
    )
    assert read_header(sql_text) == (
        "01 Title",
        ["First paragraph, over two lines.", "Second paragraph."],
    )


def test_to_markdown():
    table = to_markdown(["a", "b"], [(1, None), (Decimal("2.50"), True)])
    assert table == "| a | b |\n| --- | --- |\n| 1 |  |\n| 2.50 | yes |"


def test_format_value_keeps_decimal_digits():
    # Decimal('1E+1') would print as 1E+1 with str(); results show 10.
    assert format_value(Decimal("1E+1")) == "10"


def test_every_query_has_a_title_and_description():
    for path in query_files():
        title, paragraphs = read_header(path.read_text(encoding="utf-8"))
        assert title.startswith(path.name[:2]), path.name
        assert paragraphs, path.name
