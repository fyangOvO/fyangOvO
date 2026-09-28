# -*- coding: utf-8 -*-
"""
召喚物動作衍生（B1）：**複用 `gen_monster_actions.py`**，只把 `SRC` 換到召喚物的後處理輸出。

同理不複製一份：動作衍生（胸線切分的上半身位移 / 精確 90° 躺地）是與 G1 共用的技術，
複製會變成兩份會漂移的真相。這裡只覆寫 `SRC`。

用法：
    python gen_summon_actions.py             # 只產到 _g1_ai/mon
    python gen_summon_actions.py --install   # 直接寫進 game/assets/pack/creatures/
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_monster_actions as M  # noqa: E402

M.SRC = r"D:/七傳說/deliverables/gstack/素材開發/_g1_ai/out_sm"

if __name__ == "__main__":
    M.main()
