#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $RTT 'func buildToolDetectionCoversEcosystems' "falta o teste de detecção"
hasF $RTT '"./gradlew test": "gradle"' "falta caso Java (gradle)"
hasF $RTT '"mvn -q verify": "maven"' "falta caso Java (mvn)"
hasF $RTT '"dotnet test Foo.sln": "dotnet"' "falta caso C# (dotnet)"
hasF $RTT '"composer test": "composer"' "falta caso PHP (composer)"
hasF $RTT '"swift test --filter X": "swift"' "falta caso Swift"
hasF $RTT 'Set(cases.values).count == cases.count' "o teste deve exigir chaves diferentes"
finish
