# Palworld.gg map-pin snapshot

This directory contains a normalized snapshot of the public markers displayed by the Palworld.gg Palpagos and World Tree interactive maps.

## Files

- `palworld-gg-map-pins.json`: complete structured export with source metadata, counts, and marker records.
- `palworld-gg-map-pins.csv`: flat version for filtering and coordinate comparison.
- `palworld-gg-map-pin-counts.json`: category totals used for validation.

## Marker fields

- `id`: deterministic local identifier based on map, type, sequence, and coordinates.
- `map`: `palpagos` or `world-tree`.
- `category`: locations, bosses, collectibles, effigies, eggs, NPCs, or materials.
- `type`: normalized marker type such as `alpha-pal`, `fast-travel`, `treasure-chest`, or `material`.
- `name`: English display name when the source provides one; otherwise the category name.
- `worldX`, `worldY`, `worldZ`: raw game-world coordinates. Palworld.gg does not provide Z, so `worldZ` is null.
- `mapX`, `mapY`: converted in-game display coordinates.
- `levelMin`, `levelMax`: encounter levels when provided.
- `palId`: Palworld.gg internal Pal identifier when applicable.
- `subtype`: material, egg, effigy, realm, or other source subtype when applicable.
- `biome`: dungeon biome when provided.
- `sourceId`: source-side NPC or bounty identifier when applicable.
- `sourceIndex`: zero-based position within the source category.

## Scope

The export contains point markers. Pal-location heatmap polygons/point clouds are a separate feature on Palworld.gg and are not included as map pins.

Run `node Scripts/Extract-PalworldGgPins.mjs` from `PalworldLiveMap` after refreshing the downloaded public route modules in `Diagnostics/palworld-gg`.
