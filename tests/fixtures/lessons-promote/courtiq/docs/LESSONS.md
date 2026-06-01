# LESSONS

Operational memory for courtiq.

## 2026-05-29 — node:sqlite types narrow only after .all()

Returned row union needs an explicit type predicate before downstream
property access; otherwise tsc flags every column read.

## 2026-05-30 — grep -qF "--flag" treats the pattern as an option too

When the pattern's first byte is `-`, both BSD and GNU grep parse it
as an unknown option. Insert `--` between the flags and the pattern.
