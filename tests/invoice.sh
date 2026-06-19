#!/bin/bash
# tests/invoice.sh — `bin/fleet invoice <slug>` monthly ROI receipt test.
#
# Ticket 0061. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0061-fleet-invoice-monthly-roi-receipt.md (14 boxes).
#
# Stubs under $HOME/.local/bin per LESSONS 2026-05-26 (PATH reset). Backup
# / restore via `cp` per LESSONS 2026-05-27. Counts via `awk … END { print
# n+0 }` per LESSONS 2026-06-01. Every awk script declares `BEGIN { count
# = 0 }` per LESSONS 2026-06-08. Per LESSONS 2026-06-08 IFS=$'\t' middle-
# empty-field uses `-` sentinel. Per LESSONS 2026-06-15 the month-bucket
# math is pure awk arithmetic — no per-day `date -j -v` shellout. The
# clock is frozen via FLEET_NOW_OVERRIDE. Per LESSONS 2026-05-30 help-text
# greps use `grep -qF -- "$kw"`. Run-time budget: <10s.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIX_ROOT="$REPO_ROOT/tests/fixtures/invoice"

TMP="$(mktemp -d -t fleet-invoice-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Pinned epoch: 2026-06-19T08:00:00Z. Default month = May 2026 (last
# calendar month). May 2026 window: 2026-05-01T00:00:00Z through
# 2026-05-31T23:59:59Z. Prior month = April 2026.
NOW_EPOCH=1781856000  # 2026-06-19T08:00:00Z
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

# Stage manifests under a discovery root.
FIX_TMP="$TMP/projects"
mkdir -p "$FIX_TMP"
export FLEET_DISCOVERY_ROOT="$FIX_TMP"

mk_manifest() {  # $1 = slug, [extra config lines]
  local slug="$1"; shift
  mkdir -p "$FIX_TMP/$slug"
  {
    printf 'PROJECT_NAME="%s"\n' "$slug"
    printf 'SLUG="%s"\n' "$slug"
    printf 'NAMESPACE="com.%s"\n' "$slug"
    printf 'REPO_URL="https://github.com/example/%s"\n' "$slug"
    printf 'SELF_CANCEL="20990101"\n'
    while [ $# -gt 0 ]; do
      printf '%s\n' "$1"
      shift
    done
  } > "$FIX_TMP/$slug/agents.config.sh"
}

# Helpers to emit fixture rows.
emit_event() {  # $1=cache $2=epoch $3=type $4=slug [extra k=v...]
  local cache="$1" ep="$2" type="$3" slug="$4"
  shift 4
  local extra=""
  while [ $# -gt 0 ]; do
    extra+=",\"${1%%=*}\":\"${1#*=}\""
    shift
  done
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"%s"%s}\n' \
    "$(iso_at "$ep")" "$slug" "$type" "$extra" >> "$cache/events.jsonl"
}

emit_run() {  # $1=cache $2=epoch $3=slug $4=cost $5=duration_ms
  local cache="$1" ep="$2" slug="$3" cost="$4" dur="${5:-300000}"
  printf '{"slug":"%s","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":%s,"duration_ms":%s,"result_head":"SHIP test"}\n' \
    "$slug" "$(iso_at "$ep")" "$(iso_at "$((ep + 60))")" "$cost" "$dur" \
    >> "$cache/runs.jsonl"
}

emit_completed() {  # $1=cache $2=epoch $3=slug $4=duration_ms
  local cache="$1" ep="$2" slug="$3" dur="$4"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"run_completed","exit":"0","duration_ms":"%s"}\n' \
    "$(iso_at "$ep")" "$slug" "$dur" >> "$cache/events.jsonl"
}

# Epoch anchors (UTC).
MAY_EP=1777593600    # 2026-05-01T00:00:00Z
APR_EP=1775001600    # 2026-04-01T00:00:00Z

