import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const diagnostics = path.join(root, "Diagnostics");
const actorPath = path.join(diagnostics, "world-inspection.jsonl");
const pinPath = path.join(root, "Data", "palworld-gg-map-pins.json");
const outputJson = path.join(diagnostics, "actor-pin-comparison.json");
const outputCsv = path.join(diagnostics, "actor-pin-comparison.csv");
const outputHtml = path.join(diagnostics, "Actor-Pin-Comparison.html");
const exactThreshold = 250;
const nearbyThreshold = 2000;
const cellSize = nearbyThreshold;

const noiseClassPatterns = [
  [/^BP_BuildObject_/, "ordinary player/base build piece"],
  [/^StaticMeshActor$/, "generic environment mesh"],
  [/^WorldPartitionHLOD$/, "world-partition rendering proxy"],
  [/^LandscapeStreamingProxy$/, "landscape streaming proxy"],
  [/^NiagaraActor$/, "visual-effect actor"],
  [/^(?:Limit|Blocking|NavMesh).*Volume/i, "generic world volume"],
  [/^BP_PalWorldSettings_C$/, "global world settings actor"],
  [/^BP_(?:PalPlayer|Player|Throw|BackWeapon)/, "player or equipped-item runtime actor"],
  [/^PalNetworkTransmitter$/, "network runtime actor"],
];

function assessMatch(match) {
  const noise = noiseClassPatterns.find(([pattern]) => pattern.test(match.actorClass));
  if (noise) return { assessment: "noise", reason: noise[1] };
  const confirmed =
    match.confidence === "exact" && ((/^BP_LevelObject_Relic/.test(match.actorClass) && match.pinType === "effigy") ||
    (match.actorClass === "BP_LevelObject_Note_C" && match.pinType === "note") ||
    (/^BP_LevelObject_TowerFastTravelPoint_C$/.test(match.actorClass) && match.pinType === "fast-travel") ||
    (/^BP_PalBossTower(?:_MiddleBoss)?_C$/.test(match.actorClass) && match.pinType === "syndicate-tower") ||
    (match.actorClass === "BP_LevelObject_OilField_C" && match.pinName === "oil") ||
    (/^BP_MapObject_DamagableRock/.test(match.actorClass) && match.pinType === "material") ||
    (/^BP_DungeonFixedEntrance_/.test(match.actorClass) && match.pinType === "sealed-realm") ||
    (/^BP_PalSpawner_/.test(match.actorClass) && match.pinType === "alpha-pal"));
  if (confirmed) return { assessment: "confirmed", reason: "class semantics and coordinates agree" };
  if (Math.hypot(match.actorX, match.actorY) <= 100) return { assessment: "noise", reason: "world-origin/default transform; not a reliable map placement" };
  if (match.confidence !== "exact") return { assessment: "candidate", reason: "proximity only; needs class/property confirmation" };
  return { assessment: "candidate", reason: "coordinate match; class meaning still needs verification" };
}

