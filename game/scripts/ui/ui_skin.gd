## UI 皮膚層（UI Skin Layer）· 素材 → 樣式工廠
##
## 職責：把 `assets/ui/quest/`（任務 UI 素材包）與 `assets/ui/quest/backdrops/`（生態背景）
## 變成 Godot 的 `StyleBoxTexture` / `Texture2D`，供各面板（封面 / 關卡 HUD / 裝備欄）套用。
##
## 為什麼單獨一層（而不是散在各面板裡拼路徑）
## ------------------------------------------
## 專案既有的**內容替換層**鐵律：所有美術資源都必須可被玩家用 `user://content/<類別>/`
## 覆蓋（見 `content_paths.gd` 的類註釋）。UI 皮膚是新素材類別（`ContentPaths.CLASS_UI`），
## 若每個面板各寫各的路徑，這條鏈就會像 `CLASS_UI` 之前那樣**鉤子建好、零消費者**。
## 本類是 UI 素材的**唯一**解析入口，所有面板一律走這裡 → 用戶把檔案丟進
## `user://content/ui/quest/…` 即可替換，不必改代碼、不必重新打包。
##
## 三級優先（與 `ContentPaths` 一致）
## --------------------------------
##   ① `user://content/ui/<相對路徑>`   用戶覆蓋（最高）
##   ② `res://assets/ui/quest/<相對路徑>` 隨包內建
##   ③ 缺素材 → 工廠回傳 `null`           調用方回退到 `UITheme` 的 StyleBoxFlat
##
## ⚠️ **缺素材必須安全降級**：本類任何工廠方法在素材缺失時一律回傳 `null` / 空字典，
##    **絕不拋錯、絕不黑屏**。調用方（封面 / HUD / 裝備欄）拿到 `null` 就沿用既有的
##    程序化 `UITheme` 樣式 —— 這也是「把 `assets/ui/quest/` 整包移走，遊戲照樣跑」的保證。
##
## 用法：
##   var sb := UISkin.panel_stylebox()          # StyleBoxTexture 或 null
##   if sb != null: panel.add_theme_stylebox_override("panel", sb)
##   var boxes := UISkin.btn_styleboxes("gold") # {"normal":..,"hover":..,"pressed":..}
class_name UISkin
extends RefCounted

## 內建素材根目錄（用戶層為 `user://content/ui/`，相對路徑一致）
const BUILTIN_ROOT: String = "res://assets/ui/quest"

## 9-slice 邊距（像素）。SPEC.md 規定任務面板為 **8px**（四角鉚釘 + 邊框完整保留）。
const PANEL_MARGIN: int = 8
## 按鈕貼圖 96×24，邊距 6px（保留描邊與角，中央拉伸放字）。
const BTN_MARGIN: int = 6
## 物品格貼圖 48×48，邊距 4px（保留 1px 硬描邊 + 內縮）。
const SLOT_MARGIN: int = 4

