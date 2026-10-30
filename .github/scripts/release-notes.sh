#!/bin/bash
# Prints the CHANGELOG.md section for a version, followed by install steps.
# Usage: .github/scripts/release-notes.sh 1.0.0
# Fails if the changelog has no entry for that version.
set -euo pipefail
VERSION="$1"
CHANGES=$(awk -v v="$VERSION" '
    $0 ~ "^## \\[" v "\\]" { found = 1; next }
    found && /^## \[/       { exit }
    found && /^\[[^]]+\]: / { exit }
    found                   { print }
' CHANGELOG.md)

if [[ -z "${CHANGES//[[:space:]]/}" ]]; then
    echo "error: CHANGELOG.md has no '## [$VERSION]' section. Add one before releasing." >&2
    exit 1
fi

cat <<NOTES
$CHANGES

## Install

1. Download **Jharokha-$VERSION.dmg** below and open it.
2. Drag **Jharokha** into **Applications**.
3. Open it once. Jharokha isn't notarized by Apple yet, so macOS blocks the first launch:
   - Click *Done*, then go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Jharokha.
   - Or in Terminal: \`xattr -dr com.apple.quarantine /Applications/Jharokha.app\`
4. The welcome guide asks for **Accessibility** access (System Settings → Privacy & Security → Accessibility), which is how every window manager moves windows. Then look for the arched-window icon in your menu bar.

Universal app (Apple silicon + Intel), macOS 15 Sequoia or later.
Full history: [CHANGELOG.md](https://github.com/vipulchaudhary16/Jharokha/blob/main/CHANGELOG.md).
NOTES
