#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
07-check_dev_tasks.py —— 第七步「匯總為 AI 可讀開發文檔」校驗腳本

分組：
  A 組 · 本檔自洽性（結構 / 計數 / 唯一性 / 批次覆蓋）
  B 組 · 跨步工單完整性（六步全部工單在場 + 分布正確）
  C 組 · 同批硬約束（14 條，逐條檢查 members 是否含指定工單）
  D 組 · 素材總帳（去重警示 / 硬約束 / 優先級）
  E 組 · 驗收總表（六腳本基線 + 失敗項定性）
  F 組 · 跨步修訂表（14 行 + 政策）
  G 組 · 靜默失敗清單（12 條 + 關鍵項）
  H 組 · 主文檔 07-開發總表.md 同步性
  E-repo · 工程側漂移（僅 --repo 時）

用法：
  python 07-check_dev_tasks.py
  python 07-check_dev_tasks.py --repo D:/七傳說
"""
import json
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
JSON_PATH = os.path.join(HERE, "07-dev-tasks.json")
MD_PATH = os.path.join(HERE, "07-开发总表.md")

REPO = None
for i, a in enumerate(sys.argv):
    if a == "--repo" and i + 1 < len(sys.argv):
        REPO = sys.argv[i + 1].rstrip("/\\")

PASS = 0
FAIL = 0
FAILED = []


def ck(cond, msg):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        FAILED.append(msg)


def read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# ============================================================
# A 組 · 本檔自洽性
# ============================================================
def group_a(D, md):
    print("\n--- A. 本檔自洽性 ---")

    ck(D.get("version") == "1.0", "A1 version == '1.0'")
    ck(D.get("generated") == "2026-09-24", "A2 generated == 2026-09-24")
    ck(len(D["steps_summary"]) == 7, f"A3 steps_summary == 7（實 {len(D['steps_summary'])}）")
    ck("本輪交付" in D["steps_summary"][6]["status"], "A4 第 7 步 status 含「本輪交付」")

    wo = D["work_orders"]
    ids = [x["id"] for x in wo]
    ck(len(wo) == 180, f"A5 work_orders == 180（實 {len(wo)}）")
    ck(len(set(ids)) == len(ids), "A6 工單 id 無重複")

    prio = Counter(x["priority"] for x in wo)
    ck(set(prio) <= {"P0", "P1", "P2", "P3"}, f"A7 priority 取值合法 {dict(prio)}")
    ck(prio["P0"] == 73 and prio["P1"] == 59 and prio["P2"] == 43 and prio["P3"] == 5,
       f"A8 優先級分布 P0/P1/P2/P3 = 73/59/43/5（實 {prio['P0']}/{prio['P1']}/{prio['P2']}/{prio['P3']}）")

    step = Counter(x["step"] for x in wo)
    ck(step[1] == 33 and step[2] == 42 and step[3] == 47 and step[4] == 17 and step[5] == 13 and step[6] == 28,
       f"A9 步分布 33/42/47/17/13/28（實 {step[1]}/{step[2]}/{step[3]}/{step[4]}/{step[5]}/{step[6]}）")

    ck(all(x.get("title") for x in wo), "A10 全部工單 title 非空")
    ck(all(x.get("files") for x in wo), "A11 全部工單 files 非空")
    ck(all(x.get("verify") for x in wo), "A12 全部工單 verify 非空")
    ck(all("depends_on" in x for x in wo), "A13 全部工單有 depends_on 字段")

    # 依賴引用必須存在
    idset = set(ids)
    bad_dep = []
    for x in wo:
        for dep in x["depends_on"]:
            if dep not in idset:
                bad_dep.append(f"{x['id']}→{dep}")
    ck(not bad_dep, f"A14 全部 depends_on 指向存在的工單（孤兒 {len(bad_dep)}: {bad_dep[:5]}）")

    # 無自環 / 無循環（簡單檢測：依賴圖拓撲排序）
    graph = {x["id"]: list(x["depends_on"]) for x in wo}
    color = {}

    def dfs(n, path):
        color[n] = 1
        for m in graph.get(n, []):
            if color.get(m) == 1:
                return False
            if color.get(m, 0) == 0 and not dfs(m, path + [m]):
                return False
        color[n] = 2
        return True

    acyclic = all(dfs(n, [n]) for n in graph if color.get(n, 0) == 0)
    ck(acyclic, "A15 工單依賴圖無環")

    batches = D["batches"]
    bids = {b["id"] for b in batches}
    ck(len(batches) == 8, f"A16 batches == 8（實 {len(batches)}）")
    ck(all(x["batch"] in bids | {"—"} for x in wo), "A17 全部工單 batch 合法")

    mem = Counter()
    missing = []
    for b in batches:
        for m in b["members"]:
            if m not in idset:
                missing.append(m)
            mem[m] += 1
    ck(not missing, f"A18 batch members 全部存在（缺失 {missing[:5]}）")
    multi = [k for k, v in mem.items() if v > 1]
    ck(not multi, f"A19 無工單跨多個 batch（重複 {multi[:5]}）")
    uncovered = sorted(idset - set(mem))
    ck(uncovered == ["5-W5-12"], f"A20 唯一未入批次的工單 = 5-W5-12（實 {uncovered}）")
    ck(len(mem) == 179, f"A21 批次覆蓋 179 條（實 {len(mem)}）")

    tot = D["_meta"]["totals"]
    ck(tot["work_orders"] == len(wo), "A22 _meta.totals.work_orders 與實際一致")
    ck(tot["batches"] == len(batches), "A23 _meta.totals.batches 與實際一致")
    ck(tot["by_step"] == {str(k): v for k, v in sorted(step.items())}, "A24 _meta.totals.by_step 與實際一致")

    ck("不改 game/" in D["_meta"]["role_boundary"], "A25 role_boundary 明示不改 game/")
    ck(len(D["assertions_for_checker"]) >= 40, f"A26 自帶斷言清單 >= 40 條（實 {len(D['assertions_for_checker'])}）")
    return ids, idset


# ============================================================
# B 組 · 跨步工單完整性
# ============================================================
def group_b(D, idset):
    print("\n--- B. 跨步工單完整性 ---")

    # 第一步
    for pfx, n, label in [("1-D", 7, "資料層"), ("1-L", 15, "邏輯層"), ("1-V", 11, "驗證層")]:
        got = [i for i in idset if i.startswith(pfx)]
        ck(len(got) == n, f"B 第一步 {label} {pfx}* == {n}（實 {len(got)}）")

    # 第二步
    for pfx, n, label in [("2-D", 8, "資料層"), ("2-L", 16, "邏輯層")]:
        got = [i for i in idset if i.startswith(pfx)]
        ck(len(got) == n, f"B 第二步 {label} {pfx}* == {n}（實 {len(got)}）")
    v2 = [i for i in idset if i.startswith("2-V")]
    ck(len(v2) == 18, f"B 第二步 驗證層 2-V* == 18（V1–V17 + V7b；實 {len(v2)}）")
    ck("2-V7b" in idset, "B 2-V7b 存在（底材 base_stats 白名單）")

    # 第三步
    for pfx, n, pat in [("3-K", 10, r"3-K\d+"), ("3-B", 4, r"3-B\d+"), ("3-S", 4, r"3-S\d+"),
                        ("3-X", 6, r"3-X\d+"), ("3-F", 3, r"3-F\d+"), ("3-BL", 2, r"3-BL\d+"),
                        ("3-SUM", 2, r"3-SUM\d+"), ("3-E", 8, r"3-E\d+"), ("3-M", 8, r"3-M\d+")]:
        got = [i for i in idset if re.fullmatch(pat, i)]
        ck(len(got) == n, f"B 第三步 {pfx}* == {n}（實 {len(got)}）")
    ck("3-BL1" in idset and "3-BL2" in idset, "B 3-BL1/BL2 格擋兩條在場")
    ck("3-SUM0" in idset and "3-SUM1" in idset, "B 3-SUM0/SUM1 召喚物兩條在場")

    # 第四步
    w4 = ["4-W1", "4-W2", "4-W3", "4-W3-b", "4-W3-c", "4-W4", "4-W5-a", "4-W5-b", "4-W5-c",
          "4-W5-d", "4-W5-e", "4-W6", "4-W7", "4-W8", "4-W9", "4-W10", "4-W11"]
    miss4 = [w for w in w4 if w not in idset]
    ck(not miss4, f"B 第四步 W1–W11（含衍生）17 條全在（缺 {miss4}）")

    # 第五步
    w5 = [f"5-W5-{i}" for i in range(1, 14)]
    miss5 = [w for w in w5 if w not in idset]
    ck(not miss5, f"B 第五步 W5-1–W5-13 全在（缺 {miss5}）")

    # 第六步
    w6 = [f"6-W6-{i:02d}" for i in range(1, 21)]
    q6 = [f"6-W6-Q{i}" for i in range(1, 9)]
    miss6 = [w for w in w6 + q6 if w not in idset]
    ck(not miss6, f"B 第六步 W6-01–W6-20 + Q1–Q8 = 28 條全在（缺 {miss6}）")

    # 關鍵工單存在性
    keys = ["1-D1", "1-L2", "2-L7", "2-L8", "3-K1", "3-K9", "3-BL1", "3-E1", "3-M7",
            "4-W1", "4-W2", "4-W3", "4-W10", "4-W11", "5-W5-1", "5-W5-4",
            "6-W6-01", "6-W6-11", "6-W6-12", "6-W6-13", "6-W6-19", "6-W6-Q5", "6-W6-Q7"]
    missk = [k for k in keys if k not in idset]
    ck(not missk, f"B 關鍵工單全在（缺 {missk}）")

    # 已降級項
    dg = [x for x in D["work_orders"] if x["id"] == "5-W5-12"][0]
    ck(dg["batch"] == "—" and "不執行" in dg["note"], "B 5-W5-12 已降級（batch=— 且 note 含「不執行」）")
    ck(dg["priority"] == "P3", "B 5-W5-12 priority == P3")


# ============================================================
# C 組 · 同批硬約束
# ============================================================
def group_c(D):
    print("\n--- C. 同批硬約束 ---")

    hc = D["hard_batch_constraints"]
    ck(len(hc) == 14, f"C1 硬約束 == 14 條（實 {len(hc)}）")

    bmap = {b["id"]: set(b["members"]) for b in D["batches"]}
    by_id = {c["id"]: c for c in hc}

    def check_group(cid, members, label):
        if cid not in by_id:
            ck(False, f"C {cid} 存在（{label}）")
            return
        # 檢查這些工單是否落在同一 batch
        batches_of = {}
        for m in members:
            for bid, ms in bmap.items():
                if m in ms:
                    batches_of[m] = bid
        same = len(set(batches_of.values())) == 1
        ck(same, f"C {cid} 的 {label} 同屬一個 batch（實 {batches_of}）")

    check_group("C1", ["4-W1", "4-W2", "4-W3"], "W1+W2+W3")
    check_group("C2", ["4-W2", "4-W10", "4-W11"], "路線 A 三件套")
    check_group("C3", ["4-W2", "5-W5-4"], "W2+W5-4")
    check_group("C4", ["5-W5-1", "5-W5-3"], "W5-1+W5-3")
    check_group("C5", ["5-W5-4", "5-W5-10"], "W5-4+W5-10")
    check_group("C6", ["3-E1", "3-E2", "3-E3", "3-E4", "3-E5"], "E1–E5")
    check_group("C8", ["6-W6-11", "6-W6-12", "6-W6-13"], "特殊檔三件套")
    check_group("C9", ["6-W6-Q5", "6-W6-Q6", "6-W6-Q7"], "半重鑄三件套")

    # 規則文字必須點名具體工單
    text_of = {c["id"]: c["rule"] + c["why"] for c in hc}
    ck(all(k in text_of.get("C1", "") for k in ["W1", "W2", "W3"]), "C2 C1 文字點名 W1/W2/W3")
    ck(all(k in text_of.get("C2", "") for k in ["W2", "W10", "W11"]), "C3 C2 文字點名 W2/W10/W11")
    ck("W5-4" in text_of.get("C3", "") and "W2" in text_of.get("C3", ""), "C4 C3 文字點名 W5-4 與 W2")
    ck("W5-1" in text_of.get("C4", "") and "W5-3" in text_of.get("C4", ""), "C5 C4 文字點名 W5-1 與 W5-3")

    # C7 順序約束
    ck("6-W6-01" in text_of.get("C7", ""), "C6 C7 點名 6-W6-01（存檔升版最先行）")

    # 依賴方向正確性（DAG 上真的先後）
    by_id_wo = {x["id"]: x for x in D["work_orders"]}
    ck("4-W2" in by_id_wo["5-W5-4"]["depends_on"], "C7 5-W5-4 的 depends_on 含 4-W2")
    ck("5-W5-1" in by_id_wo["5-W5-3"]["depends_on"], "C8 5-W5-3 的 depends_on 含 5-W5-1")
    ck("5-W5-4" in by_id_wo["5-W5-10"]["depends_on"], "C9 5-W5-10 的 depends_on 含 5-W5-4")
    ck("6-W6-01" in by_id_wo["6-W6-11"]["depends_on"], "C10 6-W6-11 的 depends_on 含 6-W6-01")
    ck("6-W6-11" in by_id_wo["6-W6-12"]["depends_on"], "C11 6-W6-12 的 depends_on 含 6-W6-11")
    ck("6-W6-11" in by_id_wo["6-W6-13"]["depends_on"], "C12 6-W6-13 的 depends_on 含 6-W6-11")
    ck("3-SUM0" in by_id_wo["3-SUM1"]["depends_on"], "C13 3-SUM1 的 depends_on 含 3-SUM0")
    ck("1-D1" in by_id_wo["1-D2"]["depends_on"], "C14 1-D2 的 depends_on 含 1-D1")
    ck("2-D1" in by_id_wo["2-D4"]["depends_on"], "C15 2-D4 的 depends_on 含 2-D1")


# ============================================================
# D 組 · 素材總帳
# ============================================================
def group_d(D):
    print("\n--- D. 素材總帳 ---")

    ml = D["material_ledger"]
    ck(len(ml["by_step_raw"]) == 6, f"D1 by_step_raw == 6（實 {len(ml['by_step_raw'])}）")
    ck(bool(ml.get("_critical_overlap_warning")), "D2 跨步重疊警示非空")
    ov = ml["_critical_overlap_warning"]
    ck("召喚物" in ov and "元素圖標" in ov and "技能圖標" in ov, "D3 重疊警示點名三處（召喚物/元素圖標/技能圖標）")

    hc = " ".join(ml["hard_constraints"])
    ck("遇缺即停" in hc, "D4 硬約束含「NN 從 01 起、遇缺即停」")
    ck("rarity_" in hc, "D5 硬約束含「不要新做 rarity_* 前綴素材」")
    ck("PALETTE_ALL" in hc, "D6 硬約束含唯一色源 PALETTE_ALL")
    ck("整數縮放" in hc and "旋轉" in hc, "D7 硬約束含整數縮放 + 禁止旋轉")
    ck("DirAccess" in hc, "D8 硬約束含導出包目錄枚舉鐵律")
    ck("cast" in hc, "D9 硬約束含 cast 動作需改代碼")

    dd = ml["deduped_totals"]
    ck("normal_plan" in dd and "refined_plan_delta" in dd, "D10 去重口徑含一般/細化兩段")
    ck("_note" in dd, "D11 去重口徑有說明")

    po = ml["priority_order"]
    ck(len(po) >= 12, f"D12 素材優先級 >= 12 行（實 {len(po)}）")
    ck(po[0]["p"] == "P0" and "idle" in po[0]["item"], "D13 首項 = P0 玩家 idle 8 方向")
    ck(any("cast" in x["item"] for x in po[:3]), "D14 前三項含 cast")

    # 第五步素材口徑（D4 不新增 BOSS）
    s5 = [x for x in ml["by_step_raw"] if x["step"] == 5][0]
    ck(s5["normal"]["monster_frames"] == 672, "D15 第五步怪 672 幀")
    ck(s5["normal"]["subtotal_frames"] == 696, "D16 第五步小計 696 幀")
    s6 = [x for x in ml["by_step_raw"] if x["step"] == 6][0]
    ck(s6["normal"]["fx_frames"] == 13, "D17 第六步特效 13 幀")
    s2 = [x for x in ml["by_step_raw"] if x["step"] == 2][0]
    ck(s2["normal"]["sheets"] == 59, "D18 第二步一般方案 59 張")


# ============================================================
# E 組 · 驗收總表
# ============================================================
def group_e(D):
    print("\n--- E. 驗收總表 ---")

    acc = D["acceptance"]
    sc = acc["scripts"]
    ck(len(sc) == 6, f"E1 六份校驗腳本齊（實 {len(sc)}）")
    ck(acc["totals"]["pass"] == 372, f"E2 通過 372（實 {acc['totals']['pass']}）")
    ck(acc["totals"]["fail"] == 4, f"E3 失敗 4（實 {acc['totals']['fail']}）")
    ck(acc["totals"]["fail_is_expected"] is True, "E4 4 條失敗標為已知待修")

    f2 = [s for s in sc if s["id"] == "02"][0]
    ck("11 通過 / 4 失敗" in f2["result"], "E5 02 腳本基線 = 11/4")
    ck("待修" in f2["note"], "E6 02 腳本備註說明 4 條為待修缺口")

    f6 = [s for s in sc if s["id"] == "06"][0]
    ck("186" in f6["result"] and "202" in f6["result"], "E7 06 腳本基線 = 186 / 202")
    f5 = [s for s in sc if s["id"] == "05"][0]
    ck("66" in f5["result"], "E8 05 腳本基線 = 66")
    f4 = [s for s in sc if s["id"] == "04"][0]
    ck("46" in f4["result"], "E9 04 腳本基線 = 46")
    f1 = [s for s in sc if s["id"] == "01"][0]
    ck("27" in f1["result"], "E10 01 腳本基線 = 27")
    f3 = [s for s in sc if s["id"] == "03"][0]
    ck("36" in f3["result"], "E11 03 腳本基線 = 36")

    ai = acc["assertion_index"]
    ck(len(ai) == 6, f"E12 斷言索引 6 組（實 {len(ai)}）")
    ck(any("T1–T20" in x["ids"] for x in ai), "E13 含第四步 T1–T20")
    ck(any("V1–V17" in x["ids"] for x in ai), "E14 含第二步 V1–V17")

    kt = {x["id"]: x for x in acc["key_thresholds"]}
    ck(kt["T8"]["threshold"].startswith("5,400–5,900"), "E15 T8 預算合計閾值正確")
    ck(kt["T17"]["threshold"] == "= 20", "E16 T17 賬號上限 = 20")
    ck("0.05" in kt["S12-b"]["threshold"], "E17 S12 橙 0.05 硬約束在場")
    s12c = kt["S12-c"]["assert"] + kt["S12-c"]["threshold"]
    ck("空池" in s12c and "return null" in s12c, "E18 S12-c 點名空池 return null 風險")


# ============================================================
# F 組 · 跨步修訂表
# ============================================================
def group_f(D):
    print("\n--- F. 跨步修訂表 ---")

    cs = D["cross_step_revisions"]
    ck("不回改" in cs["_policy"], "F1 政策含「不回改」")
    rows = cs["rows"]
    ck(len(rows) == 14, f"F2 修訂行 == 14（實 {len(rows)}）")
    ck(len(set(r["id"] for r in rows)) == len(rows), "F3 修訂行 id 唯一")
    ck(all(r.get("original") and r.get("current") and r.get("basis") for r in rows),
       "F4 每行有 original / current / basis")

    r = {x["id"]: x for x in rows}
    ck("S11" in r["R1"]["basis"], "F5 R1 依據 S11")
    ck("二階段" in r["R1"]["current"] or "二阶段" in r["R1"]["current"], "F6 R1 內容為二階段")
    ck("S12" in r["R2"]["basis"], "F7 R2 依據 S12")
    ck("10 檔" in r["R2"]["current"], "F8 R2 內容為 10 檔")
    ck("保持 D4 不變" in r["R3"]["current"], "F9 R3 明確保持 D4 不變")
    ck("不執行" in r["R4"]["current"], "F10 R4 標為不執行")
    ck("不入素材清單" in r["R5"]["current"], "F11 R5 標為不入素材清單")
    ck("D1" in r["R6"]["basis"], "F12 R6 依據第五步 D1")
    ck("D2" in r["R7"]["basis"], "F13 R7 依據第五步 D2")
    ck("D3" in r["R8"]["basis"], "F14 R8 依據第五步 D3")
    ck("D5" in r["R9"]["basis"], "F15 R9 依據第五步 D5")
    ck("推翻" in r["R11"]["current"], "F16 R11 標明三條推翻")
    ck("1920×1080" in r["R12"]["original"], "F17 R12 原文為過期視口描述")
    ck("1.284" in r["R13"]["original"], "F18 R13 原文為舊成長率")
    ck("偽校驗" in r["R14"]["original"], "F19 R14 原文標為偽校驗")
    ck(all(r[k]["apply_to"] for k in r if k != "R3"), "F20 除 R3 外每行有 apply_to")


# ============================================================
# G 組 · 靜默失敗清單
# ============================================================
def group_g(D):
    print("\n--- G. 靜默失敗清單 ---")

    items = D["silent_failure_checklist"]["items"]
    ck(len(items) == 12, f"G1 靜默失敗項 == 12（實 {len(items)}）")
    ids = {x["id"] for x in items}
    need = {"SF1", "SF2", "SF3", "SF4", "SF5", "SF6", "SF7", "SF8", "SF9", "SF10", "SF11", "SF12"}
    ck(ids == need, f"G2 SF1–SF12 全在（缺 {need - ids}）")
    ck(all(x.get("symptom") and x.get("check") for x in items), "G3 每項有 symptom + check")

    m = {x["id"]: x for x in items}

    def blob(k):
        return m[k]["name"] + " " + m[k]["symptom"] + " " + m[k]["check"]

    ck("migrate" in blob("SF6"), "G4 SF6 為 migrate 兜底")
    ck("空池" in blob("SF7") and "null" in blob("SF7"), "G5 SF7 為空池 return null")
    ck("光柱" in blob("SF8"), "G6 SF8 為光柱視覺相同")
    ck("source" in blob("SF9"), "G7 SF9 為 AffixData source 缺失")
    ck("大小寫" in blob("SF10") or "Survive" in blob("SF10"), "G8 SF10 為大小寫不符")
    ck("MATERIAL_KEY_MAP" in blob("SF11"), "G9 SF11 點名 MATERIAL_KEY_MAP")
    ck("埋點" in blob("SF12"), "G10 SF12 為 budget 埋點")


# ============================================================
# H 組 · 主文檔同步性
# ============================================================
def group_h(D, md):
    print("\n--- H. 主文檔同步性 ---")

    ck(bool(md), "H1 主文檔存在且非空")
    ck("180" in md, "H2 主文檔含工單總數 180")
    ck("07-dev-tasks.json" in md, "H3 主文檔引用 JSON")
    ck("07-check_dev_tasks.py" in md, "H4 主文檔引用校驗腳本")

    # 六步各至少出現一次
    for s in ["第一步", "第二步", "第三步", "第四步", "第五步", "第六步"]:
        ck(s in md, f"H5 主文檔含 {s}")

    # 14 條硬約束全部在文檔
    for c in D["hard_batch_constraints"]:
        ck(c["rule"] in md or c["rule"].replace(" + ", "+") in md or c["rule"].split("必須")[0].strip() in md,
           f"H6 主文檔含硬約束 {c['id']}")

    # 跨步修訂 14 行全部在文檔
    for r in D["cross_step_revisions"]["rows"]:
        ck(r["id"] in md, f"H7 主文檔含修訂行 {r['id']}")

    # 靜默失敗 12 條
    for it in D["silent_failure_checklist"]["items"]:
        ck(it["id"] in md, f"H8 主文檔含靜默失敗項 {it['id']}")

    # 素材總帳
    ck("696" in md, "H9 主文檔含第五步 696 幀")
    ck("672" in md, "H10 主文檔含 672 幀")
    ck("48" in md, "H11 主文檔含 48 張詞綴圖標")
    ck("去重" in md or "重疊" in md, "H12 主文檔提示素材重疊")

    # 驗收
    ck("372" in md, "H13 主文檔含 372 通過")
    ck("186" in md and "202" in md, "H14 主文檔含 06 腳本基線")

    # 全部 180 條工單編號在文檔中出現（抽樣全集）
    missing = []
    for x in D["work_orders"]:
        if x["id"] not in md:
            missing.append(x["id"])
    ck(not missing, f"H15 全部 180 條工單編號在文檔中出現（缺 {len(missing)}: {missing[:8]}）")


# ============================================================
# E-repo 組 · 工程側漂移（僅 --repo）
# ============================================================
def group_repo(D):
    print("\n--- E-repo. 工程側漂移（僅 --repo） ---")

    ck(REPO and os.path.isdir(REPO), f"R1 repo 目錄存在（{REPO}）")
    if not (REPO and os.path.isdir(REPO)):
        return

    gc = os.path.join(REPO, "game", "scripts", "core", "game_constants.gd")
    ck(os.path.isfile(gc), "R2 game_constants.gd 存在")

    def const_of(path, name):
        """取 `const NAME[: type] = value` 的 value（容忍類型標註）。"""
        if not os.path.isfile(path):
            return None
        t = read_text(path)
        m = re.search(rf"const\s+{re.escape(name)}\s*(?::[^=\n]*)?=\s*([0-9.]+)", t)
        return m.group(1) if m else None

    if os.path.isfile(gc):
        # W1 已落地（B1 · 2026-09-28）：1.22 / 1.16 → 1.12 / 1.12
        v = const_of(gc, "MONSTER_HP_GROWTH")
        ck(v == "1.12", f"R3 MONSTER_HP_GROWTH = 1.12（B1 已落地；實 {v or 'N/A'}）")
        v = const_of(gc, "MONSTER_DMG_GROWTH")
        ck(v == "1.12", f"R4 MONSTER_DMG_GROWTH = 1.12（B1 已落地；實 {v or 'N/A'}）")
        # S12 未落地：稀有度仍 8 檔
        v = const_of(gc, "RARITY_COUNT")
        ck(v == "8", f"R5 RARITY_COUNT 仍為 8（實 {v or 'N/A'}）")
        ck("SPECIAL_ABYSS" not in read_text(gc), "R6 SPECIAL_ABYSS 尚未定義（S12 未落地）")
        # B5-1 已落地：SAVE_VERSION 5 → 6（S10 落地 v6 = tickets + tower_progress）
        v = const_of(gc, "SAVE_VERSION")
        ck(v == "6", f"R7 SAVE_VERSION 已為 6（B5-1 / S10 落地；實 {v or 'N/A'}）")

    al = os.path.join(REPO, "game", "scripts", "account", "account_level.gd")
    ck(os.path.isfile(al), "R8 account_level.gd 存在")
    if os.path.isfile(al):
        # W10 已落地（B1 · 2026-09-28）：60 → 20
        v = const_of(al, "MAX_ACCOUNT_LEVEL")
        ck(v == "20", f"R9 MAX_ACCOUNT_LEVEL = 20（B1 已落地；實 {v or 'N/A'}）")

    sd = os.path.join(REPO, "game", "resources", "save_data.gd")
    ck(os.path.isfile(sd), "R10 save_data.gd 存在")
    if os.path.isfile(sd):
        t = read_text(sd)
        ck("tickets" in t, "R11 save_data 已含 tickets 字段（B5-1 / S10 落地）")
        ck("tower_progress" in t, "R12 save_data 已含 tower_progress 字段（B5-1 / S10 落地）")

    # 目錄級漂移：特殊檔底材不存在
    eq = os.path.join(REPO, "game", "data", "equipment")
    if os.path.isdir(eq):
        files = os.listdir(eq)
        ck(not any("special" in f for f in files), f"R13 尚無 special_*.json 底材（實 {[f for f in files if 'special' in f]}）")

    # 塔/深淵關卡不存在
    lv = os.path.join(REPO, "game", "data", "levels")
    if os.path.isdir(lv):
        files = os.listdir(lv)
        ck(not any(("tower" in f or "abyss" in f) for f in files), "R14 尚無塔/深淵關卡文件")

    # 二階段未落地：bosses.json 仍為 4 階段
    bj = os.path.join(REPO, "game", "data", "bosses", "bosses.json")
    if os.path.isfile(bj):
        t = read_text(bj)
        ck("0.75" in t, "R15 bosses.json 仍為 4 階段（thresholds 含 0.75，S11 未落地）")

    # 策劃側未動工程：git 目錄存在
    gd = os.path.join(REPO, ".git")
    ck(os.path.isdir(gd), "R16 .git 存在（可選檢查）")


# ============================================================
def main():
    print("=" * 70)
    print("第七步校驗 · 07-check_dev_tasks.py")
    print(f"工程根目錄：{REPO if REPO else '（未提供，跳過 E-repo 組）'}")
    print("=" * 70)

    D = load_json(JSON_PATH)
    md = read_text(MD_PATH) if os.path.isfile(MD_PATH) else ""

    ids, idset = group_a(D, md)
    group_b(D, idset)
    group_c(D)
    group_d(D)
    group_e(D)
    group_f(D)
    group_g(D)
    group_h(D, md)
    if REPO:
        group_repo(D)

    print("\n" + "=" * 70)
    print(f"通過 {PASS} / 失敗 {FAIL}")
    if FAILED:
        print("失敗項：")
        for f in FAILED:
            print("  -", f)
    print("=" * 70)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
