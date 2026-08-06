using System.Buffers.Binary;
using PalworldLiveMap.Reader.Interop;
using PalworldLiveMap.Reader.Memory;
using PalworldLiveMap.Reader.Unreal;

namespace PalworldLiveMap.Reader;

internal static class SelfTests
{
    internal static void Run()
    {
        PatternParsingAndMatching();
        RipRelativeResolution();
        ProcessRightsRemainReadOnly();
        ActorLayerClassification();
        Console.WriteLine("Self-tests passed.");
    }

    private static void ActorLayerClassification()
    {
        Equal("fast-travel", ActorLayerClassifier.Classify("BP_FastTravelPoint_C", "BP_FastTravelPoint_C_12")!, "fast travel layer");
        Equal("dungeons", ActorLayerClassifier.Classify("BP_DungeonEntrance_C", "Entrance_4")!, "dungeon layer");
        Equal("lifmunk-effigy", ActorLayerClassifier.Classify("BP_RelicObject_C", "Relic_9")!, "effigy layer");
        Equal("pal-bosses", ActorLayerClassifier.Classify("BP_PalCharacter_C", "Pal_2", "BOSS_Anubis")!, "Pal boss layer");
        Equal("tower-bosses", ActorLayerClassifier.Classify("BP_PalCharacter_C", "Pal_2", "GYM_ThunderDragonMan")!, "tower boss layer");
        Equal("towers", ActorLayerClassifier.Classify("BP_PalBossTower_C", "TowerPin_2")!, "Syndicate Tower structure layer");
        Equal("pal-bosses", ActorLayerClassifier.Classify("BP_FairyDragon_BOSS_C", "FieldBoss_2")!, "field boss pin layer");
        Equal("bounty-bosses", ActorLayerClassifier.Classify("BP_BountyBoss_C", "BountyTarget_2")!, "bounty boss layer");
        Equal("floating-wreckage-rank-1", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_FishingJunkSpot_Junk_Rank1_C", "Fishing_2")!, "floating wreckage rank layer");
        Equal("shore-fishing-spots-rank-3", ActorLayerClassifier.Classify("BP_MapObject_ShoreFishingSpot_Rank3_C", "FishingSpot_2")!, "shore fishing rank layer");
        Equal("salvage", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_RequiredLongHold_Junk_C", "Junk_2")!, "salvage layer");
        Equal("magnet-spots", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_MagnetSpot_C", "Magnet_2")!, "magnet spot layer");
        Equal("treasure-map-03", ActorLayerClassifier.Classify("BP_TreasureMap_03_C", "TreasureMap03_2")!, "treasure map layer");
        Equal("respawn-points", ActorLayerClassifier.Classify("BP_PlayerCampRespawnPoint_C", "CampRespawn_2")!, "respawn point layer");
        Equal("oil-rigs", ActorLayerClassifier.Classify("BP_OilRigPlatform_C", "OilRig_2")!, "oil rig layer");
        Equal("predator-pals", ActorLayerClassifier.Classify("BP_PredatorPalCharacter_C", "PredatorPal_2")!, "predator Pal layer");
        Equal("mutant-enemy-pals", ActorLayerClassifier.Classify("BP_MutantEnemyPal_C", "Enemy_Mutant_2")!, "mutant enemy Pal layer");
        Equal("guild-members", ActorLayerClassifier.Classify("BP_PalPlayerCharacter_C", "PlayerCharacter_2")!, "guild member layer");
        Equal("element-chest-water", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_ElementalLock_Water_C", "ElementChest_2")!, "water element chest layer");
        Equal("element-chest-electric", ActorLayerClassifier.Classify("BP_TreasureBoxVisual_ElementalLock_Electric_C", "ElementChest_3")!, "electric element chest layer");
        Equal("ground-resources", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_VisibleContent_AdjustFloor_C", "GroundItem_3")!, "ground resource layer");
        Equal("ground-paldium", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_VisibleContent_AdjustFloor_C BP_Item_Paldium_C", "SM_PalCrystalS")!, "Paldium pickup layer");
        Equal("ground-food-egg", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_VisibleContent_AdjustFloor_C BP_Item_Egg_C", "SM_Egg")!, "food egg pickup layer");
        Equal("ground-pal-sphere", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_VisibleContent_AdjustFloor_C BP_Item_PalSphere_C", "SM_Orb_x500")!, "Pal Sphere pickup layer");
        Equal("ore", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_VisibleContent_AdjustFloor_C BP_Item_Ore_Steel_C", "SM_Ore_Steel")!, "Steel Ore pickup layer");
        Equal("ground-leather", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_VisibleContent_AdjustFloor_C BP_Item_LeatherRaw_C", "SM_LeatherRaw")!, "Raw Leather pickup layer");
        Equal("coal", ActorLayerClassifier.Classify("BP_MapObject_TreasureBox_VisibleContent_AdjustFloor_C BP_Item_Ore_Coal_C", "SM_Ore_Coal")!, "Coal pickup layer");
        True(ActorLayerClassifier.Classify("BP_DungeonFixedEntrance_grass_6_C", "Entrance_2") is null, "fixed dungeon entrance duplicate rejection");
        Equal("notes", ActorLayerClassifier.Classify("BP_LevelObject_Note_C", "Note_2")!, "note layer");
        Equal("rooby-effigy", ActorLayerClassifier.Classify("BP_LevelObject_Relic_FlameBambi_C", "Relic_2")!, "Rooby effigy layer");
        Equal("cattiva-effigy", ActorLayerClassifier.Classify("BP_LevelObject_Relic_PinkCat_C", "Relic_3")!, "Cattiva effigy layer");
        Equal("statue-of-power", ActorLayerClassifier.Classify("BP_LevelObject_GoddessStatue_C", "Statue_2")!, "Statue of Power layer");
        Equal("arenas", ActorLayerClassifier.Classify("BP_ArenaEntrance_C", "Arena_2")!, "arena layer");
        Equal("world-tree-entrance", ActorLayerClassifier.Classify("BP_LevelObject_WarpPointDestination_WorldTreeEntrance_C", "Warp_2")!, "World Tree entrance layer");
        Equal("npc", ActorLayerClassifier.Classify("BP_NPCSpawnPointOnly_C", "NpcSpawn_2")!, "NPC spawn point layer");
        Equal("ore", ActorLayerClassifier.Classify("BP_BoxPlacementTool_Copper2_C", "Copper_2")!, "copper ore node layer");
        Equal("random-events", ActorLayerClassifier.Classify("BP_PalRandomIncidentSpawner_grass_B_C", "Incident_2")!, "random event area layer");
        Equal("ground-pal-soul-large", ActorLayerClassifier.Classify("BP_Item_PalSoul_Large_C", "Soul_2")!, "large Pal Soul layer");
        True(ActorLayerClassifier.IsUnreliableWorldOrigin("BP_Item_Egg_C", 0, 0), "origin pickup rejection");
        True(!ActorLayerClassifier.IsUnreliableWorldOrigin("BP_LevelObject_TowerFastTravelPoint_C", 6, 0), "origin fast-travel preservation");
        Equal("pal-sheepball", ActorLayerClassifier.Classify("BP_PalCharacter_C", "Pal_3", "SheepBall")!, "pal layer");
        True(ActorLayerClassifier.Classify("StaticMeshActor", "Tree_1") is null, "unclassified actor rejection");
    }

    private static void PatternParsingAndMatching()
    {
        BytePattern pattern = BytePattern.Parse("48 8B ? 7F ?? 90");
        byte[] input = [0x00, 0x48, 0x8B, 0x12, 0x7F, 0xFE, 0x90, 0x00];
        Equal(1, pattern.Find(input), "wildcard pattern offset");
        True(pattern.MatchesAt(input, 1), "wildcard pattern match");
        Equal(-1, pattern.Find([0x48, 0x8A, 0x12, 0x7F, 0xFE, 0x90]), "pattern rejection");
    }

    private static void RipRelativeResolution()
    {
        const long instruction = 0x0000_0001_4000_1000;
        const long target = 0x0000_0001_4000_2040;
        int displacement = checked((int)(target - (instruction + 7)));
        Span<byte> encoded = stackalloc byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(encoded, displacement);
        int decoded = BinaryPrimitives.ReadInt32LittleEndian(encoded);
        Equal(target, UnrealGlobals.ResolveRipRelative(instruction, 7, decoded), "RIP-relative target");
    }

    private static void ProcessRightsRemainReadOnly()
    {
        ProcessAccess rights = ProcessAccess.QueryInformation | ProcessAccess.VirtualMemoryRead;
        Equal((uint)0x410, (uint)rights, "process access mask");
        True((rights & (ProcessAccess)0x20) == 0, "VM write permission absent");
        True((rights & (ProcessAccess)0x08) == 0, "VM operation permission absent");
    }

    private static void Equal<T>(T expected, T actual, string label)
        where T : IEquatable<T>
    {
        if (!actual.Equals(expected))
        {
            throw new InvalidOperationException(
                $"Self-test '{label}' failed: expected {expected}, got {actual}.");
        }
    }

    private static void True(bool condition, string label)
    {
        if (!condition)
        {
            throw new InvalidOperationException($"Self-test '{label}' failed.");
        }
    }
}
