# StylusScroll

**Middle-click drag → system scroll for drawing tablets on macOS.**

If you use a drawing tablet (XP-PEN, Huion, Wacom, etc.) you've probably noticed that holding the middle button and dragging does nothing in Safari, Finder, or most apps — even though it works fine in apps like DaVinci Resolve that handle raw tablet input themselves.

StylusScroll fixes this. It runs as a tiny menu bar app and converts middle-button drag into smooth scroll events system-wide, in every app, without breaking anything else.

---

## Download

**[→ Download the latest release](https://github.com/meeer-theblackintels/StylusScroll/releases/latest)**

No Xcode needed. Download, open, done.

---

## Features

- ✅ Middle-click drag scrolls in **every app** — Safari, Finder, Chrome, Figma, anything
- ✅ Works with **XP-PEN, Huion, Wacom** and any tablet that registers a middle button
- ✅ Works with **OpenTabletDriver** and official tablet drivers
- ✅ **App blocklist** — automatically pauses in DaVinci Resolve, Blender, Photoshop, etc. so their native middle-click behaviour is preserved
- ✅ **Key mappings** — map any key combo to mouse buttons, scroll, or other keys (e.g. Shift+F13 → Mouse Button 4)
- ✅ Adjustable scroll speed, momentum, axis inversion
- ✅ Menu bar app — no Dock icon, lives quietly in the top right
- ✅ Launch at login support

---

## Requirements

- macOS 13 Ventura or later
- A drawing tablet with a middle button / barrel button

---

## Installation

1. Download `StylusScroll.app` from the [Releases page](https://github.com/meeer-theblackintels/StylusScroll/releases)
2. Move it to your **Applications** folder
3. Open it — a hand icon appears in the menu bar
4. Click the icon → grant **Accessibility permission** when prompted
5. Done — middle-click drag now scrolls everywhere

> **First launch note:** macOS may show a warning saying the app is from an unidentified developer. Right-click the app → Open → Open to bypass it. This happens because the app is not yet signed with a paid Apple Developer certificate.

---

## How to use

**Scrolling:** Hold your stylus middle button and drag up/down/left/right. That's it.

**Menu bar icon:**
- 🟢 Green = active
- 🟠 Orange = paused (current app is on the blocklist)

**Settings:** Click the menu bar icon → Open Settings

---

## App Blocklist

Apps like DaVinci Resolve handle middle-click natively for node panning. StylusScroll automatically pauses itself when these apps are focused so their native behaviour works normally.

**Default blocked apps:** DaVinci Resolve, Blender, Photoshop, Illustrator, After Effects, Maya, Nuke, Houdini

To add or remove apps: Settings → App Blocklist tab. You can block the currently active app with one click.

---

## Key Mappings

Map any key combo to a mouse button, scroll direction, or keyboard shortcut.

**Example:** Map `Shift+F13` to Mouse Button 4 for browser back/forward.

Settings → Key Mappings tab → Add Mapping → record your trigger key → choose action → Save.

---

## Build from source

1. Install **Xcode** (free from the Mac App Store)
2. Clone this repo:
```
git clone https://github.com/meeer-theblackintels/StylusScroll.git
```
3. Open Xcode → **File → New → Project** → macOS App
4. Delete the auto-generated `ContentView.swift`
5. Drag the files from `v0.32/` into your Xcode project
6. In **Signing & Capabilities**, remove App Sandbox and sign with your Apple ID
7. Set `CODE_SIGN_ENTITLEMENTS` to `StylusScroll.entitlements` in Build Settings
8. Press **⌘R** to build and run

---

## Versions

| Version | Changes |
|---|---|
| v0.32 | OpenTabletDriver support, momentum ghost cursor fix |
| v0.31 | App blocklist, key mappings, edit mappings fix |

---

## Why does this need Accessibility permission?

StylusScroll uses a macOS `CGEventTap` to intercept middle-button events system-wide. macOS requires explicit Accessibility permission for any app that reads system-wide input events. StylusScroll does not log keystrokes, does not make network connections, and does not collect any data. The source code is available above so you can verify this yourself.

---

## Compatibility

- macOS 13 Ventura and later (including macOS Tahoe)
- Apple Silicon and Intel Macs
- Official tablet drivers (XP-PEN, Huion, Wacom)
- OpenTabletDriver (v0.32+)

---

*Built with Swift + SwiftUI + CoreGraphics.*
