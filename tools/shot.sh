#!/usr/bin/env bash
# Render a captured terminal log as a PNG "screenshot".
# Usage: tools/shot.sh <output.txt> <out.png> [title]
set -e
in=$1; out=$2; title=${3:-Terminal}
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
html=$(mktemp).html
lines=$(wc -l < "$in")
height=$(( lines * 19 + 90 ))
{
  echo "<html><body style='margin:0;background:#1e1e1e'>"
  echo "<div style='background:#323233;color:#ccc;font:13px -apple-system;padding:8px 14px'>&#9679; &#9679; &#9679; &nbsp; $title</div>"
  echo "<pre style='margin:0;padding:14px;color:#d4d4d4;font:13px/19px Menlo,monospace;white-space:pre-wrap'>"
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
      -e 's/^\(\$ .*\)$/<span style="color:#4ec9b0">\1<\/span>/' \
      -e 's/^\(#.*\)$/<span style="color:#6a9955">\1<\/span>/' "$in"
  echo "</pre></body></html>"
} > "$html"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1000,$height \
  --screenshot="$out" "file://$html" >/dev/null 2>&1
rm -f "$html"
