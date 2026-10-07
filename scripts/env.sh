# Sourced by the other scripts. Picks an SDK the installed toolchain can build SwiftUI with:
# the macOS 27 SDK turns @State into a macro whose plugin (SwiftUIMacros) ships only with Xcode,
# so with Command Line Tools alone we fall back to the newest macOS 26 SDK.
if [[ -z "${SDKROOT:-}" ]]; then
  DEV_DIR="$(xcode-select -p)"
  if [[ "$DEV_DIR" == *CommandLineTools* ]] && ! ls "$DEV_DIR"/usr/lib/swift/host/plugins | grep -q SwiftUIMacros; then
    SDK26="$(ls -d "$DEV_DIR"/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1)"
    [[ -n "$SDK26" ]] && export SDKROOT="$SDK26"
  fi
fi
