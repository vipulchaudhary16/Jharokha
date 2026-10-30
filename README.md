# Jharokha

Automatic window tiling for macOS 15+. Every window gets a place as it opens, and the rest reflow when one closes.

A jharokha (झरोखा) is the carved, latticed window of Rajasthani palaces. Its working name was Pane: the bundle identifier `dev.pane.Pane` and the "Pane Local Signing" certificate keep it, so Accessibility access and settings carry over.

## Build and run

```sh
./scripts/install.sh         # builds, installs to /Applications and relaunches
                             # menu bar only; grant Accessibility access when asked
swift run JharokhaCoreChecks     # layout and tiling model checks
```

This needs only the Command Line Tools, not Xcode. Builds are signed with the "Pane Local Signing" certificate when your login keychain has one, so the Accessibility grant survives rebuilds. Without it they're ad-hoc signed, and macOS asks again after every build. `SIGN_IDENTITY` overrides the choice.

## Layout

- `Sources/JharokhaCore`: the pure layout engine (Grid, Columns, Rows, Side, plus ultrawide and vertical handling) and the per-screen tile and stack model.
- `Sources/Jharokha`: the app. It has the Accessibility window wrapper, window observer, tiling manager, hotkeys, menu bar and toasts.

## Shortcuts (⌃⌥ prefix, remappable in Settings › Keyboard)

| Keys | Action |
|---|---|
| ← → ↑ ↓ | Swap with the neighbour in that direction; past the screen edge, move to the next display |
| ↩ | Make the active window primary |
| ] / [ | Activate the next / previous window |
| ` / ⇧` | Next / previous window in this tile's stack |
| ⌘↓ / ⌘↑ | Scroll down / up through this tile's stack |
| ⌃⌥⇥ / ⌃⌥⇧⇥ | Tab View: every window, screen by screen |
| = / − / 0 | Grow / shrink the active window, reset sizes |
| F / ⇧F | Float the active window / always float its app |
| ⌘P | Pin the active app to every desktop (floats and follows you between screens) |
| Z | Focus mode |
| D | No peek: fade every other window |
| P | Privacy Mode: share one window; the others show only as app cards |
| R | Re-apply tiling |
| ⌘1–⌘5 | Tile up to N windows on this screen |

**Mouse:**
- Drag a window onto another tile to swap the two, or onto another screen to move it there. Hold ⌥⌘ while dragging to add it to that tile's stack instead.
- Drag the edge between two windows to resize both.
- Rest the pointer on the grip above the active window to open its stack chips or quick actions.

## Credits

Window-handling techniques (the size/position/size frame write, the enhanced-UI workaround, `_AXUIElementGetWindow`) follow [Rectangle](https://github.com/rxhanson/Rectangle) (MIT, © Ryan Hanson).

## Releasing

Add a `## [x.y.z]` section to `CHANGELOG.md`, then push a tag:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

GitHub Actions (`.github/workflows/release.yml`) builds a universal app and publishes a release with `Jharokha-x.y.z.dmg`, a zip and checksums, using the changelog section as notes. `UNIVERSAL=1 ./scripts/bundle.sh` makes the same DMG locally in `build/`.
