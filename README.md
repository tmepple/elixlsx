# Elixlsx

[![Build Status](https://travis-ci.com/xou/elixlsx.svg?branch=master)](https://travis-ci.org/xou/elixlsx)
[![Module Version](https://img.shields.io/hexpm/v/elixlsx.svg)](https://hex.pm/packages/elixlsx)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/elixlsx/)
[![Total Download](https://img.shields.io/hexpm/dt/elixlsx.svg)](https://hex.pm/packages/elixlsx)
[![License](https://img.shields.io/hexpm/l/elixlsx.svg)](https://github.com/xou/elixlsx/blob/master/LICENSE)
[![Last Updated](https://img.shields.io/github/last-commit/xou/elixlsx.svg)](https://github.com/xou/elixlsx/commits/master)

Elixlsx is a writer for the MS Excel OpenXML format (`.xlsx`).

> **This is a maintained fork** of [xou/elixlsx](https://github.com/xou/elixlsx), which has
> had no release since 0.6.0 (March 2024). It is not published to Hex; depend on it by git
> tag (see Installation). Changes since 0.6.0 are in the [changelog](CHANGELOG.md).

Features:

- Multiple (named) sheets with custom column widths & column heights.
- (Unicode-)strings, Numbers, Dates
- Font formatting (size, bold, italic, underline, strike)
- Horizontal alignment and text wrapping
- Font and cell background color, borders
- Merged cells
- Auto filters, page setup (orientation, fit to page)
- Formulas, with an optional cached value


## Installation

Elixlsx requires Elixir 1.12 or above. This fork is installed from GitHub, pinned to a tag:

```elixir
defp deps do
  [{:elixlsx, github: "tmepple/elixlsx", tag: "v0.7.0"}]
end
```

## Usage

1-Line tutorial:

```elixir
(alias Elixlsx.Workbook, alias Elixlsx.Sheet)
iex(1)> Workbook.append_sheet(%Workbook{}, Sheet.with_name("Sheet 1") |> Sheet.set_cell("A1", "Hello", bold: true)) |> Elixlsx.write_to("hello.xlsx")
```

See [example.exs](example.exs) for examples how to use the various features.

- Formula text is escaped by the writer. Write formulas as you would type them in Excel
  (`A1&"<"&B1`); do not XML-escape them yourself, or they will be escaped twice.
- Dates are passed as `Date`, `NaiveDateTime` or `DateTime` structs, or Erlang `:calendar`
  tuples. A bare number in a date-formatted cell raises; use `{:excelts, serial}` or
  `{:unix, seconds}` to say which kind of number it is.

## Development

`mix test` runs everything it has the tools for and says which tests it left out:

- `:schema` tests validate the generated XML against the SpreadsheetML schema with `xmllint`.
  They catch elements written in the wrong order, which Excel answers with a repair prompt.
  Fetch the schemas once with `scripts/fetch_schemas.sh` (they are not part of this repository).
- `:interop` tests have openpyxl read the file back and LibreOffice recalculate it. They need
  `uv` and `soffice` on the path.

When adding a feature, generate a reference file with openpyxl or XlsxWriter and copy the XML
they emit, add the element at its place in `Elixlsx.XMLTemplates.make_sheet/2` (the list there
is in schema order), and open one generated file in Excel itself before tagging.

## Number and date formatting reference

A quick introduction how number formattings look like can be found
[here](https://social.msdn.microsoft.com/Forums/office/en-US/e27aaf16-b900-4654-8210-83c5774a179c/xlsx-numfmtid-predefined-id-14-doesnt-match).


## License

Copyright (c) 2015 Nikolai Weh

This library is MIT licensed. See the [LICENSE](LICENSE) for details.