function explainActor(actorClass, pinType, assessment) {
  const rules = [
    [/^BP_LevelObject_TowerLockBarrier_C$/, "The interactable lock/energy-dome barrier attached to a locked fast-travel tower. Captured evidence: BarrierMesh, BP_InteractableBox, GimmickObjectIds, and bLocked.", "Do not use as the primary pin. Use BP_LevelObject_TowerFastTravelPoint_C; this actor may only indicate locked state."],
    [/^BP_LevelObject_TowerFastTravelPoint_C$/, "The actual fast-travel interaction point placed at an eagle statue/tower.", "Use as the primary fast-travel scanner actor."],
    [/^BP_pal_map_small_tower_C$/i, "The visible small fast-travel tower/statue map structure. It is colocated with the interaction point.", "Useful as fallback evidence, but prefer TowerFastTravelPoint to avoid duplicate pins."],
    [/^BP_PalBossTower(?:_MiddleBoss)?_C$/, "A Syndicate Tower level object—the structure used for humanoid tower-boss encounters, not an Alpha Pal.", "Use for Syndicate Tower pins only."],
    [/^BP_LevelObject_Relic(?:_.+)?_C$/, "A collectible effigy level object. The suffix identifies the Pal represented by non-Lifmunk variants.", "Use directly for effigy pins and discovered-state tracking."],
    [/^BP_LevelObject_Note_C$/, "A collectible journal/note level object.", "Use directly for Note pins and discovered-state tracking."],
    [/^BP_DungeonFixedEntrance_/, "A fixed dungeon or sealed-realm entrance object. The biome suffix describes its environment rather than its boss.", "Use for entrance pins; determine dungeon versus sealed realm from coordinates or nested data."],
    [/^BP_PalSpawner_/, "A Pal spawn controller. FBOSS in the class usually denotes a field/Alpha boss spawn configuration rather than the live Pal actor.", "Use when the coordinate and palworld.gg boss agree; map the spawner class to the specific Pal icon."],
    [/^BP_LevelObject_OilField_C$/, "A natural crude-oil field/resource point.", "Use directly for oil resource pins."],
    [/^BP_MapObject_DamagableRock/, "A destructible natural rock/resource node. This captured variant aligns with Paldium deposits.", "Use only after mapping each class variant to its resource type."],
    [/^BP_LockGimmickDestructionTarget_C$/, "A helper/destruction target belonging to a lock gimmick, not a standalone map location.", "Ignore as a primary pin; associate it with its owning gimmick if state detection is needed."],
    [/^BP_LevelObject_ItemPickupTower_C$/, "A tower-like pickup/level-object helper. Nearby matches can belong to several unrelated pin types.", "Do not classify from proximity alone; inspect its owning object and identifiers."],
    [/^BP_Item_/, "A live dropped or pickup item actor. Its coordinates can reflect player activity rather than a permanent world spawn.", "Ignore for static map pins unless specifically building a live-loot layer."],
    [/^BP_PalMapObjectFarmCrop_/, "A crop growing in a player-built farm plot.", "Ignore for world-map discovery."],
    [/^BP_BuildObject_/, "An ordinary player-built base piece, workstation, storage object, farm, or decoration.", "Ignore for static map pins."],
    [/^StaticMeshActor$/, "A generic placed 3D environment mesh with no reliable gameplay identity.", "Ignore unless nested asset names provide unique evidence."],
    [/^WorldPartitionHLOD$/, "A rendering proxy used to display distant groups of world geometry.", "Always ignore for scanner classification."],
    [/^LandscapeStreamingProxy$/, "A streamed terrain section used by Unreal Engine.", "Always ignore for scanner classification."],
    [/^NiagaraActor$/, "A visual-effects actor such as particles, glow, smoke, or weather.", "Ignore unless creating an effects/debug layer."],
    [/Volume/i, "An invisible trigger, collision, navigation, or gameplay boundary volume.", "Do not create a pin from it without a uniquely identified owner."],
    [/Spawner/i, "A spawn-controller actor whose class or properties may identify what appears in this area.", "Inspect class suffixes and nested spawn data before confirming."],
  ];
  const match = rules.find(([pattern]) => pattern.test(actorClass));
  if (match) return { meaning: match[1], recommendation: match[2] };
  const readable = actorClass.replace(/^BP_/, "").replace(/_C$/, "").replaceAll("_", " ").replace(/([a-z])([A-Z])/g, "$1 $2");
  return {
    meaning: `Unclassified Unreal actor. Its internal name reads roughly as “${readable}”; this is a clue, not a confirmed gameplay label.`,
    recommendation: assessment === "confirmed" ? `Coordinate and class semantics support using it for ${pinType}.` : "Review nested properties/owner and map examples before using it as a scanner rule.",
  };
}

