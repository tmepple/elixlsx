# Changelog

## 0.8.0

### Added

- Cell notes: `Sheet.set_note/4`, `Sheet.remove_note/2`. A note is the yellow box shown when
  the pointer rests on a cell (Excel 365's "Note"; threaded "Comments" are not written). The
  box's height is estimated from the text unless given. Sheets with notes get a comments part,
  a VML drawing and a relationships part.

### Changed

- The workbook window opens twice as wide and twice as tall as in 0.7.0 (about 1610 x 966 points).

### Internal

- `Elixlsx.XlsxCheck.check_package!/1`: every relationship resolves to a part and every part
  has a content type.
- One CI workflow on current Elixir replaces the two for Elixir 1.12 and 1.15.

## 0.7.0

First release of the [tmepple/elixlsx](https://github.com/tmepple/elixlsx) fork. Not published
to Hex; install from the `v0.7.0` git tag.

### Breaking

- Formula text is escaped by the writer (`&` and `<`). Callers that XML-escaped formulas
  themselves must stop, or the formula is escaped twice.
- A bare number in a date-formatted cell raises `ArgumentError`. It used to be read as a Unix
  timestamp, so a valid Excel serial such as `45474` silently became 1970-01-01. Use
  `{:excelts, serial}` or `{:unix, seconds}`, or pass a date struct.

### Added

- Auto filter: `Sheet.set_auto_filter/1,2`, `Sheet.remove_auto_filter/1`. Covers an explicit
  A1 range or the sheet's used range, and writes the hidden `_xlnm._FilterDatabase` defined
  name alongside.
- Page setup: `Sheet.set_page_setup/2` with `:orientation`, `:fit_to_width`, `:fit_to_height`.
- `Date`, `NaiveDateTime` and `DateTime` structs as cell content, with a default number format
  when the cell has none.
- `Sheet.autofit_col_widths/2`: column widths estimated from the widest cell.
- `Sheet.used_range/1`; `<dimension>` now carries the used range instead of a fixed `A1`.
- The workbook view carries a window position and size, so Excel opens the file in a normal
  window instead of filling the screen.

### Fixed

- A formula with options (`{:formula, f, value: v}`) in a date-formatted cell raised
  `FunctionClauseError`.
- `:empty` or text in a date-formatted cell raised `FunctionClauseError`.
- A sheet with no rows logged a range warning on current Elixir.

### Internal

- The children of `<worksheet>` are assembled from a list kept in schema order.
- Test harness (`Elixlsx.XlsxCheck`): schema validation with `xmllint`, read-back with
  openpyxl, recalculation with LibreOffice.
- Dev dependencies updated so the project builds on current Elixir.

## 0.6.0

! Minimum elixir version raised to ~~1.7 (#116)~~ 1.12 (#140)
- Add cell validations (#109)
- Fix some typos (#120)
- Add a new YYYY-MM date format (#123)
- Fix warnings for range syntax (#139)
- Update README.md, call out requirement to escape '<' and '>' characters (#138)
- Fix: Actually throw ArgumentError when cell content type is invalid (#140)

## 0.5.1

- Revert autofilter support (breaks build)
- Migrate travis-ci.com, fixing the CI system (which apparently failed open for months) 

## 0.5.0

- Autofilter support (#105)
- Namespace XML module (#111, #107)
- Documentation improvements (#103, #106)
- Preserve leading whitespace (#95)
- `mix format` the entire codebase

## 0.4.2

- Dialyzer fixes
- Speed improvements
- XML character validation fixes

## 0.4.1

- Fixes for Dialyzer, documentation.
- Added support for boolean values in cells

## 0.4.0

### Changed

- Increased minimum elixir version required to 1.3
