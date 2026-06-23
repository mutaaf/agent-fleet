---
id: 0065
title: fleet lessons-import codifies a third-party lesson-pack contract so a peer's hard-won LESSONS can pre-load a fresh fleet without copy-paste
status: groomed
priority: P2
area: engine
created: 2026-06-23
owner: gtm-innovation
---

## User story

As a fleet operator who has been running `agent-fleet` against
`courtiq` for 8 weeks — who has watched a PEER (also running
their own fleet against a totally separate set of projects)
accumulate three months of distinct operational LESSONS that
ALSO apply to my fleet (e.g. the peer's "supabase port-bind on
docs-only PR" lesson directly informs my CI design, the peer's
"em-dash sign-extension under LC_ALL=C" lesson is generic
enough to defuse a trap I haven't hit yet) — who knows the kit
has `fleet lessons-promote` (0028) for promoting one of MY
lessons into MY OWN cross-LESSONS feed, and `fleet lessons-
sync` (0009) for aggregating MY OWN projects' lessons across
slugs, but who has NO contract for IMPORTING a peer's curated
LESSONS PACK into my cross-LESSONS so my next `fleet groom`
PHASE 0 read includes the peer's wisdom — I want `bin/fleet
lessons-import <url-or-file>` to (1) accept a versioned,
hash-validated, signed-by-publisher LESSON PACK file (a small
JSON envelope wrapping a list of dated paragraphs), (2)
validate the schema and the publisher signature, (3) dedupe
against my existing cross-LESSONS via the same text-sha logic
0028 uses, (4) write the imported paragraphs into a clearly-
attributed namespace section in my CROSS_LESSONS.md
(`## from <publisher>:<slug>` rather than the existing
project-slug sections), and (5) emit a new `lessons_imported
{source, version, count, dedup_skipped}` event so the
adoption-of-third-party-wisdom is auditable, so that the
kit's operational-memory moat compounds across operators, not
just across the slugs ONE operator runs.

## Why now (four lenses)

### Product Owner

The kit's existing LESSONS surface is OPERATOR-LOCAL: 0009
aggregates within ONE operator's slugs into ONE
`CROSS_LESSONS.md`, 0028 promotes ONE local lesson into that
same `CROSS_LESSONS.md`, 0039 prunes expired paragraphs, 0040
self-checks for known-trap call shapes the kit's own lessons
warn against, 0045 suggests PRINCIPLES.md additions from
recurring lesson-draft clusters, 0051 diffs ONE slug's PHASE
0 reads against the cross-LESSONS coverage, 0057 ranks the
most-cited LESSONS to feed promote / prune decisions. NONE
of them handle the THIRD-PARTY case: a friend of the
operator who has accumulated 3 months of lessons running
their own fleet against their own projects and wants to
SHARE those lessons with the operator, so the operator
gets immediate cross-OPERATOR wisdom rather than re-deriving
the same traps from scratch. The smallest meaningful unit of
value is one importable lesson-pack file + one command:

```
$ fleet lessons-import https://github.com/peer/their-lessons-pack/releases/download/v3.2.0/lessons.pack.json
fleet lessons-import — validating pack from peer/their-lessons-pack v3.2.0

  download:    /tmp/lessons-pack-XXXX.json (12 KB)
  schema:      version 1 (compatible)
  signature:   verified (peer-pubkey-sha256:a3c1...e98f)
  publisher:   peer (declared in pack)
  lessons:     42 paragraphs in pack
  dedup pass:  18 already present in your cross-lessons (skipped)
               24 new (will import)

  preview new section heading: `## from peer:courtiq`
  preview first 3 imported lesson dates: 2026-05-12, 2026-05-18, 2026-06-01

  confirm import? (y/N)  y

  wrote: 24 paragraphs to /Users/op/.local/share/agent-fleet/CROSS_LESSONS.md
  event: lessons_imported {source: peer/their-lessons-pack, version: 3.2.0, count: 24, dedup_skipped: 18}
  next: `fleet skill-gap <slug>` will now reference 24 new cross-fleet lessons
```

Subtraction: the operator stops manually copy-pasting peer
lessons one paragraph at a time. Per P-5 (operator
confidence over feature richness), the win is cross-
operator operational memory becoming an INSTITUTIONAL asset
rather than a tribal one.

The pack format is intentionally MINIMAL: a JSON envelope
with `schema_version`, `publisher`, `version`, `created_at`,
`signature` (ed25519 over the canonical JSON body), and
`lessons[]` (each lesson carries `date`, `title`, `body`,
`expires?`). Publishers compose packs by hand (or via a
companion `fleet lessons-export-pack` ticket later — that's
out of scope for v1). The signature is mandatory in v1:
operators MUST verify they trust the publisher BEFORE
importing. The kit ships with NO bundled pubkeys; the
operator adds one to `$HOME/.local/share/agent-fleet/
trusted-pubkeys.txt` (one ed25519 pubkey per line, with a
human-readable comment) BEFORE the first import from that
publisher succeeds.

The imported paragraphs land in a CLEARLY ATTRIBUTED
namespace section (`## from <publisher>:<slug>`) so they
do NOT pollute the operator's own `## <slug>` sections.
A future `fleet lessons-import --untrust <publisher>`
removes all paragraphs sourced from that publisher and
emits a `lessons_untrusted` event (v2 follow-up).

