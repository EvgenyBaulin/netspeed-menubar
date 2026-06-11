# NetSpeed MenuBar

Native macOS menu bar app (Swift / SwiftUI / AppKit hybrid) that shows live
network stats right in the menu bar, with a click-to-open history panel built
on Swift Charts and the Liquid Glass design language.

![menu bar](docs/screenshot.png)

## Features

- **Connection-type icon** — Wi-Fi, Personal Hotspot (USB tethering), Ethernet,
  or offline, detected via `NWPathMonitor` + SystemConfiguration hardware-port
  names. Updates automatically when the network changes.
- **Stacked ↓/↑ speeds** — download on top, upload directly below, refreshed
  every second from kernel interface counters (`getifaddrs`), summed over all
  non-loopback interfaces.
- **Ping latency** — averaged over a configurable list of hosts (default
  `1.1.1.1`), pinged in parallel every 3 seconds; **jitter** and **packet
  loss %** are shown under the Ping chart. Failed pings are gaps in the data,
  never fake zero/negative points.
- **Click-to-open panel** — an `NSPopover` with three separate Swift Charts
  (Download, Upload, Ping): smoothed lines, gradient fills, auto-scaled Y axis,
  a time-based X axis, live 1-second updates while open.
- **Settings window** — gear button in the panel or right-click menu:
  - **Launch at Login** (`SMAppService`, needs the installed `.app`);
  - per-chart **units** for Download and Upload: Auto / Mbit/s / MB/s /
    Kbit/s / KB/s (Ping is always ms);
  - chart **time window**: 1 min / 5 min / 15 min / 1 hour (default 5 min),
    shared by all three charts; long windows are downsampled for smooth
    rendering.
  - All settings persist across launches.
- **Localized UI (EN / RU)** — follows the system language, including chart
  titles, connection types, units, and settings labels. Numbers use
  locale-aware formatting (decimal comma in Russian).
- **Liquid Glass UI** — system materials (`.regularMaterial`) and semantic
  colors only; no hard-coded colors or transparency, so the app automatically
  respects Reduce Transparency and picks up future Liquid Glass refinements.
- **Menu bar agent** — no Dock icon (`.accessory` activation policy). Quit from
  the panel or the right-click context menu.

## Requirements

- macOS 26+ (Apple Silicon)
- Xcode (used as the Swift toolchain only — no Xcode project needed)
- VS Code + the official [Swift extension](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode)

## Build & run in VS Code

1. Open this folder in VS Code and install the recommended Swift extension
   (`swiftlang.swift-vscode`).
2. **Build:** `Cmd+Shift+B`, or `swift build` in the terminal.
3. **Run / debug:** `F5`, or `swift run` in the terminal. The app appears as a
   menu bar item (it is an agent — no Dock icon). Stop it with **Quit** in the
   panel / right-click menu, or by stopping the debug session.

> **Note (iCloud):** if the project lives inside iCloud Drive, keep build
> artifacts out of the synced folder, otherwise iCloud will try to sync
> thousands of files from `.build`. This repo expects `.build` to be a symlink
> to a folder outside the cloud:
>
> ```bash
> EXT="$HOME/Library/Developer/netspeed-menubar-build"
> mkdir -p "$EXT"
> ln -sfn "$EXT" ".build"
> ```

## Build a standalone app bundle

To get a regular `NetSpeedMac.app` you can keep in `/Applications` and launch
from Spotlight:

```bash
zsh scripts/bundle.sh
```

This builds a release binary, assembles `dist/NetSpeedMac.app` (ad-hoc signed,
`LSUIElement` — no Dock icon) including the SwiftPM resource bundle so
localization works inside the app, and prints the resulting path. In VS Code it
is also available as the **bundle NetSpeedMac.app** build task. Like `.build`,
`dist` is a symlink to a folder outside iCloud — the script creates it
automatically (iCloud's extended attributes would otherwise break strict
code-signature verification).

```bash
cp -R dist/NetSpeedMac.app /Applications/
open /Applications/NetSpeedMac.app
```

## Launch at Login

1. Build and install the app bundle as above (a bare binary cannot be a login
   item).
2. Open the panel → gear → **General** → enable **Launch at Login**.
3. The first time, confirm the login item in
   **System Settings → General → Login Items** if macOS asks.

### Alternative: manual LaunchAgent

1. Build a release binary:

   ```bash
   swift build -c release
   ```

2. Copy the binary somewhere stable (a path that does not change between
   builds), e.g.:

   ```bash
   mkdir -p ~/.local/bin
   cp "$(swift build -c release --show-bin-path)/NetSpeedMenuBar" ~/.local/bin/
   ```

3. Copy [com.user.netspeed.plist.example](com.user.netspeed.plist.example) to
   `~/Library/LaunchAgents/com.user.netspeed.plist` and replace the placeholder
   path with the binary location from step 2.

4. Load it:

   ```bash
   launchctl load -w ~/Library/LaunchAgents/com.user.netspeed.plist
   ```

## Localization

The UI is localized (English, Russian) and follows the system language. The
source of truth is the String Catalog
[Localization/Localizable.xcstrings](Localization/Localizable.xcstrings).
Command-line SwiftPM does not compile string catalogs (that is an Xcode
build-system feature), so the compiled `.lproj/Localizable.strings` files are
generated by `scripts/genstrings.sh` (requires Xcode) and committed under
`Sources/NetSpeedMenuBar/Resources/`. Re-run the script after editing the
catalog. Strings are resolved against `Bundle.module` — in a SwiftPM executable
target, resources never land in `Bundle.main`.

## Compatibility

Built for **macOS 26** (deployment target `macOS 26`). Uses only stable public
APIs (SwiftUI, AppKit, Swift Charts, Network, ServiceManagement,
SystemConfiguration, Darwin) and system materials / semantic colors, so it is
forward-compatible with **macOS 27**: the refined Liquid Glass appearance
(improved legibility, transparency controls) is adopted automatically without
code changes.

## Limitations

- **Personal Hotspot over Wi-Fi is shown as Wi-Fi.** Without private APIs, a
  hotspot joined over Wi-Fi is indistinguishable from a regular Wi-Fi network,
  so no guessing heuristics are applied. USB tethering ("iPhone USB") **is**
  detected reliably via its hardware-port name.
- Ping uses the system `/sbin/ping` binary; if ICMP is blocked on your network,
  latency shows `—` and the chart has a gap.

## License

[MIT](LICENSE)