const actors = fs.readFileSync(actorPath, "utf8").split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line))
  .filter((entry) => entry.type === "actor" && Number.isFinite(entry.actor?.x) && Number.isFinite(entry.actor?.y)).map((entry) => entry.actor);
const pinDocument = JSON.parse(fs.readFileSync(pinPath, "utf8"));
const pins = pinDocument.markers.filter((pin) => Number.isFinite(pin.worldX) && Number.isFinite(pin.worldY));

const grid = new Map();
const cellKey = (x, y) => `${Math.floor(x / cellSize)},${Math.floor(y / cellSize)}`;
for (const pin of pins) {
  const key = cellKey(pin.worldX, pin.worldY);
  if (!grid.has(key)) grid.set(key, []);
  grid.get(key).push(pin);
}

function candidates(actor) {
  const cellX = Math.floor(actor.x / cellSize), cellY = Math.floor(actor.y / cellSize);
  const result = [];
  for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) result.push(...(grid.get(`${cellX + dx},${cellY + dy}`) || []));
  return result;
}

const matches = [];
for (const actor of actors) {
  let nearest = null, nearestDistance = Infinity;
  for (const pin of candidates(actor)) {
    const distance = Math.hypot(actor.x - pin.worldX, actor.y - pin.worldY);
    if (distance < nearestDistance) { nearest = pin; nearestDistance = distance; }
  }
  if (!nearest || nearestDistance > nearbyThreshold) continue;
  const match = {
    confidence: nearestDistance <= exactThreshold ? "exact" : "nearby",
    distance: Math.round(nearestDistance * 10) / 10,
    actorId: actor.id,
    actorClass: actor.className,
    actorName: actor.objectName,
    actorX: actor.x,
    actorY: actor.y,
    actorZ: actor.z,
    pinId: nearest.id,
    pinMap: nearest.map,
    pinCategory: nearest.category,
    pinType: nearest.type,
    pinName: nearest.name,
    pinX: nearest.worldX,
    pinY: nearest.worldY,
    pinMapX: nearest.mapX,
    pinMapY: nearest.mapY,
    palId: nearest.palId,
    subtype: nearest.subtype,
  };
  Object.assign(match, assessMatch(match));
  matches.push(match);
}

const assessmentRank = { confirmed: 0, candidate: 1, noise: 2 };
matches.sort((a, b) => assessmentRank[a.assessment] - assessmentRank[b.assessment] || a.distance - b.distance || a.actorClass.localeCompare(b.actorClass));
const groupsMap = Map.groupBy(matches, (match) => `${match.actorClass}\u0000${match.pinCategory}\u0000${match.pinType}`);
const groups = [...groupsMap.entries()].map(([key, rows]) => {
  const [actorClass, pinCategory, pinType] = key.split("\u0000");
  return {
    actorClass, pinCategory, pinType, count: rows.length,
    exact: rows.filter((row) => row.confidence === "exact").length,
    confirmed: rows.filter((row) => row.assessment === "confirmed").length,
    noise: rows.filter((row) => row.assessment === "noise").length,
    assessment: rows.every((row) => row.assessment === "noise") ? "noise" : rows.some((row) => row.assessment === "confirmed") ? "confirmed" : "candidate",
    minDistance: Math.min(...rows.map((row) => row.distance)),
    averageDistance: Math.round(rows.reduce((sum, row) => sum + row.distance, 0) / rows.length * 10) / 10,
    samplePin: rows[0].pinName,
  };
}).sort((a, b) => assessmentRank[a.assessment] - assessmentRank[b.assessment] || b.confirmed - a.confirmed || b.exact - a.exact || b.count - a.count || a.actorClass.localeCompare(b.actorClass));

