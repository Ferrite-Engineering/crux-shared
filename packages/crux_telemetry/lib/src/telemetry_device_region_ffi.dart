// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';

import 'package:crux_telemetry/src/telemetry_region.dart'
    show telemetryCountriesInLocaleId;
import 'package:ffi/ffi.dart';

/// CoreFoundation's current locale: the user's Region setting, owned by the
/// caller.
@Native<Pointer<Void> Function()>(symbol: 'CFLocaleCopyCurrent')
external Pointer<Void> _cfLocaleCopyCurrent();

/// A locale's identifier, such as `en_GB` or `en_US@rg=gbzzzz`. Not owned.
@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: 'CFLocaleGetIdentifier')
external Pointer<Void> _cfLocaleGetIdentifier(Pointer<Void> locale);

@Native<Long Function(Pointer<Void>)>(symbol: 'CFStringGetLength')
external int _cfStringGetLength(Pointer<Void> string);

@Native<Uint16 Function(Pointer<Void>, Long)>(
  symbol: 'CFStringGetCharacterAtIndex',
)
external int _cfStringGetCharacterAtIndex(Pointer<Void> string, int index);

@Native<Void Function(Pointer<Void>)>(symbol: 'CFRelease')
external void _cfRelease(Pointer<Void> object);

/// The Windows Country or region setting, as an ISO 3166 code or a UN M.49
/// number. Returns the number of characters written, including the
/// terminator, or 0 on failure.
@Native<Int32 Function(Pointer<Utf16>, Int32)>(symbol: 'GetUserDefaultGeoName')
external int _getUserDefaultGeoName(Pointer<Utf16> geoName, int count);

/// The environment variables a Linux session keeps its language, formats and
/// region in. `LANGUAGE` is a colon-separated list.
const List<String> _linuxLocaleVariables = <String>[
  'LC_ALL',
  'LC_MESSAGES',
  'LC_CTYPE',
  'LC_TIME',
  'LC_NUMERIC',
  'LC_MONETARY',
  'LC_PAPER',
  'LC_MEASUREMENT',
  'LC_ADDRESS',
  'LC_TELEPHONE',
  'LC_NAME',
  'LC_IDENTIFICATION',
  'LC_COLLATE',
  'LANG',
  'LANGUAGE',
];

/// See `telemetry_device_region.dart`. Never throws: a setting that cannot be
/// read contributes nothing, which leaves the decision to the other signals.
List<String> platformRegionCountries() {
  final countries = <String>{};
  void addLocaleId(String? id) {
    if (id == null || id.isEmpty) return;
    countries.addAll(telemetryCountriesInLocaleId(id));
  }

  try {
    if (Platform.isMacOS || Platform.isIOS) {
      addLocaleId(_appleCurrentLocaleId());
    } else if (Platform.isWindows) {
      // Dart reads the regional format through `GetUserDefaultLocaleName`.
      addLocaleId(Platform.localeName);
      final geo = _windowsGeoName();
      if (geo != null && RegExp(r'^[A-Za-z]{2}$').hasMatch(geo)) {
        countries.add(geo.toUpperCase());
      }
    } else if (Platform.isLinux) {
      final environment = Platform.environment;
      for (final name in _linuxLocaleVariables) {
        environment[name]?.split(':').forEach(addLocaleId);
      }
    }
  } on Object catch (_) {
    // A `@Native` symbol is bound on first call, and a process that does not
    // export it raises there. That is a setting that cannot be read.
  }
  return countries.toList(growable: false);
}

String? _appleCurrentLocaleId() {
  final locale = _cfLocaleCopyCurrent();
  if (locale == nullptr) return null;
  try {
    final identifier = _cfLocaleGetIdentifier(locale);
    if (identifier == nullptr) return null;
    final length = _cfStringGetLength(identifier);
    return String.fromCharCodes(<int>[
      for (var i = 0; i < length; i++)
        _cfStringGetCharacterAtIndex(identifier, i),
    ]);
  } finally {
    _cfRelease(locale);
  }
}

String? _windowsGeoName() {
  const capacity = 16;
  final buffer = calloc<Uint16>(capacity).cast<Utf16>();
  try {
    final written = _getUserDefaultGeoName(buffer, capacity);
    return written > 0 ? buffer.toDartString() : null;
  } finally {
    calloc.free(buffer);
  }
}
