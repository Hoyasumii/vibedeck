#!/usr/bin/env bash
# O formato novo (action/control/label) tem teste: codificação, decodificação tolerante e filtro por ação.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckCore/Logging\.swift$|^Tests/VibeDeckCoreTests/LoggingTests\.swift$'
T=Tests/VibeDeckCoreTests/LoggingTests.swift
grep -q 'func actionMetadataRoundTripsAndDecodesOlderEntries' "$T" || { echo "$T: teste de codificação/decodificação tolerante ausente"; exit 1; }
grep -q 'func actionFilterIncludesOnlyItsReactions' "$T" || { echo "$T: teste do filtro por ação ausente"; exit 1; }
run_tests LoggingTests
