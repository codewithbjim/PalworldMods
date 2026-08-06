import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(scriptDirectory, "..");
const sourcePath = path.join(projectDirectory, "Data", "palworld-gg-map-pins.json");
const outputPath = path.join(projectDirectory, "App", "chest-reference-pins.js");
const source = JSON.parse(fs.readFileSync(sourcePath, "utf8"));

const pins = source.markers
  .filter((marker) => marker.category === "collectibles" && (marker.type === "treasure-chest" || marker.type === "element-chest"))
  .map((marker) => ({
    id: marker.id,
    layer: marker.type === "element-chest" ? "element-chest" : "treasure",
    mapId: marker.map === "world-tree" ? "tree" : "world",
    x: marker.worldX,
    y: marker.worldY,
    z: marker.worldZ,
    name: marker.name,
    chestReference: true,
  }));

fs.writeFileSync(outputPath, `window.ChestReferencePins = Object.freeze(${JSON.stringify(pins)});\n`);
console.log(`Wrote ${pins.length} chest reference pins to ${outputPath}`);
