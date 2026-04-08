#!/usr/bin/env python3
"""Section 508 static lint for CSS/HTML files.

Two execution modes:
  Pre-commit:  lint-508.py file1.html file2.css ...
  Claude Code: reads PostToolUse JSON from stdin (file_path in tool_input)

Exit 0 = clean, exit 1 = violations found.
"""
import json
import re
import sys

# ---------------------------------------------------------------------------
# Skip patterns
# ---------------------------------------------------------------------------
VENDOR_SKIP = ("/vendor/", ".min.css", ".min.js", "/example_data/")

COMMENT_PREFIXES = ("/*", " *", " * ", "<!--", "{#", "#")


def _is_comment(line: str) -> bool:
    stripped = line.lstrip()
    return any(stripped.startswith(p) for p in COMMENT_PREFIXES)


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------
# Each rule: (id, description, file_extensions, checker_fn)
# checker_fn(filepath, lines) -> list[(line_number, message)]

_RE_0D6EFD = re.compile(r"#0d6efd", re.IGNORECASE)

_RE_RGBA = re.compile(r"rgba\s*\(")
_RGBA_CHART_KEYWORDS = re.compile(
    r"chart|Chart|backgroundColor|borderColor|getStatusColor|pointBackground"
    r"|pointBorder|segment|dataset",
    re.IGNORECASE,
)
_RGBA_FULL = re.compile(
    r"rgba\s*\(\s*[\d.]+\s*,\s*[\d.]+\s*,\s*[\d.]+\s*,\s*([\d.]+)\s*\)"
)

_RE_IMG = re.compile(r"<img\b", re.IGNORECASE)
_RE_ALT = re.compile(r"alt\s*=", re.IGNORECASE)

_RE_FORM_EL = re.compile(r"<(input|select|textarea)\b", re.IGNORECASE)
_RE_LABEL_ASSOC = re.compile(
    r"aria-label\s*=|aria-labelledby\s*=|<label\b", re.IGNORECASE
)
_RE_TYPE_HIDDEN = re.compile(r'type\s*=\s*["\']hidden["\']', re.IGNORECASE)

_RE_TH = re.compile(r"<th\b", re.IGNORECASE)
_RE_SCOPE = re.compile(r"scope\s*=", re.IGNORECASE)

_RE_FA_ICON = re.compile(r'<i\b[^>]*class\s*=\s*["\'][^"\']*\bfa[-\s]', re.IGNORECASE)
_RE_ARIA_HIDDEN = re.compile(r"aria-hidden", re.IGNORECASE)

_RE_BLANK = re.compile(r'target\s*=\s*["\']_blank["\']', re.IGNORECASE)
_RE_VH = re.compile(r"visually-hidden", re.IGNORECASE)

_RE_CANVAS = re.compile(r"<canvas\b", re.IGNORECASE)
_RE_ROLE_IMG = re.compile(r'role\s*=\s*["\']img["\']', re.IGNORECASE)

_RE_REQUIRED = re.compile(r"\brequired\b", re.IGNORECASE)
_RE_ARIA_REQUIRED = re.compile(r"aria-required", re.IGNORECASE)


def _get_tag_text(lines: list[str], start: int, lookahead: int = 5) -> str:
    """Join lines from start through the closing '>' or lookahead limit."""
    buf = lines[start]
    if ">" in buf:
        return buf
    end = min(start + lookahead, len(lines))
    for i in range(start + 1, end):
        buf += " " + lines[i]
        if ">" in lines[i]:
            break
    return buf


def _context_window(lines: list[str], idx: int, radius: int = 2) -> str:
    """Return a few surrounding lines joined for keyword searching."""
    lo = max(0, idx - radius)
    hi = min(len(lines), idx + radius + 1)
    return " ".join(lines[lo:hi])


# -- Individual rule checkers ------------------------------------------------


def check_e001(filepath: str, lines: list[str]) -> list[tuple[int, str]]:
    """508-E001: Bootstrap default #0d6efd used instead of EEOC override."""
    hits = []
    for i, line in enumerate(lines):
        if _is_comment(line):
            continue
        if _RE_0D6EFD.search(line):
            hits.append((i + 1, "Bootstrap default #0d6efd — use EEOC override color"))
    return hits


def check_e002(filepath: str, lines: list[str]) -> list[tuple[int, str]]:
    """508-E002: rgba() with opacity < 1.0 in chart color context."""
    hits = []
    for i, line in enumerate(lines):
        if _is_comment(line):
            continue
        if not _RE_RGBA.search(line):
            continue
        ctx = _context_window(lines, i)
        if not _RGBA_CHART_KEYWORDS.search(ctx):
            continue
        for m in _RGBA_FULL.finditer(line):
            opacity = float(m.group(1))
            if opacity < 1.0:
                hits.append(
                    (i + 1, f"rgba() with opacity {opacity} in chart context — use solid rgb()")
                )
                break
    return hits


def check_e003(filepath: str, lines: list[str]) -> list[tuple[int, str]]:
    """508-E003: <img> missing alt attribute."""
    hits = []
    for i, line in enumerate(lines):
        if _RE_IMG.search(line):
            tag = _get_tag_text(lines, i)
            if not _RE_ALT.search(tag):
                hits.append((i + 1, '<img> missing alt attribute'))
    return hits


