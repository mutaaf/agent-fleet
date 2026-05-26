#!/bin/bash
# agent-fleet/lib/install.sh — install one project's fleet agents into launchd.
#
# Usage: bash install.sh /abs/path/to/project   (the dir holding agents.config.sh)
#
# macOS refuses to let launchd-launched bash touch ~/Desktop without Full Disk
# Access, so we copy the kit (lib + prompts) AND the project's manifest to a
# TCC-safe location under ~/.local/share, and point the plists there. The agents
# themselves operate on a fresh git checkout under ~/.cache, also TCC-safe.
#
# Idempotent — re-run after editing the manifest or any kit script to refresh.

set -euo pipefail

PROJECT_DIR="$( cd "${1:?usage: install.sh /abs/path/to/project}" && pwd )"
[ -f "$PROJECT_DIR/agents.config.sh" ] || { echo "no agents.config.sh in $PROJECT_DIR" >&2; exit 2; }

# shellcheck disable=SC1090
source "$PROJECT_DIR/agents.config.sh"
: "${SLUG:?manifest missing SLUG}"
NAMESPACE="${NAMESPACE:-com.fleet.$SLUG}"
SHIP_MINUTE="${SHIP_MINUTE:-41}"
# Optional. When set (e.g. "0 6 12 18"), ship fires only at those hours instead
# of every hour — used to throttle the cadence on projects under rate-limit
# pressure. Empty (the default) keeps the original "every hour at :SHIP_MINUTE".
SHIP_HOURS="${SHIP_HOURS:-}"
GROOM_HOURS="${GROOM_HOURS:-0 6 12 18}"
GROOM_MINUTE="${GROOM_MINUTE:-17}"
REVIEW_INTERVAL="${REVIEW_INTERVAL:-300}"
ENG_ENABLED="${ENG_ENABLED:-0}"
ENG_HOURS="${ENG_HOURS:-3 9 15 21}"
ENG_MINUTE="${ENG_MINUTE:-23}"

KIT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
INSTALL_ROOT="$HOME/.local/share/agent-fleet"
CFG_DIR="$INSTALL_ROOT/projects/$SLUG"
LOG_DIR="$HOME/.cache/${SLUG}-agent/logs"
AGENTS_DIR="$HOME/Library/LaunchAgents"
DOMAIN="gui/$UID"

mkdir -p "$INSTALL_ROOT" "$CFG_DIR" "$LOG_DIR" "$AGENTS_DIR"

# TCC-safe copy of the engine (shared by all projects) + this project's manifest.
/bin/cp -Rf "$KIT_ROOT/lib"     "$INSTALL_ROOT/"
/bin/cp -Rf "$KIT_ROOT/prompts" "$INSTALL_ROOT/"
# Same file? Skip the copy (otherwise cp -f errors "are identical"). Happens when
# install is re-run against the already-installed manifest dir (e.g. fleet-control's
# in-place edit for a project whose working tree is gone).
if ! [ "$PROJECT_DIR/agents.config.sh" -ef "$CFG_DIR/agents.config.sh" ]; then
  /bin/cp -f "$PROJECT_DIR/agents.config.sh" "$CFG_DIR/agents.config.sh"
fi
chmod +x "$INSTALL_ROOT/lib/"*.sh

# --- prompt-version pin (ticket 0005) -------------------------------------
# Stamp the COPIED manifest with the current prompts/ SHA so the runner can
# tell, at every fire, whether the kit has drifted since this install. The
# operator's SOURCE manifest is left untouched — they own it. Idempotent:
# strip any prior pin lines before re-appending so re-running install.sh
# never accumulates duplicate stamps.
#
# We write two lines: a `# PROMPTS_SHA pinned at install time: <sha>` audit
# comment (per ticket spec — visible at a glance to humans grepping the
# manifest) AND a real `PROMPTS_SHA="<sha>"` assignment so that sourcing
# the manifest in lib/common.sh actually sets the variable the drift check
# reads. The two lines move together; the strip pattern catches both.
PROMPTS_DIR_FOR_PIN="$INSTALL_ROOT/prompts"
if [ -d "$PROMPTS_DIR_FOR_PIN" ]; then
  PIN_SHA=$( (cd "$PROMPTS_DIR_FOR_PIN/.." && find prompts -type f -name '*.md' | sort | xargs cat) \
              | shasum -a 256 | awk '{print $1}' )
  if [ -n "$PIN_SHA" ]; then
    # macOS sed needs the empty `-i ''` arg. Strip any old stamp (both lines),
    # then append the fresh pair.
    /usr/bin/sed -i '' \
      -e '/^# PROMPTS_SHA pinned at install time:/d' \
      -e '/^PROMPTS_SHA=/d' \
      "$CFG_DIR/agents.config.sh"
    {
      printf '# PROMPTS_SHA pinned at install time: %s\n' "$PIN_SHA"
      printf 'PROMPTS_SHA="%s"\n' "$PIN_SHA"
    } >> "$CFG_DIR/agents.config.sh"
  fi