# Sanity: above epochs.
mk_cache() {  # $1 = slug
  local cache="$HOME/.cache/$1-agent"
  mkdir -p "$cache"
  : > "$cache/events.jsonl"
  : > "$cache/runs.jsonl"
  printf -- '%s' "$cache"
}

# ========================================================================
# net-positive slug — 14 PRs in May, $7.84 cost. 11 PRs in April for prior.
# ========================================================================
mk_manifest net-positive
CACHE_NP="$(mk_cache net-positive)"
# May 2026 — 14 pr_footer_posted events between days 2..29.
for d in 2 3 4 6 8 10 12 14 16 18 20 22 25 29; do
  ep=$(( MAY_EP + (d-1) * 86400 + 12 * 3600 ))
  emit_event "$CACHE_NP" "$ep" pr_footer_posted "net-positive" "pr=$d"
  emit_run   "$CACHE_NP" "$ep" "net-positive" "0.56" "300000"
  emit_completed "$CACHE_NP" "$ep" "net-positive" "300000"
done
# Three gate_failed events in May (heal cycles).
for d in 5 11 19; do
  ep=$(( MAY_EP + (d-1) * 86400 + 13 * 3600 ))
  emit_event "$CACHE_NP" "$ep" gate_failed "net-positive" "check=shellcheck"
done
# Two lesson_draft_emitted events in May (send-backs).
for d in 7 21; do
  ep=$(( MAY_EP + (d-1) * 86400 + 14 * 3600 ))
  emit_event "$CACHE_NP" "$ep" lesson_draft_emitted "net-positive" "pr=$d"
done
# Prior month (April): 11 pr_footer_posted, $7.00 cost (delta line).
for d in 1 3 5 7 9 11 13 15 17 19 21; do
  ep=$(( APR_EP + (d-1) * 86400 + 12 * 3600 ))
  emit_event "$CACHE_NP" "$ep" pr_footer_posted "net-positive" "pr=apr$d"
  ap_cost="0.6364"  # ~ 7.00/11
  emit_run   "$CACHE_NP" "$ep" "net-positive" "$ap_cost" "300000"
done

# ========================================================================
# break-even slug — kit_cost ≈ Cursor alt ($20). 5 PRs in May → 6.25h
# displaced. Contractor = 6.25*$80 = $500. Min(20, 500) = 20. kit_cost
# = $20 → break-even branch.
# ========================================================================
mk_manifest break-even
CACHE_BE="$(mk_cache break-even)"
for d in 4 9 14 19 24; do
  ep=$(( MAY_EP + (d-1) * 86400 + 12 * 3600 ))
  emit_event "$CACHE_BE" "$ep" pr_footer_posted "break-even" "pr=$d"
  emit_run   "$CACHE_BE" "$ep" "break-even" "4.00" "180000"
done
# Prior month: 3 PRs.
for d in 6 12 20; do
  ep=$(( APR_EP + (d-1) * 86400 + 12 * 3600 ))
  emit_event "$CACHE_BE" "$ep" pr_footer_posted "break-even" "pr=apr$d"
  emit_run   "$CACHE_BE" "$ep" "break-even" "3.50" "180000"
done

# ========================================================================
# net-negative slug — kit_cost > 1.1 × alternative. Pick 1 PR & $50 cost.
# 1 PR × 75min = 1.25h. Contractor = $100. Cursor = $20.
# min = $20. 1.1 × 20 = $22. kit_cost = $50 > $22 → net_negative.
# ========================================================================
mk_manifest net-negative
CACHE_NN="$(mk_cache net-negative)"
ep=$(( MAY_EP + 9 * 86400 + 12 * 3600 ))
emit_event "$CACHE_NN" "$ep" pr_footer_posted "net-negative" "pr=1"
emit_run   "$CACHE_NN" "$ep" "net-negative" "50.00" "600000"
# Prior month: 2 PRs (so the "vs last month" delta still computes).
for d in 5 15; do
  ep=$(( APR_EP + (d-1) * 86400 + 12 * 3600 ))
  emit_event "$CACHE_NN" "$ep" pr_footer_posted "net-negative" "pr=apr$d"
  emit_run   "$CACHE_NN" "$ep" "net-negative" "10.00" "180000"
