# -*- coding: utf-8 -*-
"""
召喚物後處理（B1）：**複用 `g1_postprocess.py` 的整條管線**，只換輸入／輸出路徑。

為什麼是薄包裝而不是複製一份：
    G1 那條管線（相鄰差泛洪摳底 + 純底色補挖 + 裁地面陰影 + 整數降採樣 + 量化）
    是踩了 3 個失敗方案才定案的，**複製一份就會變成兩份會各自漂移的真相**。
    這裡只覆寫模組級常數，邏輯一行不改 ⇒ 之後修 G1 的 bug，召喚物自動受益。

用法：
    python gen_summon_postprocess.py [關鍵字...]      # 可選：只處理檔名含關鍵字的
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import g1_postprocess as G  # noqa: E402

_ROOT = r"D:/七傳說/deliverables/gstack/素材開發/_g1_ai"
G.RAW = os.path.join(_ROOT, "raw_sm2")
G.OUT_ROOT = os.path.join(_ROOT, "out_sm")

if __name__ == "__main__":
    G.main()