_RE_HAS_ID = re.compile(r'\bid\s*=\s*["\']', re.IGNORECASE)


def check_e004(filepath: str, lines: list[str]) -> list[tuple[int, str]]:
    """508-E004: Form element without label association."""
    hits = []
    for i, line in enumerate(lines):
        m = _RE_FORM_EL.search(line)
        if not m:
            continue
        tag = _get_tag_text(lines, i)
        if _RE_TYPE_HIDDEN.search(tag):
            continue
        if _RE_LABEL_ASSOC.search(tag):
            continue
        # id= implies a <label for="..."> elsewhere in the template
        if _RE_HAS_ID.search(tag):
            continue
        # Check preceding lines for <label>
        for back in range(1, 4):
            if i >= back and re.search(r"<label\b", lines[i - back], re.IGNORECASE):
                break
        else:
            hits.append((i + 1, f'<{m.group(1)}> missing aria-label, aria-labelledby, or associated <label>'))
    return hits


def check_e005(filepath: str, lines: list[str]) -> list[tuple[int, str]]:
    """508-E005: <th> missing scope attribute."""
    hits = []
    for i, line in enumerate(lines):
        if _RE_TH.search(line):
            tag = _get_tag_text(lines, i)
            if not _RE_SCOPE.search(tag):
                hits.append((i + 1, '<th> missing scope attribute'))
    return hits


def check_e006(filepath: str, lines: list[str]) -> list[tuple[int, str]]:
    """508-E006: Font Awesome icon missing aria-hidden."""
    hits = []
    for i, line in enumerate(lines):
        if _RE_FA_ICON.search(line):
            tag = _get_tag_text(lines, i)
            if not _RE_ARIA_HIDDEN.search(tag):
                hits.append((i + 1, 'Icon missing aria-hidden="true"'))
    return hits


def check_e007(filepath: str, lines: list[str]) -> list[tuple[int, str]]:
    """508-E007: target='_blank' without visually-hidden SR indicator."""
    hits = []
    for i, line in enumerate(lines):
        if _RE_BLANK.search(line):
            ctx = _context_window(lines, i, radius=3)
            if not _RE_VH.search(ctx):
                hits.append((i + 1, 'target="_blank" without visually-hidden SR indicator'))
    return hits


def check_e008(filepath: str, lines: list[str]) -> list[tuple[int, str]]:
    """508-E008: <canvas> missing role='img'."""
    hits = []
    for i, line in enumerate(lines):
        if _RE_CANVAS.search(line):
            tag = _get_tag_text(lines, i)
            if not _RE_ROLE_IMG.search(tag):
                hits.append((i + 1, '<canvas> missing role="img"'))
    return hits


def check_e009(filepath: str, lines: list[str]) -> list[tuple[int, str]]:
    """508-E009: required attribute without aria-required."""
    hits = []
    for i, line in enumerate(lines):
        if _RE_REQUIRED.search(line):
            tag = _get_tag_text(lines, i)
            if not _RE_ARIA_REQUIRED.search(tag):
                # Skip lines that are purely aria-required (no bare required)
                stripped = _RE_ARIA_REQUIRED.sub("", tag)
                if _RE_REQUIRED.search(stripped):
                    hits.append((i + 1, 'required without aria-required="true"'))
    return hits


# -- Rule registry -----------------------------------------------------------

CSS_RULES = [check_e001]
HTML_RULES = [
    check_e001,
    check_e002,
    check_e003,
    check_e004,
    check_e005,
    check_e006,
    check_e007,
    check_e008,
    check_e009,
]


# ---------------------------------------------------------------------------
# File processing
# ---------------------------------------------------------------------------


def lint_file(filepath: str) -> list[tuple[int, str, str]]:
    """Return list of (line_number, rule_id, message) for a single file."""
    if any(skip in filepath for skip in VENDOR_SKIP):
        return []

    is_html = filepath.endswith(".html")
    is_css = filepath.endswith(".css")
    if not (is_html or is_css):
        return []

    try:
        with open(filepath, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return []

    rules = HTML_RULES if is_html else CSS_RULES
    results = []
    for checker in rules:
        rule_id = checker.__doc__.split(":")[0] if checker.__doc__ else "508-E000"
        for lineno, msg in checker(filepath, lines):
            results.append((lineno, rule_id, msg))

    results.sort(key=lambda r: r[0])
    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    # Determine file list from args or stdin JSON
    if len(sys.argv) > 1:
        files = sys.argv[1:]
    else:
        try:
            data = json.load(sys.stdin)
            path = data.get("tool_input", {}).get("file_path", "")
            files = [path] if path else []
        except (json.JSONDecodeError, KeyError):
            files = []

    violations = []
    for filepath in files:
        for lineno, rule_id, msg in lint_file(filepath):
            violations.append(f"{filepath}:{lineno}: [{rule_id}] {msg}")

    if violations:
        for v in violations:
            print(v)
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
