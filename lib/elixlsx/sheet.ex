defmodule Elixlsx.Sheet do
  alias __MODULE__
  alias Elixlsx.Sheet
  alias Elixlsx.Util

  @moduledoc ~S"""
  Describes a single sheet with a given name. The name can be up to 31
  characters long.

  The rows property is a list, each corresponding to a
  row (from the top), of lists, each corresponding to
  a column (from the left), of contents.

  Content may be:

  - a String.t (unicode),
  - a number, or
  - a list [String|number, property_list...]

  The property list describes formatting options for that
  cell. See `Font.from_props/1` for a list of options.
  """
  defstruct name: "",
            rows: [],
            col_widths: %{},
            row_heights: %{},
            group_cols: [],
            group_rows: [],
            merge_cells: [],
            pane_freeze: nil,
            show_grid_lines: true,
            data_validations: [],
            auto_filter: nil,
            page_setup: [],
            notes: %{}

  @type t :: %Sheet{
          name: String.t(),
          rows: list(list(any())),
          col_widths: %{pos_integer => number},
          row_heights: %{pos_integer => number},
          group_cols: list(rowcol_group),
          group_rows: list(rowcol_group),
          merge_cells: [{String.t(), String.t()}],
          pane_freeze: {number, number} | nil,
          show_grid_lines: boolean(),
          data_validations: list({String.t(), String.t(), list(String.t()) | String.t()}),
          auto_filter: nil | true | String.t(),
          page_setup: Keyword.t(),
          notes: %{optional(String.t()) => note}
        }
  @type note :: %{text: String.t(), author: String.t(), width: number | nil, height: number | nil}
  @type rowcol_group :: Range.t() | {Range.t(), opts :: keyword}

  @doc ~S"""
  Create a sheet with a sheet name.

  The name can be up to 31 characters long.
  """
  @spec with_name(String.t()) :: Sheet.t()
  def with_name(name) do
    %Sheet{name: name}
  end

  defp split_cell_content_props(cell) do
    cond do
      is_list(cell) ->
        {hd(cell), tl(cell)}

      true ->
        {cell, []}
    end
  end

  @doc ~S"""
  Returns a "CSV" representation of the Sheet.

  This is mainly used for doctests and does not generate valid CSV (yet).
  """
  def to_csv_string(sheet) do
    Enum.map_join(sheet.rows, "\n", fn row ->
      Enum.map_join(row, ",", fn cell ->
        {content, _} = split_cell_content_props(cell)

        case content do
          nil -> ""
          _ -> to_string(content)
        end
      end)
    end)
  end

  @spec set_cell(Sheet.t(), String.t(), any(), Keyword.t()) :: Sheet.t()
  @doc ~S"""
  Set a cell indexed by excel coordinates.

  ## Examples

      iex> %Elixlsx.Sheet{} |>
      ...> Elixlsx.Sheet.set_cell("C1", "Hello World",
      ...>                bold: true, underline: true) |>
      ...> Elixlsx.Sheet.to_csv_string
      ",,Hello World"

  """

  def set_cell(sheet, index, content, opts \\ []) when is_binary(index) do
    {row, col} = Util.from_excel_coords0(index)
    set_at(sheet, row, col, content, opts)
  end

  @spec set_at(Sheet.t(), non_neg_integer, non_neg_integer, any(), Keyword.t()) :: Sheet.t()
  @doc ~S"""
  Set a cell at a given row/column index.

  Indizes start at 0.

  ## Examples

      iex> %Elixlsx.Sheet{} |>
      ...> Elixlsx.Sheet.set_at(0, 2, "Hello World",
      ...>                bold: true, underline: true) |>
      ...> Elixlsx.Sheet.to_csv_string
      ",,Hello World"

  """
  def set_at(sheet, rowidx, colidx, content, opts \\ [])
      when is_number(rowidx) and is_number(colidx) do
    cond do
      length(sheet.rows) <= rowidx ->
        # append new rows, call self again with new sheet
        n_new_rows = rowidx - length(sheet.rows)
        new_rows = 0..n_new_rows |> Enum.map(fn _ -> [] end)

        update_in(sheet.rows, &(&1 ++ new_rows))
        |> set_at(rowidx, colidx, content, opts)

      length(Enum.at(sheet.rows, rowidx)) <= colidx ->
        n_new_cols = colidx - length(Enum.at(sheet.rows, rowidx))
        new_cols = 0..n_new_cols |> Enum.map(fn _ -> nil end)
        new_row = Enum.at(sheet.rows, rowidx) ++ new_cols

        update_in(sheet.rows, &List.replace_at(&1, rowidx, new_row))
        |> set_at(rowidx, colidx, content, opts)

      true ->
        update_in(sheet.rows, fn rows ->
          List.update_at(rows, rowidx, fn cols ->
            List.replace_at(cols, colidx, [content | opts])
          end)
        end)
    end
  end

  @spec set_col_width(Sheet.t(), String.t(), number) :: Sheet.t()
  @doc ~S"""
  Set the column width for a given column.

  Column is indexed by name ("A", ...)
  """
  def set_col_width(sheet, column, width) do
    update_in(
      sheet.col_widths,
      &Map.put(&1, Util.decode_col(column), width)
    )
  end

  @spec set_row_height(Sheet.t(), number, number) :: Sheet.t()
  @doc ~S"""
  Set the row height for a given row.

  Row is indexed starting from 1
  """
  def set_row_height(sheet, row_idx, height) do
    update_in(
      sheet.row_heights,
      &Map.put(&1, row_idx, height)
    )
  end

  @spec group_cols(Sheet.t(), String.t(), String.t()) :: Sheet.t()
  @doc ~S"""
  Group given column range. (i.e. increase outline level by one)

  Column is indexed by name ("A", ...)

  ## Options

    - `collapsed`: if true, collapse this group.
  """
  def group_cols(sheet, first_col, last_col, opts \\ []) do
    col_range = Range.new(Util.decode_col(first_col), Util.decode_col(last_col))
    new_group = if opts === [], do: col_range, else: {col_range, opts}
    update_in(sheet.group_cols, fn groups -> groups ++ [new_group] end)
  end

  @spec group_rows(Sheet.t(), pos_integer, pos_integer) :: Sheet.t()
  @doc ~S"""
  Group given row range. (i.e. increase outline level by one)

  Row is indexed starting from 1.

  ## Options

    - `collapsed`: if true, collapse this group.
  """
  def group_rows(sheet, first_row_idx, last_row_idx, opts \\ []) do
    row_range = Range.new(first_row_idx, last_row_idx)
    new_group = if opts === [], do: row_range, else: {row_range, opts}
    update_in(sheet.group_rows, fn groups -> groups ++ [new_group] end)
  end

  @spec set_pane_freeze(Sheet.t(), number, number) :: Sheet.t()
  @doc ~S"""
  Set the pane freeze at the given row and column.

  Row and column are indexed starting from 1.
  Special value 0 means no freezing, e.g. {1, 0} will freeze first row and no columns.
  """
  def set_pane_freeze(sheet, row_idx, col_idx) do
    %{sheet | pane_freeze: {row_idx, col_idx}}
  end

  @spec remove_pane_freeze(Sheet.t()) :: Sheet.t()
  @doc ~S"""
  Removes any pane freezing that has been set.
  """
  def remove_pane_freeze(sheet) do
    %{sheet | pane_freeze: nil}
  end

  @spec add_data_validations(Sheet.t(), String.t(), String.t(), String.t() | list(String.t())) ::
          Sheet.t()
  def add_data_validations(sheet, start_cell, end_cell, values) do
    %{sheet | data_validations: [{start_cell, end_cell, values} | sheet.data_validations]}
  end

  @a1_range ~r/^\$?([A-Z]{1,3})\$?([1-9]\d*):\$?([A-Z]{1,3})\$?([1-9]\d*)$/

  @spec set_auto_filter(Sheet.t(), true | String.t()) :: Sheet.t()
  @doc ~S"""
  Puts filter dropdowns on the first row of a range.

  With no range (or `true`) the filter covers the sheet's used range, worked
  out when the file is written, so rows added afterwards are included. An
  explicit range is given in A1 notation; `$` signs are accepted and ignored.

  ## Examples

      iex> sheet = %Elixlsx.Sheet{rows: [["Name", "Amount"], ["a", 1], ["b", 2]]}
      iex> sheet |> Elixlsx.Sheet.set_auto_filter() |> Elixlsx.Sheet.auto_filter_ref()
      "A1:B3"

      iex> %Elixlsx.Sheet{} |> Elixlsx.Sheet.set_auto_filter("$A$1:$D$10") |> Elixlsx.Sheet.auto_filter_ref()
      "A1:D10"

      iex> Elixlsx.Sheet.set_auto_filter(%Elixlsx.Sheet{}, "nope")
      ** (ArgumentError) auto filter range must be in A1 notation such as "A1:D10", got: "nope"

  """
  def set_auto_filter(sheet, range \\ true)
  def set_auto_filter(sheet, true), do: %{sheet | auto_filter: true}

  def set_auto_filter(sheet, range) when is_binary(range) do
    case Regex.run(@a1_range, range) do
      [_, c1, r1, c2, r2] ->
        %{sheet | auto_filter: "#{c1}#{r1}:#{c2}#{r2}"}

      nil ->
        raise ArgumentError,
              "auto filter range must be in A1 notation such as \"A1:D10\", got: #{inspect(range)}"
    end
  end

  @spec remove_auto_filter(Sheet.t()) :: Sheet.t()
  @doc "Removes the auto filter."
  def remove_auto_filter(sheet), do: %{sheet | auto_filter: nil}

  @spec auto_filter_ref(Sheet.t()) :: String.t() | nil
  @doc ~S"""
  The range the auto filter will cover, or `nil` when there is none (no filter
  set, or a used-range filter on a sheet with no cells).
  """
  def auto_filter_ref(%Sheet{auto_filter: nil}), do: nil
  def auto_filter_ref(%Sheet{auto_filter: true} = sheet), do: used_range(sheet)
  def auto_filter_ref(%Sheet{auto_filter: range}) when is_binary(range), do: range

  @spec used_range(Sheet.t()) :: String.t() | nil
  @doc ~S"""
  The A1 range from `A1` to the last row and the widest row's last column, or
  `nil` when the sheet has no cells.

  ## Examples

      iex> Elixlsx.Sheet.used_range(%Elixlsx.Sheet{rows: [["a", "b", "c"], ["d"]]})
      "A1:C2"

      iex> Elixlsx.Sheet.used_range(%Elixlsx.Sheet{})
      nil

  """
  def used_range(%Sheet{rows: rows}) do
    case rows |> Enum.map(&length/1) |> Enum.max(fn -> 0 end) do
      0 -> nil
      last_col -> "A1:" <> Util.to_excel_coords(length(rows), last_col)
    end
  end

  @a1_cell ~r/^\$?([A-Z]{1,3})\$?([1-9]\d*)$/

  @spec set_note(Sheet.t(), String.t(), String.t(), Keyword.t()) :: Sheet.t()
  @doc ~S"""
  Attaches a note to a cell: the yellow box shown when the pointer rests on a
  cell with a red corner mark. A cell holds one note; setting another replaces
  it. The cell does not need to have content.

  Excel 365 calls this a "Note". Its threaded "Comments" are a different
  feature and are not written by this library.

  ## Options

    - `author`: recorded with the note (default `""`). Excel does not show it
      in the box unless it is part of the text.
    - `width`, `height`: size of the box in points. The width defaults to 200
      and the height is estimated from the text.

  ## Examples

      iex> sheet = Elixlsx.Sheet.set_note(%Elixlsx.Sheet{}, "B2", "Typed in by hand", author: "Ada")
      iex> sheet.notes
      %{"B2" => %{text: "Typed in by hand", author: "Ada", width: nil, height: nil}}

      iex> Elixlsx.Sheet.set_note(%Elixlsx.Sheet{}, "B", "text")
      ** (ArgumentError) a note needs a single cell in A1 notation such as "B2", got: "B"

  """
  def set_note(sheet, cell, text, opts \\ []) when is_binary(cell) and is_binary(text) do
    %{sheet | notes: Map.put(sheet.notes, note_cell!(cell), new_note(text, opts))}
  end

  @spec remove_note(Sheet.t(), String.t()) :: Sheet.t()
  @doc "Removes the note on a cell, if there is one."
  def remove_note(sheet, cell) when is_binary(cell) do
    %{sheet | notes: Map.delete(sheet.notes, note_cell!(cell))}
  end

  defp note_cell!(cell) do
    case Regex.run(@a1_cell, cell) do
      [_, col, row] ->
        col <> row

      nil ->
        raise ArgumentError,
              "a note needs a single cell in A1 notation such as \"B2\", got: #{inspect(cell)}"
    end
  end

  defp new_note(text, opts) do
    case Keyword.keys(opts) -- [:author, :width, :height] do
      [] ->
        %{
          text: text,
          author: Keyword.get(opts, :author, ""),
          width: Keyword.get(opts, :width),
          height: Keyword.get(opts, :height)
        }

      unknown ->
        raise ArgumentError,
              "unknown note option(s) #{inspect(unknown)}; known options: [:author, :width, :height]"
    end
  end

  @page_setup_keys [:orientation, :fit_to_width, :fit_to_height]

  @spec set_page_setup(Sheet.t(), Keyword.t()) :: Sheet.t()
  @doc ~S"""
  Sets how the sheet prints.

  ## Options

    - `orientation`: `:portrait` or `:landscape`.
    - `fit_to_width`, `fit_to_height`: scale the sheet to this many pages wide
      and tall. `0` means as many pages as needed. Giving only one of the two
      leaves the other at `0`, so `fit_to_width: 1` prints every column on one
      page width and lets the rows run on.

  Options given here are merged over any set earlier.

  ## Examples

      iex> sheet = Elixlsx.Sheet.set_page_setup(%Elixlsx.Sheet{}, orientation: :landscape, fit_to_width: 1)
      iex> sheet.page_setup
      [orientation: :landscape, fit_to_width: 1]

      iex> Elixlsx.Sheet.set_page_setup(%Elixlsx.Sheet{}, orientation: :sideways)
      ** (ArgumentError) page setup :orientation must be :portrait or :landscape, got: :sideways

  """
  def set_page_setup(sheet, opts) when is_list(opts) do
    Enum.each(opts, &validate_page_setup!/1)
    %{sheet | page_setup: Keyword.merge(sheet.page_setup, opts)}
  end

  defp validate_page_setup!({:orientation, value}) when value in [:portrait, :landscape], do: :ok

  defp validate_page_setup!({:orientation, value}) do
    raise ArgumentError,
          "page setup :orientation must be :portrait or :landscape, got: #{inspect(value)}"
  end

  defp validate_page_setup!({key, value})
       when key in [:fit_to_width, :fit_to_height] and is_integer(value) and value >= 0,
       do: :ok

  defp validate_page_setup!({key, value}) when key in [:fit_to_width, :fit_to_height] do
    raise ArgumentError,
          "page setup #{inspect(key)} must be a non-negative integer, got: #{inspect(value)}"
  end

  defp validate_page_setup!({key, _value}) do
    raise ArgumentError,
          "unknown page setup option #{inspect(key)}; known options: #{inspect(@page_setup_keys)}"
  end

  @spec autofit_col_widths(Sheet.t(), Keyword.t()) :: Sheet.t()
  @doc ~S"""
  Sets each column's width from its widest cell.

  This is an estimate from character counts, not a measurement of rendered
  text: Excel only knows real widths once it lays the sheet out. Text and
  numbers count their characters as written (a number format that adds
  thousands separators or a currency sign is not accounted for), dates count
  by their format, and formulas get a fixed allowance since their result is
  not known here.

  Widths are set for every column that has a non-blank cell, replacing widths
  set earlier. Call `set_col_width/3` afterwards to pin individual columns.

  ## Options

    - `padding`: characters added to every column (default `0`).
    - `min`, `max`: bounds for the resulting width.

  ## Examples

      iex> sheet = %Elixlsx.Sheet{rows: [["Name", "Amount"], ["Alexander", 12.5]]}
      iex> Elixlsx.Sheet.autofit_col_widths(sheet, padding: 2).col_widths
      %{1 => 11, 2 => 8}

  """
  def autofit_col_widths(sheet, opts \\ []) do
    padding = Keyword.get(opts, :padding, 0)
    min = Keyword.get(opts, :min, 0)
    max = Keyword.get(opts, :max)

    widths =
      Enum.reduce(sheet.rows, %{}, fn row, acc ->
        row
        |> Enum.with_index(1)
        |> Enum.reduce(acc, fn {cell, col}, inner ->
          Map.update(inner, col, cell_display_len(cell), &max(&1, cell_display_len(cell)))
        end)
      end)

    # A column holding only blanks keeps the default width.
    widths =
      for {col, len} <- widths, len > 0, into: %{} do
        width = max(len + padding, min)
        {col, if(max, do: min(width, max), else: width)}
      end

    update_in(sheet.col_widths, &Map.merge(&1, widths))
  end

  @formula_len 18
  @other_len 8

  defp cell_display_len(cell) do
    {content, props} = Elixlsx.Cell.normalize(cell)

    cond do
      is_nil(content) or content == :empty -> 0
      props[:datetime] -> 18
      props[:yyyymmdd] -> 14
      props[:yyyymm] -> 10
      is_binary(content) -> String.length(content)
      is_integer(content) or is_float(content) -> content |> to_string() |> String.length()
      match?({:formula, _}, content) or match?({:formula, _, _}, content) -> @formula_len
      true -> @other_len
    end
  end
end