## 邏輯名 → 相對路徑（相對 `BUILTIN_ROOT`；用戶層同構）。
## ⚠️ 相對路徑即**用戶覆蓋契約**：改名等於破壞玩家既有的 `user://content/ui/` 佈局。
const TEX: Dictionary = {
	# 面板 / 橫幅 / 分隔
	"panel": "quest_panel_9slice.png",
	"banner": "quest_banner_256x48.png",
	"divider": "divider_160x8.png",
	"marker": "quest_marker_24.png",
	# 按鈕三態（金系主按鈕 / 藍灰次按鈕）
	# ⚠️ 128×24（規範 C6）：2× 整數放大 ⇒ 顯示 256×48。舊 96×24 在 296px 內容區裡
	#    左右各空 52px，讀成「按鈕太窄」。**改尺寸必須同步改 `verify_ui_assets.gd`
	#    的 `EXPECT_TEX` 與 `BTN_SIZE` 斷言**，否則回歸立刻變紅。
	"btn_gold_normal": "btn_gold_normal_128x24.png",
	"btn_gold_hover": "btn_gold_hover_128x24.png",
	"btn_gold_pressed": "btn_gold_pressed_128x24.png",
	"btn_dark_normal": "btn_dark_normal_128x24.png",
	"btn_dark_hover": "btn_dark_hover_128x24.png",
	"btn_dark_pressed": "btn_dark_pressed_128x24.png",
	# 物品格（默認 / 選中 / 五階稀有度）
	"slot_normal": "slot_normal_48.png",
	"slot_selected": "slot_selected_48.png",
	"slot_common": "slot_common_48.png",
	"slot_rare": "slot_rare_48.png",
	"slot_epic": "slot_epic_48.png",
	"slot_legend": "slot_legend_48.png",
	"slot_orange": "slot_orange_48.png",
	# 高階稀有度（2026-09-21 補缺口）：神話紅 / 套裝綠 / 隱藏彩虹
	"slot_mythic": "slot_mythic_48.png",
	"slot_set": "slot_set_48.png",
	"slot_hidden": "slot_hidden_48.png",
	# 星級 / 背景
	# ⚠️ 2026-09-21 之前 `star_lit_16.png` **真的是四角十字**（檔名說謊，見規範 L3）；
	#    已由 `quest_pack_gen.py` 重導為**真五角星**（16×16，亮 `D9A521` / 暗 `3A424F`，
	#    描邊 `0B0D10`）。**檔名不變** ⇒ 本表與消費方零改動。
	"star_lit": "star_lit_16.png",
	"star_dim": "star_dim_16.png",
	"backdrop_forest": "backdrops/backdrop_forest_640x360.png",
	"backdrop_frost": "backdrops/backdrop_frost_640x360.png",
	"backdrop_volcanic": "backdrops/backdrop_volcanic_640x360.png",
	# ── 2026-09-21 用戶像素素材包接入（`ui/`）─────
	# 用戶原話「ui素材優先用這裡面的」。面板 / 槽位 / 稀有度框 / 三張生態背景
	# 是**同名替換**（檔名不變、內容換成包裡的）⇒ 本表與消費方零改動。
	# 以下這批是包**新增**、遊戲原本沒有的件，故在此追加邏輯名。
	#
	# ⚠️ 封面主菜單背景：包提供 `main_menu_bg_640x360.png`（暗色地牢 + 紅星空）。
	#    它由 `main_menu_screen.gd` 的 `_build_backdrop()` 優先使用，生態 backdrop 作回退。
	"main_menu_bg": "main_menu_bg_640x360.png",
	# 血 / 藍條（160×16，凹槽 + 金屬端帽）。填滿一律靠**代碼裁切**，不要拉伸端帽。
	"bar_hp": "bar_hp_160x16.png",
	"bar_mp": "bar_mp_160x16.png",
	# 技能欄槽（48×48，斜切角 + 四角鉚釘）與四個技能圖標。
	# ⚠️ 圖標與技能的對應關係見 `level_scene.gd` 的 `SKILL_BAR`——**不要憑檔名猜**，
	#    以 `game/data/skills.json` 的真實 id 為準。
	"skill_slot": "skill_slot_48.png",
	"skill_icon_slash": "skill_icon_slash_48.png",
	"skill_icon_fireburst": "skill_icon_fireburst_48.png",
	"skill_icon_frostnova": "skill_icon_frostnova_48.png",
	"skill_icon_shadowdash": "skill_icon_shadowdash_48.png",
	# 2026-09-21 補缺口：雷系閃電鏈 / 毒系毒雲
	"skill_icon_lightning_chain": "skill_icon_lightning_chain_48.png",
	"skill_icon_poison_cloud": "skill_icon_poison_cloud_48.png",
	"skill_icon_piercing_shot": "skill_icon_piercing_shot_48.png",
	"skill_icon_arrow_rain": "skill_icon_arrow_rain_48.png",
	# ── 2026-09-22 首頁定稿：標題 LOGO 底板 + 燙金字 + 火把 + 三職業立繪 ──
	# 標題徽章（336×112，金框龍紋 + 深色銘牌 + 副標題已烘焙）與燙金像素字（240×64）
	"title_emblem": "title_emblem.png",
	"title_text": "title_text.png",
	# 壁掛火把（80×80，含火焰；動態氛圍由場景層做 flicker + 火星粒子）
	"torch": "torch.png",
	# 三職業立繪（188×250 透明底；首頁展示戰士，弓/法為步驟 2 角色選擇備用）
	"panel_gold": "panel_gold.png",
	"portrait_warrior": "portraits/char_warrior.png",
	"portrait_archer": "portraits/char_archer.png",
	"portrait_mage": "portraits/char_mage.png",
	# 據點 NPC 立繪（透明底，2048 原尺寸，場景縮放到 56×84）
	"npc_smith": "npc/smith_small.png",
	"npc_tailor": "npc/tailor_small.png",
	"npc_gem": "npc/gem_small.png",
	"npc_master": "npc/master_small.png",
	# ── 2026-09-23 步骤 8A：消耗品药水图标（48×48 像素风，与技能图标同套）──
	"potion_life": "potion_life_48.png",
	"potion_mana": "potion_mana_48.png",
	# ── 2026-09-24 步骤 2-L16：词缀图标 48 条（32×32，严格 44 色）──
	# 由 deliverables/gstack/素材開發/gen_icons.py 产出；一键一图，不复用。
	# ⚠️ 缺档时 texture() 回 null（安全降级），不会报错。
	"affix_ailment_chance": "affix_ailment_chance_32.png",
	"affix_ailment_duration": "affix_ailment_duration_32.png",
	"affix_ailment_effect": "affix_ailment_effect_32.png",
	"affix_all_attributes": "affix_all_attributes_32.png",
	"affix_all_element_damage": "affix_all_element_damage_32.png",
	"affix_all_resist": "affix_all_resist_32.png",
	"affix_armor_penetration": "affix_armor_penetration_32.png",
	"affix_attack_speed": "affix_attack_speed_32.png",
	"affix_block_chance": "affix_block_chance_32.png",
	"affix_burn_damage": "affix_burn_damage_32.png",
	"affix_chill_damage": "affix_chill_damage_32.png",
	"affix_cold_resist": "affix_cold_resist_32.png",
	"affix_cooldown_reduction": "affix_cooldown_reduction_32.png",
	"affix_crit_chance": "affix_crit_chance_32.png",
	"affix_crit_damage": "affix_crit_damage_32.png",
	"affix_curse_damage": "affix_curse_damage_32.png",
	"affix_damage_vs_ailment": "affix_damage_vs_ailment_32.png",
	"affix_dodge": "affix_dodge_32.png",
	"affix_echo_strike": "affix_echo_strike_32.png",
	"affix_elemental_damage": "affix_elemental_damage_32.png",
	"affix_elemental_penetration": "affix_elemental_penetration_32.png",
	"affix_fire_resist": "affix_fire_resist_32.png",
	"affix_flat_armor": "affix_flat_armor_32.png",
	"affix_flat_attack": "affix_flat_attack_32.png",
	"affix_flat_hp": "affix_flat_hp_32.png",
	"affix_gold_gain": "affix_gold_gain_32.png",
	"affix_kill_heal": "affix_kill_heal_32.png",
	"affix_life_on_hit": "affix_life_on_hit_32.png",
	"affix_life_regen": "affix_life_regen_32.png",
	"affix_lightning_resist": "affix_lightning_resist_32.png",
	"affix_magic_find": "affix_magic_find_32.png",
	"affix_max_resource": "affix_max_resource_32.png",
	"affix_move_speed": "affix_move_speed_32.png",
	"affix_pct_armor": "affix_pct_armor_32.png",
	"affix_pct_attack": "affix_pct_attack_32.png",
	"affix_pct_hp": "affix_pct_hp_32.png",
	"affix_physical_resist": "affix_physical_resist_32.png",
	"affix_pickup_radius": "affix_pickup_radius_32.png",
	"affix_poison_damage": "affix_poison_damage_32.png",
	"affix_poison_resist": "affix_poison_resist_32.png",
	"affix_resist_penetration": "affix_resist_penetration_32.png",
	"affix_resource_regen": "affix_resource_regen_32.png",
	"affix_shadow_resist": "affix_shadow_resist_32.png",
	"affix_shock_damage": "affix_shock_damage_32.png",
	"affix_skill_cost_reduction": "affix_skill_cost_reduction_32.png",
	"affix_skill_level": "affix_skill_level_32.png",
	"affix_thorns": "affix_thorns_32.png",
	"affix_xp_gain": "affix_xp_gain_32.png",
	# ── 2026-09-24 步骤 3（元素）：属性图标 6 + 抗性图标 5（24×24，严格 44 色）──
	# 命名依 03-elements.json → naming.element_icon / resist_icon。
	# 物理无抗性图标（走护甲），故 resist 只有 5 个。
	"elem_physical": "elem_physical_24.png",
	"elem_fire": "elem_fire_24.png",
	"elem_cold": "elem_cold_24.png",
	"elem_lightning": "elem_lightning_24.png",
	"elem_poison": "elem_poison_24.png",
	"elem_shadow": "elem_shadow_24.png",
	"resist_fire": "resist_fire_24.png",
	"resist_cold": "resist_cold_24.png",
	"resist_lightning": "resist_lightning_24.png",
	"resist_poison": "resist_poison_24.png",
	"resist_shadow": "resist_shadow_24.png",
	# ── 2026-09-24 步骤 1（技能体系）：36 技能各自一张专属图标（48×48）──
	# 旧版是「12 技能共用 4 张通用图标」；本批改为**一技能一图标**（附錄A §A.8）。
	# 已在上方登记的 4 张（lightning_chain / poison_cloud / piercing_shot / arrow_rain）不重复。
	"skill_icon_cleave": "skill_icon_cleave_48.png",
	"skill_icon_spin_slash": "skill_icon_spin_slash_48.png",
	"skill_icon_dash_strike": "skill_icon_dash_strike_48.png",
	"skill_icon_power_strike": "skill_icon_power_strike_48.png",
	"skill_icon_shadow_blink": "skill_icon_shadow_blink_48.png",
	"skill_icon_whirlwind": "skill_icon_whirlwind_48.png",
	"skill_icon_shield_bash": "skill_icon_shield_bash_48.png",
	"skill_icon_warcry": "skill_icon_warcry_48.png",
	"skill_icon_ground_slam": "skill_icon_ground_slam_48.png",
	"skill_icon_blade_toss": "skill_icon_blade_toss_48.png",
	"skill_icon_blood_rage": "skill_icon_blood_rage_48.png",
	"skill_icon_iron_bulwark": "skill_icon_iron_bulwark_48.png",
	"skill_icon_venom_shot": "skill_icon_venom_shot_48.png",
	"skill_icon_multishot": "skill_icon_multishot_48.png",
	"skill_icon_explosive_arrow": "skill_icon_explosive_arrow_48.png",
	"skill_icon_trap_spike": "skill_icon_trap_spike_48.png",
	"skill_icon_hawk_eye": "skill_icon_hawk_eye_48.png",
	"skill_icon_wind_walk": "skill_icon_wind_walk_48.png",
	"skill_icon_poison_field": "skill_icon_poison_field_48.png",
	"skill_icon_spirit_wolf": "skill_icon_spirit_wolf_48.png",
	"skill_icon_shadow_volley": "skill_icon_shadow_volley_48.png",
	"skill_icon_hunters_mark": "skill_icon_hunters_mark_48.png",
	"skill_icon_fireball": "skill_icon_fireball_48.png",
	"skill_icon_frost_nova": "skill_icon_frost_nova_48.png",
	"skill_icon_frost_bolt": "skill_icon_frost_bolt_48.png",
	"skill_icon_meteor": "skill_icon_meteor_48.png",
	"skill_icon_arcane_shield": "skill_icon_arcane_shield_48.png",
	"skill_icon_blink": "skill_icon_blink_48.png",
	"skill_icon_summon_elemental": "skill_icon_summon_elemental_48.png",
	"skill_icon_thunder_storm": "skill_icon_thunder_storm_48.png",
	"skill_icon_mana_surge": "skill_icon_mana_surge_48.png",
	"skill_icon_void_rift": "skill_icon_void_rift_48.png",
	# ── 2026-09-24 步骤 1：符文图标 24 张（32×32，图鉴式解锁）──
	# 命名去掉冗余的 `rune_` 前缀：id `rune_projectile` → 键 `rune_icon_projectile`。取用見 `rune_icon()`。
	"rune_icon_projectile": "rune_icon_projectile_32.png",
	"rune_icon_chain": "rune_icon_chain_32.png",
	"rune_icon_split": "rune_icon_split_32.png",
	"rune_icon_pierce": "rune_icon_pierce_32.png",
	"rune_icon_ground": "rune_icon_ground_32.png",
	"rune_icon_echo": "rune_icon_echo_32.png",
	"rune_icon_fire": "rune_icon_fire_32.png",
	"rune_icon_cold": "rune_icon_cold_32.png",
	"rune_icon_lightning": "rune_icon_lightning_32.png",
	"rune_icon_poison": "rune_icon_poison_32.png",
	"rune_icon_shadow": "rune_icon_shadow_32.png",
	"rune_icon_wider": "rune_icon_wider_32.png",
	"rune_icon_swift": "rune_icon_swift_32.png",
	"rune_icon_thrifty": "rune_icon_thrifty_32.png",
	"rune_icon_heavy": "rune_icon_heavy_32.png",
	"rune_icon_leech": "rune_icon_leech_32.png",
	"rune_icon_stun": "rune_icon_stun_32.png",
	"rune_icon_freeze": "rune_icon_freeze_32.png",
	"rune_icon_burn": "rune_icon_burn_32.png",
	"rune_icon_execute": "rune_icon_execute_32.png",
	"rune_icon_opener": "rune_icon_opener_32.png",
	"rune_icon_barrier": "rune_icon_barrier_32.png",
	"rune_icon_mana": "rune_icon_mana_32.png",
	"rune_icon_amplify": "rune_icon_amplify_32.png",
	# ── 2026-09-24 步骤 2（装备）：强化/洗练/重铸 系统入口标识（48×48）与材料图标（32×32）──
	"forge_icon": "forge_icon_48.png",
	"enchant_icon": "enchant_icon_48.png",
	"reroll_icon": "reroll_icon_48.png",
	"stone_forge": "stone_forge_32.png",
	"scroll_enchant": "scroll_enchant_32.png",
	"crystal_reroll": "crystal_reroll_32.png",
	# ── 2026-09-28 步骤 3（元素）：异常 6 + 单元素伤害 6 + 附着层 6 + 技能边框 6 + 专精角标 5 ──
	# 命名依 03-elements.json → naming（ailment_icon / attach_layer / skill_frame / affix_badge），
	# 并合 04-数值与数据模型.md §8.3。尺寸依序 24 / 24 / 32 / 48 / 16。
	# ⚠️ elem_dmg_* 与 elem_* **同基元**，只多四向爆裂刺 ⇒ 一眼看出「同元素、加强版」。
	"ailment_burn": "ailment_burn_24.png",
	"ailment_chill": "ailment_chill_24.png",
	"ailment_poison": "ailment_poison_24.png",
	"ailment_shock": "ailment_shock_24.png",
	"ailment_curse": "ailment_curse_24.png",
	"ailment_sunder": "ailment_sunder_24.png",
	"elem_dmg_physical": "elem_dmg_physical_24.png",
	"elem_dmg_fire": "elem_dmg_fire_24.png",
	"elem_dmg_cold": "elem_dmg_cold_24.png",
	"elem_dmg_lightning": "elem_dmg_lightning_24.png",
	"elem_dmg_poison": "elem_dmg_poison_24.png",
	"elem_dmg_shadow": "elem_dmg_shadow_24.png",
	"attach_physical": "attach_physical_32.png",
	"attach_fire": "attach_fire_32.png",
	"attach_cold": "attach_cold_32.png",
	"attach_lightning": "attach_lightning_32.png",
	"attach_poison": "attach_poison_32.png",
	"attach_shadow": "attach_shadow_32.png",
	"skill_frame_physical": "skill_frame_physical_48.png",
	"skill_frame_fire": "skill_frame_fire_48.png",
	"skill_frame_cold": "skill_frame_cold_48.png",
	"skill_frame_lightning": "skill_frame_lightning_48.png",
	"skill_frame_poison": "skill_frame_poison_48.png",
	"skill_frame_shadow": "skill_frame_shadow_48.png",
	"elem_badge_fire": "elem_badge_fire_16.png",
	"elem_badge_cold": "elem_badge_cold_16.png",
	"elem_badge_lightning": "elem_badge_lightning_16.png",
	"elem_badge_poison": "elem_badge_poison_16.png",
	"elem_badge_shadow": "elem_badge_shadow_16.png",
	# ── 2026-09-28 步骤 4（数值）：临时增益系统 UI（04-数值与数据模型.md §8.1）──
	# ⚠️ 该系统**代码侧尚未实现**（scripts/ 下无 temp_buff / shrine 消费点）
	# ⇒ 图标先备好并登记，待系统落地即可直接用；现取用会得到非 null 贴图但无人调用。
	"temp_buff_shrine_fury": "temp_buff_shrine_fury_32.png",
	"temp_buff_shrine_swift": "temp_buff_shrine_swift_32.png",
	"temp_buff_shrine_ward": "temp_buff_shrine_ward_32.png",
	"temp_buff_orb_haste": "temp_buff_orb_haste_24.png",
	"temp_buff_orb_pierce": "temp_buff_orb_pierce_24.png",
	"temp_buff_orb_leech": "temp_buff_orb_leech_24.png",
	"temp_buff_orb_boss_might": "temp_buff_orb_boss_might_24.png",
	"temp_buff_orb_boss_echo": "temp_buff_orb_boss_echo_24.png",
	"temp_buff_timer_bar_bg": "temp_buff_timer_bar_bg.png",
	"temp_buff_timer_bar_fill": "temp_buff_timer_bar_fill.png",
	# ── 2026-09-28 步骤 1（技能体系）：技能分支图标 28 张（32×32）──
	# 14 模板 × 2 态（normal / sel）；id 取自 `01-branches.json` 的 `branches[].id`。
	# ⚠️ **消费端尚未实现**：`skill_controller.gd` 只做了 SINGLE/AOE/DASH，
	#    缺 projectile / ground / summon / buff —— 分支系统落地后即可直接取用。
	"branch_icon_single_focus_normal": "branch_icon_single_focus_normal_32.png",
	"branch_icon_single_focus_sel": "branch_icon_single_focus_sel_32.png",
	"branch_icon_single_combo_normal": "branch_icon_single_combo_normal_32.png",
	"branch_icon_single_combo_sel": "branch_icon_single_combo_sel_32.png",
	"branch_icon_aoe_expand_normal": "branch_icon_aoe_expand_normal_32.png",
	"branch_icon_aoe_expand_sel": "branch_icon_aoe_expand_sel_32.png",
	"branch_icon_aoe_linger_normal": "branch_icon_aoe_linger_normal_32.png",
	"branch_icon_aoe_linger_sel": "branch_icon_aoe_linger_sel_32.png",
	"branch_icon_dash_pierce_normal": "branch_icon_dash_pierce_normal_32.png",
	"branch_icon_dash_pierce_sel": "branch_icon_dash_pierce_sel_32.png",
	"branch_icon_dash_afterimage_normal": "branch_icon_dash_afterimage_normal_32.png",
	"branch_icon_dash_afterimage_sel": "branch_icon_dash_afterimage_sel_32.png",
	"branch_icon_proj_sharp_normal": "branch_icon_proj_sharp_normal_32.png",
	"branch_icon_proj_sharp_sel": "branch_icon_proj_sharp_sel_32.png",
	"branch_icon_proj_scatter_normal": "branch_icon_proj_scatter_normal_32.png",
	"branch_icon_proj_scatter_sel": "branch_icon_proj_scatter_sel_32.png",
	"branch_icon_ground_deep_normal": "branch_icon_ground_deep_normal_32.png",
	"branch_icon_ground_deep_sel": "branch_icon_ground_deep_sel_32.png",
	"branch_icon_ground_pulse_normal": "branch_icon_ground_pulse_normal_32.png",
	"branch_icon_ground_pulse_sel": "branch_icon_ground_pulse_sel_32.png",
	"branch_icon_summon_legion_normal": "branch_icon_summon_legion_normal_32.png",
	"branch_icon_summon_legion_sel": "branch_icon_summon_legion_sel_32.png",
	"branch_icon_summon_elite_normal": "branch_icon_summon_elite_normal_32.png",
	"branch_icon_summon_elite_sel": "branch_icon_summon_elite_sel_32.png",
	"branch_icon_buff_lasting_normal": "branch_icon_buff_lasting_normal_32.png",
	"branch_icon_buff_lasting_sel": "branch_icon_buff_lasting_sel_32.png",
	"branch_icon_buff_empower_normal": "branch_icon_buff_empower_normal_32.png",
	"branch_icon_buff_empower_sel": "branch_icon_buff_empower_sel_32.png",
	# ── 2026-09-28 D4（装备特色玩法）：状态栏图标 12 张（24×24）──
	# buff 6（teal 系＋▲角標）/ debuff 6（blood 系＋▼角標）；id 依
	# `03-装备特色玩法.md` §11.1.1（AILMENT_*）與 C4 光環技能裁定。
	# ⚠️ **消费端尚未实现**（状态栏 UI 本身未做）⇒ 图标先备好，待系统落地。
	"status_warcry": "status_warcry_24.png",
	"status_blood_rage": "status_blood_rage_24.png",
	"status_iron_bulwark": "status_iron_bulwark_24.png",
	"status_hawk_eye": "status_hawk_eye_24.png",
	"status_regen": "status_regen_24.png",
	"status_shield": "status_shield_24.png",
	"status_burn": "status_burn_24.png",
	"status_chill": "status_chill_24.png",
	"status_poison": "status_poison_24.png",
	"status_shock": "status_shock_24.png",
	"status_curse": "status_curse_24.png",
	"status_sunder": "status_sunder_24.png",
}

