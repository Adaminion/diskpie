# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

DiskPie is a desktop-first Flutter app that scans a folder, shows its contents as a pie chart, keeps a history of recent scans, and saves lightweight snapshots. Windows is the primary (and most complete) platform; macOS is in progress and currently broken (see Platform notes).

## Commands

- `flutter pub get` — install dependencies
- `flutter run -d windows` / `flutter run -d macos` — run the app (desktop targets; android/ios/web/linux scaffolding exists but is not the focus)
- `flutter analyze` — static analysis (stock `flutter_lints`, no custom rules)
- `flutter test` — run tests (scanner + byte-formatting suites in `test/`). `main()` itself cannot be exercised in widget tests because `window_manager` requires platform channels
- `dart run tool/bench_scan.dart <path>` — time the scanner on a real folder, print totals in both Finder- and Explorer-style units (`tool/bench_scan_old.dart` is the pre-rewrite algorithm, kept for benchmarking comparisons)
- `flutter build windows` / `flutter build macos` — release builds
- `dart run flutter_launcher_icons` — regenerate app icons from `assets/icon.png`

## Architecture

Single-screen app with **no state-management library**: all app state lives in `_HomeScreenState` (`lib/home_screen.dart`, ~940 lines) and is mutated with plain `setState`. That widget orchestrates everything; the rest of `lib/` is leaf utilities it calls:

- `lib/scanner.dart` — `DiskScanner.scanDirectory()` recursively builds a `FileNode` tree (path, name, size, isFile, children) **on a background isolate using synchronous IO**; the finished tree is handed back zero-copy via `Isolate.exit`. Returns `null` when `cancel()` was called. Progress (`ScanProgress`: item count + current folder) is throttled to one message per 100 ms. Symlinks are never followed (`followLinks: false` returns them as `Link`, which is skipped), so directory cycles are impossible — do not reintroduce canonical-path tracking, it was a major slowdown/memory cost. Unreadable entries are tallied in `ScanResult.skippedCount` instead of being silently dropped.
- `lib/format_bytes.dart` — `formatBytes()` matches the platform file manager's convention: decimal units on macOS/Linux (Finder: 1 GB = 10^9), binary on Windows (Explorer: 1 GB = 2^30). Do not format with 1024-math + SI labels everywhere; that caused a constant ~7–10% apparent mismatch vs Finder.
- `lib/models/snapshot.dart` — `Snapshot` = a `FileNode` tree + scan metadata, JSON-(de)serializable.
- `lib/services/snapshot_service.dart` — persists snapshots as pretty-printed JSON in `<app documents>/diskpie_snapshots/<id>.json`. The snapshot **id is the user-entered name and the filename** — no UUID despite the dependency.
- `lib/services/recent_scans_service.dart` — last 10 scanned paths in `shared_preferences`.
- `lib/services/disk_service.dart` — total/used/free disk space plus the volume mount point (`DiskUsage.mountedOn`): PowerShell `Get-CimInstance` on Windows, `df -P -k` on macOS/Linux. `mountedOn` lets the UI detect whole-volume scans and show an "Outside Scan" stat — used space the scan couldn't see (Trash, system folders, no-permission items) — so totals reconcile with Finder/Explorer.
- `lib/services/logger_service.dart` — singleton file logger appending to `<app documents>/diskpie_logs.txt`; viewable in-app via the bug-report icon in the AppBar.

### Data-model invariants (easy to break)

- **The scanned tree is lossy by design.** For each directory the scanner keeps only the 20 largest children and collapses the rest into a synthetic node named `"Others (N items)"`. Sizes are still accurate; the structure isn't.
- **Synthetic nodes are identified by magic name strings.** `home_screen.dart` checks `name.startsWith("Others")` and `name == "Files"` (the UI groups all loose files of the displayed root into a synthetic "Files" slice in `_processedChildren`). For live whole-volume scans, `_processedChildren` also appends "Outside Scan" and "Free Space" nodes (consts `_kOutsideScanName`/`_kFreeSpaceName`) so the pie totals the entire disk; they get grey slice colors and special icons. Renaming any of these labels in one place breaks icon choice, context menus, and grouping elsewhere.
- **Snapshots are pruned before saving**: root + shallow copies of its immediate children only (`shallowCopy()` drops grandchildren). A loaded snapshot therefore cannot be drilled into.
- **Two display modes share one UI.** `_isViewingSnapshot` switches the `_displayRootNode` getter between `_liveRootNode` and `_snapshotRootNode`; snapshot mode disables scanning/saving and tints the header amber. New features must handle both modes.

### Platform notes

- macOS builds are sandboxed with only `com.apple.security.files.user-selected.read-only` (see `macos/Runner/*.entitlements`), so the app can read only folders the user picked via the dialog in this session. Rescanning a path stored in "Recent Locations" fails under the sandbox. The most recent commit ("nie dziala na macu" — Polish for "doesn't work on mac") reflects this; some commit messages are in Polish.
- The user-visible version is the `appVersion` const in `lib/app_info.dart` (used by the window title and the About dialog). Keep it in sync with `pubspec.yaml` `version:` when bumping.

## Marketing pages

Static HTML/CSS unrelated to the Flutter app: `site/` (simple landing page, referenced by the README) and `website/` (richer multi-page site). Open the HTML files directly in a browser to preview.
