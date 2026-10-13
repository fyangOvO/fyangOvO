# 《七傳說》Playground 開發描述 v2（爆款暗黑向 · 已升級）

> 用途：把「第 1 節英文 Prompt」直接貼進 Google Playground 輸入框，選 **2D game · Single player**。
> v2 升級方向：對標當下最熱門的「高速割草 + Build 聚變 + 打擊感拉滿」暗黑刷寶玩法
> （Vampire Survivors / Brotato 的滿屏爽感 × Hades 的三選一祝福 × 暖雪的武器聖物 Build 聚變 × Halls of Torment 的復古厚重像素暗黑）。
> 第 3 節是新增的「像素美術與動效規格」，決定生成出來的畫面好不好看、動不動得起來。

---

## 1. 直接貼給 Playground 的英文 Prompt（v2 · 複製這段）

```
Build "Seven Legends" (七傳說): a 2D top-down pixel-art dark-fantasy action roguelike looter, single player. Think Vampire Survivors / Brotato (fast screen-filling mowing) meets Hades (mid-run choice-of-3 boons) meets Warm Snow (weapon + relic build fusion) meets Halls of Torment (chunky retro 90s dark pixel look).

FEEL FIRST (this is the #1 priority):
- Fast, juicy, screen-filling combat. Waves of 50–200+ monsters flood the screen; skills cover the floor in fire/poison/lightning fields and flying projectiles; the player carves through crowds in a shower of particles, damage numbers and gold drops.
- Heavy impact feedback on every hit: brief hit-stop (freeze 30–60ms on crit), camera shake scaled to hit size, colored damage-number popups (crit = big yellow, elemental = element color, DoT = small ticks), blood/ember/spark particle bursts, ground scorch marks and lingering burn/poison patches.
- Crisp responsive controls: WASD move, mouse aim, left-click attack, keys 1/2/3 skills, dash/i-frame. Movement must feel tight; enemies must telegraph attacks before landing.

CORE LOOP: Pick a class → fight through a stage of escalating monster waves → LEVEL-UP MID-RUN and choose 1 of 3 boons (Hades-style: new skill / upgrade existing skill / stat boost / relic) → survive and scale your build → beat a chapter BOSS with big telegraphed AoE attacks → return to a dark hub camp → spend gold + loot on permanent upgrades, gear rerolls and talent tree → unlock harder nightmare tiers. Death sends you back to the hub with kept meta-currency (roguelite meta-progression).

THREE CLASSES (fast, expressive):
- Warrior: melee bruiser, whirlwind spins that suck crowds in, ground slam shockwaves, warcry buffs, lifesteal. (close-range AoE blender)
- Archer: kiting crit machine, piercing multi-arrows, arrow rains, traps, poison fields, a summon spirit wolf tank. (ranged crowd control)
- Mage: elemental nuke caster, homing/projectile fireballs, chaining lightning, freeze nova, meteor burns the ground, thunderstorms, void rift that pulls enemies in. (screen-filling elemental chaos)

SKILL MORPHOLOGY (7 shapes): single-target, self-AoE, dash/i-frame, flying projectile, ground damage-over-time field, friendly summon (AI unit that fights for you), self-buff/shield. Every skill has cooldown + mana cost; skills can be wildly re-shaped by runes.

RUNES = THE BUILD ENGINE (the heart of the game): 24 collectible runes drop from monsters (normal 2% / elite 8% / boss 25%). First pickup PERMANENTLY unlocks it (codex, free equip/unequip, no cost); duplicates convert to currency. Each skill has 3 rune sockets. Runes let you FUSE a skill into a totally different build:
- Change FORM: turn a melee swing into a piercing projectile, or chain lightning, or split into 3, or a lingering ground field, or echo-cast twice.
- Change ELEMENT: fire(+burn) / cold(+slow/freeze) / lightning / poison(+DoT) / shadow — each +15% and applies its status.
- Amplify: wider radius, -25% cooldown, -40% mana, +25% damage, lifesteal, stun, freeze, execute low-HP, +shield on cast.
- Same group mutually exclusive → every skill is a real build decision. At skill level 5 pick a 2-way branch.
GOAL: make silly-but-powerful combos (e.g. "whirlwind + fire rune + wider radius + lifesteal = spinning fire blender that heals") the core fun.

IN-RUN BOONS (Hades-style, mid-run level-ups): offer a random draw of 3 from a pool of ~40 — unlock a new skill, upgrade a skill's level, add a relic (passive that synergizes with your element/form), +crit, +move speed, +damage taken reduction, lifesteal, area size, projectile count. Picks must visibly compound: by minute 10 the screen should be chaos with 3 fields + projectiles + summons out.

GEAR & LOOT: 6 equipment slots, random affixes (attack%, crit, crit damage, cooldown reduction, skill-cost reduction, per-element damage & resistances, +skill level). Rarity tiers gray→magic(yellow)→rare(blue)→epic(purple)→legendary(orange)→mythic(red)→hidden(rainbow). Legendary items have unique PROC effects firing on hit/crit/kill/low-HP/block/cast — e.g. crit-stacks-then-explodes, kill-spreads-fire, lifesteal chains, near-death shield. 3 themed sets (ice-slow burst / fire-stack burn / tank block-heal) give 4pc & 6pc bonuses. Hub has a forge: upgrade +N, reroll affixes, reroll legendary effect, dismantle, craft.

ELEMENTS: physical / fire(burn DoT) / cold(slow+freeze) / lightning / poison(DoT) / shadow; each with own damage bonus & resistance. Damage popups colored per element.

ENEMIES: dense swarms of normal monsters (slimes, skeletons, imps, rat swarms, wisps), faster/tankier ELITES with colored health bars and guaranteed drops, and a big named BOSS per chapter with clearly telegraphed ground circles before its attacks. ~250–300 normals + 8–10 elites + 1 boss per run; difficulty scales by wave.

HUB CAMP: dark campfire scene with 8 NPCs (blacksmith, gemcrafter, quest giver, guard, merchant, rift/abyss keeper, master) — click to open skills / rune codex / inventory / forge / shop / talent tree / stage select.

VISUAL STYLE (pixel & animation — see spec below): chunky 16-bit dark-fantasy pixel art, moody gothic palette (deep blues/purples/charcoal with fiery orange accents), 8-direction characters with smooth 4–6 frame walk/idle/cast/hurt/death animations (NOT static standees), particles for every action, dynamic lighting feel (glow from fire/lightning/ground fields), screen shake, damage popups, juicy pickup animations (items pop out with a sparkle, magnet-pickup near player).

MINIMUM PLAYABLE SLICE: tight move+attack+dash, one full stage with escalating waves ending in a boss, ground loot that pops out and magnet-picks up, mid-run level-up "choose 1 of 3", a basic inventory/gear screen, and the hub camp. Controls: WASD + mouse + 1/2/3 + dash. Make it FEEL GOOD first, content second.
```

