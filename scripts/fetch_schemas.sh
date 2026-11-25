#!/usr/bin/env bash
# Downloads the SpreadsheetML schemas (ECMA-376 5th edition, Part 4, Transitional)
# from Ecma International into test/schemas/, where the :schema tests look for
# them. The directory is git-ignored; the schemas are not part of this repository.
set -euo pipefail

url="https://ecma-international.org/wp-content/uploads/ECMA-376-4_5th_edition_december_2016.zip"
dest="$(cd "$(dirname "$0")/.." && pwd)/test/schemas"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $url"
curl -fsSL -o "$tmp/part4.zip" "$url"
unzip -q "$tmp/part4.zip" "OfficeOpenXML-XMLSchema-Transitional.zip" -d "$tmp"
mkdir -p "$dest"
unzip -q -o "$tmp/OfficeOpenXML-XMLSchema-Transitional.zip" -d "$dest"
echo "Schemas written to $dest ($(ls "$dest" | wc -l | tr -d ' ') files)"
