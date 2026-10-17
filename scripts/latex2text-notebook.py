#!/usr/bin/env python3
import re
import sys
from typing import Optional

from pylatexenc.latex2text import LatexNodes2Text


def convert_cases(source: str) -> Optional[str]:
    match = re.fullmatch(r"\s*\\begin\{cases\}(.*?)\\end\{cases\}\s*", source, re.S)
    if not match:
        return None

    rows = [row.strip() for row in re.split(r"\\\\(?:\[[^\]]*\])?", match.group(1))]
    rows = [row for row in rows if row]
    if not rows:
        return ""

    converter = LatexNodes2Text()
    rendered = [converter.latex_to_text(row.replace("&", "")) for row in rows]
    rendered = [re.sub(r"×(?=\S)", "× ", row) for row in rendered]
    if len(rendered) == 1:
        braces = ["{"]
    else:
        braces = ["⎧"] + ["⎪"] * (len(rendered) - 2) + ["⎩"]
        if len(rendered) == 2:
            braces = ["⎧", "⎩"]
        elif len(rendered) == 3:
            braces = ["⎧", "⎨", "⎩"]
    return "\n".join(f"{brace} {row}" for brace, row in zip(braces, rendered))


def main() -> None:
    source = sys.stdin.read()
    converted = convert_cases(source)
    if converted is None:
        converted = LatexNodes2Text().latex_to_text(source)
    sys.stdout.write(converted)


if __name__ == "__main__":
    main()
