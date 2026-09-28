#!/usr/bin/env python3
"""技能 DPS 系数区间校验（第一步 · 技能体系配套工具）

用途：校验 skills.json 中全部伤害技能的 DPS 系数是否落在设计区间内。
     对应《技能体系设计-2026-09-24.md》§5.1「统一标尺：DPS 系数」。

口径（关键，勿改）：
  single / aoe  : total = multiplier
  projectile    : total = multiplier × projectile_count      （按全中计）
  ground        : total = impact_multiplier + multiplier × (duration / tick_interval)
  dash          : total = multiplier
  buff / summon : 不适用（无伤害）
  DPS 系数 = total ÷ cooldown

设计区间：
  single / aoe / projectile : 0.40 – 0.70
  ground                    : 0.45 – 0.75
  dash                      : 0.10 – 0.20

用法：
  python 01-check_skill_dps.py [skills.json 路径]
  （默认读取同目录下的 01-skills.json）

退出码：0 = 全部合规；1 = 存在超区间项
"""
import json
import os
import sys

RANGES = {
    "single": (0.40, 0.70),
    "aoe": (0.40, 0.70),
    "projectile": (0.40, 0.70),
    "ground": (0.45, 0.75),
    "dash": (0.10, 0.20),
}

NO_DAMAGE = ("buff", "summon")


def total_damage(s):
    """单次施放的总伤害倍率（× 攻击力）"""
    t = s["type"]
    m = float(s["multiplier"])
    if t == "ground":
        return float(s.get("impact_multiplier", 0.0)) + m * (s["duration"] / s["tick_interval"])
    if t == "projectile":
        return m * int(s.get("projectile_count", 1))
    return m


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "01-skills.json")
    with open(path, encoding="utf-8") as f:
        skills = json.load(f)

    bad = []
    print("%-20s %-11s %8s %8s  %s" % ("id", "type", "total", "DPS", "判定"))
    for s in sorted(skills, key=lambda x: (x["type"], x["id"])):
        t = s["type"]
        if t in NO_DAMAGE:
            print("%-20s %-11s %8s %8s  —" % (s["id"], t, "-", "-"))
            continue
        total = total_damage(s)
        dps = total / float(s["cooldown"])
        lo, hi = RANGES[t]
        ok = lo <= dps <= hi
        if not ok:
            bad.append((s["id"], t, round(dps, 3), (lo, hi)))
        print("%-20s %-11s %8.2f %8.3f  %s" % (s["id"], t, total, dps, "OK" if ok else "!! 超区间"))

    print()
    if bad:
        print("超区间 %d 项：" % len(bad))
        for sid, t, dps, rng in bad:
            print("  %-20s %-11s DPS=%.3f  期望 %.2f–%.2f" % (sid, t, dps, rng[0], rng[1]))
        return 1
    print("全部 %d 条伤害技能落在设计区间内 ✅" % sum(1 for s in skills if s["type"] not in NO_DAMAGE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
