# Shoji feature analysis and build decision

Sources: shojimac.com landing page, /docs (how-tiling-works, stacks, resizing, no-peek,
clean-space, tab-view, menu-bar-panel, keyboard-shortcuts), /changelog (v1.3, 29 Oct 2026).
Shoji is paid ($14.99, no trial, no public DMG), so no binary was inspected. Everything
below is *documented* behaviour, not observed implementation.

## 1. Shoji feature spec

### Core: automatic tiling (the thing Rectangle does not do)
- Every new standard window is placed automatically. Rule: "each new window takes half of the newest space".
- Closing, minimizing, hiding, or moving a window to another screen makes the rest reflow. Reflow starts on the close/minimize *click*, during the close animation.
- Window order is the order windows opened. The first window is primary. If the primary closes, the next window becomes primary.
- Layouts are per screen, and sizes are stored per screen and per Space:
  - **Grid** (default): 1 fills the screen; 2 side by side; 3 has the right half split top and bottom; 4 is a 2×2 grid.
  - **Columns**: full height. The first column takes the main share, and the others split the rest.
  - **Rows**: full width, primary on top.
  - **Side**: primary large on the left, with the others in a right column.
- Capacity (MacBook / big monitor): Grid 4/4, Columns 3/4, Rows 2/3, Side 3/4. The default count is 3, user-selectable from 1 to 4.
- **Ultrawide** (width ≥ 2×height): in Side, two large windows plus a ¼-width column, up to 5 windows.
- **Vertical monitor**: rows by default. Grid and Side put the main window on top. Columns is disabled.
- **Main window size**: Half (default), 60%, or Two-thirds.
- **Minimum sizes**: learns each app's minimum size and stores it locally. Split lines move to make room. If the windows can't fit, it tiles fewer and greys out those counts in the menu, naming the app that causes the limit.
- **Never tiled**: dialogs, sheets, panels, pop-ups, minimized, full-screen, and non-resizable windows, excluded apps, plus defaults (Calculator, Stickies, System Settings, iPhone Mirroring, Photo Booth). Floating windows go in the middle.
- **Tabbed apps** (Terminal, Ghostty): a new tab takes the existing window's slot, and other windows don't move.
- Pauses while Stage Manager is on. Works with Spaces. Supports a per-screen or all-screens "screen edge" reserve for third-party docks and bars.

### Stacks
- When a screen is full, a new window stacks on top in the active tile at the same size. A one-time notice explains this.
- ⌥⌘-drag onto a tile adds the window to that tile's stack (highlight text: "Add to stack").
- **Grip** above the active window: one orange segment per stacked window, and clicking a segment shows that window.
- Hovering the grip opens a chip bar with app icons. It supports ‹ › arrows, scrolling, × or middle-click to close, and dragging a chip to another tile ("Move here").
- An inactive stacked tile shows orange dots in the gap above it. Click a dot to show that window.
- If the showing window closes or minimizes, the most recently used window in the tile comes forward. Swaps move only the showing windows. Resizing a tile resizes every window in it.
- Alternative setting: "Float in the middle" with a "This Space is full" notice.

### Rearranging and resizing
- ⌘-drag a title bar onto another window to swap them. Dragging a window onto another screen moves it there.
- Drag the edge between windows to resize. Neighbours make room, and the outer screen edges stay fixed.
- ⌃⌥=/− step-resizes by moving shared edges, with "Minimum/Maximum size reached" toasts and the alert sound. ⌃⌥0 resets sizes.
- Sizes belong to *positions*, not windows, so they survive swaps.

### Modes
- **Focus** (⌃⌥Z): the active window fills the screen, and pressing again restores everything.
- **No peek** (⌃⌥D): dims and blurs every window except the active app's window, its sheets and menus, the menu bar, and the Dock. Dim ranges from 10–90% (default 50%) with an optional blur. Works on all screens.
- **Clean Space** (⌃⌥P): the active window is shown on a plain background (Graphite, Mist, or Stone), and everything else goes behind it. Nothing is moved or closed. New windows opened on that screen join it. Turns off on sleep, lock, or screen disconnect, and the menu bar icon shows a mark while it's on.
- **Tab View** (⌃⌥⇥ / ⌃⌥⇧⇥): a window switcher laid out per screen like the real desktop. Each tile shows the app icon, app name, and window title, with minimized windows in a row below. The previous window is preselected, arrow keys move spatially across screens, and you release the keys, press Return, or click to switch. Esc cancels. Titles are read only while it's open.
- **Retile** (⌃⌥R): restores every window's position, and a toast says whether anything had moved.
- **Float toggle** (⌃⌥F) and "always float this kind" (⌃⌥⇧F).

