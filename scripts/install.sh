#!/bin/zsh
# Builds Jharokha, replaces /Applications/Jharokha.app and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bundle.sh
pkill -x Jharokha || true
pkill -x Pane || true          # builds from before the rename
sleep 0.5
rm -rf /Applications/Pane.app /Applications/Jharokha.app
ditto build/Jharokha.app /Applications/Jharokha.app
open /Applications/Jharokha.app
echo "Installed /Applications/Jharokha.app"