`--dry-run` walks the validate + dedupe pass and prints
the preview WITHOUT writing. `--file <path>` accepts a
local pack file (for an air-gapped operator OR for
testing via the harness). `--allow-unsigned` is an
escape-hatch flag the operator can use ONCE, with the
command refusing on a second use without a `--reason`
argument (the kit nudges signing as the default).

### Stakeholder

This is **moat-deepening on the NETWORK-EFFECTS axis** —
the kit's first surface that lets operational memory
COMPOUND across OPERATORS, not just across the slugs ONE
operator runs. That is a different shape of moat than
0009/0028 (intra-operator aggregation): with
lessons-import, the marginal operator joining the
ecosystem gains immediate access to the curated wisdom
of every operator who has shared a pack — which directly
reduces the time-to-trust-the-loop for new operators and
the cost of operating a fleet for veterans. Per P-6
(telemetry is the source of truth), the import path is
a PURE READER of the pack file + a CONTROLLED WRITER to
`CROSS_LESSONS.md` (under the strict
`## from <publisher>:<slug>` namespace) + ONE new event
emission. The diff is the pack parser + the schema
validator + the signature verifier + the namespace
writer + the new event type. ~390 lines.

The PACK SHAPE is the moat: it codifies "what a portable
fleet-operator lesson looks like" into a single JSON
schema. The publisher's signature provenance is the
moat-on-the-moat: an operator who imports a pack from
publisher X can audit every paragraph back to X's
signing key, and a future `--untrust` flag lets them
walk it all back if X turns out to be wrong. This
auditable third-party-wisdom contract is the kind of
ecosystem primitive that produces network effects: every
publisher's pack makes the next operator's fleet
smarter, which makes the next publisher's pack more
valuable, which keeps the kit at the center of the
ecosystem.

The NEW EVENT TYPE `lessons_imported {source, version,
count, dedup_skipped}` is justified per the brief's
"It MAY introduce a new event type (with a full schema
spec) if and only if doing so makes the contract
stronger." Without the event, operators have no audit
trail for which third-party wisdom landed in their fleet
when; with the event, `fleet provenance` (0029) can
attribute every cited cross-LESSON to its import event,
`fleet weekly` (0025) can include "this week imported N
lessons from publisher P", and a future consumer can
build a "supply chain bill of materials" view of the
operator's cross-LESSONS provenance.

Per LESSONS 2026-06-03 (UTF-8 sign-extension trap in
`_json_escape`) the pack parser MUST preserve UTF-8
bytes in lesson body text — em-dashes, smart quotes,
and any non-ASCII character that landed in a peer's
LESSONS.md must round-trip. The parser uses `node`'s
built-in JSON.parse (kit dep already) for the envelope
plus `preflight_json_escape` called directly (per
LESSONS 2026-06-13) for any back-to-JSON serialization
in the event payload.

Per LESSONS 2026-06-08 (`IFS=$'\t'` middle-empty-field
collapse) the dedupe pass uses a `-` sentinel for the
optional `expires` column when emitting the TSV record
for the dedupe walker.

Per LESSONS 2026-06-15 (per-day shellout inside per-
slug loops is O(window × N_slugs)) the dedupe pass is
ONE awk pass per pack over the existing CROSS_LESSONS.md
PLUS ONE awk pass over the pack's lessons[] array —
total budget <500ms for a 200-paragraph pack against a
500-paragraph cross-LESSONS.

Per LESSONS 2026-06-15 (`while (match(s, /pat/)) { s =
before repl after }` infinite-loop trap) the
`## from <publisher>:<slug>` section writer uses the
CURSOR-based walk pattern when inserting paragraphs
under an existing section — the section heading itself
contains the literal text the section-finder matches.

Per cross-LESSONS courtiq 2026-05-22 (two-PR ship
ritual) `lessons-import` writes directly to
`CROSS_LESSONS.md` and emits the event in ONE pass —
the file is NOT a tracked backlog file requiring a
separate chore PR. The operator's normal git workflow
(or a `fleet provenance` snapshot) is the audit trail
for what was imported when.

Per cross-LESSONS fleet-control 2026-05-26 (any
shell-out module needs an injectable runner for tests)
the signature verifier is a thin shell wrapper around
`openssl dgst -sha256 -verify <pubkey> -signature
<sig> <body>` with a test-stub injection point under
`$HOME/.local/bin` per LESSONS 2026-05-26 (PATH reset).