done

# ========================================================================
# first-month slug — only May data, no prior month → prior_month is empty.
# ========================================================================
mk_manifest first-month
CACHE_FM="$(mk_cache first-month)"
for d in 5 15 25; do
  ep=$(( MAY_EP + (d-1) * 86400 + 12 * 3600 ))
  emit_event "$CACHE_FM" "$ep" pr_footer_posted "first-month" "pr=$d"
  emit_run   "$CACHE_FM" "$ep" "first-month" "1.00" "300000"
done

# ========================================================================
# redacted-target slug — moderate data; exercise AC#11 --redact.
# Override MANUAL_PR_MINUTES to 120 and CONTRACTOR_USD_PER_HOUR to 100
# to test AC#5/AC#6 knobs.
# ========================================================================
mk_manifest redacted-target \
  'MANUAL_PR_MINUTES="120"' \
  'CONTRACTOR_USD_PER_HOUR="100"'
CACHE_RT="$(mk_cache redacted-target)"
for d in 3 10 17 24; do
  ep=$(( MAY_EP + (d-1) * 86400 + 12 * 3600 ))
  emit_event "$CACHE_RT" "$ep" pr_footer_posted "redacted-target" "pr=$d"
  emit_run   "$CACHE_RT" "$ep" "redacted-target" "2.00" "240000"
done

# Backup byte sizes for AC#13 pure-reader assertion.
mkdir -p "$TMP/backup"
for cache in "$CACHE_NP" "$CACHE_BE" "$CACHE_NN" "$CACHE_FM" "$CACHE_RT"; do
  base="$(basename "$cache")"
  mkdir -p "$TMP/backup/$base"
  cp "$cache/events.jsonl" "$TMP/backup/$base/events.jsonl"
  cp "$cache/runs.jsonl"   "$TMP/backup/$base/runs.jsonl"
done

# Prepend stub dir to PATH.
export PATH="$HOME/.local/bin:$PATH"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$1"; }

# ========================================================================
# AC#1 — Missing slug AND no --all: usage to stderr, exit 2. Unknown slug:
#         error to stderr, exit 2.
# ========================================================================
err="$TMP/err.txt"
if "$FLEET" invoice >"$TMP/out.txt" 2>"$err"; then
  fail "AC1: invoice with no slug should exit non-zero"
fi
if ! grep -qF -- 'invoice: usage: bin/fleet invoice <slug|--all>' "$err"; then
  fail "AC1: usage line missing on stderr (got: $(cat "$err"))"
fi

if "$FLEET" invoice bogus-slug >"$TMP/out.txt" 2>"$err"; then
  fail "AC1: invoice with unknown slug should exit non-zero"
fi
if ! grep -qF -- 'invoice: slug bogus-slug not found' "$err"; then
  fail "AC1: unknown-slug error missing (got: $(cat "$err"))"
fi
pass "AC1: usage + unknown-slug refusals"

# ========================================================================
# AC#2 — Default month is LAST CALENDAR MONTH. With NOW=2026-06-19, the
#         default window is 2026-05-01 through 2026-05-31.
# ========================================================================
"$FLEET" invoice net-positive >"$TMP/out.txt" 2>"$err" \
  || fail "AC2: invoice net-positive failed: $(cat "$err")"
if ! grep -qF -- 'May 2026' "$TMP/out.txt"; then
  fail "AC2: default month header missing 'May 2026' (got: $(cat "$TMP/out.txt"))"
fi
# JSON should report month=2026-05.
"$FLEET" invoice net-positive --json >"$TMP/out.txt" 2>"$err" \
  || fail "AC2: --json failed: $(cat "$err")"
