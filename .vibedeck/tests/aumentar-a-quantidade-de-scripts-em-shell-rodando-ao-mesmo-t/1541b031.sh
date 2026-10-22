#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $RUN 'fn build_tool_detection\(\)' "falta o teste de detecção"
hasF $RUN 'BuildToolLock::keys_in("./gradlew build"), ["gradle"]' "falta caso Java (gradle)"
hasF $RUN 'BuildToolLock::keys_in("mvn package"), ["maven"]' "falta caso Java (mvn)"
hasF $RUN 'BuildToolLock::keys_in("dotnet build"), ["dotnet"]' "falta caso C# (dotnet)"
hasF $RUN 'BuildToolLock::keys_in("composer install"), ["composer"]' "falta caso PHP (composer)"
hasF $RUN 'BuildToolLock::keys_in("swift build -c release"), ["swift"]' "falta caso Swift"
finish
