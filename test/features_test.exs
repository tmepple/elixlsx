defmodule Elixlsx.FeaturesTest do
  use ExUnit.Case, async: true

  alias Elixlsx.{Sheet, Workbook, XlsxCheck}

  doctest Elixlsx.Cell
  doctest Elixlsx.Notes

  @sheet1 "xl/worksheets/sheet1.xml"

  defp book(sheets), do: %Workbook{sheets: List.wrap(sheets)}

  defp sheet_xml(sheet), do: sheet |> book() |> XlsxCheck.part(@sheet1)

  # Positions of the given fragments in the XML, to assert the order they come in.
  defp positions(xml, fragments) do
    Enum.map(fragments, fn fragment ->
      case :binary.match(xml, fragment) do
        {pos, _} -> pos
        :nomatch -> flunk("#{inspect(fragment)} not found in:\n#{xml}")
      end
    end)
  end

  defp assert_well_formed(xml),
    do: assert({_doc, []} = :xmerl_scan.string(String.to_charlist(xml)))

  # One workbook with every feature in it, for the checks that look at a whole file.
  defp kitchen_sink do
    data =
      %Sheet{
        name: "Rep's P&L",
        rows: [
          [
            ["Name", bold: true],
            ["Amount", bold: true],
            ["When", bold: true],
            ["Note", bold: true]
          ],
          ["Alpha", [1250.5, num_format: "#,##0.00"], ~D[2026-01-02], "a & b < c"],
          ["Beta", [749.5, num_format: "#,##0.00"], ~N[2026-01-03 13:30:00], :empty],
          [
            "Total",
            [{:formula, "SUM(B2:B3)", value: 2000}, bold: true],
            [{:formula, "MAX(C2:C3)"}, yyyymmdd: true],
            [{:formula, "A2&\"<\"&A3"}]
          ],
          []
        ],
        merge_cells: [{"A6", "B6"}]
      }
      |> Sheet.set_cell("A6", "merged")
      |> Sheet.set_auto_filter("A1:D3")
      |> Sheet.set_page_setup(orientation: :landscape, fit_to_width: 1)
      |> Sheet.set_pane_freeze(1, 0)
      |> Sheet.add_data_validations("A2", "A3", ["Alpha", "Beta"])
      |> Sheet.autofit_col_widths(padding: 2)
      |> Sheet.set_note("B1", "Net of returns & allowances.\nSecond line < third.",
        author: "Ada & Co"
      )
      |> Sheet.set_note("A2", "Largest account")

    plain =
      %Sheet{name: "Plain", rows: [["x", 1], ["y", 2]]}
      |> Sheet.set_auto_filter()
      |> Sheet.set_note("B2", "A note on the second sheet", width: 120, height: 50)

    book([data, plain, %Sheet{name: "Empty"}])
  end

  describe "auto filter" do
    test "is written after sheetData and before mergeCells" do
      xml =
        %Sheet{name: "S", rows: [["a", "b"], [1, 2]], merge_cells: [{"A4", "B4"}]}
        |> Sheet.set_auto_filter()
        |> sheet_xml()

      assert xml =~ ~s(<autoFilter ref="A1:B2"/>)
      [data_end, filter, merges] = positions(xml, ["</sheetData>", "<autoFilter", "<mergeCells"])
      assert data_end < filter and filter < merges
    end

    test "an explicit range is used as given" do
      xml =
        %Sheet{name: "S", rows: [["a", "b"], [1, 2], [3, 4]]}
        |> Sheet.set_auto_filter("A1:B2")
        |> sheet_xml()

      assert xml =~ ~s(<autoFilter ref="A1:B2"/>)
    end

    test "a used-range filter on an empty sheet writes nothing" do
      xml = %Sheet{name: "S"} |> Sheet.set_auto_filter() |> sheet_xml()
      refute xml =~ "autoFilter"
    end

    test "can be removed" do
      xml =
        %Sheet{name: "S", rows: [["a"]]}
        |> Sheet.set_auto_filter()
        |> Sheet.remove_auto_filter()
        |> sheet_xml()

      refute xml =~ "autoFilter"
    end

    test "adds a hidden defined name per filtered sheet, with the sheet name quoted and escaped" do
      filtered = %Sheet{name: "A & B's", rows: [["a", "b"], [1, 2]]} |> Sheet.set_auto_filter()
      workbook = book([%Sheet{name: "First", rows: [["x"]]}, filtered])
      xml = XlsxCheck.part(workbook, "xl/workbook.xml")

      assert xml =~
               ~s(<definedName name="_xlnm._FilterDatabase" localSheetId="1" hidden="1">'A &amp; B''s'!$A$1:$B$2</definedName>)

      [sheets_end, names, calc] = positions(xml, ["</sheets>", "<definedNames>", "<calcPr"])
      assert sheets_end < names and names < calc
      assert_well_formed(xml)
    end

    test "no filter, no defined names" do
      refute XlsxCheck.part(book(%Sheet{name: "S", rows: [["a"]]}), "xl/workbook.xml") =~
               "definedNames"
    end
  end

  describe "workbook window" do
    # Without a size, Excel opens the file filling the whole screen. The values
    # are in twentieths of a point: about 1610 x 966 points, twice XlsxWriter's
    # default in each direction.
    test "has a position and size" do
      xml = XlsxCheck.part(book(%Sheet{name: "S", rows: [["a"]]}), "xl/workbook.xml")

      assert xml =~
               ~s(<workbookView xWindow="240" yWindow="15" windowWidth="32190" windowHeight="19320" activeTab="0"/>)
    end
  end

  describe "notes" do
    defp noted do
      first = %Sheet{name: "First", rows: [["a", "b"], [1, 2]]}

      second =
        %Sheet{name: "Second", rows: [["a", "b"], [1, 2]]}
        |> Sheet.set_note("B2", "Second & last", author: "Ada")
        |> Sheet.set_note("A1", "First <note>", author: "Bob")
        |> Sheet.set_note("$C$5", "On an empty cell", author: "Ada", width: 120, height: 60)

      book([first, second])
    end

    test "only a sheet with notes gets the extra parts, numbered after the sheet" do
      paths = noted() |> XlsxCheck.parts() |> Map.keys()

      assert "xl/comments2.xml" in paths
      assert "xl/drawings/vmlDrawing2.vml" in paths
      assert "xl/worksheets/_rels/sheet2.xml.rels" in paths
      refute Enum.any?(paths, &(&1 =~ ~r/comments1|vmlDrawing1|sheet1\.xml\.rels/))
    end

    test "the comments part lists authors once and notes in row order, escaped" do
      xml = XlsxCheck.part(noted(), "xl/comments2.xml")

      assert xml =~ "<authors><author>Bob</author><author>Ada</author></authors>"

      [a1, b2, c5] =
        positions(xml, [
          ~s(ref="A1" authorId="0"),
          ~s(ref="B2" authorId="1"),
          ~s(ref="C5" authorId="1")
        ])

      assert a1 < b2 and b2 < c5
      assert xml =~ "<t>First &lt;note></t>"
      assert xml =~ "<t>Second &amp; last</t>"
      assert_well_formed(xml)
    end

    test "the drawing has one shape per note, at the note's cell, with unique ids" do
      xml = XlsxCheck.part(noted(), "xl/drawings/vmlDrawing2.vml")

      assert xml =~ ~s(<o:idmap v:ext="edit" data="2"/>)

      assert Regex.scan(~r/<v:shape id="(_x0000_s\d+)"/, xml) |> Enum.map(&List.last/1) == [
               "_x0000_s2049",
               "_x0000_s2050",
               "_x0000_s2051"
             ]

      assert xml =~ "<x:Row>0</x:Row><x:Column>0</x:Column>"
      assert xml =~ "<x:Row>1</x:Row><x:Column>1</x:Column>"
      assert xml =~ "<x:Row>4</x:Row><x:Column>2</x:Column>"
      assert xml =~ "width:120pt;height:60pt"
      assert_well_formed(xml)
    end

    test "the sheet points at the drawing, last among its children" do
      xml = XlsxCheck.part(noted(), "xl/worksheets/sheet2.xml")

      [margins, drawing, close] =
        positions(xml, ["<pageMargins", ~s(<legacyDrawing r:id="rId1"/>), "</worksheet>"])

      assert margins < drawing and drawing < close
      refute XlsxCheck.part(noted(), "xl/worksheets/sheet1.xml") =~ "legacyDrawing"
    end

    test "content types cover the new parts, and a workbook without notes is unchanged" do
      types = XlsxCheck.part(noted(), "[Content_Types].xml")

      assert types =~
               ~s(<Default Extension="vml" ContentType="application/vnd.openxmlformats-officedocument.vmlDrawing"/>)

      assert types =~ ~s(<Override PartName="/xl/comments2.xml")
      assert_well_formed(types)

      plain = XlsxCheck.part(book(%Sheet{name: "S", rows: [["a"]]}), "[Content_Types].xml")
      refute plain =~ "Default"
      refute plain =~ "comments"
    end

    test "every relationship resolves and every part is typed" do
      assert :ok = XlsxCheck.check_package!(noted())
      assert :ok = XlsxCheck.check_package!(book(%Sheet{name: "S", rows: [["a"]]}))
    end

    test "setting a note again replaces it, and it can be removed" do
      sheet = %Sheet{name: "S"} |> Sheet.set_note("A1", "one") |> Sheet.set_note("A1", "two")
      assert sheet.notes["A1"].text == "two"
      assert Sheet.remove_note(sheet, "A1").notes == %{}
    end

    test "unknown options and ranges are refused" do
      assert_raise ArgumentError, ~r/unknown note option\(s\) \[:colour\]/, fn ->
        Sheet.set_note(%Sheet{}, "A1", "x", colour: "red")
      end

      assert_raise ArgumentError, ~r/a note needs a single cell/, fn ->
        Sheet.set_note(%Sheet{}, "A1:B2", "x")
      end
    end
  end

  describe "page setup" do
    test "nothing set leaves fit-to-page off and writes no pageSetup" do
      xml = sheet_xml(%Sheet{name: "S", rows: [["a"]]})
      assert xml =~ ~s(<pageSetUpPr fitToPage="false"/>)
      refute xml =~ "<pageSetup"
    end

    test "orientation alone does not turn fit-to-page on" do
      xml =
        %Sheet{name: "S", rows: [["a"]]}
        |> Sheet.set_page_setup(orientation: :landscape)
        |> sheet_xml()

      assert xml =~ ~s(<pageSetUpPr fitToPage="false"/>)
      assert xml =~ ~s(<pageSetup orientation="landscape"/>)
    end

    test "fit to width defaults the height to as many pages as needed" do
      xml =
        %Sheet{name: "S", rows: [["a"]]}
        |> Sheet.set_page_setup(orientation: :landscape, fit_to_width: 1)
        |> sheet_xml()

      assert xml =~ ~s(<pageSetUpPr fitToPage="true"/>)
      assert xml =~ ~s(<pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/>)
      [margins, setup] = positions(xml, ["<pageMargins", "<pageSetup "])
      assert margins < setup
    end

    test "later calls merge over earlier ones" do
      sheet =
        %Sheet{name: "S"}
        |> Sheet.set_page_setup(orientation: :landscape, fit_to_width: 1)
        |> Sheet.set_page_setup(fit_to_height: 2)

      assert sheet.page_setup == [orientation: :landscape, fit_to_width: 1, fit_to_height: 2]
    end

    test "unknown options are refused" do
      assert_raise ArgumentError, ~r/unknown page setup option :paper/, fn ->
        Sheet.set_page_setup(%Sheet{}, paper: :a4)
      end
    end
  end

  describe "dimension" do
    test "is the used range" do
      assert sheet_xml(%Sheet{name: "S", rows: [["a", "b", "c"], ["d"]]}) =~
               ~s(<dimension ref="A1:C2"/>)

      assert sheet_xml(%Sheet{name: "S", rows: [["a"]]}) =~ ~s(<dimension ref="A1"/>)
      assert sheet_xml(%Sheet{name: "S"}) =~ ~s(<dimension ref="A1"/>)
    end
  end

  describe "formulas" do
    test "text is escaped by the writer" do
      xml = sheet_xml(%Sheet{name: "S", rows: [[{:formula, ~s(A1&"<x>"&'P & L'!B2)}]]})
      assert xml =~ ~s(<f>A1&amp;"&lt;x>"&amp;'P &amp; L'!B2</f>)
      assert_well_formed(xml)
    end

    test "a cached value is kept" do
      assert sheet_xml(%Sheet{name: "S", rows: [[{:formula, "SUM(A2:A3)", value: 7}]]}) =~
               "<v>7</v>"
    end
  end

  describe "dates" do
    test "a Date gets a serial and a default date format" do
      workbook = book(%Sheet{name: "S", rows: [[~D[2026-01-02]]]})
      assert XlsxCheck.part(workbook, @sheet1) =~ "<v>46024.0</v>"
      assert XlsxCheck.part(workbook, "xl/styles.xml") =~ ~s(formatCode="yyyy-mm-dd")
    end

    test "a NaiveDateTime and a DateTime get the date-time format, at wall-clock time" do
      dt = DateTime.from_naive!(~N[2026-01-02 12:00:00], "Etc/UTC")
      workbook = book(%Sheet{name: "S", rows: [[~N[2026-01-02 12:00:00.123456], dt]]})
      xml = XlsxCheck.part(workbook, @sheet1)

      assert length(Regex.scan(~r{<v>46024\.5</v>}, xml)) == 2
      assert XlsxCheck.part(workbook, "xl/styles.xml") =~ ~s(formatCode="yyyy-mm-dd h:mm:ss")
    end

    test "an explicit number format wins over the default" do
      styles =
        XlsxCheck.part(
          book(%Sheet{name: "S", rows: [[[~D[2026-01-02], num_format: "mmm-yy"]]]}),
          "xl/styles.xml"
        )

      assert styles =~ ~s(formatCode="mmm-yy")
      refute styles =~ ~s(formatCode="yyyy-mm-dd")
    end

    test "a formula can carry a date format, with or without a cached value" do
      xml =
        sheet_xml(%Sheet{
          name: "S",
          rows: [
            [
              [{:formula, "DATEVALUE(B7)", value: 45474}, num_format: "mmm-yy"],
              [{:formula, "TODAY()"}, yyyymmdd: true]
            ]
          ]
        })

      assert xml =~ "<f>DATEVALUE(B7)</f>"
      assert xml =~ "<v>45474</v>"
      assert xml =~ "<f>TODAY()</f>"
    end

    test "a bare number in a date-formatted cell is refused, naming the cell" do
      error =
        assert_raise ArgumentError, fn ->
          sheet_xml(%Sheet{name: "S", rows: [["x"], ["y", [45474, num_format: "mmm-yy"]]]})
        end

      assert error.message =~ "Cell B2: a bare number (45474)"
      assert error.message =~ "{:excelts, serial}"
    end

    test "serials and Unix timestamps can be stated explicitly" do
      xml =
        sheet_xml(%Sheet{
          name: "S",
          rows: [
            [
              [{:excelts, 45474}, yyyymmdd: true],
              [{:unix, 1_719_792_000}, yyyymmdd: true],
              [{{2024, 7, 1}, {0, 0, 0}}, yyyymmdd: true]
            ]
          ]
        })

      assert length(Regex.scan(~r{<v>45474(\.0)?</v>}, xml)) == 3
    end

    test "text and blanks may sit in a date-formatted cell" do
      xml =
        sheet_xml(%Sheet{name: "S", rows: [[["When", yyyymmdd: true], [:empty, yyyymmdd: true]]]})

      assert xml =~ ~s(t="s")
      assert_well_formed(xml)
    end
  end

  describe "autofit_col_widths/2" do
    test "counts characters, with fixed widths for dates and formulas" do
      sheet =
        %Sheet{
          rows: [
            ["ab", 12345, ~D[2026-01-02], {:formula, "A1"}, nil, true],
            ["abcdef", 1.5, "x", "y", nil, "z"]
          ]
        }
        |> Sheet.autofit_col_widths()

      assert sheet.col_widths == %{1 => 6, 2 => 5, 3 => 14, 4 => 18, 6 => 8}
    end

    test "respects min and max, and a later set_col_width pins a column" do
      sheet =
        %Sheet{rows: [["a", String.duplicate("x", 80)]]}
        |> Sheet.autofit_col_widths(min: 5, max: 40)
        |> Sheet.set_col_width("A", 12)

      assert sheet.col_widths == %{1 => 12, 2 => 40}
    end
  end

  describe "whole file" do
    test "every part is well-formed XML" do
      for {path, xml} <- XlsxCheck.parts(kitchen_sink()), String.ends_with?(path, ".xml") do
        assert {_doc, []} = :xmerl_scan.string(String.to_charlist(xml)),
               "#{path} is not well-formed"
      end
    end

    @tag :schema
    test "validates against the SpreadsheetML schema" do
      assert :ok = XlsxCheck.validate_schema!(kitchen_sink())
    end

    test "is a consistent package" do
      assert :ok = XlsxCheck.check_package!(kitchen_sink())
    end

    @tag :schema
    test "a plain workbook with none of the new features still validates" do
      plain =
        %Sheet{name: "S", rows: [["a", 1], ["b", 2]], group_rows: [1..2]}
        |> Sheet.set_col_width("A", 20)

      assert :ok = XlsxCheck.validate_schema!(book(plain))
    end

    @tag :schema
    test "the schema check catches an element written out of order" do
      # Guards the guard: if this stops failing, the check has stopped checking.
      workbook = kitchen_sink()
      xml = XlsxCheck.part(workbook, @sheet1)
      [filter] = Regex.run(~r{<autoFilter[^>]*/>}, xml)

      broken =
        xml
        |> String.replace(filter, "")
        |> String.replace("<sheetData>", filter <> "<sheetData>")

      dir = Path.join(System.tmp_dir!(), "elixlsx-broken-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      file = Path.join(dir, "sheet1.xml")
      File.write!(file, broken)
      xsd = Path.join(XlsxCheck.schema_dir(), "sml.xsd")

      assert {output, status} =
               System.cmd("xmllint", ["--noout", "--schema", xsd, file], stderr_to_stdout: true)

      assert status != 0
      assert output =~ "autoFilter"
      File.rm_rf!(dir)
    end

    @tag :interop
    test "openpyxl reads back what was written" do
      read = kitchen_sink() |> XlsxCheck.write_tmp!() |> XlsxCheck.openpyxl_read!()
      sheet = read["sheets"]["Rep's P&L"]

      assert sheet["auto_filter"] == "A1:D3"
      assert sheet["orientation"] == "landscape"
      assert sheet["fit_to_page"] == true
      assert sheet["fit_to_width"] == 1
      assert sheet["fit_to_height"] == 0
      assert sheet["dimensions"] == "A1:D6"
      assert sheet["merged"] == ["A6:B6"]
      assert sheet["freeze_panes"] == "A2"

      assert Enum.at(sheet["cells"], 1) == ["Alpha", 1250.5, "2026-01-02T00:00:00", "a & b < c"]
      assert Enum.at(sheet["cells"], 2) == ["Beta", 749.5, "2026-01-03T13:30:00", nil]
      assert Enum.at(sheet["cells"], 3) == ["Total", "=SUM(B2:B3)", "=MAX(C2:C3)", ~s(=A2&"<"&A3)]
      assert sheet["number_formats"] |> Enum.at(1) |> Enum.at(2) == "yyyy-mm-dd"

      assert sheet["notes"] == %{
               "A2" => "Largest account",
               "B1" => "Net of returns & allowances.\nSecond line < third."
             }

      assert read["sheets"]["Plain"]["auto_filter"] == "A1:B2"
      assert read["sheets"]["Plain"]["notes"] == %{"B2" => "A note on the second sheet"}
      assert read["sheets"]["Empty"]["auto_filter"] in [nil, ""]

      # openpyxl consumes the hidden _xlnm._FilterDatabase names while loading, so
      # they cannot be read back here; the "auto filter" tests assert them in the XML.
    end

    @tag :interop
    @tag timeout: 120_000
    test "LibreOffice opens the file and evaluates its formulas" do
      lines = kitchen_sink() |> XlsxCheck.write_tmp!() |> XlsxCheck.libreoffice_csv!(1)
      total = Enum.at(lines, 3)

      # SUM(B2:B3), MAX(C2:C3) and A2&"<"&A3, as LibreOffice computed them.
      assert total =~ "Total,2000,2026-01-03"
      assert total =~ "Alpha<Beta"
    end
  end
end