node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if (d.month !== "2026-05") throw new Error("month="+d.month);' "$TMP/out.txt" \
  || fail "AC2: JSON month should be 2026-05"
pass "AC2: default month = last calendar month"

# ========================================================================
# AC#3 — --month YYYY-MM overrides. Invalid format / future month: exit 2.
# ========================================================================
"$FLEET" invoice net-positive --month 2026-04 >"$TMP/out.txt" 2>"$err" \
  || fail "AC3: --month 2026-04 failed: $(cat "$err")"
if ! grep -qF -- 'April 2026' "$TMP/out.txt"; then
  fail "AC3: --month 2026-04 header missing 'April 2026'"
fi
# Invalid format: not YYYY-MM.
if "$FLEET" invoice net-positive --month 2026/05 >"$TMP/out.txt" 2>"$err"; then
  fail "AC3: --month 2026/05 should refuse"
fi
if ! grep -qF -- 'invoice: --month must be YYYY-MM' "$err"; then
  fail "AC3: invalid-format error missing (got: $(cat "$err"))"
fi
# Out-of-range month.
if "$FLEET" invoice net-positive --month 2026-13 >"$TMP/out.txt" 2>"$err"; then
  fail "AC3: --month 2026-13 should refuse"
fi
if ! grep -qF -- 'invoice: --month must be YYYY-MM' "$err"; then
  fail "AC3: out-of-range month error missing"
fi
# Future month.
if "$FLEET" invoice net-positive --month 2027-01 >"$TMP/out.txt" 2>"$err"; then
  fail "AC3: future --month should refuse"
fi
if ! grep -qF -- 'invoice: --month cannot be in the future' "$err"; then
  fail "AC3: future-month error missing (got: $(cat "$err"))"
fi
pass "AC3: --month override + format/range/future refusals"

# ========================================================================
# AC#4 — PRs merged (pr_footer_posted count) / heal cycles (gate_failed
#         count) / send-backs (lesson_draft_emitted count) / runtime
#         (run_completed.duration_ms sum) all read from events.jsonl
#         window.
# ========================================================================
"$FLEET" invoice net-positive --json >"$TMP/out.txt" 2>"$err" \
  || fail "AC4: --json failed: $(cat "$err")"
node -e '
const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (d.prs_merged !== 14) throw new Error("prs_merged="+d.prs_merged+" want 14");
if (d.heal_cycles !== 3) throw new Error("heal_cycles="+d.heal_cycles+" want 3");
if (d.sendbacks !== 2) throw new Error("sendbacks="+d.sendbacks+" want 2");
if (d.runtime_minutes < 69 || d.runtime_minutes > 71) throw new Error("runtime_minutes="+d.runtime_minutes+" want ~70");
' "$TMP/out.txt" || fail "AC4: telemetry counts mismatch (got: $(cat "$TMP/out.txt"))"
pass "AC4: PRs / heal / sendbacks / runtime counts"

# ========================================================================
# AC#5 — Claude API spend reads runs.jsonl cost_usd. Displaced hours =
#         PRs × MANUAL_PR_MINUTES / 60. Manifest knob honored.
# ========================================================================
# Default manifest (MANUAL_PR_MINUTES unset → 75): 14 PRs * 75 / 60 = 17.5h.
"$FLEET" invoice net-positive --json >"$TMP/out.txt" 2>"$err" \
  || fail "AC5: --json failed: $(cat "$err")"
node -e '
const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (Math.abs(d.claude_usd - 7.84) > 0.01) throw new Error("claude_usd="+d.claude_usd+" want ~7.84");
if (Math.abs(d.displaced_hours - 17.5) > 0.01) throw new Error("displaced_hours="+d.displaced_hours+" want 17.5");
' "$TMP/out.txt" || fail "AC5: claude_usd / displaced_hours mismatch (got: $(cat "$TMP/out.txt"))"
# Override (MANUAL_PR_MINUTES=120): redacted-target has 4 PRs * 120 / 60 = 8h.
"$FLEET" invoice redacted-target --json >"$TMP/out.txt" 2>"$err" \
  || fail "AC5: redacted-target --json failed: $(cat "$err")"
