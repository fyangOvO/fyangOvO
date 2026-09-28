# -*- coding: utf-8 -*-
"""
P1 圖標批次（全部嚴格 44 色，複用 gen_icons.py 的基元與合規機制）

  D1  技能圖標     32 張 48×48  assets/ui/quest/skill_icon_<skill_id>_48.png   （8 張既有略過）
  D2  符文圖標     24 張 32×32  assets/ui/quest/rune_icon_<short>_32.png
  E3  系統標識      3 張 48×48  assets/ui/quest/{forge,enchant,reroll}_icon_48.png
  E3  材料圖標      3 張 32×32  assets/ui/quest/{stone_forge,scroll_enchant,crystal_reroll}_32.png
  E2  稀有裝備圖標  5 張 48×48  assets/icons/equipment/equip_<base_id>_48.png   （走 ContentLoader 直載）

規格來源：01-技能体系.md 附錄A §A.8 · 02-装备属性.md 附錄B §B.2.2 / §B.6
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_icons import Idx, compose, render, PRIMS  # noqa: E402

GAME = r"D:/七傳說/game"
QUEST = os.path.join(GAME, "assets/ui/quest")
EQUIP = os.path.join(GAME, "assets/icons/equipment")

# ---------------- D1 技能圖標（36 技能；既有 4 張對得上，其餘 32 張）----------------
SKILL_MAP = {
    # 戰士
    "cleave": ("sword", "blood"), "spin_slash": ("spiral", "blood"),
    "dash_strike": ("chev", "blood"), "power_strike": ("fist", "blood"),
    "shadow_blink": ("crescent", "void"), "whirlwind": ("spiral", "gold"),
    "shield_bash": ("shield", "blood"), "warcry": ("banner", "blood"),
    "ground_slam": ("plate", "blood"), "blade_toss": ("sword", "gold"),
    "blood_rage": ("heart", "mythic"), "iron_bulwark": ("shield", "ice"),
    # 弓手
    "piercing_shot": ("up", "teal"), "arrow_rain": ("up", "gold"),
    "venom_shot": ("drop", "poison"), "multishot": ("chev", "teal"),
    "explosive_arrow": ("flame", "mythic"), "trap_spike": ("thorn", "poison"),
    "hawk_eye": ("eye", "gold"), "wind_walk": ("boot", "teal"),
    "poison_field": ("dotring", "poison"), "spirit_wolf": ("fang", "teal"),
    "shadow_volley": ("crescent", "void"), "hunters_mark": ("dotring", "mythic"),
    # 法師
    "fireball": ("flame", "blood"), "frost_nova": ("snow", "ice"),
    "lightning_chain": ("bolt", "gold"), "poison_cloud": ("drop", "poison"),
    "frost_bolt": ("snow", "ice"), "meteor": ("star", "mythic"),
    "arcane_shield": ("ring", "void"), "blink": ("chev", "void"),
    "summon_elemental": ("dotring", "void"), "thunder_storm": ("bolt", "gold"),
    "mana_surge": ("drop", "ice"), "void_rift": ("spiral", "void"),
}

# ---------------- D2 符文圖標（24）----------------
RUNE_MAP = {
    "projectile": ("up", "gold"), "chain": ("dotring", "gold"),
    "split": ("chev", "gold"), "pierce": ("broken", "ice"),
    "ground": ("plate", "ice"), "echo": ("spiral", "void"),
    "fire": ("flame", "blood"), "cold": ("snow", "ice"),
    "lightning": ("bolt", "gold"), "poison": ("drop", "poison"),
    "shadow": ("crescent", "void"), "wider": ("ring", "teal"),
    "swift": ("boot", "teal"), "thrifty": ("coin", "gold"),
    "heavy": ("fist", "blood"), "leech": ("fang", "mythic"),
    "stun": ("star", "gold"), "freeze": ("hourglass", "ice"),
    "burn": ("flame", "mythic"), "execute": ("skull", "blood"),
    "opener": ("eye", "mythic"), "barrier": ("shield", "ice"),
    "mana": ("drop", "ice"), "amplify": ("gem", "gold"),
}

# ---------------- E3 系統標識 + 材料 ----------------
SYSTEM_MAP = {
    "forge_icon": ("plate", "gold"),      # 強化
    "enchant_icon": ("gem", "void"),      # 洗練
    "reroll_icon": ("spiral", "teal"),    # 重鑄
}
MATERIAL_MAP = {
    "stone_forge": ("diamond", "ice"),      # 強化石
    "scroll_enchant": ("book", "void"),     # 洗練卷
    "crystal_reroll": ("gem", "teal"),      # 重鑄晶
}

# ---------------- E2 固定檔位裝備獨立圖標（紅2 + 彩2 + 橙1）----------------
EQUIP_MAP = {
    "sword_ash_vow": ("sword", "gold"),              # 橙 · 灰誓（全表唯一固定橙）
    "mythic_crown_seven_kalpa": ("gem", "mythic"),   # 紅 · 七劫冠
    "mythic_staff_final_echo": ("bolt", "mythic"),   # 紅 · 終末回響
    "hidden_amulet_first_tale": ("ring", "teal"),    # 彩 · 最初的故事
    "hidden_boots_scavenger": ("boot", "teal"),      # 彩 · 拾荒者
}


def emit(jobs, outdir, size, name_fmt, title, skip_existing=True):
    os.makedirs(outdir, exist_ok=True)
    made = skipped = 0
    lines = []
    for key, (prim, series) in jobs:
        fn = name_fmt % key
        p = os.path.join(outdir, fn)
        if skip_existing and os.path.exists(p):
            skipped += 1
            continue
        render(prim, series, size).save(p)
        made += 1
        lines.append(fn)
    print("%-22s 新增 %2d / 跳過既有 %2d" % (title, made, skipped))
    return made, skipped


def main():
    total = 0
    print("=== P1 圖標批次（嚴格 44 色）===")
    n, _ = emit(sorted(SKILL_MAP.items()), QUEST, 48, "skill_icon_%s_48.png", "D1 技能圖標 48×48")
    total += n
    n, _ = emit(sorted(RUNE_MAP.items()), QUEST, 32, "rune_icon_%s_32.png", "D2 符文圖標 32×32")
    total += n
    n, _ = emit(sorted(SYSTEM_MAP.items()), QUEST, 48, "%s_48.png", "E3 系統標識 48×48")
    total += n
    n, _ = emit(sorted(MATERIAL_MAP.items()), QUEST, 32, "%s_32.png", "E3 材料圖標 32×32")
    total += n
    n, _ = emit(sorted(EQUIP_MAP.items()), EQUIP, 48, "equip_%s_48.png", "E2 稀有裝備圖標 48×48")
    total += n
    print("\n合計新增 %d 張" % total)
    print("  D1 落點 %s" % QUEST)
    print("  E2 落點 %s（走 ContentLoader 直載，不經 TEX 表）" % EQUIP)
    return 0


if __name__ == "__main__":
    sys.exit(main())
