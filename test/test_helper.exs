alias Elixlsx.XlsxCheck

# Tests that need outside tools are skipped, with a notice, when the tools are
# missing. See Elixlsx.XlsxCheck.
exclude =
  [
    schema:
      {XlsxCheck.schema_available?(), "xmllint and the schemas (run scripts/fetch_schemas.sh)"},
    interop: {XlsxCheck.interop_available?(), "uv and soffice (LibreOffice)"}
  ]
  |> Enum.flat_map(fn
    {_tag, {true, _needs}} ->
      []

    {tag, {false, needs}} ->
      IO.puts("Excluding :#{tag} tests: they need #{needs}.")
      [tag]
  end)

ExUnit.start(exclude: exclude)