node -e '
const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (Math.abs(d.displaced_hours - 8) > 0.01) throw new Error("displaced_hours="+d.displaced_hours+" want 8 (4 PRs * 120 / 60)");
' "$TMP/out.txt" || fail "AC5: MANUAL_PR_MINUTES override not honored"
pass "AC5: claude_usd + displaced_hours (default + manifest override)"

# ========================================================================
# AC#6 — Cursor alt = fixed $20. Contractor alt = displaced_hours *
#         CONTRACTOR_USD_PER_HOUR (default 80; manifest knob override
#         honored).
# ========================================================================
# net-positive: 17.5 * 80 = $1400. Cursor = $20.
"$FLEET" invoice net-positive --json >"$TMP/out.txt" 2>"$err" \
  || fail "AC6: --json failed"
node -e '
const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (d.cursor_alt_usd !== 20) throw new Error("cursor_alt_usd="+d.cursor_alt_usd+" want 20");
if (Math.abs(d.contractor_alt_usd - 1400) > 0.01) throw new Error("contractor_alt_usd="+d.contractor_alt_usd+" want 1400");
' "$TMP/out.txt" || fail "AC6: cursor/contractor alt mismatch"
# redacted-target: 8h * $100/h = $800.
"$FLEET" invoice redacted-target --json >"$TMP/out.txt" 2>"$err" \
  || fail "AC6: redacted-target --json failed"
node -e '
const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (Math.abs(d.contractor_alt_usd - 800) > 0.01) throw new Error("contractor_alt_usd="+d.contractor_alt_usd+" want 800 (8h*$100)");
' "$TMP/out.txt" || fail "AC6: CONTRACTOR_USD_PER_HOUR override not honored"
pass "AC6: cursor_alt + contractor_alt with manifest override"

# ========================================================================
# AC#7 — verdict: net_positive | break_even | net_negative.
# ========================================================================
# net-positive: kit_cost=7.84 vs min(20,1400)=20. 7.84 < 0.9*20=18 → net_positive.
"$FLEET" invoice net-positive --json >"$TMP/out.txt" 2>"$err" || fail "AC7: --json failed"
node -e '
const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (d.verdict !== "net_positive") throw new Error("verdict="+d.verdict+" want net_positive");
' "$TMP/out.txt" || fail "AC7: net-positive verdict wrong"

# break-even: kit_cost=20 vs min(20,500)=20. Within ±10% → break_even.
"$FLEET" invoice break-even --json >"$TMP/out.txt" 2>"$err" || fail "AC7: break-even --json failed"
node -e '
const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (d.verdict !== "break_even") throw new Error("verdict="+d.verdict+" want break_even (claude_usd="+d.claude_usd+")");
' "$TMP/out.txt" || fail "AC7: break-even verdict wrong"

# net-negative: kit_cost=50 vs min(20,100)=20. 50 > 1.1*20=22 → net_negative.
"$FLEET" invoice net-negative --json >"$TMP/out.txt" 2>"$err" || fail "AC7: net-negative --json failed"
node -e '
const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (d.verdict !== "net_negative") throw new Error("verdict="+d.verdict+" want net_negative");
' "$TMP/out.txt" || fail "AC7: net-negative verdict wrong"

# Text mode: net-negative should show "investigate" nudge. net-positive should NOT.
"$FLEET" invoice net-negative >"$TMP/out.txt" 2>"$err" || fail "AC7: net-negative text failed"
if ! grep -qF -- 'investigate' "$TMP/out.txt"; then
  fail "AC7: net-negative should show 'investigate' nudge"
fi
"$FLEET" invoice net-positive >"$TMP/out.txt" 2>"$err" || fail "AC7: net-positive text failed"
if grep -qF -- 'investigate' "$TMP/out.txt"; then
  fail "AC7: net-positive should NOT show 'investigate' nudge"