## 稀有度（`GameConstants.Rarity` 下標）→ 格子貼圖名。
##
## 素材只給 5 階，色階對齊 `PALETTE_RARITY_SEMANTIC` = [白, 藍, 黃, 紫, 橙]，
## 正好對應 Rarity 0..4（COMMON/MAGIC/RARE/EPIC/LEGENDARY）。
## ⭐ **檔名不等於稀有度語義**（`slot_rare_48` 實為魔法藍框、`slot_epic_48` 實為稀有黃框），
## 故用一個顯式表對齊「色階序號」，**嚴禁**照檔名對映（會整體偏一檔）。
##
## 5 階以上 2026-09-21 已補專屬素材（神話紅 / 套裝綠 / 隱藏彩虹），不再 clamp 到橙。
const RARITY_SLOT: Dictionary = {
	0: "slot_common",  # COMMON    白
	1: "slot_rare",    # MAGIC     藍
	2: "slot_epic",    # RARE      黃
	3: "slot_legend",  # EPIC      紫
	4: "slot_orange",  # LEGENDARY 橙
	5: "slot_mythic",  # MYTHIC    紅
	6: "slot_set",     # SET       綠
	7: "slot_hidden",  # HIDDEN    彩
}

## 會話內貼圖快取（缺失也快取為 null，避免每幀重複 IO）
static var _cache: Dictionary = {}


