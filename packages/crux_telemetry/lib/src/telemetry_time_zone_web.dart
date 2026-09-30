// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:js_interop';

@JS('Intl.DateTimeFormat')
extension type _DateTimeFormat._(JSObject _) implements JSObject {
  external factory _DateTimeFormat();
  external _ResolvedOptions resolvedOptions();
}

extension type _ResolvedOptions._(JSObject _) implements JSObject {
  external JSString? get timeZone;
}

/// See `telemetry_time_zone.dart`. The browser's resolved zone, an IANA name
/// such as `Europe/Berlin`, or `null` if the runtime cannot say.
///
/// Wrapped in a catch because this runs on the path to the first-launch
/// dialog, where a missing `Intl` — a locked-down or ancient runtime — must
/// degrade to "no evidence" rather than to no dialog.
String? platformIanaTimeZone() {
  try {
    return _DateTimeFormat().resolvedOptions().timeZone?.toDart;
  } on Object {
    return null;
  }
}
