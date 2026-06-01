# LESSONS

Operational memory for agent-fleet.

## 2026-05-28 — printf '- foo' treats the leading dash as a flag

Bash builtin printf parses the first argument as flags, so a format
string starting with `-` fails with usage banners. Fix: prefix with
`--` end-of-options marker.

## 2026-05-30 — grep -qF "--flag" treats the pattern as an option too

When the pattern's first byte is `-`, both BSD and GNU grep parse it
as an unknown option. Insert `--` between the flags and the pattern.

## 2026-05-26 — naming a shell function `tail` shadows /usr/bin/tail

Dispatch functions named after coreutils binaries collide silently.
Use a `_cmd` suffix or `command tail` to bypass.
