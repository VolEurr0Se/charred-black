#!/usr/bin/env python3
"""One-off helper used to wrap static English UI text in ERB views with t(%q{...}).
Each text node (whitespace-collapsed) becomes the lookup key; Angular {{...}} inside it is kept
in the key so translations can reorder it. Prints the list of keys.
Usage: python3 tools/wrap_erb.py file.erb [...]
"""
import re, sys, json
TEXT_RE = re.compile(r'>([^<>]+)<')
ATTR_RE = re.compile(r"""(\s(?:placeholder|title|alt|aria-label))=(['"])([^'"]*)\2""")
LETTER = re.compile(r'[A-Za-z]{2,}|[A-Za-z]\.')
def is_dynamic_only(s):
    return not LETTER.search(re.sub(r'\{\{.*?\}\}', '', s))
keys = []
def wrap_text(m):
    raw = m.group(1)
    if '<%' in raw or '%>' in raw or not raw.strip() or is_dynamic_only(raw) or raw.strip().startswith('&'):
        if raw.strip() in ('&times;', '&nbsp;'): return m.group(0)
        if is_dynamic_only(raw): return m.group(0)
    core = re.sub(r'\s+', ' ', raw).strip()
    lead = raw[:len(raw) - len(raw.lstrip())]
    trail = raw[len(raw.rstrip()):]
    keys.append(core)
    return '>' + lead + '<%= t(%q{' + core + '}) %>' + trail + '<'
def wrap_attr(m):
    name, q, val = m.groups()
    if is_dynamic_only(val): return m.group(0)
    keys.append(val)
    return f'{name}={q}<%= t(%q{{{val}}}) %>{q}'
for fn in sys.argv[1:]:
    src = open(fn, encoding='utf-8').read()
    # skip <script>/<style> blocks and the GitHub corner svg
    parts = re.split(r'(<script.*?</script>|<style.*?</style>|<svg.*?</svg>|<%.*?%>)', src, flags=re.S)
    out = []
    for p in parts:
        if re.match(r'<(script|style|svg)|<%', p): out.append(p); continue
        p = TEXT_RE.sub(wrap_text, p)
        p = ATTR_RE.sub(wrap_attr, p)
        out.append(p)
    open(fn, 'w', encoding='utf-8').write(''.join(out))
json.dump(sorted(set(keys)), sys.stdout, ensure_ascii=False, indent=1)
