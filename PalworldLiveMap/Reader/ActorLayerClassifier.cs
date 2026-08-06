namespace PalworldLiveMap.Reader;

internal static class ActorLayerClassifier
{
    internal static string? Classify(string className, string objectName, string? characterId = null)
    {
        string value = $"{className} {objectName}".ToLowerInvariant();
        if (value.Contains("palbosstower", StringComparison.Ordinal)) return "towers";
        if (value.Contains("warppointdestination_worldtreeentrance", StringComparison.Ordinal)) return "world-tree-entrance";
        if (ContainsAny(value, "fasttravel", "fast_travel", "travelpoint", "warp_point")) return "fast-travel";
        if (ContainsAny(value, "syndicatetower", "transmissiontower", "boss_tower", "gymtower", "bp_gym")) return "towers";
        // Fixed dungeon entrances are already represented by the reference map nodes.
        // Returning no live layer prevents duplicate pins when their actors are loaded.
        if (value.Contains("dungeonfixedentrance", StringComparison.Ordinal)) return null;
        if (ContainsAny(value, "dungeonentrance", "dungeon_entrance", "dungeongate", "dungeon_gate")) return "dungeons";
        if (ContainsAny(value, "sealedrealm", "sealed_realm")) return "sealed-realms";
        if (ContainsAny(value, "bountytarget", "bounty_target", "bountyboss", "bounty_boss", "boss_bounty")) return "bounty-bosses";
        if (ContainsAny(value, "treasuremap_05", "treasuremap05")) return "treasure-map-05";
        if (ContainsAny(value, "treasuremap_04", "treasuremap04")) return "treasure-map-04";
        if (ContainsAny(value, "treasuremap_03", "treasuremap03")) return "treasure-map-03";
        if (ContainsAny(value, "treasuremap_02", "treasuremap02")) return "treasure-map-02";
        if (ContainsAny(value, "treasuremap_01", "treasuremap01")) return "treasure-map-01";
        if (ContainsAny(value, "respawnpoint", "respawn_point", "playercamp", "player_camp", "camprespawn")) return "respawn-points";
        if (value.Contains("levelobject_goddessstatue", StringComparison.Ordinal)) return "statue-of-power";
        if (value.Contains("arenaentrance", StringComparison.Ordinal)) return "arenas";
        if (value.Contains("palrandomincidentspawner", StringComparison.Ordinal)) return "random-events";
        if (ContainsAny(value, "oilrig", "oil_rig", "oilplatform", "oil_platform")) return "oil-rigs";
        if (ContainsAny(value, "predatorpal", "predator_pal", "palpredator", "pal_predator")) return "predator-pals";
        if (ContainsAny(value, "mutantenemy", "mutant_enemy", "enemy_mutant", "mutantpal_enemy")) return "mutant-enemy-pals";
        if (ContainsAny(value, "playercharacter", "player_character", "palplayercharacter")) return "guild-members";
        if (ContainsAny(value, "fishingjunkspot", "fishing_junk_spot")) return RankedLayer(value, "floating-wreckage");
        if (ContainsAny(value, "shorefishingspot", "shore_fishing_spot", "fishingspot", "fishing_spot")) return RankedLayer(value, "shore-fishing-spots");
        if (ContainsAny(value, "magnetspot", "magnet_spot", "magneticspot", "magnetic_spot")) return "magnet-spots";
        if (ContainsAny(value, "requiredlonghold_junk", "salvagespot", "salvage_spot", "salvageobject")) return "salvage";
        if (value.Contains("bp_item_paldium", StringComparison.Ordinal)) return "ground-paldium";
        if (value.Contains("bp_item_egg", StringComparison.Ordinal)) return "ground-food-egg";
        if (value.Contains("bp_item_palsphere", StringComparison.Ordinal))
        {
            if (ContainsAny(value, "mega", "x1000")) return "ground-mega-sphere";
            if (ContainsAny(value, "giga", "x2000")) return "ground-giga-sphere";
            return "ground-pal-sphere";
        }
        if (value.Contains("bp_item_leatherwool", StringComparison.Ordinal)) return "ground-leather-wool";
        if (ContainsAny(value, "bp_item_leatherraw", "sm_leatherraw")) return "ground-leather";
        if (ContainsAny(value, "bp_item_ore_steel", "sm_ore_steel")) return "ore";
        if (ContainsAny(value, "bp_item_ore_coal", "sm_ore_coal")) return "coal";
        if (value.Contains("bp_item_palsoul", StringComparison.Ordinal))
        {
            if (ContainsAny(value, "extra_large", "extralarge", "xl", "_03")) return "ground-pal-soul-extra-large";
            if (ContainsAny(value, "large", "_02")) return "ground-pal-soul-large";
            if (ContainsAny(value, "medium", "middle", "_01")) return "ground-pal-soul-medium";
            return "ground-pal-soul-small";
        }
        if (value.Contains("bp_item_wood", StringComparison.Ordinal)) return "ground-wood";
        if (value.Contains("bp_item_stone", StringComparison.Ordinal)) return "ground-stone";
        if (ContainsAny(value, "treasurebox_visiblecontent", "visiblecontent_adjustfloor")) return "ground-resources";
        if (ContainsAny(value, "elementchest", "element_chest", "elementallock", "elemental_lock"))
        {
            if (ContainsAny(value, "_fire", "fire_", "flame")) return "element-chest-fire";
            if (ContainsAny(value, "_water", "water_", "aqua")) return "element-chest-water";
            if (ContainsAny(value, "_electric", "electric_", "thunder")) return "element-chest-electric";
            return "element-chest";
        }
        if (ContainsAny(value, "treasurebox", "treasure_box", "treasurechest")) return "treasure";
        if (ContainsAny(value, "skillfruit", "skill_fruit")) return "skill-fruit";
        if (value.Contains("levelobject_note", StringComparison.Ordinal)) return "notes";
        if (value.Contains("levelobject_relic_flamebambi", StringComparison.Ordinal)) return "rooby-effigy";
        if (value.Contains("levelobject_relic_guardiandog", StringComparison.Ordinal)) return "yakumo-effigy";
        if (value.Contains("levelobject_relic_icecrocodile", StringComparison.Ordinal)) return "munchill-effigy";
        if (value.Contains("levelobject_relic_lazydragon", StringComparison.Ordinal)) return "relaxaurus-effigy";
        if (value.Contains("levelobject_relic_leafmomonga", StringComparison.Ordinal)) return "herbil-effigy";
        if (value.Contains("levelobject_relic_monkey", StringComparison.Ordinal)) return "tanzee-effigy";
        if (value.Contains("levelobject_relic_mutant", StringComparison.Ordinal)) return "lunaris-effigy";
        if (value.Contains("levelobject_relic_negativekoala", StringComparison.Ordinal)) return "depresso-effigy";
        if (value.Contains("levelobject_relic_penguin", StringComparison.Ordinal)) return "pengullet-effigy";
        if (value.Contains("levelobject_relic_pinkcat", StringComparison.Ordinal)) return "cattiva-effigy";
        if (value.Contains("levelobject_relic_sheepball", StringComparison.Ordinal)) return "lamball-effigy";
        if (ContainsAny(value, "relicobject", "levelobject_relic", "lifmunkeffigy")) return "lifmunk-effigy";
        if (value.Contains("npcspawnpointonly", StringComparison.Ordinal)) return "npc";
        if (ContainsAny(value, "palmerchant", "pal_merchant")) return "pal-merchant";
        if (value.Contains("merchant", StringComparison.Ordinal)) return "merchant";
        if (ContainsAny(value, "crudeoil", "crude_oil", "oilfield")) return "oil";
        if (value.Contains("paldium", StringComparison.Ordinal)) return "paldium";
        if (ContainsAny(value, "purequartz", "pure_quartz", "quartz")) return "quartz";
        if (value.Contains("sulfur", StringComparison.Ordinal)) return "sulfur";
        if (value.Contains("coal", StringComparison.Ordinal)) return "coal";
        if (ContainsAny(value, "copperore", "copper_ore", "oredeposit", "ore_deposit", "boxplacementtool_copper")) return "ore";
        if (ContainsAny(value, "pal_boss_tower", "towerboss", "tower_boss", "gymboss", "gym_boss", "syndicateboss", "syndicate_boss")) return "tower-bosses";
        if (ContainsAny(value, "_boss_c", "fboss", "fieldboss", "bossmonster", "alpha_pal", "alphapal", "palboss", "pal_boss", "boss_pal")) return "pal-bosses";
        if (ContainsAny(value, "palcharacter", "pal_character", "palmonster") && !string.IsNullOrWhiteSpace(characterId))
        {
            string id = characterId;
            if (id.StartsWith("GYM_", StringComparison.OrdinalIgnoreCase)
                || id.StartsWith("TOWER_", StringComparison.OrdinalIgnoreCase)) return "tower-bosses";
            if (id.StartsWith("BOSS_", StringComparison.OrdinalIgnoreCase)) return "pal-bosses";
            return "pal-" + id.ToLowerInvariant().Replace('_', '-');
        }
        if (ContainsAny(value, "npccharacter", "humancharacter", "human_character")) return "npc";
        return null;
    }

    internal static bool IsUnreliableWorldOrigin(string className, double x, double y)
    {
        if ((x * x) + (y * y) > 10_000) return false;
        return !className.Contains("TowerFastTravelPoint", StringComparison.OrdinalIgnoreCase);
    }

    private static bool ContainsAny(string value, params string[] needles) =>
        needles.Any(needle => value.Contains(needle, StringComparison.Ordinal));

    private static string RankedLayer(string value, string baseLayer)
    {
        for (int rank = 5; rank >= 1; rank--)
        {
            if (ContainsAny(value, $"rank{rank}", $"rank_{rank}", $"grade{rank}", $"grade_{rank}")) return $"{baseLayer}-rank-{rank}";
        }
        return baseLayer;
    }
}