fi
pass "AC7: verdict net_positive / break_even / net_negative + investigate nudge"

# ========================================================================
# AC#8 — "this month vs last month" diff line. First-ever-month renders
#         "(no prior month data)".
# ========================================================================
# net-positive has both May and April → diff line should show percentages.
"$FLEET" invoice net-positive >"$TMP/out.txt" 2>"$err" || fail "AC8: failed"
if ! grep -qF -- 'this month vs last month' "$TMP/out.txt"; then
  fail "AC8: net-positive should show 'this month vs last month' line"
fi
# May=14 PRs vs April=11 PRs → ~+27%.
if ! grep -qE 'PRs \+[0-9]+%' "$TMP/out.txt"; then
  fail "AC8: net-positive should show 'PRs +NN%' delta"
fi

# first-month slug: no prior month data.
"$FLEET" invoice first-month >"$TMP/out.txt" 2>"$err" || fail "AC8: first-month failed"
if ! grep -qF -- '(no prior month data)' "$TMP/out.txt"; then
  fail "AC8: first-month should show '(no prior month data)'"
fi
pass "AC8: month vs prior-month + first-month branch"

# ========================================================================
# AC#9 — --all sums every slug. Verdict computed on the SUM. Date-call
#         budget < 10 across the whole --all run.
# ========================================================================
DATE_COUNT_FILE="$TMP/date-calls.txt"
echo 0 > "$DATE_COUNT_FILE"
REAL_DATE="$(command -v date)"
cat > "$HOME/.local/bin/date" <<EOF
#!/bin/bash
n=\$(cat "$DATE_COUNT_FILE" 2>/dev/null || echo 0)
echo \$((n + 1)) > "$DATE_COUNT_FILE"
exec "$REAL_DATE" "\$@"
EOF
chmod +x "$HOME/.local/bin/date"
echo 0 > "$DATE_COUNT_FILE"

PATH="$HOME/.local/bin:$PATH" "$FLEET" invoice --all >"$TMP/out.txt" 2>"$err" \
  || fail "AC9: --all failed: $(cat "$err")"
rm -f "$HOME/.local/bin/date"

# Should mention all 5 fixture slugs (per-slug breakdown table).
for s in net-positive break-even net-negative first-month redacted-target; do
  grep -qF -- "$s" "$TMP/out.txt" || fail "AC9: --all missing slug '$s' in breakdown"
done
date_calls="$(cat "$DATE_COUNT_FILE")"
if [ "$date_calls" -ge 10 ]; then
  fail "AC9: --all used $date_calls date calls (must be < 10) per LESSONS 2026-06-15"
fi
pass "AC9: --all (5 slugs, < 10 date calls)"

# ========================================================================
# AC#10 — --ytd rolls up every month-to-date. With NOW=2026-06-19, 6 month
#         rows (Jan..Jun) render.
# ========================================================================
"$FLEET" invoice net-positive --ytd >"$TMP/out.txt" 2>"$err" \
  || fail "AC10: --ytd failed: $(cat "$err")"
# Expect 6 month rows: 2026-01 .. 2026-06.
ytd_rows="$(grep -cE '^[[:space:]]*2026-0[1-6][[:space:]]' "$TMP/out.txt" || true)"
if [ "$ytd_rows" != "6" ]; then
  fail "AC10: --ytd should render 6 month rows (Jan-Jun); got $ytd_rows. Out: $(cat "$TMP/out.txt")"
fi
if ! grep -qF -- 'YTD totals' "$TMP/out.txt"; then
  fail "AC10: --ytd should have 'YTD totals' footer"
fi
pass "AC10: --ytd (6 month rows + YTD totals footer)"

# ========================================================================
# AC#11 — --redact replaces slug name, bands costs, strips repo URLs.
# ========================================================================
"$FLEET" invoice redacted-target --redact >"$TMP/out.txt" 2>"$err" \
  || fail "AC11: --redact failed: $(cat "$err")"
