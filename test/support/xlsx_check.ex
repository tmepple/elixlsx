defmodule Elixlsx.XlsxCheck do
  @moduledoc """
  Test helpers that check a generated workbook from the outside.

  Three levels, cheapest first:

    * `parts/1` and `part/2` — the package's files in memory, for assertions on
      the XML this library emits.
    * `validate_schema!/1` — runs `xmllint` against the SpreadsheetML schema
      (ECMA-376 Part 4, Transitional). This is what catches a child element of
      `<worksheet>` written out of order, which Excel answers with a repair
      prompt or by dropping the element. Needs `xmllint` and the schemas; fetch
      them with `scripts/fetch_schemas.sh` or point `ELIXLSX_SCHEMA_DIR` at a
      directory holding `sml.xsd`.
    * `openpyxl_read!/1` and `libreoffice_csv!/2` — another implementation opens
      the file. Needs `uv` and `soffice`.

  Tests using the last two levels are tagged `:schema` and `:interop`, and
  `test_helper.exs` excludes a tag when its tools are missing.
  """

  alias Elixlsx.{Compiler, Workbook, Writer}

  @validated ~r{^xl/(workbook\.xml|styles\.xml|worksheets/sheet\d+\.xml)$}

  @doc "The package as `%{path => xml}`."
  @spec parts(Workbook.t()) :: %{String.t() => String.t()}
  def parts(%Workbook{} = workbook) do
    wci = Compiler.make_workbook_comp_info(workbook)

    workbook
    |> Writer.create_files(wci)
    |> Map.new(fn {name, content} -> {to_string(name), IO.iodata_to_binary(content)} end)
  end

  @doc "One file of the package, e.g. `part(workbook, \"xl/worksheets/sheet1.xml\")`."
  @spec part(Workbook.t(), String.t()) :: String.t()
  def part(%Workbook{} = workbook, path), do: Map.fetch!(parts(workbook), path)

  @doc "Directory holding `sml.xsd`, or `nil`."
  @spec schema_dir() :: String.t() | nil
  def schema_dir do
    [System.get_env("ELIXLSX_SCHEMA_DIR"), Path.expand("../schemas", __DIR__)]
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&File.exists?(Path.join(&1, "sml.xsd")))
  end

  @doc "True when `validate_schema!/1` can run."
  def schema_available?, do: schema_dir() != nil and System.find_executable("xmllint") != nil

  @doc "True when `openpyxl_read!/1` and `libreoffice_csv!/2` can run."
  def interop_available?,
    do: System.find_executable("uv") != nil and System.find_executable("soffice") != nil

  @doc """
  Validates the workbook, style and worksheet parts against `sml.xsd`. Returns
  `:ok` or raises with xmllint's messages.

  `sharedStrings.xml` is left out: every writer puts `xml:space="preserve"` on
  `<t>`, and the published schema does not declare that attribute there.
  """
  @spec validate_schema!(Workbook.t()) :: :ok
  def validate_schema!(%Workbook{} = workbook) do
    xsd =
      Path.join(
        schema_dir() || raise("no schema directory; run scripts/fetch_schemas.sh"),
        "sml.xsd"
      )

    dir = tmp_dir("schema")

    failures =
      for {path, xml} <- parts(workbook), path =~ @validated do
        file = Path.join(dir, String.replace(path, "/", "__"))
        File.write!(file, xml)

        case System.cmd("xmllint", ["--noout", "--schema", xsd, file], stderr_to_stdout: true) do
          {_, 0} -> nil
          {output, _} -> "#{path}:\n#{String.replace(output, file, path)}"
        end
      end
      |> Enum.reject(&is_nil/1)

    File.rm_rf!(dir)

    case failures do
      [] -> :ok
      _ -> raise "schema validation failed\n\n" <> Enum.join(failures, "\n")
    end
  end

  @doc "Writes the workbook to a temporary file and returns its path."
  @spec write_tmp!(Workbook.t(), String.t()) :: String.t()
  def write_tmp!(%Workbook{} = workbook, name \\ "book") do
    path = Path.join(tmp_dir("write"), name <> ".xlsx")
    {:ok, _} = Elixlsx.write_to(workbook, path)
    path
  end

  @doc """
  Loads the file with openpyxl and returns what it read back, as a map decoded
  from `test/interop/read_back.py`'s JSON.
  """
  @spec openpyxl_read!(String.t()) :: map()
  def openpyxl_read!(path) do
    script = Path.expand("../interop/read_back.py", __DIR__)
    args = ["run", "--quiet", "--no-project", "--with", "openpyxl", "python", script, path]

    case System.cmd("uv", args, stderr_to_stdout: false) do
      {json, 0} -> Jason.decode!(json)
      {output, status} -> raise "openpyxl could not read #{path} (exit #{status}): #{output}"
    end
  end

  @doc """
  Has LibreOffice recalculate the file and export sheet number `sheet`
  (1-based) to CSV, values as displayed. Returns the CSV lines.
  """
  @spec libreoffice_csv!(String.t(), pos_integer) :: [String.t()]
  def libreoffice_csv!(path, sheet \\ 1) do
    out = Path.dirname(path)
    # 44 = comma, 34 = double quote, 76 = UTF-8, then: first row, column format,
    # language, quote all, detect special numbers, save as shown, formulas, BOM, sheet
    filter = "csv:Text - txt - csv (StarCalc):44,34,76,1,,0,false,true,false,false,false,#{sheet}"
    profile = "-env:UserInstallation=file://" <> tmp_dir("lo-profile")
    args = [profile, "--headless", "--convert-to", filter, "--outdir", out, path]

    case System.cmd("soffice", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, status} -> raise "soffice failed (exit #{status}): #{output}"
    end

    out
    |> Path.join(Path.basename(path, ".xlsx") <> "*.csv")
    |> Path.wildcard()
    |> List.first()
    |> File.read!()
    |> String.split(~r/\r?\n/, trim: true)
  end

  defp tmp_dir(tag) do
    dir = Path.join(System.tmp_dir!(), "elixlsx-#{tag}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end
end