# =============================================================================
# 路徑與貼圖
# =============================================================================

## 解析邏輯名對應的**實際可用路徑**（用戶覆蓋優先）；都無 → `""`。
static func path_for(name: String) -> String:
	var rel := str(TEX.get(name, ""))
	if rel.is_empty():
		return ""
	return ContentPaths.resolve_with_user(
		ContentPaths.CLASS_UI, rel, "%s/%s" % [BUILTIN_ROOT, rel])


## 取貼圖（帶快取）；缺失回傳 `null`（安全降級）。
static func texture(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var tex := _load(path_for(name))
	_cache[name] = tex
	return tex


## 該邏輯名的素材是否存在且可載入。
static func has(name: String) -> bool:
	return texture(name) != null


## 清快取（用戶運行時替換檔案後可調用）。
static func clear_cache() -> void:
	_cache.clear()


# =============================================================================
# 樣式工廠（全部「缺失即 null」）
# =============================================================================

## 9-slice 面板樣式（任務面板底板）。缺失 → `null`（調用方沿用 StyleBoxFlat）。
static func panel_stylebox() -> StyleBoxTexture:
	return _stylebox("panel", PANEL_MARGIN)


## 金色雕花面板（暗黑風）。缺失 → null。
static func panel_stylebox_gold() -> StyleBoxTexture:
	var tex := texture("panel_gold")
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(60)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 30
	sb.content_margin_bottom = 30
	return sb


## 按鈕三態樣式。`kind` ∈ {"gold", "dark"}。
## 回傳 `{normal, hover, pressed}`（**只含載入成功的態**）；全缺 → `{}`。
## 調用方約定：拿到空字典就完全不覆蓋 → 沿用 `UITheme` 的 StyleBoxFlat 三態。
static func btn_styleboxes(kind: String) -> Dictionary:
	var out: Dictionary = {}
	for state in ["normal", "hover", "pressed"]:
		var sb := _stylebox("btn_%s_%s" % [kind, state], BTN_MARGIN)
		if sb != null:
			out[state] = sb
	return out


## 物品格樣式。`kind` ∈ {"normal", "selected"} 或任一 `TEX` 裡的 slot_* 名。
static func slot_stylebox(kind: String) -> StyleBoxTexture:
	return _stylebox(kind, SLOT_MARGIN)


## 依稀有度（`GameConstants.Rarity`）取格子樣式；越界安全折到合法檔。
static func slot_stylebox_rarity(rarity: int) -> StyleBoxTexture:
	var name := str(RARITY_SLOT.get(rarity, "slot_normal"))
	return slot_stylebox(name)


## 生態背景（尺寸即視口 640×360）。`biome` ∈ {forest, frost, volcanic}；
## 未知生態回退 forest；都缺 → `null`。
static func backdrop_texture(biome: String) -> Texture2D:
	var key := "backdrop_%s" % biome
	if not TEX.has(key):
		key = "backdrop_forest"
	return texture(key)


## 2026-09-24 · 詞綴圖標（32×32）。`stat_key` 取自 `data/affixes/*.json`（共 48 條）。
## 缺檔回 `null`（安全降級）—— 呼叫方務必判空，別直接塞給 `TextureRect`。
static func affix_icon(stat_key: String) -> Texture2D:
	return texture("affix_%s" % stat_key)


## 2026-09-24 · 元素屬性圖標（24×24）。
## `key` ∈ `physical` / `fire` / `cold` / `lightning` / `poison` / `shadow`。
static func element_icon(key: String) -> Texture2D:
	return texture("elem_%s" % key)


## 2026-09-24 · 元素抗性圖標（24×24）。
## ⚠️ **物理沒有抗性圖標**（走護甲）⇒ 傳 `physical` 會回 `null`。
static func resist_icon(key: String) -> Texture2D:
	return texture("resist_%s" % key)


## 2026-09-24 · 技能圖標（48×48）。`skill_id` 取自 `data/skills/skills.json`（第一批 36 個）。
## ⚠️ 呼叫方通常**不該**直接用它 —— 應該走 `GameConstants.SKILL_ICON[skill_id]` 再 `texture()`，
## 因為那張表是「技能 id → 圖標鍵」的唯一權威（角色選擇面板與局內技能欄同源）。
static func skill_icon(skill_id: String) -> Texture2D:
	return texture(str(GameConstants.SKILL_ICON.get(skill_id, "")))


## 2026-09-24 · 符文圖標（32×32）。`rune_id` 形如 `rune_projectile`（會自動去掉冗餘前綴）。
static func rune_icon(rune_id: String) -> Texture2D:
	var short := rune_id.trim_prefix("rune_")
	return texture("rune_icon_%s" % short)


# ── 2026-09-28 · 元素系列便捷取用（皆為 `texture()` 的語意包裝）──────────────
# 這些全是**安全降級**：缺檔回 `null`、不報錯 ⇒ 呼叫方一律要判空。

## 異常狀態圖標（24×24）。`key` ∈ burn / chill / poison / shock / curse / sunder。
static func ailment_icon(key: String) -> Texture2D:
	return texture("ailment_%s" % key)


## 單元素傷害圖標（24×24，元素符號 + 四向爆裂刺）。
static func element_damage_icon(key: String) -> Texture2D:
	return texture("elem_dmg_%s" % key)


## 元素附著覆蓋層（32×32，虛線環 + 元素符號）。
static func attach_layer(key: String) -> Texture2D:
	return texture("attach_%s" % key)


## 元素技能邊框（48×48，由 `slot_common_48` 重上色而來）。
static func element_skill_frame(key: String) -> Texture2D:
	return texture("skill_frame_%s" % key)


## 元素專精詞綴角標（16×16）。⚠️ 只有 5 個（物理無專精）。
static func element_badge(key: String) -> Texture2D:
	return texture("elem_badge_%s" % key)


## 臨時增益 · 增益球圖標（24×24）。
## ⚠️ 該系統**代碼側尚未實現**（見 `TEX` 表同處註解）⇒ 現階段屬「素材先行」。
static func temp_buff_orb(key: String) -> Texture2D:
	return texture("temp_buff_orb_%s" % key)


## 臨時增益 · 神龕圖標（32×32）。
static func temp_buff_shrine(key: String) -> Texture2D:
	return texture("temp_buff_shrine_%s" % key)


## 任務星級（難度）貼圖。`lit` = 是否點亮。
static func star_texture(lit: bool) -> Texture2D:
	return texture("star_lit" if lit else "star_dim")


# =============================================================================
# 內部
# =============================================================================

## 由邏輯名建 StyleBoxTexture（9-slice 四邊同邊距）；素材缺失 → `null`。
static func _stylebox(name: String, margin: int) -> StyleBoxTexture:
	var tex := texture(name)
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = float(margin)
	sb.texture_margin_right = float(margin)
	sb.texture_margin_top = float(margin)
	sb.texture_margin_bottom = float(margin)
	return sb


## 通用貼圖載入（res:// 走導入系統，user:// 直接解碼）—— 與 `ContentLoader` 同策略。
## UI 皮膚自持一份，避免跨模組調用其私有 `_load_any`。
static func _load(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("user://"):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
		return null
	if ResourceLoader.exists(path):
		var r: Resource = ResourceLoader.load(path)
		if r is Texture2D:
			return r
	return null
