defmodule Elixlsx.Notes do
  @moduledoc ~S"""
  Generates the package parts behind cell notes (`Elixlsx.Sheet.set_note/4`).

  A note is the yellow box that appears when the pointer rests on a cell with a
  red corner mark. Excel 365 calls it a "Note"; older versions and the file
  format call it a comment. (What Excel 365 calls a "Comment", the threaded
  kind, is a different and newer structure that this library does not write.)

  A sheet with notes needs three extra parts, plus one element in the sheet:

    * `xl/commentsN.xml` holds the text and authors.
    * `xl/drawings/vmlDrawingN.vml` holds one shape per note. Excel draws the
      box from this legacy VML drawing, and shows nothing without it.
    * `xl/worksheets/_rels/sheetN.xml.rels` links the sheet to both.
    * `<legacyDrawing r:id="..."/>` in the sheet points at the drawing.

  The XML follows what openpyxl and XlsxWriter emit.
  """

  alias Elixlsx.Sheet
  alias Elixlsx.Util
  alias Elixlsx.XMLTemplates

  @vml_rid "rId1"
  @comments_rid "rId2"

  # Points. The height is estimated from the text when not given.
  @default_width 200
  @line_height 12
  @min_height 40
  @avg_char_width 5

  @doc "The relationship id of the VML drawing, for the sheet's `<legacyDrawing>`."
  def vml_rid, do: @vml_rid

  @doc "True when the sheet has at least one note."
  @spec any?(Sheet.t()) :: boolean
  def any?(%Sheet{notes: notes}), do: map_size(notes) > 0

  @doc """
  The notes as `{row, col, note}` (both 1-based), in row-then-column order.
  """
  def sorted(%Sheet{notes: notes}) do
    notes
    |> Enum.map(fn {cell, note} ->
      {row, col} = Util.from_excel_coords(cell)
      {row, col, note}
    end)
    |> Enum.sort_by(fn {row, col, _} -> {row, col} end)
  end

  @doc "`xl/commentsN.xml`."
  @spec comments_xml(Sheet.t()) :: String.t()
  def comments_xml(%Sheet{} = sheet) do
    notes = sorted(sheet)
    authors = notes |> Enum.map(fn {_, _, note} -> note.author end) |> Enum.uniq()
    author_id = authors |> Enum.with_index() |> Map.new()

    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <authors>#{Enum.map_join(authors, &"<author>#{escape(&1)}</author>")}</authors>
    <commentList>
    #{Enum.map_join(notes, "\n", &comment_xml(&1, author_id))}
    </commentList>
    </comments>
    """
  end

  defp comment_xml({row, col, note}, author_id) do
    ref = Util.to_excel_coords(row, col)

    "<comment ref=\"#{ref}\" authorId=\"#{author_id[note.author]}\"><text><r>" <>
      "<rPr><sz val=\"9\"/><color indexed=\"81\"/><rFont val=\"Tahoma\"/><family val=\"2\"/></rPr>" <>
      "<t>#{escape(note.text)}</t></r></text></comment>"
  end

  @doc """
  `xl/drawings/vmlDrawingN.vml`. `sheet_id` is the sheet's 1-based number; it
  keeps the shape ids of different sheets apart.
  """
  @spec vml_xml(Sheet.t(), pos_integer) :: String.t()
  def vml_xml(%Sheet{} = sheet, sheet_id) do
    shapes =
      sheet
      |> sorted()
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {note, n} -> shape_xml(note, sheet_id * 1024 + n, n) end)

    """
    <xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel">
    <o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="#{sheet_id}"/></o:shapelayout>
    <v:shapetype id="_x0000_t202" coordsize="21600,21600" o:spt="202" path="m,l,21600r21600,l21600,xe"><v:stroke joinstyle="miter"/><v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype>
    #{shapes}
    </xml>
    """
  end

  defp shape_xml({row, col, note}, shape_id, z_index) do
    {width, height} = box_size(note)

    style =
      "position:absolute;margin-left:59.25pt;margin-top:1.5pt;" <>
        "width:#{width}pt;height:#{height}pt;z-index:#{z_index};visibility:hidden"

    "<v:shape id=\"_x0000_s#{shape_id}\" type=\"#_x0000_t202\" style=\"#{style}\" fillcolor=\"#ffffe1\" o:insetmode=\"auto\">" <>
      "<v:fill color2=\"#ffffe1\"/><v:shadow on=\"t\" color=\"black\" obscured=\"t\"/><v:path o:connecttype=\"none\"/>" <>
      "<v:textbox style=\"mso-direction-alt:auto\"><div style=\"text-align:left\"></div></v:textbox>" <>
      "<x:ClientData ObjectType=\"Note\"><x:MoveWithCells/><x:SizeWithCells/><x:AutoFill>False</x:AutoFill>" <>
      "<x:Row>#{row - 1}</x:Row><x:Column>#{col - 1}</x:Column></x:ClientData></v:shape>"
  end

  @doc ~S"""
  The note box's `{width, height}` in points. A height that was not given is
  estimated from the text, so a long note is not cut off.

      iex> Elixlsx.Notes.box_size(%{text: "short", width: nil, height: nil})
      {200, 40}

      iex> Elixlsx.Notes.box_size(%{text: String.duplicate("word ", 60), width: nil, height: nil})
      {200, 106}

      iex> Elixlsx.Notes.box_size(%{text: "anything", width: 120, height: 60})
      {120, 60}
  """
  def box_size(%{text: text, width: width, height: height}) do
    width = width || @default_width
    {width, height || estimate_height(text, width)}
  end

  defp estimate_height(text, width) do
    chars_per_line = max(div(width, @avg_char_width), 1)

    lines =
      text
      |> String.split("\n")
      |> Enum.map(&max(ceil(String.length(&1) / chars_per_line), 1))
      |> Enum.sum()

    max(lines * @line_height + 10, @min_height)
  end

  @doc "`xl/worksheets/_rels/sheetN.xml.rels`."
  @spec rels_xml(pos_integer) :: String.t()
  def rels_xml(sheet_id) do
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="#{@vml_rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing" Target="../drawings/vmlDrawing#{sheet_id}.vml"/>
    <Relationship Id="#{@comments_rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="../comments#{sheet_id}.xml"/>
    </Relationships>
    """
  end

  defp escape(text), do: XMLTemplates.minimal_xml_text_escape(text)
end
