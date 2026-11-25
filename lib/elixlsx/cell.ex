defmodule Elixlsx.Cell do
  @moduledoc ~S"""
  Normalizes a cell as given in `Elixlsx.Sheet` rows into `{content, props}`.

  A cell is either bare content or a list `[content | props]`. Both the
  compiler pass (which registers strings and styles) and the XML writer go
  through `normalize/1`, so whatever is decided here is seen consistently by
  both.

  ## Date and time structs

  `Date`, `NaiveDateTime` and `DateTime` structs are accepted as content. They
  are converted to an Excel serial (`{:excelts, number}`), and when the cell
  carries no number format of its own a default is applied: `yyyy-mm-dd` for a
  `Date`, `yyyy-mm-dd h:mm:ss` for the other two.

  Excel has no notion of time zones. A `DateTime` is written as its wall-clock
  time in its own zone; shift it to the zone you want before passing it.

      iex> Elixlsx.Cell.normalize(~D[2026-01-02])
      {{:excelts, 46024.0}, [yyyymmdd: true]}

      iex> Elixlsx.Cell.normalize([~N[2026-01-02 12:00:00], bold: true])
      {{:excelts, 46024.5}, [bold: true, datetime: true]}

      iex> Elixlsx.Cell.normalize([~D[2026-01-02], num_format: "mmm-yy"])
      {{:excelts, 46024.0}, [num_format: "mmm-yy"]}

      iex> Elixlsx.Cell.normalize(["Hello", bold: true])
      {"Hello", [bold: true]}

      iex> Elixlsx.Cell.normalize(42)
      {42, []}
  """

  alias Elixlsx.Util

  @numfmt_props [:yyyymmdd, :yyyymm, :datetime, :num_format]

  @type content :: any
  @type props :: Keyword.t()

  @doc "Splits a cell into `{content, props}` without converting anything."
  @spec split(any) :: {content, props}
  def split([content | props]), do: {content, props}
  def split(content), do: {content, []}

  @doc "Splits a cell into `{content, props}`, converting date and time structs."
  @spec normalize(any) :: {content, props}
  def normalize(cell) do
    {content, props} = split(cell)
    convert(content, props)
  end

  defp convert(%Date{} = date, props) do
    {Util.to_excel_datetime({Date.to_erl(date), {0, 0, 0}}), default_numfmt(props, :yyyymmdd)}
  end

  defp convert(%NaiveDateTime{} = ndt, props) do
    {ndt |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_erl() |> Util.to_excel_datetime(),
     default_numfmt(props, :datetime)}
  end

  defp convert(%DateTime{} = dt, props), do: convert(DateTime.to_naive(dt), props)

  defp convert(content, props), do: {content, props}

  defp default_numfmt(props, default) do
    if Enum.any?(@numfmt_props, &props[&1]), do: props, else: props ++ [{default, true}]
  end
end
