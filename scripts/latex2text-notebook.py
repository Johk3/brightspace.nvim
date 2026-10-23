#!/usr/bin/env python3
"""Render notebook LaTeX as readable, unambiguous Unicode text.

pylatexenc's default math output drops grouping (``\\frac{1}{s + 1}`` becomes
``1/s + 1``), eats the space after operator macros (``c ×θ``) and joins aligned
rows with blank lines. This converter keeps pylatexenc's symbol tables and
fixes the structure: fractions and scripts keep their grouping, relations get
spaces, and aligned/cases environments render as aligned rows.
"""
import re
import sys
import unicodedata

from pylatexenc import latexwalker
from pylatexenc.latex2text import (
    EnvironmentTextSpec,
    LatexNodes2Text,
    MacroTextSpec,
    get_default_latex_context_db,
)

FRACTIONS = {"frac", "dfrac", "tfrac", "cfrac"}
ROW_BREAKS = {"\\", "cr"}
# Column-paired environments align like LaTeX's {rlrl...} columns.
ALIGNED = {"align", "align*", "aligned", "alignat", "alignat*", "alignedat", "split", "eqnarray", "eqnarray*"}
STACKED = {"gather", "gather*", "gathered", "multline", "multline*"}
MATRICES = {
    "matrix": "[]", "smallmatrix": "[]", "array": "[]", "bmatrix": "[]", "bsmallmatrix": "[]",
    "pmatrix": "()", "psmallmatrix": "()", "Bmatrix": "{}", "vmatrix": "||", "Vmatrix": "‖‖",
}
RELATIONS = re.compile(r"(?<=[^ \n])[ ]*(\+=|-=|:=|[=≠≈≤≥<>→←⇒⇐⇔↦×·±∓≡∼≃∝∈∉⊂⊆⊃⊇])[ ]*(?=[^ \n])")
# Padding uses no-break spaces so relation spacing never collapses alignment.
PAD = " "
ATOM = re.compile(r"[\w.^'̀-ͯ′]+")


def width(text):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def wrapped(text):
    """True when text is one parenthesized group, e.g. ``(a + b)`` but not ``(a)(b)``."""
    if not (text.startswith("(") and text.endswith(")")):
        return False
    depth = 0
    for i, c in enumerate(text):
        depth += c == "("
        depth -= c == ")"
        if depth == 0 and i < len(text) - 1:
            return False
    return True


def group(text):
    text = text.strip()
    return text if ATOM.fullmatch(text) or wrapped(text) else "(" + text + ")"


def word_start(text):
    return bool(text) and (text[0].isalnum() or text[0] == "(")


def fraction(node, l2tobj):
    return group(l2tobj.node_arg_to_text(node, 0)) + "/" + group(l2tobj.node_arg_to_text(node, 1))


def rows(node, l2tobj):
    """Split an environment body on ``\\\\`` and ``&`` into converted cells."""
    table, row, cell = [], [], []

    def end_cell():
        row.append(l2tobj.nodelist_to_text(cell).strip())
        cell.clear()

    for child in node.nodelist:
        if child.isNodeType(latexwalker.LatexSpecialsNode) and child.specials_chars == "&":
            end_cell()
        elif child.isNodeType(latexwalker.LatexMacroNode) and child.macroname in ROW_BREAKS:
            end_cell()
            table.append(row)
            row = []
        else:
            cell.append(child)
    end_cell()
    table.append(row)
    return [r for r in table if any(r)]


def aligned(node, l2tobj):
    table = rows(node, l2tobj)
    columns = max((len(r) for r in table), default=0)
    widths = [max((width(r[i]) for r in table if i < len(r)), default=0) for i in range(columns)]
    lines = []
    for r in table:
        line = ""
        for i, cell in enumerate(r):
            pad = PAD * (widths[i] - width(cell))
            if i % 2 == 0:
                line += (PAD * 3 if i else "") + pad + cell
            else:
                line += cell + (pad if i < len(r) - 1 else "")
        lines.append(line)
    return "\n".join(lines)


def stacked(node, l2tobj):
    return "\n".join(" ".join(c for c in r if c) for r in rows(node, l2tobj))


