#!/usr/bin/env bash
# Install the ax CLI into ~/.ax/bin.
set -euo pipefail

AX_BIN="$HOME/.ax/bin"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -x "$AX_BIN/ax" ]; then
  # "latest" (v0.3.1) ships no binaries; v0.4.0-rc.1 is the first with install.sh.
  export AX_VERSION=${AX_VERSION:-v0.4.0-rc.1}
  curl -fsSL "https://github.com/google/ax/releases/download/$AX_VERSION/install.sh" | sh
fi
export PATH="$AX_BIN:$PATH"
ax version

echo "Add to your shell: export PATH=\"$AX_BIN:\$PATH\""
