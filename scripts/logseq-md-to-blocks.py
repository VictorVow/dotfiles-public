#!/usr/bin/env python3
"""logseq-md-to-blocks.py — convert a Markdown document into a Logseq block
outline suitable for `logseq upsert block --blocks-file`.

Usage:
  logseq-md-to-blocks.py [--gfw] <input.md> [output.md]   (writes stdout if no output)

Options:
  --gfw   Add a Git Forge Watcher widget (logseq-plugin-git-forge-watcher) to
          every block that starts with a GitHub link, e.g. a heading block
          `### [hunk](https://github.com/modem-dev/hunk)`. The macro
          `{{renderer :gfw, <url-encoded link>}}` goes on the block's second
          line. The widget shows live stars, last-commit age and open
          issue/PR counts, so don't repeat those in the text.

Mapping:
  - Headings become parent blocks; each heading nests under the nearest
    shallower heading. The `#` prefix is kept, and Logseq stores it as a
    heading property on the block.
  - Each paragraph (consecutive non-blank lines, joined with spaces) becomes
    one block under the current heading.
  - Each list item (`-`, `*`, `+`, `1.`) becomes one block; indentation is
    preserved as nesting (2 spaces = one level). Numbering is dropped — block
    order carries it.
  - Fenced code blocks and tables stay whole, as one multi-line block each.
  - A list, code block or table directly following a paragraph that ends in
    ":" nests under that paragraph.
  - Blockquote lines (`>`) are kept as one block per quote.
  - Horizontal rules (`---`, `***`) are dropped.
"""

import re
import sys
from urllib.parse import quote

LIST_RE = re.compile(r'^( *)(?:[-*+] |\d+[.)] )(.*)$')
HEADING_RE = re.compile(r'^(#{1,6}) ')
HR_RE = re.compile(r'^(?:-{3,}|\*{3,}|_{3,})\s*$')
GH_LEAD_RE = re.compile(
    r'^(?:#{1,6} )?(?:\[[^\]]*\]\(|<)?(https://github\.com/[\w.-]+/[\w.-]+[^\s)>]*)')


def convert(text, gfw=False):
    lines = text.split('\n')
    out = []

    def emit(depth, block):
        m = GH_LEAD_RE.match(block) if gfw else None
        if m:
            block += '\n{{renderer :gfw, ' + quote(m.group(1), safe='') + '}}'
        first, *rest = block.split('\n')
        out.append('  ' * depth + '- ' + first)
        out.extend('  ' * depth + '  ' + r for r in rest)

    heading_depth = {}  # heading level -> block depth
    cur = 0             # depth for content under the current heading
    colon_para = False  # previous block was a paragraph ending in ":"

    def child_depth():
        return cur + (1 if colon_para else 0)

    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or HR_RE.match(line):
            i += 1
            continue

        m = HEADING_RE.match(line)
        if m:
            lvl = len(m.group(1))
            parents = [d for k, d in heading_depth.items() if k < lvl]
            d = max(parents) + 1 if parents else 0
            heading_depth = {k: v for k, v in heading_depth.items() if k < lvl}
            heading_depth[lvl] = d
            emit(d, line)
            cur, colon_para = d + 1, False
            i += 1
            continue

        if line.lstrip().startswith('```'):
            indent = len(line) - len(line.lstrip())
            j = i + 1
            while j < len(lines) and not lines[j].lstrip().startswith('```'):
                j += 1
            block = [l[indent:] if l[:indent].isspace() else l for l in lines[i:j + 1]]
            emit(child_depth(), '\n'.join(block))
            colon_para = False
            i = j + 1
            continue

        if line.startswith('|'):
            j = i
            while j < len(lines) and lines[j].startswith('|'):
                j += 1
            emit(child_depth(), '\n'.join(lines[i:j]))
            colon_para = False
            i = j
            continue

        if line.startswith('>'):
            j = i
            while j < len(lines) and lines[j].startswith('>'):
                j += 1
            emit(cur, '\n'.join(lines[i:j]))
            colon_para = False
            i = j
            continue

        if LIST_RE.match(line):
            base = child_depth()
            j = i
            while j < len(lines):
                lm = LIST_RE.match(lines[j])
                if lm:
                    emit(base + len(lm.group(1)) // 2, lm.group(2))
                elif lines[j].strip() and lines[j].startswith(' ') and out:
                    # continuation line of the previous item
                    out[-1] += ' ' + lines[j].strip()
                else:
                    break
                j += 1
            colon_para = False
            i = j
            continue

        j = i
        while (j < len(lines) and lines[j].strip()
               and not HEADING_RE.match(lines[j])
               and not lines[j].lstrip().startswith(('```', '|', '>'))
               and not LIST_RE.match(lines[j])):
            j += 1
        para = ' '.join(l.strip() for l in lines[i:j])
        emit(cur, para)
        colon_para = para.endswith(':')
        i = j

    return '\n'.join(out) + '\n'


def main():
    args = sys.argv[1:]
    gfw = '--gfw' in args
    args = [a for a in args if a != '--gfw']
    if len(args) not in (1, 2):
        sys.exit(__doc__)
    with open(args[0]) as f:
        result = convert(f.read(), gfw)
    if len(args) == 2:
        with open(args[1], 'w') as f:
            f.write(result)
    else:
        sys.stdout.write(result)


if __name__ == '__main__':
    main()