const reviewGroups = [...Map.groupBy(matches, (match) => match.actorClass).entries()].map(([actorClass, rows]) => {
  const mappingGroups = [...Map.groupBy(rows, (row) => `${row.pinCategory}\u0000${row.pinType}`).entries()]
    .map(([key, mappingRows]) => ({ key, rows: mappingRows })).sort((a, b) => b.rows.length - a.rows.length);
  const dominant = mappingGroups[0];
  const [pinCategory, pinType] = dominant.key.split("\u0000");
  const sorted = [...dominant.rows].sort((a, b) => a.distance - b.distance);
  const exampleIndexes = [...new Set([0, Math.floor((sorted.length - 1) / 2), sorted.length - 1])];
  const autoAssessment = rows.every((row) => row.assessment === "noise") ? "noise"
    : rows.some((row) => row.assessment === "confirmed") && mappingGroups.length === 1 ? "confirmed" : "candidate";
  const explanation = explainActor(actorClass, pinType, autoAssessment);
  return {
    actorClass,
    autoAssessment,
    count: rows.length,
    exact: rows.filter((row) => row.confidence === "exact").length,
    pinCategory,
    pinType,
    consistency: Math.round(dominant.rows.length / rows.length * 1000) / 10,
    mappingCount: mappingGroups.length,
    meaning: explanation.meaning,
    recommendation: explanation.recommendation,
    examples: exampleIndexes.map((index) => ({
      distance: sorted[index].distance,
      pinName: sorted[index].pinName,
      actorX: Math.round(sorted[index].actorX),
      actorY: Math.round(sorted[index].actorY),
      mapX: sorted[index].pinMapX,
      mapY: sorted[index].pinMapY,
      map: sorted[index].pinMap,
    })),
  };
}).sort((a, b) => assessmentRank[a.autoAssessment] - assessmentRank[b.autoAssessment] || b.consistency - a.consistency || b.exact - a.exact || b.count - a.count || a.actorClass.localeCompare(b.actorClass));

const result = {
  schemaVersion: 1,
  comparedAtUtc: new Date().toISOString(),
  thresholds: { exact: exactThreshold, nearby: nearbyThreshold, unit: "Unreal world units" },
  summary: {
    actorsWithCoordinates: actors.length,
    pins: pins.length,
    matches: matches.length,
    exactMatches: matches.filter((match) => match.confidence === "exact").length,
    nearbyMatches: matches.filter((match) => match.confidence === "nearby").length,
    confirmedMatches: matches.filter((match) => match.assessment === "confirmed").length,
    candidateMatches: matches.filter((match) => match.assessment === "candidate").length,
    noiseMatches: matches.filter((match) => match.assessment === "noise").length,
    uniqueActorsMatched: new Set(matches.map((match) => match.actorId)).size,
    uniquePinsMatched: new Set(matches.map((match) => match.pinId)).size,
  },
  reviewGroups,
  groups,
  matches,
};
fs.writeFileSync(outputJson, JSON.stringify(result, null, 2));

const csvColumns = ["assessment", "reason", "confidence", "distance", "actorClass", "actorName", "actorX", "actorY", "actorZ", "pinMap", "pinCategory", "pinType", "pinName", "pinX", "pinY", "pinMapX", "pinMapY", "palId", "subtype"];
const csv = [csvColumns.join(","), ...matches.map((row) => csvColumns.map((column) => `"${String(row[column] ?? "").replaceAll('"', '""')}"`).join(","))].join("\n");
fs.writeFileSync(outputCsv, csv);