# Slug name "redacted-target" must NOT appear in the output.
if grep -qF -- 'redacted-target' "$TMP/out.txt"; then
  fail "AC11: --redact should remove slug name 'redacted-target' (got: $(cat "$TMP/out.txt"))"
fi
# Should contain a pseudonym like project-a.
if ! grep -qE 'project-[a-z]' "$TMP/out.txt"; then
  fail "AC11: --redact should render pseudonym 'project-X'"
fi
# Costs should be banded (~$X / >$N / <$N) — no exact decimal "$8.00".
if grep -qE '\$8\.00|\$2\.00' "$TMP/out.txt"; then
  fail "AC11: --redact should band exact dollar amounts (still found exact decimals)"
fi
pass "AC11: --redact replaces slug, bands costs"

# ========================================================================
# AC#12 — --json emits a structured object with all required keys.
# ========================================================================
"$FLEET" invoice net-positive --json >"$TMP/out.txt" 2>"$err" \
  || fail "AC12: --json failed: $(cat "$err")"
node -e '
const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const required = ["slug","month","prs_merged","heal_cycles","sendbacks","runtime_minutes","claude_usd","displaced_hours","cursor_alt_usd","contractor_alt_usd","net_vs_cursor","net_vs_contractor","cost_per_pr","verdict","prior_month"];
for (const k of required) {
  if (!(k in d)) throw new Error("missing key: "+k);
}
if (typeof d.prior_month !== "object") throw new Error("prior_month should be object");
if (!["net_positive","break_even","net_negative"].includes(d.verdict)) throw new Error("verdict="+d.verdict);
' "$TMP/out.txt" || fail "AC12: JSON shape invalid"
pass "AC12: --json shape complete"

# ========================================================================
# AC#13 — pure reader: events.jsonl + runs.jsonl byte sizes unchanged.
# ========================================================================
# Re-run a few invocations after the reads above.
"$FLEET" invoice --all --json >/dev/null 2>&1 || true
"$FLEET" invoice net-positive --month 2026-04 >/dev/null 2>&1 || true
for cache in "$CACHE_NP" "$CACHE_BE" "$CACHE_NN" "$CACHE_FM" "$CACHE_RT"; do
  base="$(basename "$cache")"
  for f in events.jsonl runs.jsonl; do
    a_size=$(wc -c <"$TMP/backup/$base/$f" | tr -d ' ')
    b_size=$(wc -c <"$cache/$f"            | tr -d ' ')
    if [ "$a_size" != "$b_size" ]; then
      fail "AC13: pure-reader violated — $cache/$f changed $a_size → $b_size bytes"
    fi
  done
done
pass "AC13: pure reader (no events.jsonl / runs.jsonl writes)"

# ========================================================================
# AC#14 — lib/common.sh + prompts/ untouched on the feature branch.
# ========================================================================
cd "$REPO_ROOT"
changed="$(git diff --name-only origin/main...HEAD -- lib/common.sh prompts/ 2>/dev/null || true)"
if [ -n "$changed" ]; then
  fail "AC14: lib/common.sh or prompts/ changed on branch: $changed"
fi
pass "AC14: lib/common.sh + prompts/ untouched"

# ========================================================================
# AC#15 — --help mentions --all, --month, --ytd, --redact, --json. Help
#         block exits cleanly.
# ========================================================================
HELP_OUT="$TMP/help.txt"
"$FLEET" invoice --help >"$HELP_OUT" 2>"$err" \
  || fail "AC15: --help exited non-zero (err: $(cat "$err"))"
for kw in "--all" "--month" "--ytd" "--redact" "--json"; do
  grep -qF -- "$kw" "$HELP_OUT" || fail "AC15: help missing '$kw'"
done
pass "AC15: --help mentions --all + --month + --ytd + --redact + --json"

echo
echo "all 15 invoice acceptance criteria green"
