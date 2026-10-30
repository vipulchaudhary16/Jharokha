#!/bin/zsh
# Builds Pane, replaces /Applications/Pane.app and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bundle.sh
pkill -x Pane || true
sleep 0.5
rm -rf /Applications/Pane.app
ditto build/Pane.app /Applications/Pane.app
open /Applications/Pane.app
echo "Installed /Applications/Pane.app"
