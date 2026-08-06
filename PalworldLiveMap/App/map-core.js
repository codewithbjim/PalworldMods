(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.LiveMapCore = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const MAP_SIZE = 8192;
  const TREE_WORLD_MIN_X = 347351.5;
  const TREE_WORLD_MIN_Y = -818197;
  const TREE_WORLD_SPAN = 341797;
  const MAPS = Object.freeze({
    world: Object.freeze({ id: "world", label: "Palpagos", image: "assets/maps/T_WorldMap.webp", width: MAP_SIZE, height: MAP_SIZE }),
    tree: Object.freeze({ id: "tree", label: "World Tree", image: "assets/maps/T_TreeMap.webp", width: MAP_SIZE, height: MAP_SIZE }),
  });

  function finite(value, fallback) {
    return Number.isFinite(Number(value)) ? Number(value) : fallback;
  }

  function clamp(value, minimum, maximum) {
    return Math.min(maximum, Math.max(minimum, finite(value, minimum)));
  }

  function worldToLogical(mapId, point) {
    const x = finite(point && point.x, 0);
    const y = finite(point && point.y, 0);
    // Palworld.gg's World Tree labels use a separate 1.0 coordinate grid.
    if (mapId === "tree") return { x: (y - 158000) / 459, y: (x + 123888) / 459 };
    return { x: (y + 18) / 725, y: (x + 375247) / 725 };
  }

  function logicalToImage(mapId, point, width = MAP_SIZE, height = MAP_SIZE) {
    if (mapId === "tree") {
      const worldX = point.y * 459 - 123888;
      const worldY = point.x * 459 + 158000;
      return {
        x: ((worldY - TREE_WORLD_MIN_Y) / TREE_WORLD_SPAN) * width,
        y: (1 - (worldX - TREE_WORLD_MIN_X) / TREE_WORLD_SPAN) * height,
      };
    }
    return { x: ((point.x + 1000) / 2000) * width, y: ((1000 - point.y) / 2000) * height };
  }

  function worldToImage(mapId, point, width = MAP_SIZE, height = MAP_SIZE) {
    return logicalToImage(mapId, worldToLogical(mapId, point), width, height);
  }

  function imageToWorld(mapId, point, width = MAP_SIZE, height = MAP_SIZE) {
    if (mapId === "tree") {
      return {
        x: TREE_WORLD_MIN_X + (1 - finite(point.y, 0) / height) * TREE_WORLD_SPAN,
        y: TREE_WORLD_MIN_Y + (finite(point.x, 0) / width) * TREE_WORLD_SPAN,
      };
    }
    const logicalX = (finite(point.x, 0) / width) * 2000 - 1000;
    const logicalY = 1000 - (finite(point.y, 0) / height) * 2000;
    return { x: logicalY * 725 - 375247, y: logicalX * 725 - 18 };
  }

  function chooseMap(point) {
    const world = worldToLogical("world", point);
    if (Math.abs(world.x) <= 1000 && Math.abs(world.y) <= 1000) return "world";
    const tree = worldToLogical("tree", point);
    return Math.abs(tree.x) <= 2500 && Math.abs(tree.y) <= 2500 ? "tree" : "world";
  }

  function imageToScreen(point, camera, viewport) {
    const zoom = clamp(camera.zoom, 0.03, 4);
    return { x: viewport.width / 2 + (point.x - camera.x) * zoom, y: viewport.height / 2 + (point.y - camera.y) * zoom };
  }

  function screenToImage(point, camera, viewport) {
    const zoom = clamp(camera.zoom, 0.03, 4);
    return { x: camera.x + (point.x - viewport.width / 2) / zoom, y: camera.y + (point.y - viewport.height / 2) / zoom };
  }

  function worldYawToScreenRadians(yawDegrees) {
    return finite(yawDegrees, 0) * Math.PI / 180 - Math.PI / 2;
  }

  function normalizeTelemetry(value) {
    const input = value && typeof value === "object" ? value : {};
    const position = input.position && typeof input.position === "object" ? input.position : {};
    const rotation = input.rotation && typeof input.rotation === "object" ? input.rotation : {};
    const x = finite(position.x, null);
    const y = finite(position.y, null);
    return {
      connected: input.connected === true && x !== null && y !== null,
      status: typeof input.status === "string" ? input.status : "waiting",
      world: typeof input.world === "string" ? input.world : "Palworld",
      sequence: Math.max(0, Math.floor(finite(input.sequence, 0))),
      position: { x, y, z: finite(position.z, null) },
      rotation: { pitch: finite(rotation.pitch, 0), yaw: finite(rotation.yaw, 0), roll: finite(rotation.roll, 0) },
    };
  }

  return { MAPS, clamp, worldToLogical, logicalToImage, worldToImage, imageToWorld, chooseMap, imageToScreen, screenToImage, worldYawToScreenRadians, normalizeTelemetry };
});