Compounds 0009 (`cross-LESSONS aggregation` —
lessons-import writes to the same file the aggregator
writes), 0028 (`fleet lessons-promote` — import is
the inter-operator complement to promote's intra-
operator move), 0029 (`fleet provenance` — provenance
can attribute imported paragraphs back to their
publisher), 0051 (`fleet skill-gap` — skill-gap's
coverage diff now includes imported paragraphs), 0057
(`fleet lessons-rank` — rank now includes imported
paragraphs in its citation-frequency surface), 0039
(`fleet lessons-prune` — prune respects the EXPIRES
markers on imported paragraphs the same way it does
local ones), 0044 (`fleet pr-footer` — pr-footer can
cite imported lessons in its per-merge comment), 0061
(`fleet invoice` — invoice's "lessons sourced from
peers" line is a follow-up addition).

Differentiated from `fleet lessons-promote` (0028):
promote moves ONE of MY OWN lessons into MY
CROSS_LESSONS.md; import accepts a pack of SOMEONE
ELSE's lessons. Differentiated from `fleet lessons-
sync` (0009): sync aggregates MY OWN slugs' lessons
into MY CROSS_LESSONS.md; import adds a third-party
publisher's pack. Differentiated from `fleet skill-
gap` (0051): skill-gap is DIAGNOSTIC (what's missing
in my coverage); import is THERAPEUTIC (here's a pack
that fills the gap). Differentiated from manually
copy-pasting paragraphs into CROSS_LESSONS.md by
hand: import is hash-validated, signature-verified,
schema-validated, dedupe-aware, namespace-isolated,
and event-attested.

### User (operator at week 12 of running the fleet)

The operator at week 12 sees a peer post on Twitter:
"published v3.2.0 of my lessons pack — 42 lessons
from running my own fleet for 4 months. ed25519
pubkey in pinned tweet." The operator runs `echo
"<pubkey-line> # peer-2026-06-23" >> ~/.local/
share/agent-fleet/trusted-pubkeys.txt`, then `fleet
lessons-import https://github.com/peer/their-lessons-
pack/releases/download/v3.2.0/lessons.pack.json`.
The kit downloads, verifies, dedupes, prints the
preview ("24 new, 18 dedupe-skipped"), prompts for
confirmation. The operator confirms. Next `fleet
groom` PHASE 0 reads the updated CROSS_LESSONS.md —
including the 24 new paragraphs — and the next ship
run defuses two of the imported traps preemptively
before the operator hits them. Per P-5 the win is
the operator gaining 4 months of peer wisdom in 30
seconds.

Sub-scenario: an operator runs `fleet lessons-
import --dry-run --file ./test-pack.json` against
a peer's pack file before committing to the import
— sees the preview, decides to skip 2 paragraphs
that conflict with their own conventions, asks the
peer for a v3.2.1 with those paragraphs removed
(out of scope for the kit; that's just a normal
GitHub Issue), then re-imports.

Sub-scenario: an operator discovers a peer's pack
included a paragraph with bad advice (e.g.
"always use `gh pr merge --admin` to bypass
red CI" — a direct violation of AGENTS.md Hard
NOs). The operator runs `fleet lessons-import
--untrust peer/their-lessons-pack` (a v2
follow-up; v1 ships the import path only) and
the pack's paragraphs are removed from CROSS_
LESSONS.md, an `lessons_untrusted` event is
emitted, and the publisher's pubkey is moved
to a `revoked-pubkeys.txt` so future imports
from them require an explicit `--allow-revoked`
flag. v1's escape hatch is the operator
manually deleting the `## from
<publisher>:<slug>` section.

Sub-scenario: an operator publishes their OWN
pack (out of scope for v1 — that's a future
`fleet lessons-export-pack` ticket) and a
friend imports it. The kit's cross-operator
network effect is fully bidirectional once
both directions ship.

### Growth

This is the surface that turns the kit's
operational-memory advantage into a NETWORK
EFFECT — every operator who imports a pack
becomes more likely to publish one in return,
which makes the next operator's adoption
faster, which compounds. Per the brief's "why
does a friend running their own autonomous-
agent setup want to adopt it?" — lessons-
import is the answer when the friend says
"and what if I want to share what I've
learned with other operators?" The kit's
answer is a signed, schema-versioned,
auditable pack format.

Differentiated from competing autonomous-
agent tools whose operational lessons stay
locked inside vendor-cloud usage stats:
agent-fleet's lessons are PORTABLE, SIGNED,
and IMPORTABLE across operators. That open-
ecosystem stance is the kind of design
choice that attracts ecosystem-minded
operators who would otherwise stick with
closed tools.

A future "agent-fleet lessons registry"
(out of scope; community-driven) becomes
viable the moment the pack format is
standardized — operators discover each
other's packs via a GitHub topic, a small
registry repo, or word-of-mouth. v1 ships
the IMPORT primitive; the discovery layer
follows.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/lessons-import.sh`.

- [ ] `bin/fleet lessons-import <url-or-file>` is a new
      subcommand. Required arg is a URL OR a `--file
      <path>` flag with a local file. Both missing:
      prints `lessons-import: usage: bin/fleet lessons-
      import <url> | --file <path> [--dry-run] [--allow-
      unsigned --reason "<text>"] [--json]` to stderr,
      exit 2 per LESSONS 2026-06-01. Per LESSONS
      2026-05-30 the test assertion uses `grep -qF --
      "$kw"`. Test asserts both refusal AND the URL/file
      branches.

- [ ] The pack schema is a JSON envelope:
      `{"schema_version": 1, "publisher": "<str>",
      "version": "<semver>", "created_at":
      "<ISO8601-UTC>", "signature": "<base64-ed25519>",
      "pubkey_sha256": "<hex>", "lessons":
      [{"date": "YYYY-MM-DD", "title": "<str>",
      "body": "<str>", "expires": "YYYY-MM-DD|null"}]}`.
      Per LESSONS 2026-06-03 (UTF-8 sign-extension)
      the parser preserves UTF-8 in lesson bodies. Per
      LESSONS 2026-06-13 the JSON read uses Node's
      built-in `JSON.parse`; the JSON escape for the
      event payload uses `preflight_json_escape`
      called directly. A pack that fails to parse:
      prints `lessons-import: invalid JSON in pack
      file (line N: <msg>)` to stderr, exit 3. Test
      asserts via fixture: a valid pack, an invalid
      JSON pack, a missing required field
      (`publisher`), a wrong `schema_version`.

- [ ] The signature is ed25519 over the canonical
      serialization of the envelope WITHOUT the
      `signature` field. v1 uses `openssl dgst
      -sha256 -verify <pubkey> -signature <sig>
      <body>` per the standard shell-wrapping
      convention. The `pubkey_sha256` field in the
      pack is cross-checked against the resolved
      pubkey file's sha256 — refuses with
      `lessons-import: pubkey_sha256 in pack
      (<a>) does not match resolved key (<b>)` to
      stderr, exit 3 on mismatch. The operator's
      `$HOME/.local/share/agent-fleet/trusted-
      pubkeys.txt` (one pubkey per line with `#
      <comment>` suffixes) is the source of truth
      for trusted publishers. An untrusted
      publisher: refuses with `lessons-import:
      publisher <name> not in trusted-pubkeys.txt.
      add the pubkey first, OR re-run with
      --allow-unsigned --reason "<text>".` Test
      asserts all three refusals AND the happy
      path AND the `--allow-unsigned --reason`
      override path.

- [ ] The dedupe pass walks every paragraph in the
      pack AND every paragraph in the destination
      `CROSS_LESSONS.md` (resolved via
      `${FLEET_CROSS_LESSONS:-$HOME/.local/share/
      agent-fleet/CROSS_LESSONS.md}` — same
      precedence 0028 uses). For each pack
      paragraph, computes the same `text_sha`
      0028 uses (`shasum -a 256 < <body-
      normalized>` taking the first 8 hex chars).
      A paragraph whose `text_sha` already
      appears in CROSS_LESSONS.md is SKIPPED. Per
      LESSONS 2026-06-08 every awk pass declares
      `BEGIN { count = 0 }`. Per LESSONS
      2026-06-08 `IFS=$'\t'` middle-empty-field
      uses `-` sentinel for the optional
      `expires` column. Test asserts via fixture
      that a pack with 10 lessons, 4 of which
      have bodies byte-identical to existing
      cross-LESSONS paragraphs, imports 6 and
      skips 4.

- [ ] Imported paragraphs are written under a
      clearly-attributed namespace section
      heading: `## from <publisher>:<pack-slug>`
      where `pack-slug` is the lesson's
      `slug`-like derivation from the pack's
      `publisher`+`version` (e.g. `## from peer:
      their-lessons-pack-v3.2.0`). If the
      section already exists (re-import of an
      older version), the new paragraphs append
      AFTER the existing ones in date order.
      Per LESSONS 2026-06-15 (`while (match(s,
      /pat/)) { s = before repl after }`
      infinite-loop trap — `## from
      <publisher>` heading text appears inside
      itself) the section-finder uses the
      CURSOR-based walk pattern, NOT the
      recursive shape. Test asserts via fixture
      a fresh import creates the section AND a
      re-import appends without duplicating
      existing paragraphs.

- [ ] `bin/fleet lessons-import` emits a new
      typed event: `lessons_imported {source,
      version, count, dedup_skipped, unsigned}`.
      `source` is the pack's `publisher` field.
      `version` is the pack's `version` field.
      `count` is the number of paragraphs
      actually inserted. `dedup_skipped` is the
      number skipped due to dedupe. `unsigned`
      is `0` on the signature-verified path and
      `1` on the `--allow-unsigned` path.
      Carries `phase=lessons-import` and lives
      in the AGENT-FLEET kit-as-project
      `events.jsonl` (per the
      `lesson_promoted` (0028) /
      `prompts_reverted` (0035) /
      `lessons_pruned` (0039) /
      `self_check_failed` (0040) convention).
      Dry-run path (`--dry-run`) emits NO
      event. Refusal paths (invalid JSON,
      unsigned without override, pubkey
      mismatch) emit NO event. Per LESSONS
      2026-06-13 the event payload's JSON
      escape uses `preflight_json_escape`
      called directly. Test asserts the event
      fires on happy path AND is silent on
      every refusal/dry-run path.

- [ ] `bin/fleet lessons-import --dry-run`
      walks the validate + dedupe pass and
      prints the preview WITHOUT writing to
      CROSS_LESSONS.md AND WITHOUT emitting the
      event. The preview includes: pack
      metadata (publisher, version, count,
      created_at), dedupe summary (N new, M
      skipped), preview section heading, first
      3 lesson dates. Test asserts the
      destination CROSS_LESSONS.md byte size
      is unchanged AND the kit's events.jsonl
      tail is unchanged before and after
      dry-run.

- [ ] `bin/fleet lessons-import --file <path>`
      accepts a LOCAL pack file (no download).
      Missing file: prints `lessons-import:
      file <path> not found` to stderr, exit 2.
      Test asserts both branches.

- [ ] `bin/fleet lessons-import <url>` downloads
      the URL via `curl -fsSL` into a `mktemp`
      file BEFORE validation. Failed download:
      prints `lessons-import: failed to download
      <url> (curl exit N)` to stderr, exit 3.
      The temp file is cleaned up via `trap`
      on exit. Test asserts via stub `curl`
      under `$HOME/.local/bin` per LESSONS
      2026-05-26 (PATH reset) the URL path AND
      the failed-download branch.

- [ ] `bin/fleet lessons-import --allow-unsigned
      --reason "<text>"` is the escape hatch
      for an air-gapped operator OR a pack from
      a publisher whose signing setup is
      pending. The `--reason` is MANDATORY
      under this flag (refuses with
      `lessons-import: --allow-unsigned
      requires --reason "<text>"` to stderr,
      exit 2). Per LESSONS 2026-06-03 (UTF-8
      sign-extension guard) the `--reason`
      value is ASCII-validated v1 per the same
      convention as 0039 lessons-prune's
      `--cause` (rejects non-ASCII with a
      one-line stderr nudge). The reason is
      recorded in the event payload as
      `reason=<text>` (verbatim). Test
      asserts both branches.

- [ ] `bin/fleet lessons-import --json` emits
      one structured JSON object: `{"pack":
      {"publisher": "<str>", "version":
      "<str>", "created_at": "<ISO8601>"},
      "validated": <bool>, "signed": <bool>,
      "imported_count": <int>, "dedup_
      skipped_count": <int>, "section_
      heading": "<str>", "lesson_dates":
      ["YYYY-MM-DD", ...]}`. Per LESSONS
      2026-06-13 JSON escape calls
      `preflight_json_escape` directly. Test
      asserts JSON validity via Node.

- [ ] `bin/fleet lessons-import --help` prints
      USAGE mentioning `--file`, `--dry-run`,
      `--allow-unsigned`, `--reason`,
      `--json`. Per LESSONS 2026-05-30 test
      asserts via `grep -qF -- "$kw"
      "$help_out"`. Help block ends with
      `exit 0` per LESSONS 2026-06-01.

- [ ] `bin/fleet lessons-import` writes ONLY
      to the destination CROSS_LESSONS.md AND
      the kit's `events.jsonl`. NO writes to
      any slug's `agents.config.sh`, NO writes
      to any slug's `events.jsonl` (per P-6:
      the import is a kit-level event, not a
      per-slug event), NO writes to
      `lib/common.sh`, NO writes to
      `prompts/`, NO writes to `AGENTS.md`.
      Test asserts via `find` that the only
      mutated files are CROSS_LESSONS.md and
      the kit's events.jsonl.