---

## 2. 相對 v1 改了什麼（為你自己決策）

| 維度 | v1 | v2（爆款向） |
|---|---|---|
| 戰鬥密度 | 一般清怪 | **50–200+ 同屏潮水、滿屏法術/投射物**（VS/Brotato 式割草） |
| 打擊感 | 普通描述 | **頓帧 hit-stop、屏震、按元素變色飄字、血/火星粒子、地面殘留** |
| 局內成長 | 三選一 buff | **Hades 式 boon 池 ~40 個，選項互相疊加成「build 聚變」** |
| 核心樂趣 | 裝備詞綴 | **符文 = 把技能「改造成完全不同的流派」**，鼓勵髮騷但強力的 combo |
| 美術方向 | 16-bit 像素 | **Halls of Torment 式厚重復古暗黑 + 暖雪式水墨質感、動態光** |
| 節奏 | 一關一 boss | **波次遞增、10 分鐘後滿屏 chaos、死亡回營地保留 meta 貨幣（roguelite）** |

---

## 3. 像素美術與動效規格（生成畫面好不好看的關鍵）

> Playground 類工具生成像素圖時，你越明確它越不會給你「靜站姿貼紙人」。以下規格可直接追加到 Prompt 後面。

### 3.1 角色精靈（8 方向 · 必須動起來）
- 尺寸：玩家 48×48 像素；召喚物 32×32；怪物 32–48×32–48。
- 動作 × 方向：每個角色要有 **idle / walk / attack / cast / hurt / death 六組動作，8 個方向（東南西北+四斜角）**。
- 幀數：idle 4 幀（呼吸起伏）、walk 4–6 幀、attack 4–6 幀、**cast 4–6 幀（施法前搖→蓄力→釋放，和劈砍不一樣）**、hurt 2–3 幀、death 4–6 幀（倒地演出）。
- 鐵律：**不能只有正面 1 幀**（v1 舊版最大問題就是角色站著永遠正對鏡頭、走動會「啪」地轉正）。
- 三職業外觀：戰士（白髮/巨劍/重甲）、弓手（綠披風/長弓）、法師（藍袍/法杖）。

### 3.2 技能與特效動圖
- 投射物：箭矢/火球/冰錐/雷球/暗影球，16×16，4 幀循環飛行 + **拖尾**。
- 地面區域：裂地/毒霧/雷暴/隕石坑/虛空裂隙，32×32，6–8 幀循環，**邊緣發光**。
- 元素命中：物理/火/冰/雷/毒/暗 6 種，32×32 × 6 幀爆開。
- 增益光環：戰吼/血怒/鐵壁/鷹眼，角色腳下 32×32 光圈循環。
- 召喚法陣：施放時腳下 8 幀陣陣，召喚物到期粒子消散。

### 3.3 打擊感與「juice」（最影響爽感）
- **Hit-stop**：暴擊時定格 30–60ms；重击/技能命中定格稍久。
- **Screen shake**：輕擊微抖、重擊/爆炸/BOSS 技大幅抖。
- **Damage numbers**：普通白字、暴擊大黃字、元素按元素色（火橙/冰藍/雷黃/毒綠/暗影紫）、DoT 小跳字。
- **粒子**：命中火花、血濺、火星、毒霧、雷電弧、死亡煙塵。
- **地面殘留**：火燒黑印、毒霧斑、冰凍結——讓戰場有「打過的痕跡」。
- **拾取**：掉落物 pop 出來帶星光、靠近自動吸附（magnet pickup）。

### 3.4 視覺氛圍
- 調色盤：深藍/深紫/炭黑為底 + 火橙/雷黃點綴，哥特暗黑感。
- 動態光：火/雷/地面區域自帶發光，照亮周圍。
- BOSS 技：落地前**地面紅圈預警**（telegraph），玩家要能躲。

---

## 4. Playground 最小可玩切片建議
先做：移動+普攻+閃避 → 1 關波次遞增到 1 BOSS → 掉落彈出可吸附 → 局內升級三選一 → 基本背包/裝備 → 營地場景。**先把「手感」做爽，內容其次。**
