# Diskpie

Flutter app. Shows the contents of a media drive as a pie chart (disk-usage
visualizer). Desktop-focused — uses `window_manager`.

## Run / build / test

```sh
flutter pub get
flutter run -d windows
flutter test
flutter analyze
flutter build windows
```

## Code layout

```
lib/
  main.dart
  home_screen.dart                  # top-level UI
  scanner.dart                      # drive scanning
  models/snapshot.dart              # scan result model
  services/
    disk_service.dart               # filesystem walking
    snapshot_service.dart           # save / load snapshots
    recent_scans_service.dart       # MRU list
    logger_service.dart
```

## Key dependencies

- `fl_chart` — the pie chart
- `file_selector` — picking a drive / folder
- `window_manager` — desktop window control
- `shared_preferences` + `path_provider` — persistence
- `intl` — number / date formatting

## Don't (without asking)

- Add new packages to `pubspec.yaml`.
- Add mobile (iOS / Android) platform code — this is desktop-first.
- Block the UI thread on directory scans; keep work async.
