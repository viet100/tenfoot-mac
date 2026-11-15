# tenfoot-mac
An app launcher for running all your macOS games and apps, inspired by video game console menus.

TenFoot opens fullscreen and gives you a console-style home menu built for a TV and a game controller. It only runs while you have it open.

## Status
Step 1 of the build: the app skeleton and a static home screen with sample tiles. Controller input, your real games, and launching come in later steps.

## Try it
1. Open the latest **Build** run under the repo's Actions tab and download the `TenFoot-app` artifact.
2. Unzip it. The first time, right-click `TenFoot.app` and choose **Open**: it isn't notarized.
3. Use **← →** to move between tiles and **⌘Q** to exit. The Dock and menu bar come back when you quit.

Requires macOS 26 or later.

## Build from source
```bash
scripts/build-app.sh   # → build/TenFoot.app and build/TenFoot.zip
swift test             # unit tests
```

## Tuning the look
Every size, spacing, colour strength and animation is a named constant in `Sources/TenFoot/Theme.swift`. Sizes are fractions of the screen height, so the layout scales the same on a laptop and on a TV.
