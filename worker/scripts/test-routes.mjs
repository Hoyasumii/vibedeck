// Starts the worker locally (wrangler unstable_dev, local mode, no login) and checks every route.
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { unstable_dev } from "wrangler";

const here = dirname(fileURLToPath(import.meta.url));
const workerDir = resolve(here, "..");
const schemaDir = resolve(workerDir, "../schema/v1");

// Make sure public/ mirrors schema/v1.
execFileSync("npm", ["run", "--silent", "sync"], { cwd: workerDir, stdio: "inherit" });

const files = readdirSync(schemaDir).filter((f) => f.endsWith(".schema.json")).sort();
let failures = 0, passed = 0;
const check = (cond, msg) => { if (cond) passed++; else { failures++; console.error(`FAIL ${msg}`); } };

const worker = await unstable_dev(join(workerDir, "src/index.ts"), {
  config: join(workerDir, "wrangler.jsonc"),
  local: true,
  port: 0,
  logLevel: "error",
  experimental: { disableExperimentalWarning: true, disableDevRegistry: true },
});
try {
  const get = (path, init) => worker.fetch(path, init);
  const corsOk = (r, where) => check(r.headers.get("access-control-allow-origin") === "*", `${where}: falta Access-Control-Allow-Origin`);

  // Index routes.
  for (const p of ["/", "/v1", "/v1/"]) {
    const r = await get(p);
    check(r.status === 200, `GET ${p}: status ${r.status}`);
    check((r.headers.get("content-type") ?? "").includes("json"), `GET ${p}: content-type ${r.headers.get("content-type")}`);
    corsOk(r, `GET ${p}`);
    const body = await r.json();
    const urls = Object.values(body.schemas ?? {});
    const listed = urls.map((u) => new URL(u).pathname.replace(/^\/v1\//, "")).sort();
    check(JSON.stringify(listed) === JSON.stringify(files), `GET ${p}: lista de schemas diverge de schema/v1 (lista=${listed}, arquivos=${files})`);
  }

  // Each schema file.
  for (const f of files) {
    const p = `/v1/${f}`;
    const expected = readFileSync(join(schemaDir, f), "utf8");
    const r = await get(p);
    check(r.status === 200, `GET ${p}: status ${r.status}`);
    check((r.headers.get("content-type") ?? "").includes("json"), `GET ${p}: content-type ${r.headers.get("content-type")}`);
    corsOk(r, `GET ${p}`);
    check((await r.text()) === expected, `GET ${p}: corpo diferente do arquivo`);
    const h = await get(p, { method: "HEAD" });
    check(h.status === 200, `HEAD ${p}: status ${h.status}`);
    const o = await get(p, { method: "OPTIONS" });
    check(o.status === 204, `OPTIONS ${p}: status ${o.status}`);
    corsOk(o, `OPTIONS ${p}`);
    check((o.headers.get("access-control-allow-methods") ?? "").includes("GET"), `OPTIONS ${p}: sem Allow-Methods GET`);
  }

  // Errors.
  for (const p of ["/", `/v1/${files[0]}`]) {
    const r = await get(p, { method: "POST", body: "{}" });
    check(r.status === 405, `POST ${p}: status ${r.status}`);
    corsOk(r, `POST ${p}`);
  }
  for (const p of ["/nao-existe", "/v1/nao-existe.schema.json", "/v2/project.schema.json"]) {
    const r = await get(p);
    check(r.status === 404, `GET ${p}: status ${r.status}`);
    corsOk(r, `GET ${p}`);
  }
} finally {
  await worker.stop();
}

console.log(`${passed} verificações ok, ${failures} falha(s)`);
process.exit(failures ? 1 : 0);
