// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The platform's resolved IANA time zone, where the platform can name one.
///
/// Only the web build can. Browsers expose the zone the page is running in as
/// an IANA name such as `Europe/Berlin`, through `Intl.DateTimeFormat`. The
/// Dart VM exposes only an abbreviation, which is ambiguous — `IST` is Dublin
/// as well as Kolkata — so every other platform answers `null` and the
/// first-launch default there is placed by locale alone. See
/// `telemetry_region.dart` for what the value is for and why the web build
/// needs it.
///
/// Read once at the moment the disclosure needs a default, never stored,
/// never transmitted.
library;

export 'telemetry_time_zone_stub.dart'
    if (dart.library.js_interop) 'telemetry_time_zone_web.dart';
