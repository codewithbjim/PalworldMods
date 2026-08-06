import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const root = path.resolve(import.meta.dirname, "..");
const sourceDir = path.join(root, "Diagnostics", "palworld-gg");
const outputDir = path.join(root, "Data");
const palpagosSource = fs.readFileSync(path.join(sourceDir, "DFoYuZZt.js"), "utf8");
const treeSource = fs.readFileSync(path.join(sourceDir, "dzPAlgc0.js"), "utf8");
const palNamesSource = fs.readFileSync(path.join(sourceDir, "pals-en.js"), "utf8");

function expression(source, name) {
  const match = new RegExp(`(?<![A-Za-z0-9_$])${name.replaceAll("$", "\\$")}=`, "g").exec(source);
  if (!match) throw new Error(`Missing data variable ${name}`);
  let start = match.index + match[0].length;
  while (/\s/.test(source[start])) start++;
  if (source.startsWith("JSON.parse(", start)) {
    let depth = 0, quote = null, escaped = false;
    for (let index = start; index < source.length; index++) {
      const character = source[index];
      if (quote) {
        if (escaped) escaped = false;
        else if (character === "\\") escaped = true;
        else if (character === quote) quote = null;
      } else if (character === '"' || character === "'" || character === "`") quote = character;
      else if (character === "(") depth++;
      else if (character === ")" && --depth === 0) return source.slice(start, index + 1);
    }
  }
  const opening = source[start];
  const closing = opening === "[" ? "]" : opening === "{" ? "}" : null;
  if (!closing) throw new Error(`Unsupported expression for ${name}`);
  let depth = 0, quote = null, escaped = false;
  for (let index = start; index < source.length; index++) {
    const character = source[index];
    if (quote) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === quote) quote = null;
    } else if (character === '"' || character === "'" || character === "`") quote = character;
    else if (character === opening) depth++;
    else if (character === closing && --depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Unterminated expression for ${name}`);
}

function value(source, name) {
  return vm.runInNewContext(`(${expression(source, name)})`, { JSON }, { timeout: 2000 });
}

function references(source, name) {
  const input = expression(source, name);
  return Object.fromEntries([...input.matchAll(/(?:^|[,{}])([A-Za-z0-9_-]+):([A-Za-z0-9_$]+)/g)].map(([, key, variable]) => [key, variable]));
}

function referencedValues(source, name) {
  return Object.fromEntries(Object.entries(references(source, name)).map(([key, variable]) => [key, value(source, variable)]));
}

const palNames = new Map();
for (const match of palNamesSource.matchAll(/\{id:"([^"]+)"[^{}]{0,900}?name:"([^"]+)"/gs)) palNames.set(match[1].toLowerCase(), match[2]);
const palName = (id) => palNames.get(String(id || "").toLowerCase()) || String(id || "Unknown Pal");

const markers = [];
const countBy = new Map();
function add(map, category, type, coordinates, details = {}) {
  if (!coordinates || !Number.isFinite(Number(coordinates[0])) || !Number.isFinite(Number(coordinates[1]))) return;
  const x = Number(coordinates[0]), y = Number(coordinates[1]);
  const sequenceKey = `${map}:${category}:${type}`;
  const sequence = (countBy.get(sequenceKey) || 0) + 1;
  countBy.set(sequenceKey, sequence);
  const mapX = Math.round((y - 158000) / 459);
  const mapY = Math.round((x + 123888) / 459);
  markers.push({
    id: `${map}-${type}-${sequence}-${Math.round(x)}-${Math.round(y)}`.toLowerCase().replace(/[^a-z0-9-]+/g, "-"),
    map,
    category,
    type,
    name: details.name || `${type} ${sequence}`,
    worldX: x,
    worldY: y,
    worldZ: null,
    mapX,
    mapY,
    levelMin: details.levelMin ?? null,
    levelMax: details.levelMax ?? null,
    palId: details.palId ?? null,
    subtype: details.subtype ?? null,
    biome: details.biome ?? null,
    sourceId: details.sourceId ?? null,
    sourceIndex: sequence - 1,
  });
}

function addCoordinateArray(map, category, type, rows, name, detailer = () => ({})) {
  rows.forEach((row, index) => add(map, category, type, row, { name, ...detailer(row, index) }));
}

function addPalRows(map, category, type, rows) {
  rows.forEach((row) => add(map, category, type, [row.x, row.y], {
    name: palName(row.pal), palId: row.pal, levelMin: row.lv?.[0] ?? null, levelMax: row.lv?.[1] ?? row.lv?.[0] ?? null,
  }));
}

function addNamedActors(map, category, type, rows, names = {}) {
  rows.forEach((row) => add(map, category, type, [row.x, row.y], {
    name: names[row.id]?.en || row.id || type,
    sourceId: row.id || null,
    levelMin: Array.isArray(row.lv) ? row.lv[0] : row.lv ?? null,
    levelMax: Array.isArray(row.lv) ? row.lv[1] : row.lv ?? null,
    palId: row.pal || null,
    subtype: row.realm || null,
  }));
}

function extractPalpagos() {
  addCoordinateArray("palpagos", "locations", "fast-travel", value(palpagosSource, "o3"), "Fast Travel");
  addCoordinateArray("palpagos", "locations", "syndicate-tower", value(palpagosSource, "n3"), "Syndicate Tower");
  addCoordinateArray("palpagos", "locations", "dungeon", value(palpagosSource, "r3"), "Dungeon", (row) => ({ biome: row[2] || null }));
  addPalRows("palpagos", "bosses", "alpha-pal", value(palpagosSource, "l3"));
  addPalRows("palpagos", "bosses", "predator-pal", value(palpagosSource, "d3"));
  addCoordinateArray("palpagos", "collectibles", "note", value(palpagosSource, "i3"), "Note");
  addCoordinateArray("palpagos", "collectibles", "skill-fruit", value(palpagosSource, "s3"), "Skill Fruit");
  addCoordinateArray("palpagos", "collectibles", "treasure-chest", value(palpagosSource, "c3"), "Treasure Chest");
  addCoordinateArray("palpagos", "collectibles", "element-chest", value(palpagosSource, "u3"), "Element Chest");

  const actors = referencedValues(palpagosSource, "m");
  addNamedActors("palpagos", "bosses", "sealed-realm", actors.sealed, value(palpagosSource, "J7"));
  addNamedActors("palpagos", "bosses", "bounty-target", actors.bounty, value(palpagosSource, "Z7"));
  addNamedActors("palpagos", "npcs", "npc", actors.npc, value(palpagosSource, "Y7"));
  addCoordinateArray("palpagos", "npcs", "merchant", actors.merchant, "Merchant");
  addCoordinateArray("palpagos", "npcs", "pal-merchant", actors.palMerchant, "Pal Merchant");

  for (const [subtype, rows] of Object.entries(referencedValues(palpagosSource, "t1"))) {
    addCoordinateArray("palpagos", "effigies", "effigy", rows, `${palName(subtype)} Effigy`, () => ({ palId: subtype, subtype }));
  }
  for (const [subtype, rows] of Object.entries(referencedValues(palpagosSource, "o1"))) {
    addCoordinateArray("palpagos", "eggs", "egg", rows, `${subtype} Egg`, () => ({ subtype }));
  }
  for (const [subtype, rows] of Object.entries(referencedValues(palpagosSource, "j1"))) {
    addCoordinateArray("palpagos", "materials", "material", rows, subtype, () => ({ subtype }));
  }
}

function extractWorldTree() {
  addCoordinateArray("world-tree", "locations", "fast-travel", value(treeSource, "G0"), "Fast Travel");
  addCoordinateArray("world-tree", "locations", "syndicate-tower", value(treeSource, "Z0"), "Syndicate Tower");
  addCoordinateArray("world-tree", "locations", "dungeon", value(treeSource, "X0"), "Dungeon");
  addPalRows("world-tree", "bosses", "alpha-pal", value(treeSource, "e6"));
  addPalRows("world-tree", "bosses", "predator-pal", value(treeSource, "t6"));
  addCoordinateArray("world-tree", "collectibles", "note", value(treeSource, "Y0"), "Note");
  addCoordinateArray("world-tree", "collectibles", "skill-fruit", value(treeSource, "K0"), "Skill Fruit");
  addCoordinateArray("world-tree", "collectibles", "treasure-chest", value(treeSource, "n6"), "Treasure Chest");
  addCoordinateArray("world-tree", "collectibles", "element-chest", value(treeSource, "o6"), "Element Chest");
  addCoordinateArray("world-tree", "effigies", "effigy", value(treeSource, "J0"), "Effigy", (row) => ({ palId: row[2] || null, subtype: row[2] || null, name: `${palName(row[2])} Effigy` }));
  addCoordinateArray("world-tree", "eggs", "egg", value(treeSource, "Q0"), "World Tree Egg", (row) => ({ subtype: row[2] || "worldtree" }));

  const actors = referencedValues(treeSource, "m");
  addNamedActors("world-tree", "bosses", "sealed-realm", actors.sealed, value(treeSource, "J4"));
  addNamedActors("world-tree", "bosses", "bounty-target", actors.bounty, value(treeSource, "Q4"));
  addNamedActors("world-tree", "npcs", "npc", actors.npc, value(treeSource, "K4"));
  addCoordinateArray("world-tree", "npcs", "merchant", actors.merchant, "Merchant");
  addCoordinateArray("world-tree", "npcs", "pal-merchant", actors.palMerchant, "Pal Merchant");
  for (const [subtype, rows] of Object.entries(referencedValues(treeSource, "b5"))) {
    addCoordinateArray("world-tree", "materials", "material", rows, subtype, () => ({ subtype }));
  }
}

extractPalpagos();
extractWorldTree();
markers.sort((a, b) => a.map.localeCompare(b.map) || a.category.localeCompare(b.category) || a.type.localeCompare(b.type) || a.sourceIndex - b.sourceIndex);

const counts = Object.entries(Object.groupBy(markers, (marker) => `${marker.map}/${marker.category}/${marker.type}`))
  .map(([key, rows]) => ({ key, count: rows.length }))
  .sort((a, b) => a.key.localeCompare(b.key));
const capturedAtUtc = new Date().toISOString();
const result = {
  schemaVersion: 1,
  source: { site: "palworld.gg", palpagosUrl: "https://palworld.gg/map", worldTreeUrl: "https://palworld.gg/map/world-tree", capturedAtUtc, bundles: ["DFoYuZZt.js", "dzPAlgc0.js", "CK2A4_hG.js"] },
  markerCount: markers.length,
  counts,
  markers,
};

fs.mkdirSync(outputDir, { recursive: true });
fs.writeFileSync(path.join(outputDir, "palworld-gg-map-pins.json"), JSON.stringify(result, null, 2));
const columns = ["id", "map", "category", "type", "name", "worldX", "worldY", "worldZ", "mapX", "mapY", "levelMin", "levelMax", "palId", "subtype", "biome", "sourceId", "sourceIndex"];
const csv = [columns.join(","), ...markers.map((marker) => columns.map((column) => `"${String(marker[column] ?? "").replaceAll('"', '""')}"`).join(","))].join("\n");
fs.writeFileSync(path.join(outputDir, "palworld-gg-map-pins.csv"), csv);
fs.writeFileSync(path.join(outputDir, "palworld-gg-map-pin-counts.json"), JSON.stringify(counts, null, 2));
console.log(JSON.stringify({ markerCount: markers.length, counts }, null, 2));
