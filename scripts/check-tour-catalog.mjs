#!/usr/bin/env node
// Tour catalog integrity check — fails CI when AGENTS.md § Telemetry
// defines an event type that `lib/tour-catalog.sh` has no matching
// `tour_catalog_<type>()` function for.
//
// Ticket 0050. `bin/fleet tour` annotates each events.jsonl line by
// dispatching to the catalog function for the line's `type`. If the
// telemetry contract grows an event type without the matching catalog
// entry, the tour would render a fallback "not in the catalog yet"
// block for an event the kit DOES know about — that's a regression of
// the "every event type ships with an operator-readable gloss" promise.
// This gate is the seatbelt.
//
// Resolution order (test seam first, repo-relative fallback):
//   1. FLEET_CHECK_TOUR_AGENTS_MD   — fixture AGENTS.md path.
//      FLEET_CHECK_TOUR_CATALOG     — fixture lib/tour-catalog.sh path.
//      Both env vars MUST be present together; either-alone is rejected.
//   2. Otherwise: <repo>/AGENTS.md and <repo>/lib/tour-catalog.sh.
//
// No dependencies — both files are parsed line-by-line with regex.

import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "..");

const seamAgents = process.env.FLEET_CHECK_TOUR_AGENTS_MD;
const seamCatalog = process.env.FLEET_CHECK_TOUR_CATALOG;
if ((seamAgents && !seamCatalog) || (!seamAgents && seamCatalog)) {
  console.error("✗ tour-catalog: FLEET_CHECK_TOUR_AGENTS_MD and FLEET_CHECK_TOUR_CATALOG must be set together.");
  process.exit(1);
}

const agentsPath = seamAgents || join(REPO_ROOT, "AGENTS.md");
const catalogPath = seamCatalog || join(REPO_ROOT, "lib", "tour-catalog.sh");

if (!existsSync(agentsPath)) {
  console.error(`✗ tour-catalog: AGENTS.md not found at ${agentsPath}`);
  process.exit(1);
}
if (!existsSync(catalogPath)) {
  console.error(`✗ tour-catalog: lib/tour-catalog.sh not found at ${catalogPath}`);
  process.exit(1);
}

// Extract event type identifiers from AGENTS.md § Telemetry. The list
// begins at the line `- **Event types** emitted by the kit today:` and
// runs until the next non-bullet, non-blank paragraph (`Add new event
// types in the same file…` in today's AGENTS.md, or the `**Demo path`
// boundary). Anchoring to that range keeps us from sweeping up the
// gating-check bullets (`shellcheck`, `validate`) and the schema-key
// bullets (`ts`, `slug`, `phase`, `type`).
const agentsText = readFileSync(agentsPath, "utf8");
const agentsTypes = new Set();
{
  const lines = agentsText.split(/\r?\n/);
  let inList = false;
  for (const line of lines) {
    if (!inList) {
      if (/^- \*\*Event types\*\*/.test(line)) inList = true;
      continue;
    }
    // List ends at a top-level paragraph (no leading space) that isn't
    // a continuation. We treat any non-blank line that doesn't start
    // with whitespace as the end-of-list.
    if (/^\S/.test(line)) break;
    // The list shape is `  - \`<type> {schema}\` — prose`. We capture
    // just the type identifier; the schema block trails it inside the
    // same backtick pair.
    const m = line.match(/^\s+- `([a-z_][a-z_0-9]*)\b/);
    if (m) agentsTypes.add(m[1]);
  }
}

// Extract `tour_catalog_<type>()` function names from the catalog.
const catalogText = readFileSync(catalogPath, "utf8");
const catalogTypes = new Set();
for (const line of catalogText.split(/\r?\n/)) {
  const m = line.match(/^tour_catalog_([a-z_][a-z_0-9]*)\(\)/);
  if (!m) continue;
  // Skip the helper `tour_catalog_principle_title` — it is not an event
  // type, it is the P-N → title lookup.
  if (m[1] === "principle_title") continue;
  catalogTypes.add(m[1]);
}

const missing = [...agentsTypes].filter((t) => !catalogTypes.has(t)).sort();
const orphan  = [...catalogTypes].filter((t) => !agentsTypes.has(t)).sort();

const errors = [];
for (const t of missing) errors.push(`AGENTS.md event type \`${t}\` has no tour_catalog_${t}() in lib/tour-catalog.sh`);
for (const t of orphan)  errors.push(`tour_catalog_${t}() in lib/tour-catalog.sh has no matching event type in AGENTS.md`);

if (errors.length) {
  console.error(`✗ tour-catalog: ${errors.length} mismatch(es) between AGENTS.md § Telemetry and lib/tour-catalog.sh`);
  for (const e of errors) console.error(`  - ${e}`);
  console.error("\nAdd or remove the matching tour_catalog_<type>() function in lib/tour-catalog.sh so every AGENTS.md event type carries an operator-readable gloss.");
  process.exit(1);
}

console.log(`✓ tour-catalog: ${agentsTypes.size} event types, all covered by lib/tour-catalog.sh.`);
process.exit(0);
