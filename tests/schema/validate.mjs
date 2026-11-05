// Development-only schema tests: valid documents must pass, unsafe ones must be rejected.
// Run: npm ci --prefix tests/schema && node tests/schema/validate.mjs
import Ajv2020 from "ajv/dist/2020.js";
import { parse } from "yaml";
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const ajv = new Ajv2020({ allErrors: true, strict: false });
const load = (p) => JSON.parse(readFileSync(join(root, p), "utf8"));
const doc = ajv.compile(load("schema/v1/document.schema.json"));
const idx = ajv.compile(load("schema/v1/index.schema.json"));

// YAML 1.2 core schema (yaml v2 default): dates stay strings. Custom tags are rejected.
const yaml = (text) => parse(text, { customTags: [], uniqueKeys: true });
const front = (p) => {
  const m = readFileSync(join(root, p), "utf8").match(/^---\n([\s\S]*?)\n---\n/);
  if (!m) throw new Error(`${p}: no frontmatter`);
  return yaml(m[1]);
};

let failed = 0;
const expect = (name, validate, data, valid) => {
  const result = validate(data);
  const pass = result === valid;
  if (!pass) failed++;
  console.log(`${pass ? "ok  " : "FAIL"}  ${valid ? "accepts" : "rejects"}  ${name}`);
  if (!pass && !result) console.log(JSON.stringify(validate.errors.slice(0, 3), null, 1));
};

const docs = [
  "examples/.flowscribe/flows/checkout.md",
  "examples/.flowscribe/modules/payments.md",
  ...readdirSync(join(root, "payload/files/.flowscribe/templates")).map((f) => `payload/files/.flowscribe/templates/${f}`),
];
for (const p of docs) expect(p, doc, front(p), true);
expect("examples index", idx, yaml(readFileSync(join(root, "examples/.flowscribe/index.yaml"), "utf8")), true);

const flow = front("examples/.flowscribe/flows/checkout.md");
const mod = front("examples/.flowscribe/modules/payments.md");
const with_ = (base, change) => { const x = structuredClone(base); change(x); return x; };

expect("env variable with a value", doc, with_(mod, (x) => { x.env = ["PAYMENT_SERVER_KEY=SB-server-abc123"]; }), false);
expect("absolute path in files", doc, with_(mod, (x) => { x.files = ["/etc/passwd"]; }), false);
expect("parent traversal in files", doc, with_(mod, (x) => { x.files = ["../other-repo/x.php"]; }), false);
expect("home path in files", doc, with_(mod, (x) => { x.files = ["~/.ssh/id_rsa"]; }), false);
expect("unknown field", doc, with_(mod, (x) => { x.password = "hunter2"; }), false);
expect("URL in a call", doc, with_(flow, (x) => { x.steps[0].calls = ["GET https://10.0.0.5/admin"]; }), false);
expect("credentials in a call target", doc, with_(flow, (x) => { x.steps[1].calls = [{ type: "db", target: "root:pw@db" }]; }), false);
expect("full URL as a route", doc, with_(flow, (x) => { x.steps[0].screen.route = "https://staging.example.com/cart"; }), false);
expect("URL in trigger", doc, with_(flow, (x) => { x.trigger = "Webhook from https://hooks.example.com"; }), false);
expect("terminal step with next", doc, with_(flow, (x) => { x.steps[3].next = "cart"; }), false);
expect("screen step without screen", doc, with_(flow, (x) => { delete x.steps[0].screen; }), false);
expect("unknown contract version", doc, with_(flow, (x) => { x.flowscribe = 2; }), false);
expect("summary over 160 chars", doc, with_(flow, (x) => { x.summary = "x".repeat(161); }), false);
expect("more than 20 steps", doc, with_(flow, (x) => { x.steps = Array.from({ length: 21 }, (_, i) => ({ id: `s${i}`, kind: "system", title: "t" })); }), false);
expect("index entry outside .flowscribe", idx, { flowscribe: 1, generated: true, app: { name: "a", summary: "b" }, modules: [{ id: "x1", path: "../secret.md", summary: "s", status: "active" }], flows: [] }, false);

let threw = false;
try { yaml("a: !!js/function 'return 1'"); } catch { threw = true; }
const custom = !threw && (() => { try { return typeof yaml("a: !!js/function 'x'").a === "function"; } catch { return false; } })();
if (custom) { failed++; console.log("FAIL  parser executes custom tags"); } else console.log("ok    parser never builds custom-tag objects");

console.log(failed ? `\n${failed} check(s) failed` : "\nall schema checks passed");
process.exit(failed ? 1 : 0);
