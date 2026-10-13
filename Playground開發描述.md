# 《七傳說》Playground 開發描述

> 用途：把這段「遊戲描述」貼進 Google Playground 輸入框（截圖那個 "Describe a game to start building"），
> 選擇 **2D game · Single player**，讓 AI 直接生成這款遊戲。
> 下方第 1 節是可直接複製的英文 Prompt（Playground 對英文理解最好）；
> 第 2 節是繁中策劃要點，供你自己看懂結構、或需要時換成中文貼。

---

## 1. 直接貼給 Playground 的英文 Prompt（複製這段）

```
Build "Seven Legends" (七傳說): a 2D top-down pixel-art action RPG (ARPG) roguelike looter, single player, dark fantasy 16-bit style with a limited palette.

CORE LOOP: Pick a hero class → enter a hand-crafted chapter stage full of monsters → fight in real time with WASD movement + mouse aim/attack + 3 hotbar skills → kill monsters to loot gold, materials, equipment and runes → level up mid-stage via a "choose 1 of 3" buff upgrade → beat a chapter BOSS → return to a hub camp town → upgrade/forge/reroll gear → push deeper into harder stages (N nightmare tiers).

THREE CLASSES (each 12 skills, only 3 equipped at a time):
- Warrior: melee, high HP, front-line tank. (cleave, spinning whirlwind, dash strike, shield bash stun, warcry +attack, ground slam AoE, thrown blades, blood rage lifesteal, iron wall shield buff…)
- Archer: ranged, high crit, kiting. (piercing arrows, arrow rain, poison arrows, multi-shot fan, explosive arrow, spike trap, hawk-eye +crit, speed dodge buff, poison field, summon spirit wolf, hunter's mark…)
- Mage: caster, high burst, elemental mastery. (projectile fireball, frost nova, chaining lightning, poison cloud, frost bolt slow, meteor with burn ground, arcane shield, teleport blink, summon elemental, thunderstorm, mana surge, void rift pull…)

SKILL MORPHOLOGY: 7 skill shapes — single-target, AoE around self, dash, projectile (flying bullet), ground area (damage-over-time field), summon (friendly AI unit), self-buff/shield. Every skill has cooldown + mana cost.

RUNE SYSTEM (build depth): 24 collectible runes drop from monsters (normal 2% / elite 8% / boss 25%). First pickup PERMANENTLY unlocks it (codex style, free equip/unequip); duplicates auto-convert to currency. Each skill has 3 rune sockets (unlocked at skill level 3/6/9). Runes modify a skill: change its form (turn melee into a projectile, chain, split, pierce, ground field, echo), change its element (fire/cold/lightning/poison/shadow, +15% elemental damage, apply burn/slow/poison), or amplify it (wider radius, -25% cooldown, -40% mana cost, +25% damage, lifesteal, stun, freeze, execute low-HP targets, +shield…). Runes in the same group are mutually exclusive, forcing choices. Each skill at level 5 also gets a 2-way branch (e.g. single: +40% damage vs. extra hit).

GEAR & LOOT: 6 equipment slots (weapon/offhand/helm/chest/gloves/boots/jewelry). Items roll random affixes (attack %, crit, crit damage, cooldown reduction, skill-cost reduction, elemental damage per element, elemental resistances, skill level…). Rarity tiers from normal up through magic/rare/epic/legendary/mythic/hidden. Legendary gear carries powerful PROC effects that fire on combat triggers (on-hit, on-crit, on-kill, on-taken-damage, at-low-HP, on-block, on-cast, on-pickup-gold) — e.g. lifesteal chains, crit-stack explosions, kill-spread-fire, near-death shield. Three gear sets (Frostbite/ice slow+ice-burst, Emberpath/fire stack+burn-on-kill, Oathkeeper/block heal+last-stand) give 4-piece and 6-piece set bonuses. Hub town has forge: upgrade (+N), reroll affixes, re-roll legendary effect, dismantle, craft.

ELEMENTS: physical / fire / cold / lightning / poison / shadow, each with its own damage bonus and resistance; fire=burn, cold=slow/freeze, poison=poison DoT.

ENEMIES: packs of normal monsters (slimes, skeletons, imps, rat swarms, wisp…), tougher ELITES with more HP and better drops, and a named BOSS at the end of each chapter with telegraphed area attacks. Roughly 250–300 normal monsters + 8–10 elites + 1 boss per run.

HUB CAMP: a campfire scene with 8 NPCs (blacksmith, tailor/gemcrafter, quest giver, guard, merchant, abyss/rift keeper, master) — clicking an NPC opens its panel (skills, rune codex, gear, forge, shop, talent tree, stage select).

VISUAL & FEEL: crisp 16-bit pixel sprites, 8-direction movement with smooth walk/idle/cast/hurt/death animations, particles for hits/spells/pickups, damage numbers colored by element, HUD with HP/mana bars, 3-skill hotbar with cooldown masks, minimap-light dark atmosphere.

MAKE IT PLAYABLE: core combat (move/attack/skills), one full stage with waves + a boss, loot drops that show on the ground and can be picked up, a basic inventory/gear screen, and the hub camp. Keep controls simple (WASD + mouse + 1/2/3 skills).
```

