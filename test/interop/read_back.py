"""Loads an xlsx with openpyxl and prints what it read back, as JSON.

Run by Elixlsx.XlsxCheck.openpyxl_read!/1:
    uv run --no-project --with openpyxl python read_back.py book.xlsx
"""
import json
import sys
import warnings

from openpyxl import load_workbook

# Elixlsx writes no named "Normal" cell style; openpyxl supplies its own and says so.
warnings.filterwarnings("ignore", message="Workbook contains no default style")


def cell_value(cell):
    value = cell.value
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def main(path):
    wb = load_workbook(path)
    sheets = {}
    for ws in wb.worksheets:
        sheets[ws.title] = {
            "dimensions": ws.dimensions,
            "auto_filter": ws.auto_filter.ref,
            "orientation": ws.page_setup.orientation,
            "fit_to_width": ws.page_setup.fitToWidth,
            "fit_to_height": ws.page_setup.fitToHeight,
            "fit_to_page": bool(ws.sheet_properties.pageSetUpPr and ws.sheet_properties.pageSetUpPr.fitToPage),
            "merged": sorted(str(r) for r in ws.merged_cells.ranges),
            "freeze_panes": ws.freeze_panes,
            "notes": {c.coordinate: c.comment.text for row in ws.iter_rows() for c in row if c.comment},
            "cells": [[cell_value(c) for c in row] for row in ws.iter_rows()],
            "number_formats": [[c.number_format for c in row] for row in ws.iter_rows()],
        }
    json.dump({"sheets": sheets}, sys.stdout)


if __name__ == "__main__":
    main(sys.argv[1])
