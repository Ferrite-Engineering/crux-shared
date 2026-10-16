// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The countries the operating system's region settings name, where the
/// platform has region settings a process can read.
///
/// The locale list Flutter reports is the user's *languages*. On macOS, iOS
/// and Windows the region is a separate setting, so a machine set to US
/// English with its region set to the United Kingdom reports `en-US` there and
/// `GB` here. Each platform is read where it keeps the setting:
///
/// - **macOS and iOS**: the current CoreFoundation locale, whose identifier
///   carries the Region setting, including an `rg` region override.
/// - **Windows**: the regional format (`GetUserDefaultLocaleName`) and the
///   Country or region setting (`GetUserDefaultGeoName`).
/// - **Linux**: `LANG`, `LANGUAGE` and the `LC_*` variables, which is where a
///   desktop session puts its formats and region.
/// - **Android**: nothing extra. Android has no region setting apart from the
///   locale list, and every entry in that list already carries its country.
/// - **The web**: nothing. A page cannot see the operating system's region;
///   the browser's time zone stands in for it there.
///
/// Read once at the moment the disclosure needs a default, never stored,
/// never transmitted. See `telemetry_region.dart` for what the value decides.
library;

export 'telemetry_device_region_stub.dart'
    if (dart.library.ffi) 'telemetry_device_region_ffi.dart';
