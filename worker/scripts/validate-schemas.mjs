// Compiles every schema in ../schema/v1 (draft 2020-12), checks $id against the
// served URL and validates the repo's real data against the matching schema.
import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, relative, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const schemaDir = join(root, "schema/v1");
const BASE = "https://vibedeck-schema.alanreisanjo.workers.dev/v1";

let failures = 0;
const fail = (msg) => { failures++; console.error(`FAIL ${msg}`); };

const ajv = new Ajv2020({ strict: true, strictRequired: false, allErrors: true });
addFormats(ajv);

// 1. Schemas: compile + $id.
const validators = new Map(); // short name -> validate fn
const files = readdirSync(schemaDir).filter((f) => f.endsWith(".schema.json")).sort();
const schemas = files.map((f) => ({ f, json: JSON.parse(readFileSync(join(schemaDir, f), "utf8")) }));
for (const { f, json } of schemas) {
  const expected = `${BASE}/${f}`;
  if (json.$id !== expected) fail(`schema/v1/${f}: $id = ${json.$id}, esperado ${expected}`);
  try { ajv.addSchema(json); } catch (e) { fail(`schema/v1/${f}: ${e.message}`); }
}
for (const { f, json } of schemas) {
  try { validators.set(f.replace(".schema.json", ""), ajv.getSchema(json.$id) ?? ajv.compile(json)); }
  catch (e) { fail(`schema/v1/${f}: compilação: ${e.message}`); }
}
console.log(`schemas compilados: ${validators.size}/${files.length}`);

// 2. Data: walk dirs (including subfolders, skipping hidden entries below the root dir).
function walk(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const name of readdirSync(dir).sort()) {
    if (name.startsWith(".")) continue;
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) out.push(...walk(p));
    else if (name.endsWith(".json")) out.push(p);
  }
  return out;
}
const targets = [
  ["project", [join(root, "vibedeck.json")].filter(existsSync)],
  ["review-group", walk(join(root, ".vibedeck/reviews"))],
  ["rule-topic", walk(join(root, ".vibedeck/rules"))],
  ["idea", walk(join(root, ".vibedeck/ideas"))],
  ["agent", walk(join(root, ".vibedeck/agents"))],
  ["command", walk(join(root, ".vibedeck/commands"))],
  ["skill", walk(join(root, ".vibedeck/skills"))],
  ["workflow", walk(join(root, ".vibedeck/workflows"))],
  ["rule-check", walk(join(root, ".vibedeck/checks"))],
  ["workflow-run", walk(join(root, ".vibedeck/runs"))],
];
for (const [name, list] of targets) {
  const validate = validators.get(name);
  if (!validate) { fail(`sem validador para ${name}`); continue; }
  let ok = 0;
  for (const file of list) {
    const rel = relative(root, file);
    let data;
    try { data = JSON.parse(readFileSync(file, "utf8")); } catch (e) { fail(`${rel}: JSON inválido: ${e.message}`); continue; }
    if (typeof data?.$schema === "string" && data.$schema !== `${BASE}/${name}.schema.json`) {
      fail(`${rel}: $schema = ${data.$schema}, esperado ${BASE}/${name}.schema.json`);
    }
    if (validate(data)) ok++;
    else for (const err of validate.errors) fail(`${rel}: ${err.instancePath || "$"} ${err.message} ${JSON.stringify(err.params)}`);
  }
  console.log(`${name}: ${ok}/${list.length} ok`);
}

if (failures) { console.error(`${failures} falha(s)`); process.exit(1); }
console.log("validação ok");
