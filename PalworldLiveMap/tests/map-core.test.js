"use strict";

const assert = require("assert");
const Core = require("../App/map-core.js");

for (const mapId of ["world", "tree"]) {
  const world = mapId === "world" ? { x: 51200, y: 16600 } : { x: 430000, y: -620000 };
  const image = Core.worldToImage(mapId, world);
  const roundTrip = Core.imageToWorld(mapId, image);
  assert.ok(Math.abs(roundTrip.x - world.x) < 0.001, `${mapId} x round trip`);
  assert.ok(Math.abs(roundTrip.y - world.y) < 0.001, `${mapId} y round trip`);
}

const camera = { x: 4096, y: 4096, zoom: 0.25 };
const viewport = { width: 1000, height: 800 };
const imagePoint = { x: 5000, y: 3000 };
assert.deepStrictEqual(Core.screenToImage(Core.imageToScreen(imagePoint, camera, viewport), camera, viewport), imagePoint);
assert.strictEqual(Core.chooseMap({ x: 0, y: 0 }), "world");
assert.strictEqual(Core.chooseMap({ x: 430000, y: -620000 }), "tree");

const dualith = { x: 517450, y: -626940 };
const dualithLogical = Core.worldToLogical("tree", dualith);
const dualithImage = Core.worldToImage("tree", dualith);
assert.ok(Math.abs(dualithLogical.x - -1710.11) < 0.02, "World Tree map X matches current 1.0 coordinates");
assert.ok(Math.abs(dualithLogical.y - 1397.25) < 0.02, "World Tree map Y matches current 1.0 coordinates");
assert.ok(Math.abs(dualithImage.x - 4583.94) < 0.1, "World Tree raster X is correctly scaled");
assert.ok(Math.abs(dualithImage.y - 4115.17) < 0.1, "World Tree raster Y is correctly scaled");

assert.ok(Math.abs(Core.worldYawToScreenRadians(0) + Math.PI / 2) < 1e-12, "yaw 0 points up");
assert.ok(Math.abs(Core.worldYawToScreenRadians(90)) < 1e-12, "yaw 90 points right");
assert.ok(Math.abs(Core.worldYawToScreenRadians(180) - Math.PI / 2) < 1e-12, "yaw 180 points down");

const valid = Core.normalizeTelemetry({ connected: true, sequence: 4.9, status: "live", position: { x: 1, y: 2, z: 3 }, rotation: { yaw: 90 } });
assert.strictEqual(valid.connected, true);
assert.strictEqual(valid.sequence, 4);
assert.strictEqual(valid.rotation.yaw, 90);
assert.strictEqual(Core.normalizeTelemetry({ connected: true, position: { x: "bad", y: 2 } }).connected, false);

console.log("map-core tests passed");
