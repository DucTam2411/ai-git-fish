#!/usr/bin/env python3
"""Render aicommit task bullets as a simple grid. Tasks come from stdin, one per line."""
import shutil
import sys
import unicodedata


def dwidth(s):
    """Display width: wide/fullwidth + emoji count as 2."""
    n = 0
    for ch in s:
        if unicodedata.east_asian_width(ch) in ("W", "F") or ord(ch) >= 0x1F000:
            n += 2
        else:
            n += 1
    return n


def pad(s, width):
    return s + " " * (width - dwidth(s))


def wrap(s, maxw):
    """Word-wrap to display width maxw. Returns list of lines (>=1). No text lost."""
    if dwidth(s) <= maxw:
        return [s]
    lines, cur = [], ""
    for word in s.split(" "):
        # word itself longer than the column -> hard-break it by char
        while dwidth(word) > maxw:
            head = ""
            for ch in word:
                if dwidth(head) + dwidth(ch) > maxw:
                    break
                head += ch
            if cur:
                lines.append(cur)
                cur = ""
            lines.append(head)
            word = word[len(head):]
        cand = word if not cur else cur + " " + word
        if dwidth(cand) > maxw:
            lines.append(cur)
            cur = word
        else:
            cur = cand
    if cur:
        lines.append(cur)
    return lines or [""]


def main():
    tasks = [l.rstrip("\n") for l in sys.stdin if l.strip()]
    if not tasks:
        return
    nw = max(dwidth("#"), max(len(str(i)) for i in range(1, len(tasks) + 1)))
    # fit task column to the terminal; borders/padding eat (nw + 7) cols
    term = shutil.get_terminal_size((100, 24)).columns
    maxtw = max(20, term - nw - 7)
    wrapped = [wrap(t, maxtw) for t in tasks]
    tw = max(dwidth("Task"), max(dwidth(ln) for w in wrapped for ln in w))

    def row(a, b):
        return "│ " + pad(a, nw) + " │ " + pad(b, tw) + " │"

    def sep(l, m, r):
        return l + "─" * (nw + 2) + m + "─" * (tw + 2) + r

    inner = nw + tw + 5  # total dashes between corners on top line
    title = " ✅ Tasks Done "
    print("┌" + title + "─" * (inner - dwidth(title)) + "┐")
    print(sep("├", "┬", "┤"))
    print(row("#", "Task"))
    print(sep("├", "┼", "┤"))
    for i, w in enumerate(wrapped, 1):
        print(row(str(i), w[0]))
        for cont in w[1:]:
            print(row("", cont))  # continuation lines: blank # column
    print(sep("└", "┴", "┘"))


if __name__ == "__main__":
    main()