def matrix(node, l2tobj, environmentname):
    opening, closing = MATRICES[environmentname]
    return opening + "; ".join(", ".join(r) for r in rows(node, l2tobj)) + closing


def trailing_space(node):
    """Whitespace LaTeX swallowed after a macro, including after its last argument."""
    if not node.isNodeType(latexwalker.LatexMacroNode):
        return ""
    args = [a for a in (node.nodeargd.argnlist if node.nodeargd else None) or [] if a is not None]
    if args:
        return trailing_space(args[-1])
    return node.macro_post_space


def cases(node, l2tobj):
    table = [[c for c in r if c] for r in rows(node, l2tobj)]
    widths = [max((width(r[0]) for r in table if r), default=0)]
    lines = [r[0] + (PAD * (widths[0] - width(r[0]) + 2) + "  ".join(r[1:]) if len(r) > 1 else "") for r in table if r]
    if len(lines) == 1:
        braces = ["{"]
    elif len(lines) == 2:
        braces = ["⎧", "⎩"]
    else:
        braces = ["⎧"] + ["⎪"] * (len(lines) - 2) + ["⎩"]
        braces[len(lines) // 2] = "⎨"
    return "\n".join(b + " " + line for b, line in zip(braces, lines))


class NotebookMath(LatexNodes2Text):
    def __init__(self):
        db = get_default_latex_context_db()
        db.add_context_category(
            "brightspace-notebook",
            prepend=True,
            macros=[MacroTextSpec(name, simplify_repl=fraction) for name in FRACTIONS],
            environments=[EnvironmentTextSpec(name, simplify_repl=aligned) for name in ALIGNED]
            + [EnvironmentTextSpec(name, simplify_repl=stacked) for name in STACKED]
            + [EnvironmentTextSpec(name, simplify_repl=matrix) for name in MATRICES]
            + [EnvironmentTextSpec("cases", simplify_repl=cases), EnvironmentTextSpec("dcases", simplify_repl=cases)],
        )
        super().__init__(latex_context=db, math_mode="text")

    def chars_node_to_text(self, node, textcol=0):
        # Source line breaks are only whitespace in math; rows come from \\.
        return super().chars_node_to_text(node, textcol).replace("\n", " ")

    def group_node_to_text(self, node):
        text = super().group_node_to_text(node)
        return group(text) if getattr(node, "script", False) and text.strip() else text

    def nodelist_to_text(self, nodelist):
        nodelist = list(nodelist)
        for previous, node in zip(nodelist, nodelist[1:]):
            if (previous.isNodeType(latexwalker.LatexCharsNode) and previous.chars.endswith(("_", "^"))
                    and node.isNodeType(latexwalker.LatexGroupNode)):
                node.script = True
        out, spaced = "", False
        previous = None
        for node in nodelist:
            if previous is not None and node.isNodeType(latexwalker.LatexCharsNode) and not node.chars[:1].isspace():
                out += trailing_space(previous)
            piece = self.node_to_text(node)
            is_fraction = node.isNodeType(latexwalker.LatexMacroNode) and node.macroname in FRACTIONS
            if node.isNodeType(latexwalker.LatexCharsNode):
                # LaTeX scripts take one token: x_ip is x_i followed by p.
                piece = re.sub(r"(?<=[_^])(\w)(?=\w)", r"\1 ", piece)
            if piece and out and not out[-1].isspace() and (
                (spaced and word_start(piece)) or (is_fraction and (out[-1].isalnum() or out[-1] == ")"))
            ):
                out += " "
            if "\n" in piece and out:
                # Continue multi-line output under its first column.
                indent = PAD * width(out.rsplit("\n", 1)[-1])
                piece = piece.replace("\n", "\n" + indent)
            out += piece
            if piece.strip():
                spaced = is_fraction or getattr(node, "script", False) or bool(
                    node.isNodeType(latexwalker.LatexCharsNode) and re.search(r"[_^]\w$", piece))
            previous = node
        return out


def convert(source):
    text = NotebookMath().latex_to_text(source)
    lines = [RELATIONS.sub(r" \1 ", line).rstrip() for line in text.split("\n")]
    return "\n".join(lines).strip(" \n")


def main() -> None:
    sys.stdout.write(convert(sys.stdin.read()))


if __name__ == "__main__":
    main()