const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
const reviewRows = reviewGroups.map((group) => {
  const examples = group.examples.map((example) => {
    return `<div><strong>${escapeHtml(example.pinName)}</strong> · ${example.distance}u<small>world ${example.actorX}, ${example.actorY} · map ${example.mapX}, ${example.mapY}</small></div>`;
  }).join("");
  const search = escapeHtml(`${group.actorClass} ${group.pinCategory} ${group.pinType} ${group.meaning} ${group.recommendation} ${group.examples.map((example) => example.pinName).join(" ")}`.toLowerCase());
  return `<tr class="review-row" data-class="${escapeHtml(group.actorClass)}" data-auto="${group.autoAssessment}" data-material="${group.pinCategory === "materials"}" data-search="${search}"><td class="decision-cell"></td><td><span class="badge ${group.autoAssessment}">${group.autoAssessment}</span></td><td><strong>${escapeHtml(group.actorClass)}</strong><p>${escapeHtml(group.meaning)}</p><small><strong>Recommendation:</strong> ${escapeHtml(group.recommendation)}</small></td><td>${group.count}<small>${group.exact} exact</small></td><td><strong>${group.consistency}%</strong><small>${group.mappingCount} pin type${group.mappingCount === 1 ? "" : "s"}</small></td><td>${escapeHtml(group.pinCategory)}<small>${escapeHtml(group.pinType)}</small></td><td class="examples">${examples}</td><td class="remark-cell"><textarea rows="4" placeholder="Type your remark…" aria-label="Remark for ${escapeHtml(group.actorClass)}"></textarea></td><td class="actions"><button data-action="confirmed">Confirm</button><button data-action="noise">Noise</button><button data-action="skipped">Skip</button></td></tr>`;
}).join("");
const groupRows = groups.map((group) => `<tr class="filter-row" data-noise="${group.assessment === "noise"}" data-material="${group.pinCategory === "materials"}" data-search="${escapeHtml(`${group.actorClass} ${group.pinCategory} ${group.pinType} ${group.samplePin}`.toLowerCase())}"><td><span class="badge ${group.assessment}">${group.assessment}</span></td><td>${group.count}</td><td>${group.exact}</td><td>${group.confirmed}</td><td>${escapeHtml(group.actorClass)}</td><td>${escapeHtml(group.pinCategory)}</td><td>${escapeHtml(group.pinType)}</td><td>${group.minDistance}</td><td>${group.averageDistance}</td><td>${escapeHtml(group.samplePin)}</td></tr>`).join("");
const matchRows = matches.map((match) => {
  const search = escapeHtml(`${match.actorClass} ${match.actorName} ${match.pinCategory} ${match.pinType} ${match.pinName} ${match.palId}`.toLowerCase());
  return `<tr class="filter-row match" data-noise="${match.assessment === "noise"}" data-material="${match.pinCategory === "materials"}" data-search="${search}"><td><span class="badge ${match.assessment}">${match.assessment}</span><small>${escapeHtml(match.reason)}</small></td><td><span class="badge ${match.confidence}">${match.confidence}</span></td><td>${match.distance}</td><td><strong>${escapeHtml(match.actorClass)}</strong><small>${escapeHtml(match.actorName)}</small></td><td>${escapeHtml(match.pinName)}<small>${escapeHtml(`${match.pinCategory} / ${match.pinType}`)}</small></td><td>${Math.round(match.actorX)}, ${Math.round(match.actorY)}</td><td>${match.pinMapX}, ${match.pinMapY}</td></tr>`;
}).join("");
const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Actor to Map Pin Comparison</title><style>
:root{color-scheme:dark;background:#07131b;color:#dcecf4;font:14px/1.45 system-ui,sans-serif}body{margin:0;padding:24px}main{max-width:1700px;margin:auto}h1{margin-bottom:3px}h2{margin-top:28px}.muted,small{display:block;color:#88a5b2;font-size:11px}.cards{display:flex;flex-wrap:wrap;gap:10px;margin:18px 0}.card{padding:10px 14px;border:1px solid #274755;border-radius:9px;background:#102530}.card strong{display:block;color:#62e1bd;font-size:21px}.controls{display:flex;flex-wrap:wrap;gap:10px 14px;align-items:center;margin:8px 0 12px}.controls input[type=search]{min-width:280px;flex:1;box-sizing:border-box;padding:11px;border:1px solid #315668;border-radius:8px;background:#0b1c25;color:#fff}.controls label{white-space:nowrap}button{padding:6px 9px;border:1px solid #416476;border-radius:6px;background:#153442;color:#dcecf4;cursor:pointer}button:hover{background:#235064}.actions{white-space:nowrap}.actions button{margin:0 3px 3px 0}.examples div{margin-bottom:7px}.map-link{display:inline-block;margin-left:7px;color:#62e1bd;font-size:11px;font-weight:700}.remark-cell textarea{box-sizing:border-box;min-width:190px;width:100%;resize:vertical;padding:7px;border:1px solid #315668;border-radius:6px;background:#071820;color:#fff;font:12px/1.4 system-ui,sans-serif}.remark-cell textarea:focus{outline:2px solid #62e1bd;border-color:transparent}table{width:100%;border-collapse:collapse;margin-bottom:28px;background:#0b1c25}th{position:sticky;top:0;background:#16313f;text-align:left}th,td{padding:8px;border-bottom:1px solid #203d4b;vertical-align:top}.badge{display:inline-block;padding:2px 6px;border-radius:10px;font-size:10px;text-transform:uppercase}.badge.exact,.badge.confirmed{color:#07131b;background:#62e1bd}.badge.nearby,.badge.candidate,.badge.skipped{color:#07131b;background:#ffc75f}.badge.noise{background:#5d7180;color:#fff}.review-row[data-decision=confirmed]{box-shadow:inset 4px 0 #62e1bd}.review-row[data-decision=noise]{opacity:.58}.hidden{display:none}details{margin-top:28px}summary{cursor:pointer;font-size:20px;font-weight:600;margin-bottom:14px}
</style></head><body><main><h1>In-game Actors ↔ Palworld.gg Pins</h1><div class="muted">Review one actor class at a time. Remarks and decisions are saved automatically in this browser · Generated ${escapeHtml(result.comparedAtUtc)}</div><div class="cards"><div class="card"><strong id="remaining">0</strong>unresolved classes</div><div class="card"><strong id="reviewed">0</strong>reviewed classes</div><div class="card"><strong>${result.summary.confirmedMatches}</strong>auto-confirmed matches</div><div class="card"><strong>${result.summary.noiseMatches}</strong>auto-noise matches</div></div><div class="controls"><input id="search" type="search" placeholder="Search meaning, remark, actor, pin type, or Pal…"><label><input id="hideMaterials" type="checkbox" checked> Hide materials</label><label><input id="showResolved" type="checkbox"> Show resolved/automatic</label><button id="export">Export approved scanner rules</button><button id="clear">Clear my decisions and remarks</button></div><h2>Actor-class review queue</h2><div class="muted">Consistency is the percentage of this class that maps to its dominant pin type. Examples show nearest, median, and farthest dominant matches.</div><table><thead><tr><th>Your decision</th><th>Automatic</th><th>Actor meaning and recommendation</th><th>Findings</th><th>Consistency</th><th>Dominant map pin</th><th>Representative examples</th><th>Your remark</th><th>Review</th></tr></thead><tbody>${reviewRows}</tbody></table><details><summary>Detailed findings</summary><div class="controls"><label><input id="showNoise" type="checkbox"> Show ${result.summary.noiseMatches} noise matches</label></div><h2>Class/type mappings</h2><table><thead><tr><th>Assessment</th><th>Matches</th><th>Exact</th><th>Confirmed</th><th>Actor class</th><th>Pin category</th><th>Pin type</th><th>Minimum distance</th><th>Average distance</th><th>Example</th></tr></thead><tbody>${groupRows}</tbody></table><h2>Individual matches</h2><div class="muted"><span id="count">0</span> visible matches</div><table><thead><tr><th>Assessment</th><th>Distance class</th><th>Distance</th><th>Actor</th><th>Palworld.gg pin</th><th>World coordinates</th><th>Map coordinates</th></tr></thead><tbody>${matchRows}</tbody></table></details></main><script>
const storageKey='palworld-actor-pin-review-v1',remarkKey='palworld-actor-pin-remarks-v1',decisions=JSON.parse(localStorage.getItem(storageKey)||'{}'),remarks=JSON.parse(localStorage.getItem(remarkKey)||'{}');
const input=document.querySelector('#search'),showNoise=document.querySelector('#showNoise'),showResolved=document.querySelector('#showResolved'),hideMaterials=document.querySelector('#hideMaterials'),detailRows=[...document.querySelectorAll('.filter-row')],matches=[...document.querySelectorAll('.match')],reviewRows=[...document.querySelectorAll('.review-row')],count=document.querySelector('#count'),remaining=document.querySelector('#remaining'),reviewed=document.querySelector('#reviewed');
function save(){localStorage.setItem(storageKey,JSON.stringify(decisions));localStorage.setItem(remarkKey,JSON.stringify(remarks))}
function render(){const q=input.value.trim().toLowerCase();let left=0,done=0;for(const row of reviewRows){const actorClass=row.dataset.class,decision=decisions[actorClass],remark=remarks[actorClass]||'',textarea=row.querySelector('textarea');row.dataset.decision=decision||'';if(document.activeElement!==textarea)textarea.value=remark;row.querySelector('.decision-cell').innerHTML=decision?'<span class="badge '+decision+'">'+decision+'</span>':'—';const resolved=Boolean(decision)||row.dataset.auto!=='candidate';if(decision)done++;else if(row.dataset.auto==='candidate')left++;const searchable=row.dataset.search+' '+remark.toLowerCase(),show=(!q||searchable.includes(q))&&(!hideMaterials.checked||row.dataset.material!=='true')&&(showResolved.checked||!resolved);row.classList.toggle('hidden',!show)}remaining.textContent=left;reviewed.textContent=done;for(const row of detailRows){const show=(!q||row.dataset.search.includes(q))&&(showNoise.checked||row.dataset.noise!=='true')&&(!hideMaterials.checked||row.dataset.material!=='true');row.classList.toggle('hidden',!show)}count.textContent=matches.filter(row=>!row.classList.contains('hidden')).length}
document.querySelector('tbody').addEventListener('click',event=>{const button=event.target.closest('button[data-action]');if(!button)return;const row=button.closest('.review-row');decisions[row.dataset.class]=button.dataset.action;save();render()});
document.querySelector('tbody').addEventListener('input',event=>{if(!event.target.matches('textarea'))return;const row=event.target.closest('.review-row'),value=event.target.value.trim();if(value)remarks[row.dataset.class]=event.target.value;else delete remarks[row.dataset.class];save()});
input.addEventListener('input',render);showNoise.addEventListener('change',render);showResolved.addEventListener('change',render);hideMaterials.addEventListener('change',render);
document.querySelector('#clear').addEventListener('click',()=>{if(!confirm('Clear all saved review decisions and remarks?'))return;for(const key of Object.keys(decisions))delete decisions[key];for(const key of Object.keys(remarks))delete remarks[key];save();render()});
document.querySelector('#export').addEventListener('click',()=>{const approved=reviewRows.filter(row=>decisions[row.dataset.class]==='confirmed').map(row=>({actorClass:row.dataset.class,pinCategory:row.children[5].childNodes[0].textContent,pinType:row.children[5].querySelector('small').textContent,meaning:row.children[2].querySelector('p').textContent,recommendation:row.children[2].querySelector('small').textContent.replace(/^Recommendation:\s*/,''),remark:remarks[row.dataset.class]||'',source:'palworld.gg coordinate comparison'}));const blob=new Blob([JSON.stringify({schemaVersion:1,exportedAtUtc:new Date().toISOString(),approvedMappings:approved,decisions,remarks},null,2)],{type:'application/json'}),link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download='approved-actor-scanner-rules.json';link.click();setTimeout(()=>URL.revokeObjectURL(link.href),1000)});render();
</script></body></html>`;
fs.writeFileSync(outputHtml, html);
console.log(JSON.stringify(result.summary, null, 2));
