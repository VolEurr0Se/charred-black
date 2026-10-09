#!/usr/bin/env python3
"""Extract every translatable game-data string from src/data into categories.
Usage: python3 tools/i18n_extract.py > /tmp/strings.json
"""
import json, glob, os, sys
ROOT = os.path.join(os.path.dirname(__file__), '..', 'src', 'data')
out = {k: {} for k in ('setting','lifepath','lead','skill','trait','resource','free','root','restrict_tag')}
def strings_in(v):
    if isinstance(v, str): yield v
    elif isinstance(v, list):
        for x in v: yield from strings_in(x)
def add(cat, s, src):
    if not isinstance(s, str) or not s.strip(): return
    out[cat].setdefault(s, set()).add(os.path.relpath(src, os.path.join(ROOT,'..','..')))
def lp_files():
    return sorted(glob.glob(f'{ROOT}/*/lifepaths.json') + glob.glob(f'{ROOT}/*/lifepaths/*.json'))
for fn in lp_files():
    for st, lps in json.load(open(fn, encoding='utf-8')).items():
        add('setting', st, fn)
        for n, l in lps.items():
            add('lifepath', n, fn)
            add('lifepath', l.get('display_name'), fn)
            for x in l.get('leads', []): add('lead', x, fn)
            for x in l.get('key_leads', []): add('setting', x, fn)
            for x in strings_in(l.get('skills', [])): add('skill', x, fn)
            for x in strings_in(l.get('traits', [])): add('trait', x, fn)
            for x in strings_in(l.get('common_traits', [])): add('trait', x, fn)
            for k in ('requires', 'restrict', 'note', 'restriction', 'Requires'):
                v = l.get(k)
                if isinstance(v, str): add('free', v, fn)
                elif isinstance(v, list):
                    for x in v:
                        if isinstance(x, str): add('free', x, fn)
for fn in sorted(glob.glob(f'{ROOT}/*/skills.json')):
    for n, s in json.load(open(fn, encoding='utf-8')).items():
        add('skill', n, fn)
        for r in (s.get('roots') or []): add('root', r, fn)
for fn in sorted(glob.glob(f'{ROOT}/*/traits.json')):
    for n, t in json.load(open(fn, encoding='utf-8')).items():
        add('trait', n, fn)
        for r in (t.get('restrict') or []): add('restrict_tag', r, fn)
def walk_res(node, fn):
    if isinstance(node, list):
        for x in node: walk_res(x, fn)
    elif isinstance(node, dict):
        add('resource', node.get('name'), fn)
        walk_res(node.get('resources'), fn)
for fn in sorted(glob.glob(f'{ROOT}/*/resources.json') + glob.glob(f'{ROOT}/*/resources/*.json')):
    walk_res(json.load(open(fn, encoding='utf-8')), fn)
json.dump({k: {s: sorted(v) for s, v in sorted(d.items())} for k, d in out.items()}, sys.stdout, ensure_ascii=False, indent=1)
