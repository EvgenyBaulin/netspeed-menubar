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
- **Ping latency** — round-trip time to `1.1.1.1` every 3 seconds, rendered to
  the right of the speed block, vertically centered between ↓ and ↑.
- **Click-to-open panel** — an `NSPopover` with three separate Swift Charts
  (Download, Upload, Ping): smoothed lines, gradient fills, auto-scaled Y axis,
  ~60 points of history each, live 1-second updates while open.
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

## Run at login (LaunchAgent)

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

## Compatibility

Built for **macOS 26** (deployment target `macOS 26`). Uses only stable public
APIs (SwiftUI, AppKit, Swift Charts, Network, SystemConfiguration, Darwin) and
system materials / semantic colors, so it is forward-compatible with
**macOS 27**: the refined Liquid Glass appearance (improved legibility,
transparency controls) is adopted automatically without code changes.

## Limitations

- **Personal Hotspot over Wi-Fi is shown as Wi-Fi.** Without private APIs, a
  hotspot joined over Wi-Fi is indistinguishable from a regular Wi-Fi network,
  so no guessing heuristics are applied. USB tethering ("iPhone USB") **is**
  detected reliably via its hardware-port name.
- Ping uses the system `/sbin/ping` binary; if ICMP is blocked on your network,
  latency shows `—`.

## License

[MIT](LICENSE)