---

## 2. 繁中策劃要點（給你自己看 / 可換成中文貼）

### 一句話定位
《七傳說》是一款 **2D 俯視像素風、單人、暗黑奇幻「刷寶 ARPG」**，融合暗黑式裝備詞綴養成 + 類幸存者的局內三選一成長 + 肉鴿關卡推進。

### 核心循環
選職業 → 進關卡清怪 → 即時戰鬥（走位 + 普攻 + 3 個技能）→ 撿金錢/材料/裝備/符文 → 局內升級三選一 buff → 打章節 BOSS → 回營地強化裝備 → 挑戰更難關卡（夢魘 I–V 難度層級）。

### 三大職業（每職 12 技能，出戰只帶 3 個）
- **戰士**：近戰、高生命、正面硬撼（裂斬/旋刃風暴/突進/盾擊眩暈/戰吼/踐踏/擲刃/血怒吸血/鐵壁護盾…）
- **弓箭手**：遠程、高暴擊、放風箏（穿透箭/箭雨/淬毒箭/多重射擊/爆裂箭/尖刺陷阱/鷹眼暴擊/疾風步/毒霧/召喚靈狼/獵手印記…）
- **法師**：法術、高爆發、元素掌控（火球投射/冰霜新星/閃電鏈/毒雲/寒冰箭減速/隕石火海/秘法護盾/瞬移/召喚元素僕從/雷暴/法力湧動/虛空裂隙拉拽…）

### 七種技能形態
單體 / 範圍 / 位移 / **投射物（飛行彈道）** / **持續地面區域（DoT）** / **召喚友方 AI** / **自身增益護盾**。

### 符文系統（核心構築深度）
- 24 種符文，怪物掉落（普通 2% / 精英 8% / BOSS 25%）。
- **首獲永久解鎖**（圖鑑式、免費拆裝），重複自動轉成魔石；沒解鎖不能裝。
- 每技能 3 個符文槽（技能等級 3/6/9 解鎖）。
- 符文可：**改形態**（單體變投射/連鎖/分裂/穿透/地面化/回響）、**改元素**（火冰雷毒暗 +15% 元素傷並附灼燒/減速/中毒）、**改數值**（擴幅/冷卻-25%/耗藍-40%/倍率+25%/吸血/眩暈/冰封/處決/加護盾…）。同組互斥，逼取捨。
- 技能等級 5 還可二選一分支（如單體：+40% 傷 vs 追加一段）。

### 裝備與掉落
- 6 個裝備位；隨機詞綴（攻擊%、暴擊、暴傷、冷卻縮減、耗藍縮減、各元素傷/抗、技能等級…）。
- 稀有度：普通 → 魔法 → 稀有 → 史詩 → 傳奇 → 神話(紅) → 隱藏(彩)。
- **傳奇特效**：穿在身上會在戰鬥中觸發（命中/暴擊/擊殺/受傷/低血/格擋/施法/撿金幣），如吸血鏈、暴擊疊層爆炸、擊殺擴散火焰、瀕死免死護盾。
- **三套套裝**：霜噬(冰減速+霜爆)、燼途(火疊層+擊殺燃燒)、守誓者(格擋回血+背水一戰)，4 件/6 件檔獎勵。
- 營地鍛造：強化(+N)、洗練詞綴、重鑄傳奇特效、分解、打造。

### 元素體系
物理 / 火(灼燒) / 冰(減速凍結) / 雷 / 毒(中毒 DoT) / 暗影；每元素有獨立傷害加成與抗性。

### 敵人關卡
每局約 250–300 隻普通怪（史萊姆/骷髏/小惡魔/鼠群/精靈…）+ 8–10 隻精英 + 1 個章節名 BOSS（有預警範圍技）。章節 BOSS 依序為骸骨暴君 → 熔心之主 → 終章。

### 營地（Hub）
篝火營地場景 + 8 個 NPC 熱區（鍛造/裁縫珠寶/任務/守衛/商人/深淵裂隙/宗師），點擊開對應面板（技能、符文圖鑑、背包、鍛造、商店、天賦樹、選關）。

### 視覺與手感
16-bit 像素、有限色調、8 方向移動、流暢待機/走路/施法/受擊/死亡動畫、命中與法術粒子、按元素變色的傷害跳字、HUD 血/藍條 + 3 技能快捷欄（冷卻遮罩）、偏暗黑陰沉氛圍。

### Playground 最小可玩切片建議
先做：移動/普攻/3 技能戰鬥 → 1 關小怪潮 + 1 BOSS → 地面掉落可拾取 → 基本背包/裝備界面 → 營地場景。操作：WASD + 滑鼠 + 1/2/3 放技能。
