#!/usr/bin/env python3
"""汉化覆盖率检查：列出游戏数据与界面中尚无中文对照的字符串（运行时会回退显示英文）。
用法：python3 tools/i18n_check.py [--locale zh-CN]
退出码始终为 0；结果仅供补充对照表时参考。
"""
import json, os, re, subprocess, sys, glob
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
LOC = sys.argv[sys.argv.index('--locale') + 1] if '--locale' in sys.argv else 'zh-CN'
base = os.path.join(ROOT, 'src', 'data', 'i18n', LOC)
ui = json.load(open(os.path.join(base, 'ui.json'), encoding='utf-8'))
terms = json.load(open(os.path.join(base, 'terms.json'), encoding='utf-8'))
summ = json.load(open(os.path.join(base, 'trait_summaries.json'), encoding='utf-8'))
lower = {k.lower(): v for k, v in terms.items()}
def known(s):
    k = s.strip()
    if k in ui or k in terms or k.lower() in lower: return True
    if k.lower().endswith('-wise') and known(k[:-5]): return True
    for suf in (' Subsetting', ' Setting'):
        if k.endswith(suf) and known(k[:-len(suf)]): return True
    return False
data = json.loads(subprocess.check_output([sys.executable, os.path.join(ROOT, 'tools', 'i18n_extract.py')]))
missing = 0
for cat, items in data.items():
    miss = [s for s in items if s.strip() not in ('*',) and not known(s)]
    if miss:
        missing += len(miss)
        print(f'[{cat}] {len(miss)} 条无对照：')
        for s in miss: print('   ', s, '←', ', '.join(items[s][:2]))
# 有说明但没有中文摘要的特质
for fn in sorted(glob.glob(os.path.join(ROOT, 'src', 'data', '*', 'traits.json'))):
    for n, t in json.load(open(fn, encoding='utf-8')).items():
        if t.get('desc') and n not in summ:
            missing += 1; print('[trait_summary] 无中文摘要：', n)
# ERB 中的 t(%q{...}) 键
for fn in sorted(glob.glob(os.path.join(ROOT, 'src', 'views', '**', '*.erb'), recursive=True)):
    src = open(fn, encoding='utf-8').read()
    for m in re.finditer(r"t\(%q\{((?:[^{}]|\{[^{}]*\}|\{\{[^{}]*\}\})*)\}\)", src):
        if m.group(1) not in ui:
            missing += 1; print('[ui]', os.path.relpath(fn, ROOT), m.group(1))
# JS 中 tr("...") / trf("...") 的键
for fn in sorted(glob.glob(os.path.join(ROOT, 'src', 'public', 'js', 'burning*.js'))):
    src = open(fn, encoding='utf-8').read()
    for m in re.finditer(r'\btrf?\("((?:[^"\\]|\\.)*)"', src):
        if m.group(1) not in ui and not known(m.group(1)):
            missing += 1; print('[ui-js]', os.path.basename(fn), m.group(1))
print(f'\n合计 {missing} 条缺失（缺失项在界面上显示英文原文）。')