fi

# Emit a <key>StartCalendarInterval</key> block from a list of hours at one minute.
calendar_array() {  # $1 = "0 6 12 18", $2 = minute
  echo "  <key>StartCalendarInterval</key>"; echo "  <array>"
  for h in $1; do
    echo "    <dict><key>Hour</key><integer>$h</integer><key>Minute</key><integer>$2</integer></dict>"
  done
  echo "  </array>"
}

# Emit one plist. $1=label suffix (ship/groom/review/eng) $2=runner $3=schedule-xml
write_plist() {
  local suffix="$1" runner="$2" schedule="$3"
  local label="$NAMESPACE.agent-$suffix"
  cat >"$AGENTS_DIR/$label.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$INSTALL_ROOT/lib/$runner</string>
    <string>$CFG_DIR</string>
  </array>
$schedule
  <key>StandardOutPath</key><string>$LOG_DIR/launchd-$suffix.out</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/launchd-$suffix.err</string>
  <key>ProcessType</key><string>Background</string>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
EOF
}

if [ -n "$SHIP_HOURS" ]; then
  write_plist ship ship.sh "$(calendar_array "$SHIP_HOURS" "$SHIP_MINUTE")"
else
  write_plist ship ship.sh "  <key>StartCalendarInterval</key>
  <dict><key>Minute</key><integer>$SHIP_MINUTE</integer></dict>"
fi
write_plist groom  groom.sh  "$(calendar_array "$GROOM_HOURS" "$GROOM_MINUTE")"
write_plist review review.sh "  <key>StartInterval</key><integer>$REVIEW_INTERVAL</integer>"

LABELS="agent-ship agent-groom agent-review"
if [ "$ENG_ENABLED" = "1" ]; then
  write_plist eng eng.sh "$(calendar_array "$ENG_HOURS" "$ENG_MINUTE")"
  LABELS="$LABELS agent-eng"
fi

# (Re)load. bootout is idempotent on a missing label.
for L in $LABELS; do launchctl bootout "$DOMAIN/$NAMESPACE.$L" 2>/dev/null || true; done
for L in $LABELS; do
  launchctl bootstrap "$DOMAIN" "$AGENTS_DIR/$NAMESPACE.$L.plist"
  launchctl enable "$DOMAIN/$NAMESPACE.$L"
done

echo
echo "✓ installed fleet agents for $SLUG ($NAMESPACE.*):"
if [ -n "$SHIP_HOURS" ]; then
  echo "    agent-ship   — at :$SHIP_MINUTE on hours [$SHIP_HOURS]"
else
  echo "    agent-ship   — every hour at :$SHIP_MINUTE"
fi
echo "    agent-groom  — at :$GROOM_MINUTE on hours [$GROOM_HOURS]"
echo "    agent-review — every $((REVIEW_INTERVAL/60)) min (polls; self-gates)"
[ "$ENG_ENABLED" = "1" ] && echo "    agent-eng    — at :$ENG_MINUTE on hours [$ENG_HOURS]"
echo
echo "Engine:    $INSTALL_ROOT/lib  (TCC-safe)"
echo "Manifest:  $CFG_DIR/agents.config.sh"
echo "Logs:      $LOG_DIR/"
echo "Run now:   launchctl kickstart -k $DOMAIN/$NAMESPACE.agent-ship"
echo "Uninstall: bash $KIT_ROOT/lib/uninstall.sh $PROJECT_DIR"

# --- cross-project LESSONS aggregation (ticket 0009) ---------------------
# Re-merge every installed project's docs/LESSONS.md into
# ~/.local/share/agent-fleet/CROSS_LESSONS.md so prompts running inside any
# project's fresh checkout can see what the rest of the fleet has learned.
# Idempotent: fleet lessons-sync only rewrites the file when content
# changes, so re-running install.sh stays a no-op for the merged file's
# mtime when no new lessons exist. Best-effort: a failure here MUST NOT
# undo the launchctl bootstrap above (the install is still successful).
#
# Test seam: FLEET_LESSONS_SYNC_CMD lets tests/lessons-sync.sh point at a
# stub binary without shadowing `fleet` on PATH.
LESSONS_SYNC_CMD="${FLEET_LESSONS_SYNC_CMD:-$KIT_ROOT/bin/fleet}"
if [ -x "$LESSONS_SYNC_CMD" ]; then
  "$LESSONS_SYNC_CMD" lessons-sync >/dev/null 2>&1 || true
fi
