"""Curate DCSS (CC0, 32x32) tiles into per-biome folders for 七傳說.

Source: D:/七傳說/game/assets/_incoming/_src_dcss/  (extracted OGA zip)
Dest:   D:/七傳說/game/assets/_incoming/<biome>/
Naming: <biome>_<role>_<descriptor>.png   role in {ground, wall, prop, deco}
"""
import os
import shutil

SRC = r"D:\七傳說\game\assets\_incoming\_src_dcss\Dungeon Crawl Stone Soup Full"
DST = r"D:\七傳說\game\assets\_incoming"

D = "dungeon"


def R(*parts):
    return os.path.join(SRC, *parts)


# biome -> list of (source_relpath, dest_filename)
PLAN = {
    "forest": [
        # ---- ground / floor (幽林: dark mossy forest, decaying roots) ----
        (f"{D}/floor/moss_0.png", "forest_ground_moss_0.png"),
        (f"{D}/floor/moss_1.png", "forest_ground_moss_1.png"),
        (f"{D}/floor/moss_2.png", "forest_ground_moss_2.png"),
        (f"{D}/floor/moss_3.png", "forest_ground_moss_3.png"),
        (f"{D}/floor/lair_0_new.png", "forest_ground_lair_0.png"),
        (f"{D}/floor/lair_1_new.png", "forest_ground_lair_1.png"),
        (f"{D}/floor/lair_2_new.png", "forest_ground_lair_2.png"),
        (f"{D}/floor/lair_3_new.png", "forest_ground_lair_3.png"),
        (f"{D}/floor/floor_vines_0_new.png", "forest_ground_roots_0.png"),
        (f"{D}/floor/floor_vines_1_new.png", "forest_ground_roots_1.png"),
        (f"{D}/floor/floor_vines_2_new.png", "forest_ground_roots_2.png"),
        (f"{D}/floor/floor_vines_3_new.png", "forest_ground_roots_3.png"),
        (f"{D}/floor/floor_vines_4_new.png", "forest_ground_roots_4.png"),
        (f"{D}/floor/floor_vines_5_new.png", "forest_ground_roots_5.png"),
        (f"{D}/floor/floor_vines_6_new.png", "forest_ground_roots_6.png"),
        (f"{D}/floor/bog_green_0_new.png", "forest_ground_bog_0.png"),
        (f"{D}/floor/bog_green_1_new.png", "forest_ground_bog_1.png"),
        (f"{D}/floor/bog_green_2_new.png", "forest_ground_bog_2.png"),
        (f"{D}/floor/bog_green_3_new.png", "forest_ground_bog_3.png"),
        (f"{D}/floor/grey_dirt_0_new.png", "forest_ground_dirt_0.png"),
        (f"{D}/floor/grey_dirt_1_new.png", "forest_ground_dirt_1.png"),
        (f"{D}/floor/grey_dirt_2_new.png", "forest_ground_dirt_2.png"),
        (f"{D}/floor/grey_dirt_3_new.png", "forest_ground_dirt_3.png"),
        (f"{D}/floor/grass/grass_0_new.png", "forest_ground_grass_0.png"),
        (f"{D}/floor/grass/grass_1_new.png", "forest_ground_grass_1.png"),
        (f"{D}/floor/grass/grass_2_new.png", "forest_ground_grass_2.png"),
        (f"{D}/floor/grass/grass0-dirt-mix_1.png", "forest_ground_grassmix_1.png"),
        (f"{D}/floor/grass/grass0-dirt-mix_2.png", "forest_ground_grassmix_2.png"),
        (f"{D}/floor/grass/grass0-dirt-mix_3.png", "forest_ground_grassmix_3.png"),
        # ---- wall ----
        (f"{D}/wall/wall_vines_0.png", "forest_wall_vines_0.png"),
        (f"{D}/wall/wall_vines_1.png", "forest_wall_vines_1.png"),
        (f"{D}/wall/wall_vines_2.png", "forest_wall_vines_2.png"),
        (f"{D}/wall/wall_vines_3.png", "forest_wall_vines_3.png"),
        (f"{D}/wall/wall_vines_4.png", "forest_wall_vines_4.png"),
        (f"{D}/wall/wall_vines_5.png", "forest_wall_vines_5.png"),
        (f"{D}/wall/wall_vines_6.png", "forest_wall_vines_6.png"),
        (f"{D}/wall/lair_0_new.png", "forest_wall_lair_0.png"),
        (f"{D}/wall/lair_1_new.png", "forest_wall_lair_1.png"),
        (f"{D}/wall/lair_2_new.png", "forest_wall_lair_2.png"),
        (f"{D}/wall/lair_3_new.png", "forest_wall_lair_3.png"),
        (f"{D}/wall/brick_brown-vines_1.png", "forest_wall_brickvines_1.png"),
        (f"{D}/wall/brick_brown-vines_2.png", "forest_wall_brickvines_2.png"),
        (f"{D}/wall/brick_brown-vines_3.png", "forest_wall_brickvines_3.png"),
        (f"{D}/wall/brick_brown-vines_4.png", "forest_wall_brickvines_4.png"),
        # ---- props / obstacles ----
        (f"{D}/trees/mangrove_1.png", "forest_prop_tree_mangrove_1.png"),
        (f"{D}/trees/mangrove_2.png", "forest_prop_tree_mangrove_2.png"),
        (f"{D}/trees/mangrove_3.png", "forest_prop_tree_mangrove_3.png"),
        (f"{D}/trees/tree_1_yellow.png", "forest_prop_tree_yellow_1.png"),
        (f"{D}/boulder.png", "forest_prop_boulder.png"),
        (f"{D}/mold_large_1.png", "forest_prop_mold_1.png"),
        (f"{D}/mold_large_2.png", "forest_prop_mold_2.png"),
        (f"{D}/mold_large_3.png", "forest_prop_mold_3.png"),
        (f"{D}/mold_large_4.png", "forest_prop_mold_4.png"),
        (f"{D}/statues/granite_stump_new.png", "forest_prop_stump.png"),
        (f"{D}/statues/crumbled_column_1.png", "forest_prop_broken_pillar_1.png"),
        (f"{D}/statues/crumbled_column_2.png", "forest_prop_broken_pillar_2.png"),
        (f"{D}/statues/crumbled_column_3.png", "forest_prop_broken_pillar_3.png"),
        # ---- deco: bones (蜘蛛巢/骸骨 atmosphere) ----
        (f"{D}/floor/green_bones_1.png", "forest_deco_bones_1.png"),
        (f"{D}/floor/green_bones_2.png", "forest_deco_bones_2.png"),
        (f"{D}/floor/green_bones_3.png", "forest_deco_bones_3.png"),
        (f"{D}/floor/green_bones_4.png", "forest_deco_bones_4.png"),
        (f"{D}/floor/green_bones_5.png", "forest_deco_bones_5.png"),
        (f"{D}/floor/green_bones_6.png", "forest_deco_bones_6.png"),
        (f"{D}/floor/grass/grass_flowers_blue_1_new.png", "forest_deco_flower_blue_1.png"),
        (f"{D}/floor/grass/grass_flowers_red_1_new.png", "forest_deco_flower_red_1.png"),
        (f"{D}/floor/grass/grass_flowers_yellow_1_new.png", "forest_deco_flower_yellow_1.png"),
    ],
    "volcanic": [
        # ---- ground / floor (灰烬堡: ash fortress, foundry, ember/lava) ----
        (f"{D}/floor/volcanic_floor_0.png", "volcanic_ground_ash_0.png"),
        (f"{D}/floor/volcanic_floor_1.png", "volcanic_ground_ash_1.png"),
        (f"{D}/floor/volcanic_floor_2.png", "volcanic_ground_ash_2.png"),
        (f"{D}/floor/volcanic_floor_3.png", "volcanic_ground_ash_3.png"),
        (f"{D}/floor/volcanic_floor_4.png", "volcanic_ground_ash_4.png"),
        (f"{D}/floor/volcanic_floor_5.png", "volcanic_ground_ash_5.png"),
        (f"{D}/floor/volcanic_floor_6.png", "volcanic_ground_ash_6.png"),
        (f"{D}/floor/lava_0.png", "volcanic_ground_lava_0.png"),
        (f"{D}/floor/lava_1.png", "volcanic_ground_lava_1.png"),
        (f"{D}/floor/lava_2.png", "volcanic_ground_lava_2.png"),
        (f"{D}/floor/lava_3.png", "volcanic_ground_lava_3.png"),
        (f"{D}/floor/infernal_1.png", "volcanic_ground_infernal_1.png"),
        (f"{D}/floor/infernal_2.png", "volcanic_ground_infernal_2.png"),
        (f"{D}/floor/infernal_3.png", "volcanic_ground_infernal_3.png"),
        (f"{D}/floor/infernal_4.png", "volcanic_ground_infernal_4.png"),
        (f"{D}/floor/infernal_5.png", "volcanic_ground_infernal_5.png"),
        (f"{D}/floor/infernal_6.png", "volcanic_ground_infernal_6.png"),
        (f"{D}/floor/demonic_red_1.png", "volcanic_ground_demonic_1.png"),
        (f"{D}/floor/demonic_red_2.png", "volcanic_ground_demonic_2.png"),
        (f"{D}/floor/demonic_red_3.png", "volcanic_ground_demonic_3.png"),
        (f"{D}/floor/demonic_red_4.png", "volcanic_ground_demonic_4.png"),
        (f"{D}/floor/demonic_red_5.png", "volcanic_ground_demonic_5.png"),
        (f"{D}/floor/rough_red_0.png", "volcanic_ground_rough_0.png"),
        (f"{D}/floor/rough_red_1.png", "volcanic_ground_rough_1.png"),
        (f"{D}/floor/rough_red_2.png", "volcanic_ground_rough_2.png"),
        (f"{D}/floor/rough_red_3.png", "volcanic_ground_rough_3.png"),
        (f"{D}/floor/cobble_blood_1_new.png", "volcanic_ground_cobble_1.png"),
        (f"{D}/floor/cobble_blood_2_new.png", "volcanic_ground_cobble_2.png"),
        (f"{D}/floor/cobble_blood_3_new.png", "volcanic_ground_cobble_3.png"),
        (f"{D}/floor/cobble_blood_4_new.png", "volcanic_ground_cobble_4.png"),
        (f"{D}/floor/cobble_blood_5_new.png", "volcanic_ground_cobble_5.png"),
        (f"{D}/floor/cobble_blood_6_new.png", "volcanic_ground_cobble_6.png"),
        # ---- wall (black iron, hell brick) ----
        (f"{D}/wall/volcanic_wall_0.png", "volcanic_wall_ash_0.png"),
        (f"{D}/wall/volcanic_wall_1.png", "volcanic_wall_ash_1.png"),
        (f"{D}/wall/volcanic_wall_2.png", "volcanic_wall_ash_2.png"),
        (f"{D}/wall/volcanic_wall_3.png", "volcanic_wall_ash_3.png"),
        (f"{D}/wall/volcanic_wall_4.png", "volcanic_wall_ash_4.png"),
        (f"{D}/wall/volcanic_wall_5.png", "volcanic_wall_ash_5.png"),
        (f"{D}/wall/volcanic_wall_6.png", "volcanic_wall_ash_6.png"),
        (f"{D}/wall/hell_1.png", "volcanic_wall_hell_1.png"),
        (f"{D}/wall/hell_2.png", "volcanic_wall_hell_2.png"),
        (f"{D}/wall/hell_3.png", "volcanic_wall_hell_3.png"),
        (f"{D}/wall/hell_4.png", "volcanic_wall_hell_4.png"),
        (f"{D}/wall/hell_5.png", "volcanic_wall_hell_5.png"),
        (f"{D}/wall/hell_6.png", "volcanic_wall_hell_6.png"),
        (f"{D}/wall/metal_wall.png", "volcanic_wall_metal.png"),
        (f"{D}/wall/metal_wall_brown.png", "volcanic_wall_metal_brown.png"),
        (f"{D}/wall/metal_wall_cracked.png", "volcanic_wall_metal_cracked.png"),
        (f"{D}/wall/lab-metal_0.png", "volcanic_wall_ironplate_0.png"),
        (f"{D}/wall/lab-metal_1.png", "volcanic_wall_ironplate_1.png"),
        (f"{D}/wall/lab-metal_2.png", "volcanic_wall_ironplate_2.png"),
        (f"{D}/wall/lab-metal_3.png", "volcanic_wall_ironplate_3.png"),
        (f"{D}/wall/stone_black_marked_0.png", "volcanic_wall_blackstone_0.png"),
        (f"{D}/wall/stone_black_marked_1.png", "volcanic_wall_blackstone_1.png"),
        (f"{D}/wall/stone_black_marked_2.png", "volcanic_wall_blackstone_2.png"),
        (f"{D}/wall/stone_black_marked_3.png", "volcanic_wall_blackstone_3.png"),
        (f"{D}/wall/stone_black_marked_4.png", "volcanic_wall_blackstone_4.png"),
        (f"{D}/wall/stone_black_marked_5.png", "volcanic_wall_blackstone_5.png"),
        (f"{D}/wall/pebble_red_0_new.png", "volcanic_wall_pebble_0.png"),
        (f"{D}/wall/pebble_red_1_new.png", "volcanic_wall_pebble_1.png"),
        (f"{D}/wall/pebble_red_2_new.png", "volcanic_wall_pebble_2.png"),
        (f"{D}/wall/pebble_red_3_new.png", "volcanic_wall_pebble_3.png"),
        # ---- props / obstacles (foundry pillars, ember torches) ----
        (f"{D}/zot_pillar.png", "volcanic_prop_zot_pillar.png"),
        (f"{D}/boulder.png", "volcanic_prop_boulder.png"),
        (f"{D}/wall/torches/torch_0.png", "volcanic_prop_torch_0.png"),
        (f"{D}/wall/torches/torch_1.png", "volcanic_prop_torch_1.png"),
        (f"{D}/wall/torches/torch_2.png", "volcanic_prop_torch_2.png"),
        (f"{D}/wall/torches/torch_3.png", "volcanic_prop_torch_3.png"),
        (f"{D}/wall/torches/torch_4.png", "volcanic_prop_torch_4.png"),
        (f"{D}/vaults/statue_iron_golem.png", "volcanic_prop_iron_golem.png"),
        (f"{D}/statues/crumbled_column_1.png", "volcanic_prop_broken_pillar_1.png"),
        (f"{D}/statues/crumbled_column_2.png", "volcanic_prop_broken_pillar_2.png"),
        (f"{D}/statues/crumbled_column_3.png", "volcanic_prop_broken_pillar_3.png"),
        (f"{D}/statues/crumbled_column_4.png", "volcanic_prop_broken_pillar_4.png"),
        # ---- deco ----
        (f"{D}/floor/acidic_floor_0.png", "volcanic_deco_acid_0.png"),
        (f"{D}/floor/acidic_floor_1.png", "volcanic_deco_acid_1.png"),
        (f"{D}/floor/acidic_floor_2.png", "volcanic_deco_acid_2.png"),
        (f"{D}/floor/acidic_floor_3.png", "volcanic_deco_acid_3.png"),
    ],
    "frost": [
        # ---- ground / floor (霜渊: ice cavern, permafrost) ----
        (f"{D}/floor/frozen_0.png", "frost_ground_frozen_0.png"),
        (f"{D}/floor/frozen_1.png", "frost_ground_frozen_1.png"),
        (f"{D}/floor/frozen_2.png", "frost_ground_frozen_2.png"),
        (f"{D}/floor/frozen_3.png", "frost_ground_frozen_3.png"),
        (f"{D}/floor/frozen_4.png", "frost_ground_frozen_4.png"),
        (f"{D}/floor/frozen_5.png", "frost_ground_frozen_5.png"),
        (f"{D}/floor/frozen_6.png", "frost_ground_frozen_6.png"),
        (f"{D}/floor/frozen_7.png", "frost_ground_frozen_7.png"),
        (f"{D}/floor/frozen_8.png", "frost_ground_frozen_8.png"),
        (f"{D}/floor/frozen_9.png", "frost_ground_frozen_9.png"),
        (f"{D}/floor/frozen_10.png", "frost_ground_frozen_10.png"),
        (f"{D}/floor/frozen_11.png", "frost_ground_frozen_11.png"),
        (f"{D}/floor/frozen_12.png", "frost_ground_frozen_12.png"),
        (f"{D}/floor/ice_0_new.png", "frost_ground_ice_0.png"),
        (f"{D}/floor/ice_1_new.png", "frost_ground_ice_1.png"),
        (f"{D}/floor/ice_2_new.png", "frost_ground_ice_2.png"),
        (f"{D}/floor/ice_3_new.png", "frost_ground_ice_3.png"),
        (f"{D}/floor/crystal_floor_0.png", "frost_ground_crystal_0.png"),
        (f"{D}/floor/crystal_floor_1.png", "frost_ground_crystal_1.png"),
        (f"{D}/floor/crystal_floor_2.png", "frost_ground_crystal_2.png"),
        (f"{D}/floor/crystal_floor_3.png", "frost_ground_crystal_3.png"),
        (f"{D}/floor/crystal_floor_4.png", "frost_ground_crystal_4.png"),
        (f"{D}/floor/crystal_floor_5.png", "frost_ground_crystal_5.png"),
        (f"{D}/floor/white_marble_0.png", "frost_ground_marble_0.png"),
        (f"{D}/floor/white_marble_1.png", "frost_ground_marble_1.png"),
        (f"{D}/floor/white_marble_2.png", "frost_ground_marble_2.png"),
        (f"{D}/floor/white_marble_3.png", "frost_ground_marble_3.png"),
        # ---- wall (ice crystal, permafrost rock) ----
        (f"{D}/wall/crystal_wall_0.png", "frost_wall_crystal_0.png"),
        (f"{D}/wall/crystal_wall_1.png", "frost_wall_crystal_1.png"),
        (f"{D}/wall/crystal_wall_2.png", "frost_wall_crystal_2.png"),
        (f"{D}/wall/crystal_wall_3.png", "frost_wall_crystal_3.png"),
        (f"{D}/wall/crystal_wall_4.png", "frost_wall_crystal_4.png"),
        (f"{D}/wall/crystal_wall_5.png", "frost_wall_crystal_5.png"),
        (f"{D}/wall/crystal_wall_6.png", "frost_wall_crystal_6.png"),
        (f"{D}/wall/crystal_wall_7.png", "frost_wall_crystal_7.png"),
        (f"{D}/wall/crystal_wall_8.png", "frost_wall_crystal_8.png"),
        (f"{D}/wall/crystal_wall_9.png", "frost_wall_crystal_9.png"),
        (f"{D}/wall/crystal_wall_11.png", "frost_wall_crystal_11.png"),
        (f"{D}/wall/crystal_wall_12.png", "frost_wall_crystal_12.png"),
        (f"{D}/wall/crystal_wall_13.png", "frost_wall_crystal_13.png"),
        (f"{D}/wall/cobalt_rock_1.png", "frost_wall_permafrost_1.png"),
        (f"{D}/wall/cobalt_rock_2.png", "frost_wall_permafrost_2.png"),
        (f"{D}/wall/cobalt_rock_3.png", "frost_wall_permafrost_3.png"),
        (f"{D}/wall/cobalt_rock_4.png", "frost_wall_permafrost_4.png"),
        (f"{D}/wall/cobalt_stone_1.png", "frost_wall_cobalt_1.png"),
        (f"{D}/wall/cobalt_stone_2.png", "frost_wall_cobalt_2.png"),
        (f"{D}/wall/cobalt_stone_3.png", "frost_wall_cobalt_3.png"),
        (f"{D}/wall/cobalt_stone_4.png", "frost_wall_cobalt_4.png"),
        (f"{D}/wall/cobalt_stone_5.png", "frost_wall_cobalt_5.png"),
        (f"{D}/wall/cobalt_stone_6.png", "frost_wall_cobalt_6.png"),
        # ---- props / obstacles (giant's graveyard: tombs, sarcophagi) ----
        (f"{D}/floor/tomb_0_new.png", "frost_prop_tomb_0.png"),
        (f"{D}/floor/tomb_1_new.png", "frost_prop_tomb_1.png"),
        (f"{D}/floor/tomb_2_new.png", "frost_prop_tomb_2.png"),
        (f"{D}/floor/tomb_3_new.png", "frost_prop_tomb_3.png"),
        (f"{D}/vaults/sarcophagus_sealed.png", "frost_prop_sarcophagus_sealed.png"),
        (f"{D}/vaults/sarcophagus_pedestal_left.png", "frost_prop_sarcophagus_pedestal_l.png"),
        (f"{D}/vaults/sarcophagus_pedestal_right.png", "frost_prop_sarcophagus_pedestal_r.png"),
        (f"{D}/boulder.png", "frost_prop_boulder.png"),
        (f"{D}/statues/statue_ancient_hero.png", "frost_prop_statue_hero.png"),
        (f"{D}/statues/statue_ancient_evil.png", "frost_prop_statue_evil.png"),
        (f"{D}/statues/crumbled_column_1.png", "frost_prop_broken_pillar_1.png"),
        (f"{D}/statues/crumbled_column_2.png", "frost_prop_broken_pillar_2.png"),
        (f"{D}/statues/crumbled_column_3.png", "frost_prop_broken_pillar_3.png"),
        (f"{D}/statues/crumbled_column_4.png", "frost_prop_broken_pillar_4.png"),
        (f"{D}/vaults/the_teleporter_ice_cave.png", "frost_prop_ice_portal.png"),
        # ---- deco ----
        (f"{D}/wall/abyss/abyss_blue_0.png", "frost_deco_abyss_0.png"),
        (f"{D}/wall/abyss/abyss_blue_1.png", "frost_deco_abyss_1.png"),
        (f"{D}/wall/abyss/abyss_blue_2.png", "frost_deco_abyss_2.png"),
        (f"{D}/wall/abyss/abyss_blue_3.png", "frost_deco_abyss_3.png"),
    ],
}


def main():
    total = 0
    missing = []
    for biome, items in PLAN.items():
        out = os.path.join(DST, biome)
        os.makedirs(out, exist_ok=True)
        n = 0
        for src_rel, dst_name in items:
            sp = os.path.join(SRC, src_rel)
            if not os.path.isfile(sp):
                missing.append((biome, src_rel))
                continue
            shutil.copy2(sp, os.path.join(out, dst_name))
            n += 1
        print(f"{biome:<10} {n:>3} files -> {out}")
        total += n
    print(f"\nTOTAL {total} files")
    if missing:
        print(f"\nMISSING {len(missing)}:")
        for b, s in missing:
            print(f"  [{b}] {s}")


if __name__ == "__main__":
    main()
