#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
WEBSITE="$ROOT/website"

python3 - "$WEBSITE" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
import sys

root = Path(sys.argv[1]).resolve()
index = root / "index.html"

class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []
        self.ids = set()
        self.title = ""
        self.in_title = False
        self.description = None
        self.canonical = None

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if "id" in values:
            self.ids.add(values["id"])
        for attribute in ("href", "src"):
            if attribute in values:
                self.refs.append((tag, attribute, values[attribute]))
        if tag == "title":
            self.in_title = True
        if tag == "meta" and values.get("name") == "description":
            self.description = values.get("content")
        if tag == "link" and values.get("rel") == "canonical":
            self.canonical = values.get("href")

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title += data

parser = SiteParser()
parser.feed(index.read_text(encoding="utf-8"))
errors = []

if not parser.title.strip():
    errors.append("index.html is missing a title")
if not parser.description:
    errors.append("index.html is missing a meta description")
if not parser.canonical:
    errors.append("index.html is missing a canonical URL")

for tag, attribute, value in parser.refs:
    if not value or value.startswith(("mailto:", "tel:", "data:")):
        continue
    parsed = urlparse(value)
    if parsed.scheme in ("http", "https"):
        continue
    if value.startswith("#"):
        if value[1:] not in parser.ids:
            errors.append(f"broken fragment {value}")
        continue
    target = (root / parsed.path).resolve()
    if root not in target.parents and target != root:
        errors.append(f"local reference escapes website root: {value}")
    elif not target.exists():
        errors.append(f"missing local asset: {value}")

for required in ("robots.txt", "sitemap.xml", "styles.css", "script.js"):
    if not (root / required).is_file():
        errors.append(f"missing website file: {required}")

if errors:
    print("Website verification failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"Verified website metadata, fragments, and {len(parser.refs)} references")
PY
