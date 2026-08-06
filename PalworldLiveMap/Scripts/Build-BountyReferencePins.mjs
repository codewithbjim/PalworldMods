import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(scriptDirectory, "..");
const source = JSON.parse(fs.readFileSync(path.join(projectDirectory, "Data", "palworld-gg-map-pins.json"), "utf8"));
const pins = source.markers.filter((marker) => marker.type === "bounty-target").map((marker) => ({
  id: marker.id, layer: "bounty-bosses", mapId: marker.map === "world-tree" ? "tree" : "world",
  x: marker.worldX, y: marker.worldY, z: marker.worldZ, name: marker.name,
  levelMin: marker.levelMin, levelMax: marker.levelMax, bountyReference: true,
}));
fs.writeFileSync(path.join(projectDirectory, "App", "bounty-reference-pins.js"), `window.BountyReferencePins = Object.freeze(${JSON.stringify(pins)});\n`);
console.log(`Wrote ${pins.length} bounty reference pins.`);
