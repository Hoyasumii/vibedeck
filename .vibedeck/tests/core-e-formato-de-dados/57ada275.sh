#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# RuleCheck.createdAt com frações de segundo; nome do arquivo yyyyMMdd-HHmmss-<8 do id>.json em GMT.
applies '(^|/)Sources/VibeDeckCore/(Rules|ProjectStore|Models)\.swift'
python3 -I - <<'PY'
import re, sys
bad = 0
rules = open("Sources/VibeDeckCore/Rules.swift").read()
m = re.search(r'public struct RuleCheck\b.*?\n\}', rules, re.S)
enc = re.search(r'func encode\(to.*?\n    \}', m.group(0), re.S) if m else None
if not enc or not re.search(r'forKey: \.createdAt', enc.group(0)) or "ISO8601FormatStyle(includingFractionalSeconds: true)" not in enc.group(0):
    print("Sources/VibeDeckCore/Rules.swift: RuleCheck.encode deve gravar createdAt com Date.ISO8601FormatStyle(includingFractionalSeconds: true)"); bad += 1
store = open("Sources/VibeDeckCore/ProjectStore.swift").read()
m = re.search(r'func checkFileName\(.*?\n    \}', store, re.S)
body = m.group(0) if m else ""
for needle, why in [('\\(year: .defaultDigits)\\(month: .twoDigits)\\(day: .twoDigits)-', "yyyyMMdd-"),
                    ('\\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\\(minute: .twoDigits)\\(second: .twoDigits)', "HHmmss"),
                    ("timeZone: .gmt", "fuso GMT"), ("en_US_POSIX", "locale POSIX"),
                    ("check.id.uuidString.prefix(8).lowercased()).json", "8 chars do id + .json")]:
    if needle not in body:
        print(f"Sources/VibeDeckCore/ProjectStore.swift: checkFileName mudou ({why})"); bad += 1
sys.exit(1 if bad else 0)
PY
