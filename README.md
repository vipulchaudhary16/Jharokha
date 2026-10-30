# Pane

Automatic window tiling for macOS 15+. Every window gets a place as it opens, and the rest reflow when one closes.

## Build and run

```sh
./scripts/install.sh         # builds, installs to /Applications and relaunches
                             # menu bar only; grant Accessibility access when asked
swift run PaneCoreChecks     # layout and tiling model checks
```

This needs only the Command Line Tools, not Xcode. Builds are signed with the "Pane Local Signing" certificate when your login keychain has one, so the Accessibility grant survives rebuilds. Without it they're ad-hoc signed, and macOS asks again after every build. `SIGN_IDENTITY` overrides the choice.

## Layout

- `Sources/PaneCore`: the pure layout engine (Grid, Columns, Rows, Side, plus ultrawide and vertical handling) and the per-screen tile and stack model.
- `Sources/Pane`: the app. It has the Accessibility window wrapper, window observer, tiling manager, hotkeys, menu bar and toasts.

## Shortcuts (⌃⌥ prefix, remappable in Settings › Keyboard)

| Keys | Action |
|---|---|
| ← → ↑ ↓ | Swap with the neighbour in that direction; past the screen edge, move to the next display |
| ↩ | Make the active window primary |
| ] / [ | Activate the next / previous window |
| ` / ⇧` | Next / previous window in this tile's stack |
| ⌘↓ / ⌘↑ | Scroll down / up through this tile's stack |
| ⌥⇥ / ⌥⇧⇥ (no ⌃) | Tab View: every window, screen by screen |
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
