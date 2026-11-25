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

  @validated ~r{^xl/(workbook\.xml|styles\.xml|worksheets/sheet\d+\.xml|comments\d+\.xml)$}

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

  @doc """
  Checks that the package hangs together: every relationship points at a part
  that exists, and every part has a content type, by its own `Override` or by a
  `Default` for its extension. Excel refuses a file that fails either. Returns
  `:ok` or raises listing the problems.
  """
  @spec check_package!(Workbook.t()) :: :ok
  def check_package!(%Workbook{} = workbook) do
    parts = parts(workbook)
    types = Map.fetch!(parts, "[Content_Types].xml")

    overrides =
      ~r/<Override PartName="\/([^"]+)"/ |> Regex.scan(types) |> MapSet.new(fn [_, p] -> p end)

    defaults =
      ~r/<Default Extension="([^"]+)"/ |> Regex.scan(types) |> MapSet.new(fn [_, e] -> e end)

    untyped =
      for {path, _} <- parts,
          path != "[Content_Types].xml",
          not MapSet.member?(overrides, path),
          not MapSet.member?(defaults, path |> Path.extname() |> String.trim_leading(".")),
          do: "no content type for #{path}"

    dangling =
      for {rels_path, xml} <- parts,
          String.ends_with?(rels_path, ".rels"),
          [_, target] <- Regex.scan(~r/Target="([^"]+)"/, xml),
          resolved = resolve_target(rels_path, target),
          not Map.has_key?(parts, resolved),
          do: "#{rels_path} points at #{resolved}, which is not in the package"

    case untyped ++ dangling do
      [] -> :ok
      problems -> raise "package check failed\n" <> Enum.join(problems, "\n")
    end
  end

  # A relationship target is relative to the folder of the part the .rels file
  # belongs to: xl/worksheets/_rels/sheet1.xml.rels -> xl/worksheets/.
  defp resolve_target(rels_path, target) do
    base = rels_path |> Path.dirname() |> Path.dirname()
    base = if base == ".", do: "", else: base

    [base, target]
    |> Path.join()
    |> Path.split()
    |> Enum.reduce([], fn
      "..", [_ | rest] -> rest
      segment, acc -> [segment | acc]
    end)
    |> Enum.reverse()
    |> Path.join()
  end

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
