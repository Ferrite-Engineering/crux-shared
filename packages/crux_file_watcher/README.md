# crux_file_watcher

File-system watcher with debounced events for the EDACrux suite.

Wraps `dart:io`'s `File.watch()` with a 500-ms debounce window and a clean event model (`FileWatchEvent.modified` / `FileWatchEvent.deleted`). On Flutter Web, where `dart:io` file watching is unavailable, `startWatching` is a no-op so callers don't have to special-case the platform.

## Status

Production code lifted from WaveCrux open-core (`lib/services/waveform/file_watcher_service.dart`) as part of the Step 3 extraction. WaveCrux's `file_watcher_provider.dart` and Stage `manifest_hot_reload_controller.dart` consume it via a `package:crux_file_watcher` import.

## Usage

```dart
import 'package:crux_file_watcher/crux_file_watcher.dart';

final service = FileWatcherService();
final sub = service.events.listen((event) {
  switch (event) {
    case FileWatchEvent.modified:
      // Reload the file.
    case FileWatchEvent.deleted:
      // Show "file deleted on disk" warning.
  }
});

service.startWatching('/path/to/your/file');
// ... later:
service.dispose();
```

On macOS the platform watch can stop delivering events for the rest of the process, with no error (crux-shared#25). Pass `pollInterval` to also read the file's size and modification time on that interval, so a change the watch misses is still reported:

```dart
final service = FileWatcherService(pollInterval: const Duration(seconds: 1));
```

A change both sources see is reported once. Polling is off by default.

For tests, inject a custom `WatchFactory` to feed deterministic `FileSystemEvent`s into the service without touching the real filesystem.
