import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(scriptDirectory, "..");
const sourcePath = path.join(projectDirectory, "Data", "palworld-gg-map-pins.json");
const outputPath = path.join(projectDirectory, "App", "alpha-boss-reference-pins.js");
const source = JSON.parse(fs.readFileSync(sourcePath, "utf8"));

const pins = source.markers
  .filter((marker) => marker.category === "bosses" && (marker.type === "alpha-pal" || marker.type === "sealed-realm"))
  .map((marker) => ({
    id: marker.id,
    layer: "pal-bosses",
    mapId: marker.map === "world-tree" ? "tree" : "world",
    x: marker.worldX,
    y: marker.worldY,
    z: marker.worldZ,
    name: marker.name,
    palId: marker.palId,
    levelMin: marker.levelMin,
    levelMax: marker.levelMax,
    alphaReference: true,
    sealedRealmReference: marker.type === "sealed-realm",
  }));

fs.writeFileSync(outputPath, `window.AlphaBossReferencePins = Object.freeze(${JSON.stringify(pins)});\n`);
console.log(`Wrote ${pins.length} alpha boss reference pins to ${outputPath}`);
