(function () {
  "use strict";

  const icon = (name) => `assets/icons/${name}.webp`;
  const pngIcon = (name) => `assets/icons/${name}.png`;
  const item = (id, label, count, image, symbol = "•", ring = null, composite = null, filter = null) => Object.freeze({ id, label, count, image, symbol, ring, composite, filter });
  const group = (id, label, items, open = true) => Object.freeze({ id, label, open, items: Object.freeze(items) });
  const rarityColors = [null, "#d9e3e8", "#54e879", "#4ca8ff", "#bd6cff", "#ffd34f"];
  const rankedItem = (id, label, rank, image, filter = null) => item(`${id}-rank-${rank}`, `${label} · Rank ${rank}`, null, image, String(rank), rarityColors[rank], null, filter);

  const groups = [
    group("live", "Live Map", [
      item("player", "Active Player", 1, pngIcon("player-native"), "▲"),
      item("guild-members", "Guild Member", null, pngIcon("guild-member-native"), "▲"),
      item("custom", "My Markers", null, null, "●"),
    ]),
    group("locations", "Locations", [
      item("fast-travel", "Fast Travel", 137, pngIcon("fast-travel-native"), "✦"),
      item("respawn-points", "Respawn Point", null, pngIcon("camp-native"), "⌂"),
      item("statue-of-power", "Statue of Power", null, pngIcon("goddess-statue-native"), "◆"),
      item("arenas", "Arena", null, pngIcon("sealed-realm"), "○"),
      item("world-tree-entrance", "World Tree Entrance", null, pngIcon("fast-travel-native"), "➜"),
      item("towers", "Boss Towers", 9, `${pngIcon("tower-native")}?v=2`, "◇"),
      item("oil-rigs", "Oil Rig", null, pngIcon("oil-rig-native"), "▥"),
      item("dungeons", "Dungeon", 157, pngIcon("dungeon"), "⌂"),
      item("sealed-realms", "Sealed Realm", 18, pngIcon("sealed-realm"), "⬟"),
      item("random-events", "Random Event Area", null, pngIcon("random-event-native"), "?"),
    ]),
    group("bosses", "Bosses", [
      item("pal-bosses", "Pal Bosses", 65, pngIcon("alpha-pals"), "♜"),
      item("tower-bosses", "Tower Bosses", null, `${pngIcon("tower-native")}?v=2`, "♜"),
      item("predator-pals", "Predator Pal", null, pngIcon("predator-pal-native"), "☠"),
      item("mutant-enemy-pals", "Mutant Enemy Pal", null, pngIcon("mutant-enemy-pal-native"), "☣"),
      item("bounty-bosses", "Bounty Bosses", 33, pngIcon("bounty-native"), "◎"),
    ]),
    group("collectibles", "Collectibles", [
      item("treasure", "Treasure Chest", 1412, pngIcon("treasure-native"), "▣"),
      item("element-chest-fire", "Fire Element Chest", null, null, "▣", null, { base: pngIcon("element-chest-container-native"), overlay: pngIcon("element-fire-native") }),
      item("element-chest-water", "Water Element Chest", null, null, "▣", null, { base: pngIcon("element-chest-container-native"), overlay: pngIcon("element-water-native") }),
      item("element-chest-electric", "Electric Element Chest", null, null, "▣", null, { base: pngIcon("element-chest-container-native"), overlay: pngIcon("element-electric-native") }),
      item("element-chest", "Other Element Chest", 109, pngIcon("element-chest-container-native"), "▣"),
      item("salvage", "Salvage", null, pngIcon("salvage-native"), "⚙"),
      ...Array.from({ length: 5 }, (_, index) => rankedItem("shore-fishing-spots", "Shore Fishing", index + 1, pngIcon("fishing-spot-native"))),
      ...Array.from({ length: 5 }, (_, index) => rankedItem("floating-wreckage", "Floating Wreckage", index + 1, pngIcon("salvage-native"))),
      item("shore-fishing-spots", "Shore Fishing · Unknown Rank", null, pngIcon("fishing-spot-native"), "?"),
      item("floating-wreckage", "Floating Wreckage · Unknown Rank", null, pngIcon("salvage-native"), "?"),
      item("magnet-spots", "Magnet Spot", null, pngIcon("magnet-spot-native"), "⌁"),
      item("treasure-map-01", "Treasure Map I", null, pngIcon("treasure-map-01"), "1"),
      item("treasure-map-02", "Treasure Map II", null, pngIcon("treasure-map-02"), "2"),
      item("treasure-map-03", "Treasure Map III", null, pngIcon("treasure-map-03"), "3"),
      item("treasure-map-04", "Treasure Map IV", null, pngIcon("treasure-map-04"), "4"),
      item("treasure-map-05", "Treasure Map V", null, pngIcon("treasure-map-05"), "5"),
      item("skill-fruit", "Skill Fruit", 31, icon("skill-fruit"), "♣"),
      item("notes", "Note", 55, pngIcon("note"), "▤"),
    ]),
    group("effigies", "Effigies", [
      item("lifmunk-effigy", "Lifmunk Effigy", 140, pngIcon("lifmunk-effigy-native"), "◆"),
      item("rooby-effigy", "Rooby Effigy", 30, icon("rooby"), "◆", "#54e879"),
      item("yakumo-effigy", "Yakumo Effigy", 2, icon("yakumo"), "◆", "#54e879"),
      item("munchill-effigy", "Munchill Effigy", 30, icon("munchill"), "◆", "#54e879"),
      item("relaxaurus-effigy", "Relaxaurus Effigy", 4, icon("relaxaurus"), "◆", "#54e879"),
      item("herbil-effigy", "Herbil Effigy", 30, icon("herbil"), "◆", "#54e879"),
      item("tanzee-effigy", "Tanzee Effigy", 30, icon("tanzee"), "◆", "#54e879"),
      item("lunaris-effigy", "Lunaris Effigy", 4, icon("lunaris"), "◆", "#54e879"),
      item("depresso-effigy", "Depresso Effigy", 30, icon("depresso"), "◆", "#54e879"),
      item("pengullet-effigy", "Pengullet Effigy", 30, icon("pengullet"), "◆", "#54e879"),
      item("lamball-effigy", "Lamball Effigy", 30, icon("lamball"), "◆", "#54e879"),
      item("cattiva-effigy", "Cattiva Effigy", 30, null, "◆", "#54e879"),
    ]),
    group("egg", "Egg", [
      item("grassland-egg", "Grassland Egg", 441, icon("egg-grassland"), "◉"),
      item("volcanic-egg", "Volcanic Egg", 310, icon("egg-volcanic"), "◉"),
      item("sakurajima-egg", "Sakurajima Egg", 36, icon("egg-sakurajima"), "◉"),
      item("frozen-egg", "Frozen Egg", 271, icon("egg-frozen"), "◉"),
      item("desert-egg", "Desert Egg", 122, icon("egg-desert"), "◉"),
      item("large-egg", "Large Egg", 567, icon("egg-large"), "◉"),
      item("sky-island-egg", "Sky Island Egg", 39, icon("egg-sky"), "◉"),
    ]),
    group("npcs", "NPCs", [
      item("npc", "NPC", 123, pngIcon("npc"), "♟"),
      item("merchant", "Merchant", 12, pngIcon("merchant"), "♟"),
      item("pal-merchant", "Pal Merchant", 6, pngIcon("pal-merchant"), "♟"),
    ]),
    group("materials", "Materials", [
      item("ground-resources", "Other Ground Pickup", null, null, "●"),
      item("ground-paldium", "Paldium Fragment Pickup", null, pngIcon("ground-paldium-native"), "●"),
      item("ground-food-egg", "Food Egg Pickup", null, pngIcon("ground-food-egg-native"), "●"),
      item("ground-pal-sphere", "Pal Sphere Pickup", null, pngIcon("ground-pal-sphere-native"), "●"),
      item("ground-mega-sphere", "Mega Sphere Pickup", null, pngIcon("ground-mega-sphere-native"), "●"),
      item("ground-giga-sphere", "Giga Sphere Pickup", null, pngIcon("ground-giga-sphere-native"), "●"),
      item("ground-leather-wool", "Leather / Wool Pickup", null, null, "●", null, { base: pngIcon("ground-leather-native"), overlay: pngIcon("ground-wool-native") }),
      item("ground-leather", "Leather Pickup", null, pngIcon("ground-leather-native"), "●"),
      item("ground-pal-soul-small", "Small Pal Soul", null, pngIcon("pal-soul-small-native"), "◆"),
      item("ground-pal-soul-medium", "Medium Pal Soul", null, pngIcon("pal-soul-medium-native"), "◆"),
      item("ground-pal-soul-large", "Large Pal Soul", null, pngIcon("pal-soul-large-native"), "◆"),
      item("ground-pal-soul-extra-large", "Extra Large Pal Soul", null, pngIcon("pal-soul-extra-large-native"), "◆"),
      item("ground-wood", "Wood Pickup", null, pngIcon("ground-wood-native"), "●"),
      item("ground-stone", "Stone Pickup", null, pngIcon("ground-stone-native"), "●"),
      item("ore", "Ore", 1555, icon("ore"), "⬢"),
      item("coal", "Coal", 497, icon("coal"), "⬢"),
      item("sulfur", "Sulfur", 257, icon("sulfur"), "⬢"),
      item("quartz", "Pure Quartz", 496, icon("quartz"), "✧"),
      item("paldium", "Paldium", 1173, icon("paldium"), "⬙"),
      item("soralite", "Soralite", 208, icon("soralite"), "⬙"),
      item("red-berries", "Red Berries", 1939, icon("berries"), "●"),
      item("mushrooms", "Mushrooms", 274, icon("mushrooms"), "♣"),
      item("oil", "Crude Oil", 185, icon("oil"), "◒"),
    ]),
    group("inspection", "Actor Inspection", [
      item("inspection-boss-spawners", "Likely Boss Pal Spawners", null, pngIcon("alpha-pals"), "B", "#54e879"),
      item("inspection-live-bosses", "Loaded Boss Pal Actors", null, pngIcon("alpha-pals"), "B", "#ffd34f"),
      item("inspection-pal-spawners", "Pal Spawn Areas", null, null, "P", "#8adf7b"),
      item("inspection-fishing-spots", "Fishing Spot Actors", null, null, "F", "#4ccfff"),
      item("inspection-npc-spawns", "NPC Spawn Points", null, null, "N", "#f7da6b"),
      item("inspection-respawn-points", "Respawn Points", null, null, "S", "#6ee7cf"),
    ], false),
  ];

  const pals = Array.isArray(window.PalLocationCatalog) ? window.PalLocationCatalog : [];
  if (pals.length) {
    groups.push(group("pals", "Pals Locations", pals.map((pal) => item(pal.id, pal.label, null, pal.image, "●")), false));
  }
  window.LayerCatalog = Object.freeze(groups);
})();
