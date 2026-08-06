(function () {
  "use strict";

  const Core = window.LiveMapCore;
  const panel = document.getElementById("mapPanel");
  const stage = document.getElementById("mapStage");
  const image = document.getElementById("mapImage");
  const canvas = document.getElementById("mapCanvas");
  const context = canvas.getContext("2d", { alpha: true, desynchronized: true });
  const statusDot = document.getElementById("statusDot");
  const statusText = document.getElementById("statusText");
  const coordinateValue = document.getElementById("coordinateValue");
  const altitudeValue = document.getElementById("altitudeValue");
  const assetStatus = document.getElementById("assetStatus");
  const followButton = document.getElementById("followButton");
  const markerList = document.getElementById("markerList");
  const markerHint = document.getElementById("markerHint");
  const addMarkerCallout = document.getElementById("addMarkerCallout");
  const mapScale = document.getElementById("mapScale");
  const layerGroups = document.getElementById("layerGroups");
  const layerSummary = document.getElementById("layerSummary");
  const layerSearch = document.getElementById("layerSearch");
  const hideTamedPals = document.getElementById("hideTamedPals");
  const debugMode = document.getElementById("debugMode");
  const actorDebugPanel = document.getElementById("actorDebugPanel");
  const actorDebugTitle = document.getElementById("actorDebugTitle");
  const actorDebugStatus = document.getElementById("actorDebugStatus");
  const actorDebugData = document.getElementById("actorDebugData");
  const actorDebugNotes = document.getElementById("actorDebugNotes");
  const actorDebugNotesStatus = document.getElementById("actorDebugNotesStatus");
  const actorDebugClose = document.getElementById("actorDebugClose");
  const sidebarToggle = document.getElementById("sidebarToggle");
  const filterSearchIcon = document.getElementById("filterSearchIcon");
  const pinTooltip = document.getElementById("pinTooltip");
  const pinTooltipTitle = document.getElementById("pinTooltipTitle");
  const pinTooltipDetail = document.getElementById("pinTooltipDetail");
  const pinTooltipCoordinates = document.getElementById("pinTooltipCoordinates");
  const pinDiscoveredButton = document.getElementById("pinDiscoveredButton");
  const importOverwolfDiscoveries = document.getElementById("importOverwolfDiscoveries");
  const overwolfDiscoveryFile = document.getElementById("overwolfDiscoveryFile");
  const exportActorNotes = document.getElementById("exportActorNotes");
  const importActorNotes = document.getElementById("importActorNotes");
  const actorNotesFile = document.getElementById("actorNotesFile");
  const zoomInButton = document.getElementById("zoomInButton");
  const zoomOutButton = document.getElementById("zoomOutButton");
  const actorNotesStorageKey = "palworld-live-map-actor-notes";
  const layerItems = new Map(window.LayerCatalog.flatMap((group) => group.items.map((entry) => [entry.id, entry])));
  const layerImages = new Map();
  const verticalTolerance = 500;
  const verticalIndicatorPlayerRadius = 15000;
  const movementFollowThreshold = 2;
  const liveBossPlayerRadius = 50000;
  const liveBossReferenceRadius = 30000;
  const liveChestPlayerRadius = 25000;
  const liveChestReferenceRadius = 5000;
  const sealedRealmMergeRadius = 5000;
  const fastTravelMergeRadius = 3000;
  const randomEventMergeRadius = 3000;
  const overwolfDiscoveryMap = Object.freeze({
    lifmunk_effigy: "lifmunk-effigy",
    effigy_negativekoala: "depresso-effigy",
    effigy_flamebambi: "rooby-effigy",
    effigy_icecrocodile: "munchill-effigy",
    effigy_monkey: "tanzee-effigy",
    effigy_sheepball: "lamball-effigy",
    effigy_penguin: "pengullet-effigy",
    effigy_leafmomonga: "herbil-effigy",
    effigy_guardiandog: "yakumo-effigy",
    effigy_lazydragon: "relaxaurus-effigy",
    effigy_mutant: "lunaris-effigy",
    note: "notes",
    FTPoint28: "fast-travel",
    enemy_camp: "respawn-points",
  });
  const towerDetails = [
    { x: -321596.2, y: 209085, level: 10, group: "Rayne Syndicate", npc: "Zoe", pal: "Grizzbolt" },
    { x: -108093.8, y: 77936.1, level: 30, group: "Free Pal Alliance", npc: "Lily", pal: "Lyleen" },
    { x: -361695, y: -112009, level: 40, group: "Brothers of the Eternal Pyre", npc: "Axel", pal: "Orserk" },
    { x: 29975.3, y: 413325, level: 45, group: "PIDF", npc: "Marcus", pal: "Faleris" },
    { x: 81363, y: 90183, level: 50, group: "PAL Genetic Research Unit", npc: "Victor", pal: "Shadowbeak" },
    { x: -29427.6, y: -115900.1, level: 55, group: "Moonflower", npc: "Saya", pal: "Selyne" },
  ];
  const verticalMaterialLayers = new Set(["ground-resources", "ground-paldium", "ground-food-egg", "ground-pal-sphere", "ground-mega-sphere", "ground-giga-sphere", "ground-leather-wool", "ground-leather", "ground-pal-soul-small", "ground-pal-soul-medium", "ground-pal-soul-large", "ground-pal-soul-extra-large", "ground-wood", "ground-stone", "ore", "coal", "sulfur", "quartz", "paldium", "soralite", "red-berries", "mushrooms", "oil"]);

  const state = {
    mapId: "world",
    camera: { x: 4096, y: 4096, zoom: 0.1 },
    telemetry: Core.normalizeTelemetry(null),
    lastPlayerPosition: null,
    entities: [],
    preparedEntities: [],
    entityCounts: new Map(),
    following: true,
    placing: false,
    dragging: false,
    dragMoved: false,
    pointerStart: null,
    cameraStart: null,
    markers: loadMarkers(),
    discoveredNodes: loadDiscoveredNodes(),
    pinHits: [],
    tooltipEntity: null,
    tooltipHideTimer: null,
    visibleLayers: new Set(["player", "custom", "fast-travel", "towers", "pal-bosses", "bounty-bosses"]),
    palQuery: "",
    hideTamedPals: localStorage.getItem("palworld-live-map-hide-tamed") !== "false",
    debugMode: localStorage.getItem("palworld-live-map-debug") !== "false",
    actorNotes: loadActorNotes(),
    debugContext: null,
    entityCountSignature: "",
    renderQueued: false,
  };
  const lucideIcons = {
    "chevron-down": "M6 9l6 6 6-6",
    "chevron-left": "M15 18l-6-6 6-6",
    "chevron-right": "M9 18l6-6-6-6",
    "search": "M11 19a8 8 0 1 1 8-8 8 8 0 0 1-8 8m6 6l6-6",
    "x": "M18 6L6 18M6 6l12 12",
    "plus": "M12 5v14M5 12h14",
    "minus": "M5 12h14"
  };

  function createLucideIcon(name, options = {}) {
    const data = lucideIcons[name];
    if (!data) return document.createTextNode("");
    const size = options.size || 14;
    const strokeWidth = options.strokeWidth || 2;
    const className = options.className ? `lucide-icon ${options.className}` : "lucide-icon";
    const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    icon.setAttribute("viewBox", "0 0 24 24");
    icon.setAttribute("fill", "none");
    icon.setAttribute("stroke", "currentColor");
    icon.setAttribute("stroke-width", String(strokeWidth));
    icon.setAttribute("stroke-linecap", "round");
    icon.setAttribute("stroke-linejoin", "round");
    icon.setAttribute("aria-hidden", "true");
    icon.setAttribute("focusable", "false");
    icon.setAttribute("class", className);
    icon.style.width = `${size}px`;
    icon.style.height = `${size}px`;
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", data);
    icon.appendChild(path);
    return icon;
  }

  function attachDetailsChevron(summary) {
    const section = summary.parentElement;
    const chevron = createLucideIcon("chevron-down", { className: "details-chevron", size: 14 });
    summary.append(chevron);
    const sync = () => chevron.classList.toggle("open", Boolean(section && section.open));
    if (section) section.addEventListener("toggle", sync);
    sync();
    return chevron;
  }

  function setSidebarToggle(collapsed) {
    sidebarToggle.replaceChildren(createLucideIcon(collapsed ? "chevron-right" : "chevron-left", { size: 16 }));
    const label = collapsed ? "Open filters" : "Collapse filters";
    sidebarToggle.setAttribute("aria-label", label);
    sidebarToggle.title = label;
  }

  function loadMarkers() {
    try {
      const value = JSON.parse(localStorage.getItem("palworld-live-map-markers") || "[]");
      return Array.isArray(value) ? value.filter((m) => m && Number.isFinite(m.x) && Number.isFinite(m.y) && typeof m.name === "string") : [];
    } catch (_) { return []; }
  }

  function saveMarkers() { localStorage.setItem("palworld-live-map-markers", JSON.stringify(state.markers)); }
  function loadActorNotes() {
    try {
      const value = JSON.parse(localStorage.getItem(actorNotesStorageKey) || "{}");
      return value && typeof value === "object" && !Array.isArray(value) ? value : {};
    } catch (_) { return {}; }
  }
  function saveActorNotesState() { localStorage.setItem(actorNotesStorageKey, JSON.stringify(state.actorNotes)); }
  function normalizeImportedActorNotes(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    if (raw.version === "actor-notes-v1" && typeof raw.notes === "object" && !Array.isArray(raw.notes)) return raw.notes;
    return raw;
  }
  function exportActorNotesData() {
    return JSON.stringify({
      version: "actor-notes-v1",
      exportedAt: new Date().toISOString(),
      notes: state.actorNotes,
    }, null, 2);
  }
  function exportActorNotesFile() {
    const payload = exportActorNotesData();
    const blob = new Blob([payload], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    link.href = url;
    link.download = `palworld-live-map-actor-notes-${stamp}.json`;
    link.rel = "noopener";
    document.body.appendChild(link);
    link.click();
    URL.revokeObjectURL(url);
    link.remove();
  }
  function importActorNotesFromText(rawText) {
    let parsed = null;
    try { parsed = JSON.parse(rawText); } catch (error) { throw new Error(`Unable to parse JSON: ${error.message}`); }
    const normalized = normalizeImportedActorNotes(parsed);
    if (!normalized) throw new Error("Invalid actor notes file format.");
    let imported = 0;
    let unchanged = 0;
    let skipped = 0;
    for (const [key, note] of Object.entries(normalized)) {
      if (typeof key !== "string" || !key) { skipped += 1; continue; }
      if (typeof note !== "string" || !note.trim()) { skipped += 1; continue; }
      if (state.actorNotes[key]) unchanged += 1;
      else imported += 1;
      state.actorNotes[key] = note;
    }
    if (imported + unchanged + skipped === 0) throw new Error("No importable actor notes found in this file.");
    saveActorNotesState();
    if (state.debugContext) renderDebugContext();
    return { imported, unchanged, skipped };
  }
  function actorNoteKey(entity) {
    return [entity.className || entity.layer, Math.round(entity.x || 0), Math.round(entity.y || 0), Math.round(entity.z || 0)].join(":");
  }
  function normalizeImportedDiscoveryEntry(value) {
    if (typeof value === "string" && value.includes("@")) {
      const atMatch = value.match(/^(?<type>[^@]+)@(?<x>-?\d+(?:\.\d+)?):(?<y>-?\d+(?:\.\d+)?)$/);
      if (!atMatch) return null;
      const layer = overwolfDiscoveryMap[atMatch.groups.type];
      if (!layer) return null;
      const x = Math.round(Number.parseFloat(atMatch.groups.x));
      const y = Math.round(Number.parseFloat(atMatch.groups.y));
      if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
      return `${layer}:${x}:${y}:0`;
    }
    if (typeof value === "string") {
      const keyMatch = value.match(/^(?<layer>[^:]+):(?<x>-?\d+):(?<y>-?\d+):(?<z>-?\d+)$/);
      if (!keyMatch) return null;
      return `${keyMatch.groups.layer}:${Number.parseInt(keyMatch.groups.x, 10)}:${Number.parseInt(keyMatch.groups.y, 10)}:${Number.parseInt(keyMatch.groups.z, 10)}`;
    }
    if (value && typeof value === "object" && typeof value.type === "string" && Number.isFinite(Number(value.x)) && Number.isFinite(Number(value.y))) {
      const layer = overwolfDiscoveryMap[value.type] || value.layer || value.name;
      if (!layer) return null;
      const x = Math.round(Number(value.x));
      const y = Math.round(Number(value.y));
      const z = Number.isFinite(Number(value.z)) ? Math.round(Number(value.z)) : 0;
      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) return null;
      return `${layer}:${x}:${y}:${z}`;
    }
    return null;
  }
  function mergeDiscoveredNodesFromOverwolf(rawText) {
    let input = null;
    try { input = JSON.parse(rawText); } catch (error) { throw new Error(`Unable to parse JSON: ${error.message}`); }
    if (!Array.isArray(input)) throw new Error("Expected an array in the export file.");
    let imported = 0;
    let unchanged = 0;
    let skipped = 0;
    for (const entry of input) {
      const key = normalizeImportedDiscoveryEntry(entry);
      if (!key) {
        skipped += 1;
        continue;
      }
      if (state.discoveredNodes.has(key)) unchanged += 1;
      else {
        state.discoveredNodes.add(key);
        imported += 1;
      }
    }
    if (imported + unchanged + skipped === 0) throw new Error("No importable nodes found in this file.");
    saveDiscoveredNodes();
    queueRender();
    return { imported, unchanged, skipped };
  }
  function showImportSummary(result) {
    const baseText = `Imported ${result.imported} new, kept ${result.unchanged} existing, skipped ${result.skipped} unknown/invalid entries.`;
    const status = document.getElementById("statusText");
    const markerHint = document.getElementById("markerHint");
    if (status) status.textContent = baseText;
    if (markerHint) markerHint.textContent = baseText;
    window.setTimeout(() => {
      const worldStatus = document.getElementById("statusText");
      if (worldStatus && worldStatus.textContent === baseText) worldStatus.textContent = "Waiting for Palworld";
      if (markerHint && markerHint.textContent === baseText) markerHint.textContent = "Stored only in this app.";
    }, 4000);
  }
  function signalBySuffix(liveInspection, suffix) {
    if (!liveInspection || !Array.isArray(liveInspection.signals)) return null;
    const normalized = suffix.toLowerCase();
    return liveInspection.signals.find((signal) => typeof signal.path === "string" && signal.path.toLowerCase().endsWith(normalized)) || null;
  }
  function formatGuid(rawHex) {
    if (typeof rawHex !== "string" || !/^[0-9a-f]{32}$/i.test(rawHex) || /^0+$/i.test(rawHex)) return null;
    return `${rawHex.slice(0, 8)}-${rawHex.slice(8, 12)}-${rawHex.slice(12, 16)}-${rawHex.slice(16, 20)}-${rawHex.slice(20)}`.toUpperCase();
  }
  function decodedActorContext(entity, liveInspection) {
    if (!liveInspection) return null;
    const baseCamp = signalBySuffix(liveInspection, ".BaseCampId");
    const uncapturable = signalBySuffix(liveInspection, ".bIsUncapturable");
    const forceCapturable = signalBySuffix(liveInspection, ".bIsForceCapturable");
    const inBaseReplication = signalBySuffix(liveInspection, ".bInBaseReplication") || signalBySuffix(liveInspection, "bInBaseReplication");
    const trainer = Array.isArray(liveInspection.nestedObjects) && liveInspection.nestedObjects.find((object) =>
      typeof object.path === "string" && object.path.toLowerCase().endsWith(".trainer")
      && typeof object.className === "string" && object.className.toLowerCase().includes("player"));
    const baseCampId = baseCamp && !baseCamp.isAllZero ? formatGuid(baseCamp.rawHex) : null;
    let ownership = "Unknown — no player-ownership signal was confirmed";
    let confidence = "unknown";
    const evidence = [];
    if (trainer) {
      ownership = "Tamed / player-owned (trainer relationship detected)";
      confidence = "high";
      evidence.push(`Player trainer: ${trainer.className}`);
    }
    if (baseCampId) {
      ownership = "Tamed / player-owned base worker";
      confidence = "high";
      evidence.push(`Nonzero BaseCampId: ${baseCampId}`);
    } else if (isEntityTamed(entity)) {
      ownership = "Tamed / player-owned (classified by live scanner)";
      confidence = "high";
      evidence.push("Live map entity has isTamed=true");
    }
    return {
      ownership,
      ownershipConfidence: confidence,
      evidence,
      baseCampId,
      inBaseReplicationObserved: inBaseReplication ? inBaseReplication.firstByte !== 0 : null,
      captureFlagsObserved: {
        isUncapturable: uncapturable ? uncapturable.firstByte !== 0 : null,
        isForceCapturable: forceCapturable ? forceCapturable.firstByte !== 0 : null,
      },
      interpretationNotes: [
        "BaseCampId identifies base assignment and is strong evidence that the Pal is tamed.",
        "IsCatchable/IsTamable-style flags describe whether capture is allowed; they do not prove ownership.",
        "Observed boolean values are live snapshots. Unknown means the scanner found no conclusive ownership evidence, not that the Pal is wild.",
      ],
    };
  }
  function isEntityTamed(entity) {
    if (!entity || !entity.isTamed) return false;
    const value = entity.isTamed;
    return value === true || value === 1 || value === "true" || value === "1";
  }
  function renderDebugContext() {
    if (!state.debugContext) return;
    const { entity, liveInspection } = state.debugContext;
    const investigationNote = state.actorNotes[actorNoteKey(entity)] || "";
    const decodedContext = decodedActorContext(entity, liveInspection);
    actorDebugData.textContent = JSON.stringify({ mapPin: entity, investigationNote, ...(decodedContext ? { decodedContext } : {}), ...(liveInspection ? { liveInspection } : {}) }, null, 2);
  }
  function saveCurrentActorNote() {
    if (!state.debugContext) return;
    const key = actorNoteKey(state.debugContext.entity);
    const note = actorDebugNotes.value.trim();
    if (note) state.actorNotes[key] = note; else delete state.actorNotes[key];
    saveActorNotesState();
    actorDebugNotesStatus.textContent = note ? "Saved locally and included with this actor's debug context." : "No note saved for this actor.";
    renderDebugContext();
  }
  function loadDiscoveredNodes() {
    try { return new Set(JSON.parse(localStorage.getItem("palworld-live-map-discovered") || "[]")); }
    catch (_) { return new Set(); }
  }
  function saveDiscoveredNodes() { localStorage.setItem("palworld-live-map-discovered", JSON.stringify([...state.discoveredNodes])); }
  function discoveryKey(entity) {
    const z = entity.layer === "notes" || entity.layer.endsWith("-effigy") ? 0 : Math.round(entity.z || 0);
    return `${entity.layer}:${Math.round(entity.x)}:${Math.round(entity.y)}:${z}`;
  }
  function supportsDiscovery(entity) { return entity.layer === "notes" || entity.layer.endsWith("-effigy") || entity.alphaReference === true || entity.bountyReference === true; }
  function viewport() { return { width: canvas.clientWidth, height: canvas.clientHeight }; }

  function resizeCanvas() {
    const ratio = Math.min(2, window.devicePixelRatio || 1);
    const width = Math.max(1, Math.round(canvas.clientWidth * ratio));
    const height = Math.max(1, Math.round(canvas.clientHeight * ratio));
    if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
  }

  function fitMap() {
    const map = Core.MAPS[state.mapId];
    const view = viewport();
    state.camera.x = map.width / 2;
    state.camera.y = map.height / 2;
    state.camera.zoom = Math.max(0.03, Math.min(view.width / map.width, view.height / map.height) * 0.96);
    state.following = false;
    updateFollowingUi();
    queueRender();
  }

  function setMap(mapId, preserveFollow) {
    if (!Core.MAPS[mapId]) return;
    state.mapId = mapId;
    image.src = Core.MAPS[mapId].image;
    image.alt = `${Core.MAPS[mapId].label} map`;
    assetStatus.textContent = `Loading ${Core.MAPS[mapId].label} 8192×8192…`;
    document.querySelectorAll(".map-tab").forEach((button) => button.classList.toggle("active", button.dataset.map === mapId));
    if (!preserveFollow) fitMap();
    else queueRender();
  }

  function queueRender() {
    if (state.renderQueued) return;
    state.renderQueued = true;
    requestAnimationFrame(render);
  }

  function render() {
    state.renderQueued = false;
    resizeCanvas();
    const view = viewport();
    const map = Core.MAPS[state.mapId];
    if (state.following && state.telemetry.connected && !state.dragging) {
      const playerMap = Core.chooseMap(state.telemetry.position);
      if (playerMap !== state.mapId) { setMap(playerMap, true); return; }
      const playerImage = Core.worldToImage(state.mapId, state.telemetry.position, map.width, map.height);
      state.camera.x = playerImage.x;
      state.camera.y = playerImage.y;
    }

    const left = view.width / 2 - state.camera.x * state.camera.zoom;
    const top = view.height / 2 - state.camera.y * state.camera.zoom;
    stage.style.transform = `translate3d(${left}px, ${top}px, 0) scale(${state.camera.zoom})`;
    context.clearRect(0, 0, view.width, view.height);
    state.pinHits = [];
    drawEntities(view, map);
    drawMarkers(view, map);
    drawPlayer(view, map);
    mapScale.textContent = `${Math.round(1 / state.camera.zoom * 100) / 100} image px / screen px`;
  }

  function layerColor(layer) {
    if (layer === "fast-travel") return "#6fdcff";
    if (layer === "towers") return "#ff8b6e";
    if (layer === "dungeons" || layer === "sealed-realms") return "#c49aff";
    if (layer === "pal-bosses" || layer.startsWith("pal-")) return "#ffcf67";
    if (layer === "lifmunk-effigy") return "#79f3a6";
    if (["ore", "coal", "sulfur", "quartz", "paldium", "oil"].includes(layer)) return "#d5aa75";
    return "#f4f7ef";
  }

  function getLayerImage(layer) {
    const item = layerItems.get(layer);
    if (!item || !item.image) return null;
    return getAssetImage(item.image);
  }

  function bossPalId(entity) {
    if (typeof entity.palId === "string" && entity.palId) return entity.palId.toLowerCase();
    if (typeof entity.characterId === "string" && entity.characterId) return entity.characterId.replace(/^(?:boss|alpha)_/i, "").toLowerCase();
    if (typeof entity.className !== "string") return null;
    if (/sanctuary_2_volcano_fboss|sactuary_2_volcano_fboss/i.test(entity.className)) return "blackmetaldragon";
    if (/palspawner_sheets_81_1_grass_fboss_4/i.test(entity.className)) return "thunderbird";
    const match = entity.className.match(/(?:^|\s)BP_([A-Za-z0-9_]+?)_BOSS_C(?:\s|$)/i);
    return match ? match[1].toLowerCase() : null;
  }

  function getEntityLayer(entity) {
    if (entity.layer !== "pal-bosses" && entity.layer !== "inspection-live-bosses") return entity.layer;
    const palId = bossPalId(entity);
    if (!palId) return entity.layer;
    const palLayer = `pal-${palId.replaceAll("_", "-")}`;
    return layerItems.has(palLayer) ? palLayer : entity.layer;
  }

  function entityMap(entity) { return entity.mapId || Core.chooseMap(entity); }
  function distance2d(a, b) { return Math.hypot(a.x - b.x, a.y - b.y); }
  function getTowerDetails(entity) {
    if (entity.layer !== "towers" && entity.layer !== "tower-bosses" && entity.layer !== "inspection-tower-bosses") return null;
    const nearest = towerDetails.map((tower) => ({ tower, distance: distance2d(tower, entity) })).sort((left, right) => left.distance - right.distance)[0];
    return nearest && nearest.distance <= 10000 ? nearest.tower : null;
  }
  function isLayerVisible(entity) {
    if (state.visibleLayers.has(entity.layer)) return true;
    return entity.chestReference !== true && entity.layer.startsWith("element-chest-") && state.visibleLayers.has("element-chest");
  }

  function shouldDrawAlphaBoss(entity, liveBosses) {
    if (entity.layer !== "pal-bosses") return true;
    if (!state.telemetry.connected) return entity.alphaReference === true;
    if (entity.alphaReference !== true) return distance2d(entity, state.telemetry.position) <= liveBossPlayerRadius;
    if (distance2d(entity, state.telemetry.position) > liveBossPlayerRadius) return true;
    const palId = bossPalId(entity);
    return !liveBosses.some((live) => bossPalId(live) === palId && distance2d(live, entity) <= liveBossReferenceRadius);
  }

  function chestKind(entity) {
    if (entity.layer === "treasure") return "treasure";
    return entity.layer.startsWith("element-chest") ? "elemental" : null;
  }

  function shouldDrawChest(entity, liveChests) {
    const kind = chestKind(entity);
    if (!kind) return true;
    if (!state.telemetry.connected) return entity.chestReference === true;
    if (entity.chestReference !== true) return distance2d(entity, state.telemetry.position) <= liveChestPlayerRadius;
    if (distance2d(entity, state.telemetry.position) > liveChestPlayerRadius) return true;
    return !liveChests.some((live) => chestKind(live) === kind && distance2d(live, entity) <= liveChestReferenceRadius);
  }

  function getAssetImage(source) {
    if (layerImages.has(source)) return layerImages.get(source);
    const iconImage = new Image();
    const record = { image: iconImage, ready: false, failed: false };
    iconImage.addEventListener("load", () => { record.ready = true; queueRender(); }, { once: true });
    iconImage.addEventListener("error", () => { record.failed = true; queueRender(); }, { once: true });
    iconImage.src = source;
    layerImages.set(source, record);
    return record;
  }

  function drawEntityFallback(entity, point) {
    const radius = entity.layer === "towers" || entity.layer === "fast-travel" ? 5 : 3.5;
    context.beginPath(); context.arc(point.x, point.y, radius, 0, Math.PI * 2);
    context.fillStyle = layerColor(entity.layer); context.fill();
    context.strokeStyle = "rgba(4,12,13,.9)"; context.lineWidth = 1.5; context.stroke();
  }

  function mapIconSize(layer) {
    if (layer === "fast-travel") return 44;
    if (layer.endsWith("-effigy")) return 16.5;
    if (layer === "towers" || layer === "tower-bosses" || layer === "inspection-tower-bosses") return 55;
    if (layer === "dungeons" || layer === "sealed-realms") return 26;
    if (layer === "pal-bosses" || layer.startsWith("pal-")) return 36;
    return 30;
  }

  function supportsVerticalIndicator(layer) {
    return layer === "treasure" || layer.startsWith("element-chest") || layer === "salvage" || layer.startsWith("floating-wreckage") || layer.endsWith("-effigy") || layer === "npc" || layer === "merchant" || layer === "pal-merchant" || layer.endsWith("-egg") || verticalMaterialLayers.has(layer);
  }

  function verticalRelation(entity) {
    const player = state.telemetry.position;
    const playerZ = player && player.z;
    if (!supportsVerticalIndicator(entity.layer) || !state.telemetry.connected || !player || !Number.isFinite(player.x) || !Number.isFinite(player.y) || !Number.isFinite(playerZ) || !Number.isFinite(entity.z)) return null;
    if (distance2d(entity, player) > verticalIndicatorPlayerRadius) return null;
    const difference = entity.z - playerZ;
    if (Math.abs(difference) <= verticalTolerance) return null;
    return { direction: difference > 0 ? "above" : "below", difference };
  }

  function drawVerticalIndicator(entity, point, size) {
    const relation = verticalRelation(entity);
    if (!relation) return;
    const x = point.x + Math.max(8, size * 0.36), y = point.y - Math.max(8, size * 0.36);
    context.save();
    context.beginPath(); context.arc(x, y, 8, 0, Math.PI * 2);
    context.fillStyle = relation.direction === "above" ? "#ffb84d" : "#63d8ff";
    context.shadowColor = "rgba(0,0,0,.9)"; context.shadowBlur = 4; context.fill();
    context.shadowBlur = 0; context.strokeStyle = "#07131b"; context.lineWidth = 2; context.stroke();
    context.fillStyle = "#07131b"; context.font = "900 11px system-ui, sans-serif"; context.textAlign = "center"; context.textBaseline = "middle";
    context.fillText(relation.direction === "above" ? "↑" : "↓", x, y + 0.5);
    context.restore();
  }

  function drawEntities(view, map) {
    context.save();
    const liveBosses = state.entities.filter((entity) => entity.layer === "pal-bosses" && entity.alphaReference !== true);
    const alphaBossReferences = state.entities.filter((entity) => entity.layer === "pal-bosses" && entity.alphaReference === true);
    const liveChests = state.entities.filter((entity) => chestKind(entity) && entity.chestReference !== true);
    const sealedRealmReferences = state.entities.filter((entity) => entity.sealedRealmReference === true);
    const visibleCount = state.preparedEntities.reduce((count, prepared) => count + (prepared.mapId === state.mapId && isLayerVisible(prepared.entity) ? 1 : 0), 0);
    const lightweight = visibleCount > 240 || state.camera.zoom < 0.14;
    for (const prepared of state.preparedEntities) {
      const entity = prepared.entity;
      if (!isLayerVisible(entity) || prepared.mapId !== state.mapId || !shouldDrawAlphaBoss(entity, liveBosses) || !shouldDrawChest(entity, liveChests)) continue;
      const unresolvedBoss = (entity.layer === "pal-bosses" || entity.layer === "inspection-live-bosses")
        && entity.alphaReference !== true
        && getEntityLayer(entity) === entity.layer;
      if (unresolvedBoss && alphaBossReferences.some((reference) => entityMap(reference) === prepared.mapId && distance2d(reference, entity) <= liveBossReferenceRadius)) continue;
      if (entity.layer === "sealed-realms" && sealedRealmReferences.some((reference) => entityMap(reference) === state.mapId && distance2d(reference, entity) <= sealedRealmMergeRadius)) continue;
    if (state.hideTamedPals && isEntityTamed(entity)) continue;
      const point = Core.imageToScreen(prepared.image, state.camera, view);
      if (point.x < -12 || point.y < -12 || point.x > view.width + 12 || point.y > view.height + 12) continue;
      const renderedLayer = getEntityLayer(entity);
      const item = layerItems.get(renderedLayer);
      const compositeBase = item && item.composite ? getAssetImage(item.composite.base) : null;
      const compositeOverlay = item && item.composite ? getAssetImage(item.composite.overlay) : null;
      const ring = entity.layer === "pal-bosses" || entity.layer === "inspection-live-bosses" ? "#ff5a36" : item && item.ring;
      const size = mapIconSize(entity.layer);
      const discovered = supportsDiscovery(entity) && state.discoveredNodes.has(discoveryKey(entity));
      const iconRecord = entity.bountyReference && !discovered ? getAssetImage("assets/icons/bounty-unknown-native.png") : getLayerImage(renderedLayer);
      state.pinHits.push({ entity, point, size: Math.max(size, 24), item });
      context.globalAlpha = discovered ? 0.24 : entity.alphaReference || entity.chestReference ? 0.48 : 1;
      if ((iconRecord && iconRecord.ready) || (compositeBase && compositeBase.ready && compositeOverlay && compositeOverlay.ready)) {
        context.save();
        context.shadowColor = "rgba(0,0,0,.8)"; context.shadowBlur = lightweight ? 0 : 5;
        if (item && item.composite) {
          context.drawImage(compositeBase.image, point.x - size / 2, point.y - size / 2, size, size);
          const overlaySize = Math.round(size * 0.58);
          context.drawImage(compositeOverlay.image, point.x - overlaySize / 2, point.y - overlaySize / 2, overlaySize, overlaySize);
        } else if (item && ring) {
          context.beginPath(); context.arc(point.x, point.y, size / 2 - 2, 0, Math.PI * 2);
          context.fillStyle = "#000"; context.fill();
          context.beginPath(); context.arc(point.x, point.y, size / 2 - 2, 0, Math.PI * 2); context.clip();
          if (item.filter) context.filter = item.filter;
          context.drawImage(iconRecord.image, point.x - size / 2, point.y - size / 2, size, size);
          context.filter = "none";
          context.restore(); context.save();
          context.beginPath(); context.arc(point.x, point.y, size / 2 - 1, 0, Math.PI * 2);
          context.strokeStyle = ring; context.lineWidth = 1.5; context.stroke();
        } else {
          if (item && item.filter) context.filter = item.filter;
          context.drawImage(iconRecord.image, point.x - size / 2, point.y - size / 2, size, size);
          context.filter = "none";
        }
        context.restore();
      } else {
        drawEntityFallback(entity, point);
      }
      if (entity.sealedRealmReference) {
        const lock = getAssetImage("assets/icons/sealed-realm-lock-native.png");
        if (lock.ready) {
          const badgeX = point.x + size * 0.34, badgeY = point.y - size * 0.34, badgeSize = Math.max(14, size * 0.42);
          context.save();
          context.beginPath(); context.arc(badgeX, badgeY, badgeSize * 0.56, 0, Math.PI * 2);
          context.fillStyle = "#f3a43b"; context.strokeStyle = "#481c10"; context.lineWidth = 2; context.fill(); context.stroke();
          context.drawImage(lock.image, badgeX - badgeSize / 2, badgeY - badgeSize / 2, badgeSize, badgeSize);
          context.restore();
        }
      }
      context.globalAlpha = 1;
      if ((entity.alphaReference || entity.bountyReference) && discovered) {
        const cleared = getAssetImage("assets/icons/boss-cleared-native.png");
        if (cleared.ready) {
          const badgeSize = Math.max(14, size * 0.42);
          context.drawImage(cleared.image, point.x + size * 0.12, point.y + size * 0.12, badgeSize, badgeSize);
        }
      }
      drawVerticalIndicator(entity, point, size);
    }
    context.restore();
  }

  function drawMarkers(view, map) {
    if (!state.visibleLayers.has("custom")) return;
    for (const marker of state.markers) {
      if (Core.chooseMap(marker) !== state.mapId) continue;
      const point = Core.imageToScreen(Core.worldToImage(state.mapId, marker, map.width, map.height), state.camera, view);
      if (point.x < -40 || point.y < -40 || point.x > view.width + 40 || point.y > view.height + 40) continue;
      context.beginPath(); context.arc(point.x, point.y, 6, 0, Math.PI * 2);
      context.fillStyle = "#ffc56e"; context.shadowBlur = 14; context.shadowColor = "rgba(255,197,110,.55)"; context.fill(); context.shadowBlur = 0;
      context.fillStyle = "#f3fbf7"; context.font = "600 12px system-ui, sans-serif"; context.fillText(marker.name, point.x + 11, point.y + 4);
    }
  }

  function drawPlayer(view, map) {
    if (!state.visibleLayers.has("player") || !state.telemetry.connected || Core.chooseMap(state.telemetry.position) !== state.mapId) return;
    const point = Core.imageToScreen(Core.worldToImage(state.mapId, state.telemetry.position, map.width, map.height), state.camera, view);
    const yaw = Core.worldYawToScreenRadians(state.telemetry.rotation.yaw);
    const playerIcon = getLayerImage("player");
    context.save(); context.translate(point.x, point.y);
    if (playerIcon && playerIcon.ready) {
      const size = 36;
      context.rotate(yaw + Math.PI / 2);
      context.shadowBlur = 16; context.shadowColor = "rgba(255,226,67,.72)";
      context.drawImage(playerIcon.image, -size / 2, -size / 2, size, size);
    } else {
      context.rotate(yaw);
      context.beginPath(); context.moveTo(15, 0); context.lineTo(-9, -8); context.lineTo(-5, 0); context.lineTo(-9, 8); context.closePath();
      context.fillStyle = "#63e6b5"; context.shadowBlur = 20; context.shadowColor = "rgba(99,230,181,.8)"; context.fill(); context.shadowBlur = 0;
      context.strokeStyle = "#effff9"; context.lineWidth = 1.5; context.stroke();
    }
    context.restore();
  }

  function updateTelemetryUi() {
    const live = state.telemetry.connected;
    statusDot.className = `status-dot${live ? " live" : state.telemetry.status === "map-server-error" ? " error" : ""}`;
    statusText.textContent = live ? `Live · ${state.telemetry.world}` : state.telemetry.status.replaceAll("-", " ");
    coordinateValue.textContent = live ? `${Math.round(state.telemetry.position.x).toLocaleString()}, ${Math.round(state.telemetry.position.y).toLocaleString()}` : "—, —";
    altitudeValue.textContent = live ? `Altitude ${Math.round(state.telemetry.position.z || 0).toLocaleString()} · Heading ${Math.round(state.telemetry.rotation.yaw)}°` : "Start Palworld and enter a world";
  }

  function applyTelemetry(value) {
    const next = Core.normalizeTelemetry(value);
    const previous = state.lastPlayerPosition;
    if (next.connected && previous) {
      const deltaX = next.position.x - previous.x;
      const deltaY = next.position.y - previous.y;
      if (Math.hypot(deltaX, deltaY) >= movementFollowThreshold && !state.following) {
        state.following = true;
        updateFollowingUi();
      }
    }
    state.telemetry = next;
    state.lastPlayerPosition = next.connected
      ? { x: next.position.x, y: next.position.y }
      : null;
  }

  async function pollTelemetry() {
    try {
      const response = await fetch(`/api/telemetry?t=${Date.now()}`, { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      applyTelemetry(await response.json());
    } catch (_) { applyTelemetry({ status: "map-server-error" }); }
    updateTelemetryUi(); queueRender(); window.setTimeout(pollTelemetry, 250);
  }

  function acceptTelemetry(value) {
    applyTelemetry(value);
    updateTelemetryUi();
    queueRender();
  }

  function acceptEntities(value) {
    const items = value && Array.isArray(value.items) ? value.items : [];
    const inspectionItems = Array.isArray(window.ActorInspectionCandidates) ? window.ActorInspectionCandidates : [];
    const alphaBossReferences = Array.isArray(window.AlphaBossReferencePins) ? window.AlphaBossReferencePins : [];
    const chestReferences = Array.isArray(window.ChestReferencePins) ? window.ChestReferencePins : [];
    const bountyReferences = Array.isArray(window.BountyReferencePins) ? window.BountyReferencePins : [];
    const validEntities = [...items, ...alphaBossReferences, ...chestReferences, ...bountyReferences, ...inspectionItems]
      .filter((item) => item && typeof item.layer === "string" && Number.isFinite(item.x) && Number.isFinite(item.y));
    state.entities = validEntities.filter((entity, index, all) => {
      const mergeRadius = entity.layer === "fast-travel" ? fastTravelMergeRadius
        : entity.layer === "random-events" ? randomEventMergeRadius
        : null;
      if (!mergeRadius) return true;
      return !all.slice(0, index).some((existing) => existing.layer === entity.layer
        && entityMap(existing) === entityMap(entity)
        && distance2d(existing, entity) <= mergeRadius);
    });
    state.preparedEntities = state.entities.map((entity) => {
      const mapId = entityMap(entity);
      const map = Core.MAPS[mapId];
      return { entity, mapId, image: Core.worldToImage(mapId, entity, map.width, map.height) };
    });
    state.entityCounts = new Map();
    for (const item of items) {
      if (item && typeof item.layer === "string") state.entityCounts.set(item.layer, (state.entityCounts.get(item.layer) || 0) + 1);
    }
    const countSignature = JSON.stringify([...state.entityCounts].sort(([left], [right]) => left.localeCompare(right)));
    if (countSignature !== state.entityCountSignature) {
      state.entityCountSignature = countSignature;
      renderLayerGroups(layerSearch.value);
    }
    queueRender();
  }

  async function startTelemetry() {
    if (window.palworldDesktop) {
      window.palworldDesktop.onTelemetry(acceptTelemetry);
      window.palworldDesktop.onEntities(acceptEntities);
      acceptTelemetry(await window.palworldDesktop.getTelemetry());
      acceptEntities(await window.palworldDesktop.getEntities());
      return;
    }
    pollTelemetry();
  }

  function updateFollowingUi() {
    followButton.classList.toggle("active", state.following);
    followButton.textContent = state.following ? "Following player" : "Free pan";
  }

  function setFollowing(value) { state.following = value; updateFollowingUi(); queueRender(); }
  function setPlacing(value) {
    state.placing = value; panel.classList.toggle("placing", value); addMarkerCallout.classList.toggle("hidden", !value);
    markerHint.textContent = value ? "Click the map to choose a location." : "Stored only in this browser.";
  }

  function renderLayerGroups(query = "") {
    const needle = query.trim().toLocaleLowerCase();
    const hadGroups = layerGroups.childElementCount > 0;
    const openGroups = new Set([...layerGroups.querySelectorAll("details.layer-group[open]")].map((section) => section.dataset.group));
    layerGroups.replaceChildren();
    for (const group of window.LayerCatalog) {
      const items = group.items.filter((item) => !needle || item.label.toLocaleLowerCase().includes(needle));
      if (!items.length) continue;
      const section = document.createElement("details");
      section.className = "layer-group";
      section.dataset.group = group.id;
      section.open = needle ? true : hadGroups ? openGroups.has(group.id) : group.open !== false;
      const summary = document.createElement("summary");
      const label = document.createElement("span");
      label.textContent = group.label;
      const groupCount = document.createElement("small");
      groupCount.textContent = `${items.filter((item) => state.visibleLayers.has(item.id)).length}/${items.length}`;
      summary.append(label, groupCount);
      attachDetailsChevron(summary);
      const grid = document.createElement("div");
      grid.className = "layer-grid";
      for (const item of items) {
        const button = document.createElement("button");
        const active = state.visibleLayers.has(item.id);
        button.type = "button";
        button.className = `layer-chip${active ? " active" : ""}`;
        button.dataset.layer = item.id;
        button.setAttribute("aria-pressed", String(active));
        const icon = item.composite ? document.createElement("span") : item.image ? document.createElement("img") : document.createElement("i");
        if (item.composite) {
          icon.className = "composite-icon";
          const base = document.createElement("img");
          const overlay = document.createElement("img");
          base.src = item.composite.base; base.alt = ""; base.className = "composite-base";
          overlay.src = item.composite.overlay; overlay.alt = ""; overlay.className = "composite-overlay";
          icon.append(base, overlay);
        } else if (item.image) {
          icon.src = item.image;
          icon.alt = "";
          if (item.filter) icon.style.filter = item.filter;
          if (item.ring) { icon.classList.add("ringed"); icon.style.setProperty("--ring-color", item.ring); }
          icon.addEventListener("error", () => {
            const fallback = document.createElement("i");
            fallback.textContent = item.symbol;
            icon.replaceWith(fallback);
          }, { once: true });
        } else {
          icon.textContent = item.symbol;
        }
        const name = document.createElement("span");
        name.textContent = item.label;
        const count = document.createElement("small");
        const loaded = state.entityCounts.get(item.id) || 0;
        count.textContent = loaded ? `${loaded} live` : item.count === null ? "—" : String(item.count);
        count.title = loaded ? `${loaded} currently loaded by the game` : "Reference map count";
        button.append(icon, name, count);
        button.addEventListener("click", () => {
          if (active) state.visibleLayers.delete(item.id); else state.visibleLayers.add(item.id);
          renderLayerGroups(layerSearch.value);
          queueRender();
        });
        grid.appendChild(button);
      }
      if (group.id === "pals") {
        const search = document.createElement("label");
        search.className = "pal-filter-search";
        const searchIcon = createLucideIcon("search", { size: 14, className: "pal-filter-search-icon" });
        const input = document.createElement("input");
        input.type = "search";
        input.placeholder = "Search for Pal";
        input.autocomplete = "off";
        input.value = state.palQuery;
        input.addEventListener("input", () => {
          state.palQuery = input.value;
          const palNeedle = input.value.trim().toLocaleLowerCase();
          for (const chip of grid.querySelectorAll(".layer-chip")) {
            chip.classList.toggle("filter-hidden", Boolean(palNeedle) && !chip.textContent.toLocaleLowerCase().includes(palNeedle));
          }
        });
        search.append(searchIcon, input);
        section.append(summary, search, grid);
      } else {
        section.append(summary, grid);
      }
      layerGroups.appendChild(section);
    }
    layerSummary.textContent = `${state.visibleLayers.size} active`;
  }

  function setAllLayers(visible) {
    state.visibleLayers.clear();
    if (visible) for (const group of window.LayerCatalog) for (const item of group.items) state.visibleLayers.add(item.id);
    renderLayerGroups(layerSearch.value);
    queueRender();
  }

  function renderMarkerList() {
    markerList.replaceChildren();
    if (!state.markers.length) { const empty = document.createElement("div"); empty.className = "empty-markers"; empty.textContent = "No markers yet"; markerList.appendChild(empty); return; }
    state.markers.forEach((marker, index) => {
      const row = document.createElement("div"); row.className = "marker-item";
      const dot = document.createElement("i"); const name = document.createElement("span"); name.className = "marker-name"; name.textContent = marker.name;
      const remove = document.createElement("button"); remove.className = "marker-delete"; remove.type = "button"; remove.setAttribute("aria-label", `Delete ${marker.name}`);
      remove.appendChild(createLucideIcon("x", { size: 14 }));
      remove.addEventListener("click", () => { state.markers.splice(index, 1); saveMarkers(); renderMarkerList(); queueRender(); });
      row.append(dot, name, remove); markerList.appendChild(row);
    });
  }

  function canvasPoint(event) { const bounds = canvas.getBoundingClientRect(); return { x: event.clientX - bounds.left, y: event.clientY - bounds.top }; }
  function findPin(point) {
    for (let index = state.pinHits.length - 1; index >= 0; index--) {
      const hit = state.pinHits[index];
      if (Math.hypot(point.x - hit.point.x, point.y - hit.point.y) <= hit.size / 2) return hit;
    }
    return null;
  }
  function cancelTooltipHide() {
    if (state.tooltipHideTimer !== null) window.clearTimeout(state.tooltipHideTimer);
    state.tooltipHideTimer = null;
  }
  function hidePinTooltip() {
    cancelTooltipHide();
    state.tooltipEntity = null;
    pinTooltip.classList.add("hidden");
  }
  function schedulePinTooltipHide() {
    cancelTooltipHide();
    state.tooltipHideTimer = window.setTimeout(hidePinTooltip, 220);
  }
  function showPinTooltip(hit) {
    cancelTooltipHide();
    const { entity, item, point } = hit;
    state.tooltipEntity = entity;
    const tower = getTowerDetails(entity);
    pinTooltipTitle.textContent = tower ? `Lv${tower.level} ${tower.group} Tower` : entity.investigationPin && entity.className ? entity.className : entity.sealedRealmReference && item ? item.label : (entity.alphaReference || entity.chestReference) && entity.name ? entity.name : item ? item.label : entity.layer.replaceAll("-", " ");
    const relation = verticalRelation(entity);
    const verticalText = relation ? ` · ${relation.direction === "above" ? "Above" : "Below"} player by ${Math.round(Math.abs(relation.difference) / 100)} m` : "";
    const levelText = entity.alphaReference && Number.isFinite(entity.levelMin) ? ` · Level ${entity.levelMin}${entity.levelMax !== entity.levelMin ? `–${entity.levelMax}` : ""}` : "";
    const referenceText = entity.alphaReference ? entity.sealedRealmReference ? "Sealed Realm Alpha Pal" : "Alpha Pal" : entity.bountyReference ? "Bounty Target" : entity.chestReference ? "Chest" : null;
    const towerText = tower ? `${tower.npc} + ${tower.pal}` : null;
    pinTooltipDetail.textContent = `${towerText || referenceText || (item && item.label) || entity.name || "Map location"}${levelText}${verticalText}`;
    const logical = Core.worldToLogical(state.mapId, entity);
    pinTooltipCoordinates.textContent = `World ${Math.round(entity.x).toLocaleString()}, ${Math.round(entity.y).toLocaleString()}, ${Math.round(entity.z || 0).toLocaleString()} · Map ${Math.round(logical.x)}, ${Math.round(logical.y)}`;
    if (supportsDiscovery(entity)) {
      const discovered = state.discoveredNodes.has(discoveryKey(entity));
      pinDiscoveredButton.textContent = entity.alphaReference || entity.bountyReference ? discovered ? "Mark not cleared" : "Mark as cleared" : discovered ? "Mark undiscovered" : "Mark as discovered";
      pinDiscoveredButton.classList.remove("hidden");
    } else pinDiscoveredButton.classList.add("hidden");
    pinTooltip.classList.remove("hidden");
    const maxLeft = Math.max(8, panel.clientWidth - pinTooltip.offsetWidth - 8);
    const maxTop = Math.max(8, panel.clientHeight - pinTooltip.offsetHeight - 8);
    pinTooltip.style.left = `${Math.min(maxLeft, point.x + 14)}px`;
    pinTooltip.style.top = `${Math.min(maxTop, point.y + 14)}px`;
  }

  async function openActorDebug(entity, item) {
    actorDebugPanel.classList.remove("hidden");
    actorDebugTitle.textContent = entity.className || entity.name || (item && item.label) || entity.layer;
    actorDebugStatus.textContent = "Reading actor data…";
    state.debugContext = { entity, liveInspection: null };
    actorDebugNotes.value = state.actorNotes[actorNoteKey(entity)] || "";
    actorDebugNotesStatus.textContent = actorDebugNotes.value ? "Saved locally and included with this actor's debug context." : "No note saved for this actor.";
    renderDebugContext();
    const actorAddress = entity.actorAddress || entity.id;
    if (!window.palworldDesktop || typeof window.palworldDesktop.inspectActor !== "function" || typeof actorAddress !== "string" || !/^[0-9A-F]{8,16}$/i.test(actorAddress)) {
      actorDebugStatus.textContent = "Static/reference pin — no live actor address is available.";
      return;
    }
    try {
      const inspection = await window.palworldDesktop.inspectActor(actorAddress);
      actorDebugStatus.textContent = `Captured ${inspection.actor.properties.length} properties and ${inspection.actor.nestedObjects.length} nested objects.`;
      state.debugContext.liveInspection = inspection.actor;
      renderDebugContext();
    } catch (error) {
      actorDebugStatus.textContent = error && error.message ? error.message : "Actor inspection failed.";
    }
  }
  canvas.addEventListener("pointerdown", (event) => {
    if (state.placing) return;
    state.dragging = true; state.dragMoved = false; state.pointerStart = { x: event.clientX, y: event.clientY }; state.cameraStart = { x: state.camera.x, y: state.camera.y };
    canvas.setPointerCapture(event.pointerId);
  });
  canvas.addEventListener("pointermove", (event) => {
    if (!state.dragging) {
      const hit = findPin(canvasPoint(event));
      if (hit) showPinTooltip(hit); else schedulePinTooltipHide();
      return;
    }
    const deltaX = event.clientX - state.pointerStart.x;
    const deltaY = event.clientY - state.pointerStart.y;
    if (!state.dragMoved && Math.hypot(deltaX, deltaY) < 4) return;
    if (!state.dragMoved) { state.dragMoved = true; setFollowing(false); panel.classList.add("dragging"); }
    state.camera.x = state.cameraStart.x - deltaX / state.camera.zoom;
    state.camera.y = state.cameraStart.y - deltaY / state.camera.zoom; queueRender();
  });
  canvas.addEventListener("pointerup", (event) => {
    if (state.placing) {
      const map = Core.MAPS[state.mapId];
      const world = Core.imageToWorld(state.mapId, Core.screenToImage(canvasPoint(event), state.camera, viewport()), map.width, map.height);
      const name = window.prompt("Marker name", `Marker ${state.markers.length + 1}`);
      if (name && name.trim()) { state.markers.push({ id: Date.now(), name: name.trim().slice(0, 80), x: world.x, y: world.y }); saveMarkers(); renderMarkerList(); }
      setPlacing(false); queueRender(); return;
    }
    const wasDragging = state.dragMoved;
    state.dragging = false; state.dragMoved = false; panel.classList.remove("dragging"); if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    if (!wasDragging && state.debugMode) {
      const hit = findPin(canvasPoint(event));
      if (hit) openActorDebug(hit.entity, hit.item);
    }
  });
  canvas.addEventListener("wheel", (event) => {
    event.preventDefault(); const view = viewport(); const cursor = canvasPoint(event); const before = Core.screenToImage(cursor, state.camera, view);
    state.camera.zoom = Core.clamp(state.camera.zoom * Math.exp(-event.deltaY * 0.0015), 0.03, 4);
    state.camera.x = before.x - (cursor.x - view.width / 2) / state.camera.zoom; state.camera.y = before.y - (cursor.y - view.height / 2) / state.camera.zoom;
    queueRender();
  }, { passive: false });
  pinDiscoveredButton.addEventListener("click", () => {
    const entity = state.tooltipEntity;
    if (!entity || !supportsDiscovery(entity)) return;
    const key = discoveryKey(entity);
    if (state.discoveredNodes.has(key)) state.discoveredNodes.delete(key); else state.discoveredNodes.add(key);
    saveDiscoveredNodes();
    pinDiscoveredButton.textContent = entity.alphaReference || entity.bountyReference ? state.discoveredNodes.has(key) ? "Mark not cleared" : "Mark as cleared" : state.discoveredNodes.has(key) ? "Mark undiscovered" : "Mark as discovered";
    queueRender();
  });
  pinTooltip.addEventListener("pointerenter", cancelTooltipHide);
  pinTooltip.addEventListener("pointerleave", schedulePinTooltipHide);
  actorDebugNotes.addEventListener("input", saveCurrentActorNote);
  if (exportActorNotes) {
    exportActorNotes.addEventListener("click", () => {
      exportActorNotesFile();
    });
  }
  if (importActorNotes) {
    importActorNotes.addEventListener("click", () => actorNotesFile && actorNotesFile.click());
  }
  if (actorNotesFile) {
    actorNotesFile.addEventListener("change", async () => {
      const file = actorNotesFile.files && actorNotesFile.files[0];
      if (!file) return;
      try {
        const text = await file.text();
        const result = importActorNotesFromText(text);
        const summary = `Imported actor notes: ${result.imported} new, ${result.unchanged} existing, ${result.skipped} skipped.`;
        const status = document.getElementById("statusText");
        const markerHint = document.getElementById("markerHint");
        if (status) status.textContent = summary;
        if (markerHint) markerHint.textContent = summary;
      } catch (error) {
        const status = document.getElementById("statusText");
        if (status) status.textContent = `Import failed: ${error.message}`;
      } finally {
        if (actorNotesFile) actorNotesFile.value = "";
      }
    });
  }
  importOverwolfDiscoveries.addEventListener("click", () => overwolfDiscoveryFile && overwolfDiscoveryFile.click());
  overwolfDiscoveryFile.addEventListener("change", async () => {
    const file = overwolfDiscoveryFile.files && overwolfDiscoveryFile.files[0];
    if (!file) return;
    try {
      const text = await file.text();
      const result = mergeDiscoveredNodesFromOverwolf(text);
      showImportSummary(result);
    } catch (error) {
      const status = document.getElementById("statusText");
      if (status) status.textContent = `Import failed: ${error.message}`;
      const markerHint = document.getElementById("markerHint");
      if (markerHint) markerHint.textContent = error.message;
    } finally {
      if (overwolfDiscoveryFile) overwolfDiscoveryFile.value = "";
    }
  });

  image.addEventListener("load", () => { assetStatus.textContent = `${Core.MAPS[state.mapId].label} · ${image.naturalWidth}×${image.naturalHeight}`; queueRender(); });
  image.addEventListener("error", () => { assetStatus.textContent = "Map asset missing — run Assets/Install-MapAssets.ps1"; });
  document.querySelectorAll(".map-tab").forEach((button) => button.addEventListener("click", () => setMap(button.dataset.map, false)));
  document.getElementById("zoomInButton").addEventListener("click", () => { state.camera.zoom = Core.clamp(state.camera.zoom * 1.4, 0.03, 4); queueRender(); });
  document.getElementById("zoomOutButton").addEventListener("click", () => { state.camera.zoom = Core.clamp(state.camera.zoom / 1.4, 0.03, 4); queueRender(); });
  document.getElementById("recenterButton").addEventListener("click", fitMap);
  followButton.addEventListener("click", () => setFollowing(!state.following));
  document.getElementById("addMarkerButton").addEventListener("click", () => setPlacing(!state.placing));
  document.getElementById("showAllLayers").addEventListener("click", () => setAllLayers(true));
  document.getElementById("hideAllLayers").addEventListener("click", () => setAllLayers(false));
  layerSearch.addEventListener("input", () => renderLayerGroups(layerSearch.value));
  hideTamedPals.checked = state.hideTamedPals;
  hideTamedPals.addEventListener("change", () => {
    state.hideTamedPals = hideTamedPals.checked;
    localStorage.setItem("palworld-live-map-hide-tamed", String(state.hideTamedPals));
    queueRender();
  });
  debugMode.checked = state.debugMode;
  debugMode.addEventListener("change", () => {
    state.debugMode = debugMode.checked;
    localStorage.setItem("palworld-live-map-debug", String(state.debugMode));
    if (!state.debugMode) actorDebugPanel.classList.add("hidden");
  });
  actorDebugClose.addEventListener("click", () => actorDebugPanel.classList.add("hidden"));
  document.getElementById("sidebarToggle").addEventListener("click", () => {
    const collapsed = document.body.classList.toggle("sidebar-collapsed");
    setSidebarToggle(collapsed);
    window.setTimeout(queueRender, 180);
  });
  document.querySelectorAll(".utility-panel > summary").forEach((summary) => attachDetailsChevron(summary));
  if (filterSearchIcon) filterSearchIcon.replaceChildren(createLucideIcon("search", { size: 16 }));
  actorDebugClose.replaceChildren(createLucideIcon("x", { size: 18 }));
  if (zoomInButton) zoomInButton.replaceChildren(createLucideIcon("plus", { size: 16 }));
  if (zoomOutButton) zoomOutButton.replaceChildren(createLucideIcon("minus", { size: 16 }));
  setSidebarToggle(false);
  window.addEventListener("resize", queueRender);
  window.addEventListener("keydown", (event) => { if (event.key === "Escape") setPlacing(false); });

  renderLayerGroups(); renderMarkerList(); updateTelemetryUi(); setMap("world", true); startTelemetry();
})();