- [ ] `lib/common.sh` — NO changes (the
      `_json_escape` and `fleet_emit_event`
      helpers stay byte-identical). `prompts/`
      — NO changes. `AGENTS.md` is UPDATED in
      this PR to document the new
      `lessons_imported` event type under
      § Telemetry (the contract is the moat,
      and a new event type MUST be documented
      there per the section's "Add new event
      types in the same file" instruction).
      Test asserts via `git diff --name-only
      main...HEAD -- AGENTS.md` returns
      non-empty AND a string-match for
      `lessons_imported` in the diff. Test
      asserts `git diff --name-only main...
      HEAD -- lib/common.sh prompts/` returns
      empty.

- [ ] `tests/lessons-import.sh` covers all
      14 boxes above using `$HOME/.local/bin`
      stubs (`curl`, `openssl`, `shasum`)
      per LESSONS 2026-05-26 (PATH reset).
      Fixture pack files
      (`valid-signed.pack.json`, `invalid-
      json.pack.json`, `wrong-pubkey.pack.
      json`, `untrusted-publisher.pack.json`,
      `dedupe-collision.pack.json`,
      `unicode-body.pack.json` exercising
      the UTF-8 round-trip per LESSONS
      2026-06-03), a synthetic
      `trusted-pubkeys.txt`, a synthetic
      starter `CROSS_LESSONS.md`, and the
      kit's own `events.jsonl` fixture all
      live under `tests/fixtures/lessons-
      import/`. Per LESSONS 2026-05-27
      (`$(cat)` trap) backup/restore via
      `cp`. Counts use `awk … END { print
      n+0 }` per LESSONS 2026-06-01. Per
      LESSONS 2026-06-08 every awk script
      declares `BEGIN { count = 0 }`. Per
      LESSONS 2026-06-08 `IFS=$'\t'`
      middle-empty-field uses `-`
      sentinel. Per LESSONS 2026-06-11
      the `created_at` parser uses the
      full `'%Y-%m-%dT%H:%M:%SZ'` format,
      no `date -j -f` involved. Per
      LESSONS 2026-06-15 the dedupe walk
      is ONE awk pass over the pack AND
      ONE awk pass over CROSS_LESSONS.md.
      Per LESSONS 2026-06-15 the section-
      insertion uses the cursor-walk
      pattern. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Run-time
      budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A `fleet lessons-export-pack` complement
  that builds a pack from MY OWN
  CROSS_LESSONS.md and signs it with my
  pubkey. v1 ships the IMPORT side; export
  is a separate ticket so the import shape
  can solidify first.
- A `fleet lessons-import --untrust
  <publisher>` flag that removes all
  paragraphs sourced from a publisher AND
  revokes their pubkey. v1 ships the
  import path; untrust is a v2 follow-up.
- A PUBLIC REGISTRY of available packs
  (a curated index on agent-fleet.dev).
  v1 is URL-by-URL; the registry is a
  community concern.
- AUTOMATIC PACK UPDATES (a launchd
  schedule that polls publishers for new
  versions). v1 is operator-pulled. Auto-
  update is a separate ticket with its
  own risk surface (a compromised
  publisher's auto-pushed pack is exactly
  the failure mode signing is meant to
  bound).
- A MULTIPLE-SIGNATURE / multi-publisher
  trust chain (e.g. "this pack is co-
  signed by A and B"). v1 ships single-
  publisher; multisig is a v2 candidate.
- INTEGRATING imported lessons into
  `fleet self-check` (0040) — the self-
  check catalog is a kit-internal
  contract, not a third-party-influenced
  surface. Cross-pollination is a v2
  conversation.
- A `--scope <slug>` flag that imports
  the pack into a SPECIFIC slug's
  events.jsonl rather than the cross-
  LESSONS file. v1 always writes to
  CROSS_LESSONS.md.
- WRITING A WEB UI for browsing imported
  pack contents. v1 is CLI-only; fleet-
  control can shell out if a UI is
  desired.
- A `lessons_untrusted` event type. v1
  ships ONE new event (`lessons_imported`)
  per the brief's "It MAY introduce a new
  event type … if and only if doing so
  makes the contract stronger." Untrust
  is a v2 follow-up with its own event.
- ENCRYPTING the pack file at rest. v1
  packs are public-by-default (the
  publisher decides what to share);
  encrypted packs are a separate ticket.
- A LICENSING METADATA field on packs
  (e.g. CC0 vs MIT vs proprietary). v1
  ships a minimal envelope; license is
  a v2 candidate.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `lessons_import()`
  dispatcher function (named with
  underscore to avoid the hyphen-in-
  function-name shell parse issue; the
  dispatcher block resolves `CMD =
  lessons-import` to `lessons_import`
  per the same convention 0028's
  `lessons_promote` uses). Place next
  to the existing `lessons_promote()`
  block (find via `grep -n
  '^lessons_promote()' bin/fleet`).
  Per LESSONS 2026-05-26 (`tail`
  shadow) `lessons_import` does not
  collide with any coreutils binary.
- `bin/fleet` — thirteen helpers, ALL
  defined ABOVE the dispatcher block
  per LESSONS 2026-06-05 (forward-
  reference trap):
  - `lessons_import_resolve_target_path`
    — wraps the
    `${FLEET_CROSS_LESSONS:-$HOME/
    .local/share/agent-fleet/
    CROSS_LESSONS.md}` precedence (same
    as 0028).
  - `lessons_import_resolve_pubkey_file`
    — wraps the `$HOME/.local/share/
    agent-fleet/trusted-pubkeys.txt`
    path; refuses on missing-file with
    a clear stderr nudge.
  - `lessons_import_download_pack` —
    wraps `curl -fsSL <url> -o
    <tmpfile>` with a `trap` cleanup;
    refuses on curl-exit-non-zero.
  - `lessons_import_validate_envelope`
    — Node-based JSON parse + schema
    check. Per LESSONS 2026-06-03 the
    parser preserves UTF-8.
  - `lessons_import_verify_signature` —
    wraps `openssl dgst -sha256
    -verify <pubkey> -signature <sig>
    <body>`. Per cross-LESSONS fleet-
    control 2026-05-26 (shell-out
    modules need injectable runner)
    the test stub under `$HOME/.local/
    bin/openssl` handles the
    fixture path.
  - `lessons_import_compute_text_sha` —
    8-char prefix of `shasum -a 256
    < <body-normalized>` matching the
    convention 0028 uses.
  - `lessons_import_dedupe_pass` —
    ONE awk pass per pack AND ONE awk
    pass per CROSS_LESSONS.md.
    Returns the list of new
    paragraphs as TSV (date, title,
    body-sha, expires-or-sentinel).
    Per LESSONS 2026-06-08 `BEGIN
    { count = 0 }`. Per LESSONS
    2026-06-08 `-` sentinel for
    empty `expires`.
  - `lessons_import_build_section_
    heading` — builds
    `## from <publisher>:<pack-slug>`
    string. Per LESSONS 2026-05-28
    every printf of the heading
    goes through `printf -- '%s'`.
  - `lessons_import_find_or_create_
    section` — locates the
    namespace section in
    CROSS_LESSONS.md OR creates it
    at the end of the file. Per
    LESSONS 2026-06-15 the section-
    finder uses the CURSOR-based
    walk pattern.
  - `lessons_import_insert_
    paragraphs` — appends the new
    paragraphs under the section
    heading in date order.
  - `lessons_import_emit_event` —
    fires `fleet_emit_event
    lessons_imported source=...
    version=... count=...
    dedup_skipped=... unsigned=...
    reason=...`. Per LESSONS
    2026-06-13 the event payload's
    JSON escape uses
    `preflight_json_escape`
    called directly.
  - `lessons_import_render_preview`
    — text formatter for the
    dry-run/confirm preview block.
    Width via
    `preflight_visible_width` per
    LESSONS 2026-06-05.
  - `lessons_import_render_json` —
    JSON formatter for `--json`.
    JSON escape via
    `preflight_json_escape` per
    LESSONS 2026-06-13.
- `bin/fleet` — `lessons_import()`
  end-state must be `exit 0` /
  `exit 2` / `exit 3` on every code
  path per LESSONS 2026-06-01. Exit
  codes: 0 = success, 2 = usage /
  refuses-to-start, 3 = validation
  failure (sha mismatch, schema
  mismatch, signature mismatch,
  download failure).
- `bin/fleet` — dispatcher block:
  `if [ "$CMD" = "lessons-import"
  ]; then lessons_import "$@"; fi`.
  Place AFTER the `lessons-promote`
  dispatcher.
- `bin/fleet` — help banner block
  at the top of the file gets ONE
  new line: `fleet lessons-import
  <url|file> import a third-party
  lesson pack into your cross-
  LESSONS feed`. README "Daily
  ops" code block gets the same
  line, appended via the same
  single-edit pattern that avoided
  LESSONS 2026-05-25. README also
  gets a separate paragraph
  documenting the pack format, the
  `trusted-pubkeys.txt` setup, and
  the `--allow-unsigned` escape
  hatch.
- `AGENTS.md` — § Telemetry gets
  ONE new event-type bullet for
  `lessons_imported {source,
  version, count, dedup_skipped,
  unsigned, reason?}` documenting
  the contract (when emitted, what
  the fields mean, the relationship
  to `lesson_promoted`, the
  `phase=lessons-import` value,
  the kit-as-project events.jsonl
  destination, dry-run and refusal-
  path silence). The bullet ends
  with a "Mirrors the shape of
  `lesson_promoted` (0028) and
  `lessons_pruned` (0039): one
  operator-initiated cross-fleet-
  memory action, one typed event,
  no transcript scraping required
  to reconstruct what third-party
  wisdom landed in CROSS_LESSONS.md
  when." per the convention
  established by 0028/0039/0046.
- `lib/common.sh` — NO changes.
  `fleet_emit_event` is already
  the writer this ticket uses; no
  new helper.
- `prompts/` — NO changes.
- `tests/fixtures/lessons-import/`
  — NEW directory holding the
  six pack fixtures, the synthetic
  trusted-pubkeys.txt (with one
  trusted ed25519 pubkey and one
  untrusted pubkey for the
  refusal branch), the synthetic
  starter CROSS_LESSONS.md (10
  paragraphs, 4 of which are
  byte-identical to the
  `dedupe-collision.pack.json`'s
  paragraphs), and the test's
  kit-as-project events.jsonl
  fixture. The valid-signed pack
  was generated once via `openssl
  genpkey -algorithm ed25519`
  during fixture authoring and
  the signing key is checked in
  with the fixtures (TEST-ONLY,
  documented in a fixture README).
- `tests/lessons-import.sh` — top
  of file mirrors `tests/lessons-
  promote.sh` (closest prior
  cross-LESSONS writer; shares
  the namespace-section convention).
  Stubs live under `$HOME/.local/
  bin` per LESSONS 2026-05-26
  (PATH reset): `curl` (records
  argv, can return a fixture pack
  for the URL path OR exit non-
  zero for the failed-download
  branch), `openssl` (wraps real
  openssl when present; falls
  back to a deterministic stub
  when not). Counts use `awk …
  END { print n+0 }` per LESSONS
  2026-06-01. Per LESSONS
  2026-05-27 backup/restore via
  `cp`. Per LESSONS 2026-06-08
  every awk script declares
  `BEGIN { count = 0 }`. Per
  LESSONS 2026-06-08 `IFS=$'\t'`
  middle-empty-field uses `-`
  sentinel. Per LESSONS
  2026-06-11 the timestamp
  parser uses the full
  `'%Y-%m-%dT%H:%M:%SZ'` format.
  Per LESSONS 2026-06-15 the
  dedupe walk is ONE awk pass.
  Per LESSONS 2026-06-15 the
  section-finder uses the cursor-
  walk pattern. The clock is
  frozen via `FLEET_NOW_OVERRIDE`.
  Run-time budget: <10s.
- `bin/fleet` — local variables
  inside `lessons_import()` whose
  names match other subcommand
  functions MUST be prefixed (per
  LESSONS 2026-06-19 self-check
  false-positive trap). The
  catalog of names to avoid as
  plain `local` names: every
  subcommand function name in
  the kit (`promote`, `prune`,
  `rank`, `streak`, `stuck`,
  `flaky`, `digest`, `weekly`,
  `recap`, `incident`, `diff`,
  `morning`, `inbox`, `replay`,
  `tour`, `add`, `migrate`,
  `catchup`, `pulse`, `share`,
  `invoice`, `why`, `resume`,
  `vacation`, `onboard`,
  `doctor`). Use `lessons_
  import_*`-prefixed locals
  throughout. The local var
  named `count` (a near-
  universal collision risk) is
  acceptable because no
  subcommand function is named
  `count`.
- New deps: NONE. `curl`,
  `openssl`, `shasum`, `node`,
  `awk` are all pre-installed
  on macOS and required by
  the kit elsewhere. NO new
  top-level deps per the
  AGENTS.md hard constraint
  ("No new top-level deps that
  aren't shell-only or
  `node:`-builtin").
- Public API: additive on the
  event-type front — ONE new
  event type
  (`lessons_imported`) is the
  ONLY contract change. The
  `fleet_*` public function
  signatures are UNCHANGED.
  The CROSS_LESSONS.md
  namespace section
  convention (`## from
  <publisher>:<slug>`) is a
  new documented contract
  the operator's CROSS_
  LESSONS.md adopts on first
  import; existing
  cross-LESSONS files
  without imported packs
  are byte-equivalent.
- BREAKING flag: NO. The new
  event type is additive (per
  AGENTS.md § Telemetry
  "consumers MUST tolerate
  unknown types gracefully").
  Existing consumers do not
  break on the new type.
  Existing
  `fleet lessons-promote`
  (0028) is byte-equivalent
  (`lessons_imported` is a
  DIFFERENT typed event;
  promote still emits
  `lesson_promoted`).
- Reinstall required: NO.
  `lib/` and `prompts/` are
  untouched. The new event
  type is documented in
  AGENTS.md but the engine
  reads it via the existing
  `fleet_emit_event` helper
  unchanged.
- LESSONS to defend against:
  2026-05-25 (README "Daily
  ops" code block addition),
  2026-05-26 (`tail` shadow —
  `lessons_import` is safe),
  2026-05-26 (PATH reset —
  stubs in `$HOME/.local/
  bin`), 2026-05-27 (`$(cat)`
  trap — use `cp` for
  backup/restore in tests),
  2026-05-28 (printf
  leading-dash — every
  publisher/section/path
  printf goes through
  `printf -- '%s'`),
  2026-05-30 (`grep -F --`
  trap), 2026-06-01 (`grep
  -c file || echo 0` double-
  print — counts use `awk
  … END { print n+0 }`),
  2026-06-01 (dispatcher
  fall-through — every
  code path ends `exit
  0/2/3`), 2026-06-03
  (UTF-8 sign-extension —
  pack body UTF-8 round-
  trips intact; JSON
  escape via
  `preflight_json_escape`),
  2026-06-05 (dispatcher
  forward-reference — all
  `lessons_import_*`
  helpers defined ABOVE
  the dispatcher),
  2026-06-05 (bash 3.2
  LC_ALL caching — any
  string-length op via
  `LC_ALL=C awk`),
  2026-06-05 (export-in-
  subshell trap — manifest
  reads inside `( … )`),
  2026-06-08 (awk empty-
  string-key — `BEGIN {
  count = 0 }`), 2026-06-08
  (`IFS=$'\t'` middle-
  empty-field — sentinel
  `-`), 2026-06-11 (BSD
  `date -j -f` fills
  missing time fields —
  `created_at` parser uses
  full
  `'%Y-%m-%dT%H:%M:%SZ'`
  format), 2026-06-13 (no
  `*_json_escape` wrapper
  — calls
  `preflight_json_escape`
  directly), 2026-06-15
  (per-day shellout inside
  per-slug loops is
  O(window × N_slugs) —
  dedupe walk is one awk
  pass), 2026-06-15 (awk
  `while (match(s, /pat/))
  { s = before repl after
  }` infinite-loop trap
  — section-finder uses
  cursor-walk pattern
  because the `## from
  <publisher>` heading
  contains the literal
  match text), 2026-06-19
  (`local` shadows
  subcommand-function
  name self-check false
  positive — all
  `lessons_import()`
  locals prefixed
  `lessons_import_*`).
  Cross-LESSONS courtiq
  2026-05-22 (two-PR
  ship ritual —
  irrelevant; this is a
  runtime writer to
  CROSS_LESSONS.md, not
  a backlog flow).
  Cross-LESSONS fleet-
  control 2026-05-26
  (shell-out modules
  need an injectable
  runner — test stubs
  for `curl` and
  `openssl` are the
  injection point).
  Cross-LESSONS
  digitalcraft 2026-05-25
  (mirror-source allow-
  list trap, em-dash
  brand voice) is
  worth noting: this
  ticket does NOT
  enforce any character
  filter on imported
  paragraphs — they
  land verbatim, and
  the operator's normal
  LESSONS curation
  workflow (prune,
  edit-by-hand) is the
  recovery path if a
  publisher ships
  something unwanted.
- This ticket compounds
  0009 (cross-LESSONS
  aggregation — lessons-
  import writes to the
  same file the
  aggregator writes),
  0028 (`fleet lessons-
  promote` — import is
  the inter-operator
  complement to
  promote's intra-
  operator move), 0029
  (`fleet provenance`
  — provenance can
  attribute imported
  paragraphs back to
  their publisher),
  0051 (`fleet skill-
  gap` — coverage diff
  includes imported
  paragraphs), 0057
  (`fleet lessons-
  rank` — rank
  includes imported
  paragraphs in
  citation-frequency),
  0039 (`fleet
  lessons-prune` —
  prune respects
  EXPIRES on imported
  paragraphs), 0044
  (`fleet pr-footer`
  — pr-footer can
  cite imported
  lessons), 0061
  (`fleet invoice` —
  invoice's "lessons
  sourced from peers"
  line is a follow-
  up), 0063 (`fleet
  migrate` — migrate
  packages the CROSS_
  LESSONS.md
  including any
  imported sections,
  so a fresh-machine
  restore carries
  the imported
  packs intact). Per
  P-1 the diff is
  small: ~390 lines of
  `lessons_import_*`
  helpers + ~320
  lines of test + 6
  fixture pack files
  + 1 fixture
  trusted-pubkeys.txt
  + 1 fixture
  starter CROSS_
  LESSONS.md + 1
  AGENTS.md
  § Telemetry bullet
  + one help-text
  line + one README
  "Daily ops" line +
  one README
  paragraph.

## Implementation log

(Appended by the implementation-dev agent during execution.)
