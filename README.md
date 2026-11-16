# tenfoot-mac
An app launcher for running all your macOS games and apps, inspired by video game console menus.

TenFoot opens fullscreen and gives you a console-style home menu built for a TV and a game controller. It only runs while you have it open.

## Status
Done so far: the home screen, controller navigation, a Settings screen where you add your own apps, launching games, and the Home button to resume or close a game. When a game quits, TenFoot comes back.

## Try it
1. Download the newest build: https://github.com/viet100/tenfoot-mac/releases/download/latest-dev/TenFoot.zip. The link stays the same and always has the latest version of the `dev` branch.
2. Unzip it and move `TenFoot.app` to Applications if you like.
3. The first time, macOS blocks it because it isn't notarized. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or run this in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/TenFoot.app
   ```
4. Move with the d-pad, stick or arrow keys. **A** (or Return) selects or starts a game, **B** (or Esc) goes back, and **⌘Q** exits. With a mouse or trackpad, click to select and scroll or swipe to move along the row. The Dock and menu bar come back when you quit.
5. To add your games, go down to the **Settings** button, open it, and choose **Add App**. Pick any apps or programs (you can select several at once). They show up on the home screen and are remembered next time, in `~/Library/Application Support/TenFoot/library.json`. To change their order, drag a game along the row with the mouse; hold it at the edge of the screen to scroll. To remove a game, press **Y** on it (or right-click it) and choose **Remove from TenFoot**. This only takes it off TenFoot's list; nothing is deleted from your Mac.
6. While playing, press **Home** (or **−** and **+** together) to go back to TenFoot. The game keeps running and is marked with a ▶ badge. Press **A** to resume it, or **X** to close it. If macOS also opens something when you press Home, change what the Home button does in **System Settings → Game Controllers**, or use − and +.
7. If your Mac uses the Clear, Tinted or Dark icon style, **Settings → Icon Style → Full Colour** shows each app's own colour icon instead. Apps that don't include a separate icon file keep the macOS version. A custom icon you set yourself with Finder's **Get Info** (paste an image onto the icon) is used as is, for apps and for programs like `.exe` files.

Requires macOS 26 or later.

## Build from source
```bash
scripts/build-app.sh   # → build/TenFoot.app and build/TenFoot.zip
swift test             # unit tests
```

## Tuning the look
Every size, spacing, colour strength and animation is a named constant in `Sources/TenFoot/Theme.swift`. Sizes are fractions of the screen height, so the layout scales the same on a laptop and on a TV.
