#!/usr/bin/env node
// Prompts CHANGELOG integrity check — fails CI when a PR modifies any file
// under prompts/ without also touching prompts/CHANGELOG.md.
//
// Ticket 0013. The whole point of prompts/CHANGELOG.md is that an operator
// who sees `prompts_drift` (ticket 0005) can read the why-it-changed in
// one place. If a PR mutates ship.prompt.md but skips the CHANGELOG, that
// promise breaks silently — this validator is the seatbelt.
//
// Behavior:
//   1. Determine the file-change set for the PR.
//      Resolution order (first hit wins):
//        a. $FLEET_PROMPTS_CHANGELOG_FILES = path to newline-separated list
//           (the test seam used by tests/prompts-changelog.sh).
//        b. $GITHUB_BASE_REF set (PR run on GitHub Actions) → run
//           `git diff --name-only origin/$GITHUB_BASE_REF...HEAD`.
//        c. Otherwise → run `git diff --name-only main...HEAD`.
//      A failure of (b)/(c) is treated as "no diff" and the validator
//      passes — we never block CI on a transient git error.
//   2. If the file list is empty → PASS (non-PR run, push to main, etc.).
//   3. If ANY file is under `prompts/`:
//        - If `prompts/CHANGELOG.md` IS in the change set → PASS.
//        - Otherwise → FAIL with a clear error.
//      If NO file is under `prompts/` → PASS.
//
// No dependencies — git is invoked via child_process.execSync.

import { execSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";

function getChangedFiles() {
  const seamPath = process.env.FLEET_PROMPTS_CHANGELOG_FILES;
  if (seamPath) {
    if (!existsSync(seamPath)) return [];
    return readFileSync(seamPath, "utf8")
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean);
  }
  // GITHUB_BASE_REF is set on PR runs only. On `push` it's empty.
  const base = process.env.GITHUB_BASE_REF || "main";
  // origin/<base>...HEAD on PR runs (the merge-base diff); main...HEAD
  // for local runs. Failure → treat as empty list (non-PR / shallow
  // checkout / unreachable ref).
  const targets = process.env.GITHUB_BASE_REF
    ? [`origin/${base}...HEAD`, `${base}...HEAD`]
    : [`${base}...HEAD`];
  for (const t of targets) {
    try {
      const out = execSync(`git diff --name-only ${t}`, {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      });
      return out
        .split(/\r?\n/)
        .map((s) => s.trim())
        .filter(Boolean);
    } catch {
      // Try the next form; if all fail, return [] and let the gate pass.
    }
  }
  return [];
}

const changed = getChangedFiles();
if (changed.length === 0) {
  console.log("✓ prompts changelog: no PR diff to inspect (non-PR or empty).");
  process.exit(0);
}

const promptsFiles = changed.filter(
  (p) => p.startsWith("prompts/") && p !== "prompts/CHANGELOG.md"
);
const changelogTouched = changed.includes("prompts/CHANGELOG.md");

if (promptsFiles.length > 0 && !changelogTouched) {
  console.error("✗ prompts changelog: PR touches prompts/ files without updating prompts/CHANGELOG.md\n");
  for (const f of promptsFiles) console.error(`  - ${f}`);
  console.error("\nAppend an operator-curated `## YYYY-MM-DD — <title>` entry to prompts/CHANGELOG.md describing the behavioral intent.");
  process.exit(1);
}

if (promptsFiles.length > 0 && changelogTouched) {
  console.log(`✓ prompts changelog: ${promptsFiles.length} prompt file(s) moved with CHANGELOG.`);
} else {
  console.log("✓ prompts changelog: no prompts/ files in PR diff.");
}
process.exit(0);
