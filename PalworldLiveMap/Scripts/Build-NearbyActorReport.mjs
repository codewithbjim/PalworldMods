import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const player = { x: Number(process.argv[2]), y: Number(process.argv[3]), z: Number(process.argv[4]) };
const radius = Number(process.argv[5] || 30000);
const liveSource = path.join(root, "Diagnostics", "nearby-live-inspection.jsonl");
const source = fs.existsSync(liveSource) ? liveSource : path.join(root, "Diagnostics", "world-inspection.jsonl");
const output = path.join(root, "Diagnostics", "Nearby-Actor-Debug.html");
const escape = (value) => String(value ?? "").replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
const mappedPattern = /fasttravel|towerfasttravel|palbosstower|dungeonfixedentrance|dungeonentrance|sealedrealm|treasurebox|fishingjunkspot|fishingspot|salvage|palsoul|bp_item_(?:stone|wood|egg|paldium|palsphere)|levelobject_relic|levelobject_note|oilfield|palrandomincidentspawner|_boss_c|fboss|bount/i;
const noisePattern = /^(?:BP_BuildObject_|Landscape|LandscapeStreamingProxy|InstancedFoliageActor|StaticMeshActor|BP_PalStaticMeshImposterChunk|BP_FoliageModelChunk)|Camera|Dummy|AmbientSound|GrapplingGun|Player_/i;
const actors = fs.readFileSync(source, "utf8").split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line).actor).filter(Boolean)
  .filter((actor) => Number.isFinite(actor.x) && Number.isFinite(actor.y))
  .map((actor) => ({ ...actor, distance: Math.hypot(actor.x - player.x, actor.y - player.y) }))
  .filter((actor) => actor.distance <= radius)
  .map((actor) => ({ ...actor, assessment: mappedPattern.test(actor.className) ? "mapped" : noisePattern.test(actor.className) ? "noise" : "unmapped" }))
  .sort((left, right) => ({ unmapped: 0, mapped: 1, noise: 2 })[left.assessment] - ({ unmapped: 0, mapped: 1, noise: 2 })[right.assessment] || left.distance - right.distance);
const rows = actors.map((actor) => `<details class="${actor.assessment}" data-search="${escape(`${actor.className} ${actor.objectName}`.toLowerCase())}"><summary><span class="badge">${actor.assessment}</span><strong>${escape(actor.className)}</strong><span>${Math.round(actor.distance).toLocaleString()}u</span></summary><div class="grid"><section><h3>Actor</h3><pre>${escape(JSON.stringify({ id: actor.id, className: actor.className, objectName: actor.objectName, x: actor.x, y: actor.y, z: actor.z, distanceFromPlayer: actor.distance }, null, 2))}</pre></section><section><h3>Properties (${actor.properties.length})</h3><pre>${escape(actor.properties.join("\n"))}</pre></section><section><h3>Nested objects (${actor.nestedObjects.length})</h3><pre>${escape(JSON.stringify(actor.nestedObjects, null, 2))}</pre></section></div></details>`).join("");
const counts = Object.fromEntries(["unmapped", "mapped", "noise"].map((key) => [key, actors.filter((actor) => actor.assessment === key).length]));
fs.writeFileSync(output, `<!doctype html><meta charset="utf-8"><title>Nearby Actor Debug</title><style>body{margin:0;padding:24px;background:#071011;color:#dceee9;font:13px system-ui}header{position:sticky;top:0;background:#071011;padding-bottom:14px}input{width:min(600px,100%);padding:10px;background:#102023;border:1px solid #29484d;color:white;border-radius:8px}details{margin:7px 0;border:1px solid #24383b;border-radius:8px;background:#0d191b}summary{display:grid;grid-template-columns:80px 1fr auto;gap:10px;padding:10px;cursor:pointer}.badge{font-size:10px;text-transform:uppercase}.unmapped .badge{color:#ffb65e}.mapped .badge{color:#63e6b5}.noise .badge{color:#718681}.grid{display:grid;grid-template-columns:1fr 1fr 1.4fr;gap:10px;padding:0 10px 10px}section{min-width:0}h3{font-size:11px;color:#63d8ff}pre{max-height:360px;overflow:auto;white-space:pre-wrap;background:#061012;padding:9px;border-radius:6px;font:10px/1.4 Consolas}.hidden{display:none}</style><header><h1>Nearby Actor Debug</h1><p>Player ${player.x}, ${player.y}, ${player.z} · Radius ${radius}u · ${actors.length} actors · ${counts.unmapped} unmapped · ${counts.mapped} mapped · ${counts.noise} noise</p><input id="q" placeholder="Filter class or object name"></header>${rows}<script>q.oninput=()=>document.querySelectorAll('details').forEach(x=>x.classList.toggle('hidden',!x.dataset.search.includes(q.value.toLowerCase())))</script>`);
console.log(JSON.stringify({ output, actors: actors.length, ...counts }, null, 2));
