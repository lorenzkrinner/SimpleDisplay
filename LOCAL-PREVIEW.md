# Agent preview build

This fork adds an optional live viewer for the virtual display named `Agent`. Open the menu-bar controls and click the preview icon beside Agent's settings gear and enable switch. The window is titled `SimpleDisplay (Agent)`.

The viewer captures only Agent, excludes SimpleDisplay's own windows, and forwards no mouse or keyboard input. It captures no audio. Closing it stops capture while keeping the virtual display running. The title-bar retry icon reconnects the viewer after an error or permission change. Capture is limited to 1280 pixels wide at 15 frames per second.

Opening the preview requires Screen Recording permission. The app requests it only when the viewer is opened. If access is denied, the window provides a Settings button. macOS may require quitting and reopening SimpleDisplay after granting permission.

## Dock and window behavior

Settings includes **Hide Dock Icon**, enabled by default. The app then appears in the Dock while the preview window is open and returns to menu-bar-only mode when it closes. Unchecking the setting keeps the Dock icon visible.

Command-Q closes the preview without stopping SimpleDisplay or removing Agent. To quit the app, use **Quit** in the menu-bar popover. macOS logout, restart, and shutdown remain supported.

## Build

```sh
bash scripts/build-local-preview.sh
```

The script writes `.build/local-preview/SimpleDisplay.app` without replacing an installed app. It uses an ad-hoc local signature by default. To use your own signing certificate, set `SIMPLEDISPLAY_SIGN_IDENTITY` to its name or hash. No signing certificate or private key is included in this repository.

The script uses the macOS 26.5 SDK when installed, otherwise the selected Xcode SDK. Override it with `SIMPLEDISPLAY_SDK_PATH` if needed. The command-line 27.0 SDK used during development omitted the SwiftUI macro plugin needed by the existing app; the installed 26.5 SDK built the same sources successfully.

The local build keeps `app.simpledisplay` as its bundle ID so saved display definitions remain available. It is not the upstream notarized release. Quit the installed copy before replacing its app bundle, keep a backup, and run only one copy at a time.

## Validation

Release builds, signature verification, URL-command round trips, and localization JSON checks passed. Live checks covered Screen Recording denial and approval, Calculator updates in the viewer, closing and reopening the viewer without removing Agent, popover dismissal, and Command-Q preserving the app and display. Closed-lid computer use also worked on an M3 MacBook Air with Insomnia keeping macOS awake.

The full XCTest suite could not run with the installed command-line tools because XCTest was unavailable. Long capture sessions and removing or resizing the display during capture remain untested.
