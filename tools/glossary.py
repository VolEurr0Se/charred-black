"""Load 术语表.csv into a case-insensitive English->Chinese map (shared by build scripts)."""
import csv, re
def load(path):
    g = {}
    for r in csv.reader(open(path, encoding='utf-8-sig')):
        if len(r) < 2 or not r[0].strip() or not r[1].strip(): continue
        en, zh = r[0].strip(), r[1].strip()
        en_parts = [p.strip() for p in en.split(' / ')]
        zh_parts = [p.strip() for p in zh.split(' / ')]
        pairs = list(zip(en_parts, zh_parts)) if len(en_parts) == len(zh_parts) and len(en_parts) > 1 else [(en, zh)]
        for e, z in pairs:
            e2 = re.sub(r'\s*\([^)]*\)\s*$', '', e).strip()       # "Artificer (setting/lifepath)" -> "Artificer"
            z2 = re.sub(r'（[^）]*）$', '', z).strip()               # "造物师（背景/人生历程）" -> "造物师"
            # 保留形如“叠加值（Add）”中的中文主体
            z2 = re.sub(r'（[A-Za-z0-9 ,./\'-]+）', '', z2).strip() or z2
            for key in {e, e2}:
                g.setdefault(key.lower(), z2)
    return g