### Keyboard (prefix ⌃⌥, remappable)
| Keys | Action |
|---|---|
| ←→↑↓ | Swap with the neighbour in that direction; past the screen edge, move to the next display |
| ↩ | Make the active window primary |
| ] / [ | Activate the next / previous window |
| ` / ⇧` | Next / previous window in this tile's stack |
| = / − / 0 | Grow / shrink / reset sizes |
| F / ⇧F | Float toggle / always float this kind of window |
| Z D P R | Focus / No peek / Clean Space / Retile |
| ⌘1–⌘5 | Tile N windows on this screen (also pauses) |

The shortcut editor warns about conflicts with macOS shortcuts and suggests free keys. A "Secure Input" card appears when shortcuts are blocked.

### UI and settings
- **Menu bar panel**: status dot (green, orange, grey, red), action cards (Grant access, Activate, Update, Secure Input), a mini layout preview with app icons and Reset sizes, a layout picker and count picker with disabled reasons, No peek with a slider, Clean Space, a "Tile <app>" toggle, quick switches (Retile, Borders, Hover focus), Settings, and Shortcuts.
- **Highlight**: None, active border, all borders, or glow, with a colour setting. Gap spacing defaults to 8pt.
- **Toggles**: quick-action hover bar, hover-to-focus, shortcuts on/off, stack when full, open at login.
- **Other settings**: separate light/dark appearance, 7 alternate app icons, and 5 languages (en, es, ja, ko, zh-Hans).
- **Onboarding**: welcome tour, "first tidy", Accessibility walkthrough, What's New window.
- **Distribution**: licence-key activation and deactivation, Sparkle-style signed updates (checks daily and asks before installing), Developer ID and notarization, not sandboxed, macOS 15+.
- **Performance targets**: about 62 MB RAM and about 1% CPU.

## 2. Rectangle today (cloned at ./Rectangle, MIT, ~28k lines Swift, macOS 14+)
- The architecture is command-driven: shortcut or drag-snap → `WindowAction` → one of 112 `WindowCalculation` classes → write the frame. There is no persistent model of which window is in which tile.
- It does not observe window creation or destruction. The only `AXObserver` use is `TitleBarManager` (title-bar double-click) and the animation lookup. Automatic placement and reflow, which are Shoji's core, do not exist.
- Closest pieces: `MultiWindow/` ("Tile all", tile rows/columns, cascade, cycle stacked windows as one-shot commands), `GridTiling.swift` (fits windows against fixed and resizable min/max sizes), `StackBadge/` (a stacked-window badge and list panel), `TodoMode/` (reserved sidebar).
- Reusable infrastructure: `AccessibilityElement.swift` (AX wrapper), `ScreenDetection.swift`, `AccessibilityAuthorization/`, MASShortcut, Sparkle, `LaunchOnLogin`, and window animation.

## 3. Decision: build our own app and borrow Rectangle's MIT code

Extending Rectangle would mean adding a second, opposite paradigm (stateful auto-tiler) next to its
stateless snapping engine. Its 112 calculation classes, snap areas, and settings would mostly be dead
weight or conflict with automatic layout (snapping would fight reflow). We'd also carry a permanent
fork against an active upstream.

The plan:
- Start a new Swift/SwiftUI menu-bar app (macOS 15+) with our own name and branding (not Shoji's name, icons, or copy).
- Copy and adapt, with MIT attribution: `AccessibilityElement`, `ScreenDetection`, the `GridTiling` constraint solver, the accessibility onboarding, and the MASShortcut + Sparkle wiring.
- Write fresh: the window observer, the layout model, stacks, modes, the overlay UI, and the panel.

### Proposed architecture
1. **WindowObserver**: a per-app `AXObserver` for created, destroyed, miniaturized, moved, resized, and focused-changed events. `NSWorkspace` provides launch, terminate, hide, and Space-change events. The window filter uses AX subrole `AXStandardWindow`, the resizable attribute, and the exclusion list.
2. **LayoutModel** (pure and unit-tested): Screen → Space → ordered tiles, each tile holding a stack of window IDs, plus per-position split ratios and learned min sizes. Layout functions take the layout kind, count, main ratio, orientation, gaps, and rect, and return tile rects.
3. **Applier**: diffs the target rects against the current frames and writes AX position and size in batches. It reads back the frame the app accepted and feeds min-size learning, using the `GridTiling` approach.
4. **Interactions**: a CGEventTap for ⌘-drag and ⌥⌘-drag swap/stack, edge-drag resize detection, and hover focus.
5. **Overlays** (non-activating `NSPanel`s): borders and glow, the grip and chip bar, stack dots, toasts, No peek (per-screen dim and blur `NSVisualEffectView` ordered directly below the active window), Clean Space (an opaque backdrop below the active window), and the Tab View switcher.
6. **Menu bar panel and Settings** in SwiftUI. Licensing is optional or skipped.

### Technical risks to prototype first
- Ordering overlays relative to *other apps'* windows (No peek and Clean Space) has no public API. Options are `NSWindow.order(_:relativeTo:)` using the CGWindowID, or private CGS calls. This needs a spike.
- Space identity for per-Space sizes needs private `CGSGetActiveSpace`/`CGSCopyManagedDisplaySpaces` calls (AeroSpace and yabai do this).
- Detecting edge-drag resizes versus app-initiated resizes, and avoiding feedback loops with our own writes.
- Apps that refuse frames (min size or fixed aspect ratio), and Electron/Java windows with odd AX trees.

### Phased plan
1. **MVP**: observer, Grid/Columns/Rows/Side, reflow, per-screen layout, exclusions, the ⌃⌥ swap/move/primary/float shortcuts, a basic menu bar panel.
2. Stacks (grip, chips, dots), edge-drag and keyboard resize, main size %, ultrawide and vertical handling, min-size learning.
3. Focus, Retile, borders and glow, hover focus, ⌘-drag swap.
4. No peek, Clean Space, Tab View.
5. Shortcut editor with conflict detection, onboarding, localisation, Sparkle, notarization.
