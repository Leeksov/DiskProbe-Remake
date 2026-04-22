# DiskProbe (Remake)

Rootless port and open-source reimplementation of **DiskProbe** for jailbroken iOS 14+.
Visually manage device storage, browse the entire file system, analyze disk usage by directory, and preview files.

> Built from scratch based on the original closed-source DiskProbe by [CreatureSurvive](https://twitter.com/creaturesurvive). All DRM and paid-feature gates have been removed.

## Features

- **Full file browser** — navigate `/`, `/var`, `/Applications`, `/System` and everything else with root access.
- **Visual disk usage** — segmented bar graph per directory showing size distribution.
- **Two view modes** — list and grid with cell icons, modification dates, and sizes.
- **Smart sorting** — by name, size, or age; ascending/descending; folders-first option.
- **Search** — exact substring or wildcard across the current directory.
- **Context menu actions** — Open in Filza, Open Preview, Open Info, Copy Path, Copy Name, Delete / Uninstall Application.
- **Preview** — QuickLook with fullscreen toggle, including binary plist conversion and syntax highlighting.
- **Symlink support** — follow links to their targets, show target's size, sort by real size.
- **Background sizing** — optional continuous background operation (silent-audio keepalive) so large directory scans survive the app going into the background.
- **Setuid helper** — a privileged `diskprobe-utility` binary pre-sizes all volumes so scanning begins immediately on launch.

## Installation

Download the latest `.deb` from the [Releases page](https://github.com/Leeksov/DiskProbe-Remake/releases) and install via your package manager (Sileo, Zebra, `dpkg -i`).

**Requirements:**
- iOS 14.0 or newer
- Rootless jailbreak (Dopamine, palera1n rootless)

## Building

Requires [theos](https://theos.dev).

```bash
git clone https://github.com/Leeksov/DiskProbe-Remake.git
cd DiskProbe-Remake
make package                 # rootless (default) — installs under /var/jb
make package SCHEME=rootful  # rootful — installs under /
```

Both schemes build the same source tree; `-DROOTLESS=1` is only defined for the rootless scheme, which flips path prefixes in `DPCatalog`, `DPStreamingTask`, and the postinst.

Optional: install directly to a device via SSH. Set `THEOS_DEVICE_IP` and `THEOS_DEVICE_PASSWORD` in the top-level Makefile, then:

```bash
make package install
```

## Project layout

```
.
├── DiskProbeRemake/            — the app
│   ├── Sources/                — ~40 Objective-C sources, ARC, iOS 14+
│   ├── Resources/              — Info.plist, icons, Main.storyboardc
│   └── entitlements.plist
├── DiskProbeUtilityRemake/     — the setuid CLI helper
│   └── Sources/main.m          — privileged volume sizer
├── Makefile                    — aggregate Theos build (produces a single .deb)
├── control                     — package metadata
└── layout/DEBIAN/postinst      — uicache + chmod 6755 on the utility
```

## Changelog

The in-app Changelog screen fetches live release notes from this repository's
[Releases](https://github.com/Leeksov/DiskProbe-Remake/releases) via the GitHub API and caches them for offline viewing.

## Credits

- **[CreatureSurvive](https://twitter.com/creaturesurvive)** — original DiskProbe author and UI design.
- **[Leeksov](https://github.com/Leeksov)** — rootless port, open-source rewrite, DRM removal.
- Storyboard (compiled nib) reused from the original DiskProbe v1.0.5 build.

## License

MIT. See `LICENSE`.

© 2018–2026 Leeksov
